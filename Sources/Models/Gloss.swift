import Foundation

/// Interlinear gloss of a sentence — the "Explain" feature. Ports
/// `SentenceGloss` and friends (server/src/lib/openrouter.ts).
struct SentenceGloss: Codable, Equatable {
    var chunks: [GlossChunk]
    /// Natural English translation of the whole sentence.
    var naturalTranslation: String
    /// One–two sentences on what the speaker is trying to convey.
    var intent: String
}

struct GlossChunk: Codable, Equatable {
    /// A meaningful chunk of the sentence (Japanese).
    var phrase: String
    /// Kana reading of the whole chunk.
    var reading: String
    var items: [GlossItem]
    /// Natural rendering of just this chunk (the "→" line).
    var translation: String
}

struct GlossItem: Codable, Equatable {
    /// The word / particle exactly as it appears in the chunk.
    var token: String
    /// Kana reading. Empty for particles/punctuation with no reading.
    var reading: String
    /// Literal gloss; conjugation / particle function noted in [brackets].
    var gloss: String
}
