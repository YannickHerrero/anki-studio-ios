import Foundation

/// On-device storage layout, mirroring the desktop server's `tmp/<sid>/` dirs
/// (server/src/lib/session.ts). Everything lives under the app's Documents:
///
///   Documents/sessions/<sid>/session.json
///   Documents/sessions/<sid>/video.<ext>
///   Documents/sessions/<sid>/full.m4a          (mono 16k, for Whisper)
///   Documents/sessions/<sid>/audio/<index>.m4a (per-cue clips)
///   Documents/sessions/<sid>/image/<index>.jpg (per-cue screenshots)
enum Storage {
    static let fm = FileManager.default

    static var documents: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var sessionsRoot: URL {
        documents.appendingPathComponent("sessions", isDirectory: true)
    }

    static func sessionDir(_ sid: String) -> URL {
        sessionsRoot.appendingPathComponent(sid, isDirectory: true)
    }

    static func sessionFile(_ sid: String) -> URL {
        sessionDir(sid).appendingPathComponent("session.json")
    }

    static func videoURL(_ sid: String, ext: String = "mp4") -> URL {
        sessionDir(sid).appendingPathComponent("video.\(ext)")
    }

    static func fullAudioURL(_ sid: String) -> URL {
        sessionDir(sid).appendingPathComponent("full.m4a")
    }

    static func audioDir(_ sid: String) -> URL {
        sessionDir(sid).appendingPathComponent("audio", isDirectory: true)
    }

    static func imageDir(_ sid: String) -> URL {
        sessionDir(sid).appendingPathComponent("image", isDirectory: true)
    }

    static func audioURL(_ sid: String, _ index: Int) -> URL {
        audioDir(sid).appendingPathComponent("\(index).m4a")
    }

    static func screenshotURL(_ sid: String, _ index: Int) -> URL {
        imageDir(sid).appendingPathComponent("\(index).jpg")
    }

    static func ensureDir(_ url: URL) throws {
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Create the per-session directory tree (session dir + audio + image).
    static func ensureSessionDirs(_ sid: String) throws {
        try ensureDir(sessionDir(sid))
        try ensureDir(audioDir(sid))
        try ensureDir(imageDir(sid))
    }

    // MARK: - Disk usage

    /// Allocated size of everything under `url`, in bytes.
    static func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [],
            errorHandler: { _, _ in true })
        else { return 0 }

        var total: Int64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(
                forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        return total
    }

    struct DiskUsage {
        var sessionsBytes: Int64
        var sessionCount: Int
        var appDataBytes: Int64
        var bundleBytes: Int64
    }

    /// Per-session footprint, bucketed by media kind.
    struct SessionUsage: Identifiable {
        var id: String
        var videoBytes: Int64 = 0
        var audioBytes: Int64 = 0
        var imageBytes: Int64 = 0
        var otherBytes: Int64 = 0
        var totalBytes: Int64 { videoBytes + audioBytes + imageBytes + otherBytes }
    }

    /// Walk every session directory and bucket file sizes. Call off-main.
    static func sessionUsages() -> [SessionUsage] {
        let dirs = (try? fm.contentsOfDirectory(
            at: sessionsRoot, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { dir in
            guard dir.hasDirectoryPath else { return nil }
            var usage = SessionUsage(id: dir.lastPathComponent)
            guard let enumerator = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
                options: [],
                errorHandler: { _, _ in true })
            else { return usage }
            for case let file as URL in enumerator {
                let values = try? file.resourceValues(
                    forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
                let bytes = Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
                let name = file.lastPathComponent
                let parent = file.deletingLastPathComponent().lastPathComponent
                if name.hasPrefix("video.") {
                    usage.videoBytes += bytes
                } else if parent == "audio" || name == "full.m4a" {
                    usage.audioBytes += bytes
                } else if parent == "image" {
                    usage.imageBytes += bytes
                } else {
                    usage.otherBytes += bytes
                }
            }
            return usage
        }
        .sorted { $0.totalBytes > $1.totalBytes }
    }

    /// Snapshot of what the app occupies on disk. Walks the whole data
    /// container — call it off the main thread.
    static func diskUsage() -> DiskUsage {
        let sessionDirs = (try? fm.contentsOfDirectory(
            at: sessionsRoot, includingPropertiesForKeys: nil)) ?? []
        let home = URL(fileURLWithPath: NSHomeDirectory())
        return DiskUsage(
            sessionsBytes: directorySize(sessionsRoot),
            sessionCount: sessionDirs.count,
            appDataBytes: directorySize(home),
            bundleBytes: directorySize(Bundle.main.bundleURL))
    }
}
