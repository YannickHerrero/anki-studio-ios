import Foundation

/// One subtitle line in a session: text + timing plus per-cue media and
/// enrichment state. Ports `Cue`/`SubtitleCue` from the desktop app
/// (server/src/lib/session.ts, subtitles.ts).
struct Cue: Codable, Identifiable, Equatable {
    var index: Int
    var startMs: Int
    var endMs: Int
    var text: String
    var translation: String?
    /// Freeform learner note, shown on the card back and editable in review.
    var note: String?

    var audioReady: Bool = false
    var screenshotReady: Bool = false

    /// When set, overrides the on-device tokenizer output for this cue.
    var refinedTokens: [RefinedToken]?
    /// Cached interlinear gloss, filled lazily by Explain / export so the LLM
    /// is never called twice for the same sentence.
    var gloss: SentenceGloss?

    var id: Int { index }

    var startSeconds: Double { Double(startMs) / 1000 }
    var endSeconds: Double { Double(endMs) / 1000 }
    var midSeconds: Double { Double(startMs + endMs) / 2000 }
}

/// A tokenized word with dictionary form + reading (from the LLM refine pass
/// or the on-device tokenizer).
struct RefinedToken: Codable, Equatable, Identifiable {
    var surface: String
    /// Dictionary form. For particles/punctuation, equal to `surface`.
    var lemma: String
    /// Hiragana reading. Empty when not applicable.
    var reading: String
    /// True for nouns/verbs/adjectives/adverbs/connectives.
    var content: Bool

    /// Stable enough for sheet presentation (same word → same entry anyway).
    var id: String { "\(surface)|\(lemma)" }
}
