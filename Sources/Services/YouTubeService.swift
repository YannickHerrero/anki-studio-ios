import Foundation
import YouTubeKit

enum YouTubeError: Error, LocalizedError {
    case badURL
    case noCompatibleStream
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "That doesn't look like a YouTube URL."
        case .noCompatibleStream:
            return "No AVFoundation-compatible (H.264 mp4) stream found for this video."
        case .downloadFailed(let m): return "Download failed: \(m)"
        }
    }
}

/// On-device YouTube probe + download, replacing the desktop yt-dlp
/// (server/src/lib/ytdlp.ts). Uses YouTubeKit for extraction; downloads a
/// progressive H.264 mp4 (video+audio in one file) so AVFoundation can read
/// it, capped at 480p like the desktop pipeline.
enum YouTubeService {
    struct Probe {
        var videoID: String
        var title: String
        var streamURL: URL
        var fileExtension: String
    }

    static func videoID(from url: String) -> String? {
        let patterns = [
            #"youtu\.be/([A-Za-z0-9_-]{6,})"#,
            #"youtube\.com/watch\?[^#]*v=([A-Za-z0-9_-]{6,})"#,
            #"youtube\.com/shorts/([A-Za-z0-9_-]{6,})"#,
        ]
        for pattern in patterns {
            if let match = url.range(of: pattern, options: .regularExpression) {
                let piece = String(url[match])
                if let idRange = piece.range(of: #"[A-Za-z0-9_-]{6,}$"#, options: .regularExpression) {
                    return String(piece[idRange])
                }
            }
        }
        return nil
    }

    /// Resolve the video's metadata and the best compatible stream.
    static func probe(urlString: String) async throws -> Probe {
        guard let id = videoID(from: urlString) else { throw YouTubeError.badURL }
        let video = YouTube(videoID: id)

        let streams = try await video.streams
        // Progressive mp4 = H.264 + AAC muxed in one file — exactly what
        // AVFoundation wants. Prefer the highest resolution ≤ 480p (desktop
        // parity); fall back to the lowest available progressive mp4.
        let progressive = streams
            .filter { $0.isProgressive && $0.fileExtension == .mp4 }
        let capped = progressive
            .filter { ($0.videoResolution ?? 0) <= 480 }
            .max { ($0.videoResolution ?? 0) < ($1.videoResolution ?? 0) }
        let chosen = capped ?? progressive
            .min { ($0.videoResolution ?? 0) < ($1.videoResolution ?? 0) }
        guard let stream = chosen else { throw YouTubeError.noCompatibleStream }

        let metadata = try? await video.metadata
        return Probe(
            videoID: id,
            title: metadata?.title ?? "YouTube \(id)",
            streamURL: stream.url,
            fileExtension: "mp4"
        )
    }

    /// Download the chosen stream to `destination`, reporting progress 0…1.
    static func download(
        _ probe: Probe, to destination: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try? FileManager.default.removeItem(at: destination)

        let delegate = DownloadProgressDelegate(onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let (tempURL, response) = try await session.download(from: probe.streamURL)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 || status == 206 else {
            throw YouTubeError.downloadFailed("HTTP \(status)")
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }
}

/// Bridges URLSession's delegate-based download progress into a closure.
private final class DownloadProgressDelegate: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Required by the protocol; the async `download(from:)` API handles the file.
    }
}
