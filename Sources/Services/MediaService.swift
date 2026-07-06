import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

enum MediaError: Error, LocalizedError {
    case noAudioTrack
    case exportFailed(String)
    case screenshotFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack: return "The video has no audio track."
        case .exportFailed(let m): return "Audio export failed: \(m)"
        case .screenshotFailed(let m): return "Screenshot failed: \(m)"
        }
    }
}

/// AVFoundation port of the desktop ffmpeg helpers (server/src/lib/ffmpeg.ts):
/// full-audio extraction for Whisper, per-cue audio clips, and midpoint frame
/// screenshots — all on-device, no native binaries.
enum MediaService {
    // MARK: - Full audio for Whisper (ffmpeg.ts extractFullAudio)

    /// Transcode the video's audio to mono 16 kHz AAC (~32 kbps) — small enough
    /// to stay under Whisper's 25 MB upload ceiling for ~25 min of speech.
    static func extractFullAudio(video: URL, to out: URL) async throws {
        try? FileManager.default.removeItem(at: out)
        let asset = AVURLAsset(url: video)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw MediaError.noAudioTrack
        }

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
        ])
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: out, fileType: .m4a)
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ])
        writerInput.expectsMediaDataInRealTime = false
        writer.add(writerInput)

        guard reader.startReading() else {
            throw MediaError.exportFailed(reader.error?.localizedDescription ?? "reader failed")
        }
        guard writer.startWriting() else {
            throw MediaError.exportFailed(writer.error?.localizedDescription ?? "writer failed")
        }
        writer.startSession(atSourceTime: .zero)

        let queue = DispatchQueue(label: "media.fullaudio")
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData {
                    if let sample = readerOutput.copyNextSampleBuffer() {
                        writerInput.append(sample)
                    } else {
                        writerInput.markAsFinished()
                        cont.resume()
                        return
                    }
                }
            }
        }

        await writer.finishWriting()
        if writer.status == .failed {
            throw MediaError.exportFailed(writer.error?.localizedDescription ?? "unknown")
        }
        if reader.status == .failed {
            throw MediaError.exportFailed(reader.error?.localizedDescription ?? "read error")
        }
    }

    // MARK: - Per-cue audio clip (ffmpeg.ts extractAudio, +500ms padding)

    static func extractCueAudio(
        video: URL, to out: URL,
        startMs: Int, endMs: Int,
        prePadMs: Int = 500, postPadMs: Int = 500
    ) async throws {
        try? FileManager.default.removeItem(at: out)
        let asset = AVURLAsset(url: video)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw MediaError.exportFailed("no m4a export preset")
        }
        let start = CMTime(value: CMTimeValue(max(0, startMs - prePadMs)), timescale: 1000)
        let end = CMTime(value: CMTimeValue(endMs + postPadMs), timescale: 1000)
        export.outputURL = out
        export.outputFileType = .m4a
        export.timeRange = CMTimeRange(start: start, end: end)

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { cont.resume() }
        }
        if export.status != .completed {
            throw MediaError.exportFailed(export.error?.localizedDescription ?? "status \(export.status.rawValue)")
        }
    }

    // MARK: - Midpoint screenshot (ffmpeg.ts extractScreenshot)

    static func extractScreenshot(
        video: URL, to out: URL,
        startMs: Int, endMs: Int,
        width: CGFloat = 720, quality: CGFloat = 0.72
    ) async throws {
        try? FileManager.default.removeItem(at: out)
        let asset = AVURLAsset(url: video)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: width, height: 0)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        let mid = CMTime(value: CMTimeValue((startMs + endMs) / 2), timescale: 1000)
        let cgImage: CGImage
        do {
            cgImage = try await generator.image(at: mid).image
        } catch {
            throw MediaError.screenshotFailed(error.localizedDescription)
        }

        guard let dest = CGImageDestinationCreateWithURL(
            out as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            throw MediaError.screenshotFailed("cannot create jpeg destination")
        }
        CGImageDestinationAddImage(dest, cgImage, [
            kCGImageDestinationLossyCompressionQuality: quality,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw MediaError.screenshotFailed("jpeg encode failed")
        }
    }

    /// Duration of a media file in milliseconds (ffprobe equivalent).
    static func durationMs(of url: URL) async throws -> Int {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return Int(CMTimeGetSeconds(duration) * 1000)
    }

    // MARK: - Batch per-cue processing (routes/process.ts, concurrency 4)

    /// Cut audio + screenshot for every cue, 4 at a time. Returns the updated
    /// cues; failures leave the flags false rather than aborting the batch.
    static func processCues(
        session: Session,
        onProgress: @escaping @Sendable (Int, Int) -> Void
    ) async -> [Cue] {
        let video = Storage.videoURL(session.id, ext: session.videoExt)
        var cues = session.cues
        let total = cues.count
        let counter = ProgressCounter()

        await withTaskGroup(of: (Int, Bool, Bool).self) { group in
            var iterator = cues.indices.makeIterator()
            var inFlight = 0

            func addNext(_ group: inout TaskGroup<(Int, Bool, Bool)>) {
                guard let i = iterator.next() else { return }
                let cue = cues[i]
                let sid = session.id
                inFlight += 1
                group.addTask {
                    var audioOK = false, shotOK = false
                    do {
                        try await extractCueAudio(
                            video: video, to: Storage.audioURL(sid, cue.index),
                            startMs: cue.startMs, endMs: cue.endMs)
                        audioOK = true
                    } catch {}
                    do {
                        try await extractScreenshot(
                            video: video, to: Storage.screenshotURL(sid, cue.index),
                            startMs: cue.startMs, endMs: cue.endMs)
                        shotOK = true
                    } catch {}
                    let done = await counter.increment()
                    onProgress(done, total)
                    return (i, audioOK, shotOK)
                }
            }

            for _ in 0..<min(4, cues.count) { addNext(&group) }
            while let (i, audioOK, shotOK) = await group.next() {
                inFlight -= 1
                cues[i].audioReady = audioOK
                cues[i].screenshotReady = shotOK
                addNext(&group)
            }
        }
        return cues
    }
}

private actor ProgressCounter {
    private var value = 0
    func increment() -> Int {
        value += 1
        return value
    }
}
