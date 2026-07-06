import Foundation

enum SessionSource: String, Codable {
    case upload
    case youtube
}

enum ProcessingStatus: String, Codable {
    case pending, processing, ready, error
}

/// A mining session: one (chunk of a) video plus its cues and picks. Ports the
/// relevant subset of `Session` (server/src/lib/session.ts) — server-only
/// fields (subtitle paths, audio streams, apkg paths) are dropped since the
/// phone owns everything locally.
struct Session: Codable, Identifiable, Equatable {
    var id: String
    var createdAt: Date
    var updatedAt: Date
    var source: SessionSource
    var title: String?
    var youtubeURL: String?
    /// Duration of the source video in ms, captured at ingest.
    var videoDurationMs: Int?
    /// Video container extension on disk (mp4 by default).
    var videoExt: String
    /// When the original was split, the 0-indexed chunk number and total.
    var chunkIndex: Int?
    var totalChunks: Int?
    var cues: [Cue]
    var picks: [Pick]
    var status: ProcessingStatus
    var errorMessage: String?
    /// Position of the last cue the user was on — drives the Library
    /// progress display and resume-on-open.
    var lastCueIndex: Int?

    init(
        id: String = UUID().uuidString,
        source: SessionSource,
        title: String? = nil,
        youtubeURL: String? = nil,
        videoExt: String = "mp4",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.source = source
        self.title = title
        self.youtubeURL = youtubeURL
        self.videoExt = videoExt
        self.cues = []
        self.picks = []
        self.status = .pending
    }
}
