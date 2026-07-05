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
}
