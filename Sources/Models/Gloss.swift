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
    /// Plain English meaning ("" for pure function words covered by `tag`).
    var meaning: String
    /// Dictionary form, only when it differs from the token.
    var base: String?
    /// Short grammatical label ("object particle", "honorific · past", …).
    var tag: String?

    enum CodingKeys: String, CodingKey {
        case token, reading, base, tag
        case meaning = "en"
        case legacyGloss = "gloss"
    }

    init(token: String, reading: String, meaning: String, base: String? = nil, tag: String? = nil) {
        self.token = token
        self.reading = reading
        self.meaning = meaning
        self.base = base
        self.tag = tag
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token = try c.decode(String.self, forKey: .token)
        reading = try c.decode(String.self, forKey: .reading)
        // New payloads use "en"; glosses cached before the carded redesign
        // stored the meaning (with bracketed grammar) under "gloss".
        meaning = try c.decodeIfPresent(String.self, forKey: .meaning)
            ?? c.decodeIfPresent(String.self, forKey: .legacyGloss)
            ?? ""
        base = try c.decodeIfPresent(String.self, forKey: .base)
        tag = try c.decodeIfPresent(String.self, forKey: .tag)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(token, forKey: .token)
        try c.encode(reading, forKey: .reading)
        try c.encode(meaning, forKey: .meaning)
        try c.encodeIfPresent(base, forKey: .base)
        try c.encodeIfPresent(tag, forKey: .tag)
    }
}
