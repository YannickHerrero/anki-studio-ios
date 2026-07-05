import Foundation

/// A chosen target word — one future Anki card. `id` is unique within a
/// session, so the same word picked from two cues yields two cards with
/// different example sentences. Ports `Pick` (server/src/lib/session.ts).
struct Pick: Codable, Identifiable, Equatable {
    var id: String
    var cueIndex: Int
    var lemma: String
    var surface: String
    var reading: String
    var addedAt: Date
    var exported: Bool = false
    /// LLM mining-value verdict: false = not worth learning; nil = unchecked.
    var interesting: Bool?
    /// Short reason for the mining-value verdict.
    var interestingReason: String?
    /// Filled at export time so re-export is cheap.
    var details: WordDetails?

    static func makeID(cueIndex: Int, lemma: String) -> String {
        "\(cueIndex)_\(lemma)"
    }
}

/// Context-aware dictionary info for a picked word, rendered into the card's
/// WordDetails field at export.
struct WordDetails: Codable, Equatable {
    /// Short, context-aware definition for the lemma as used in the sentence.
    var definition: String
    /// Canonical hiragana reading.
    var reading: String
    /// e.g. "[2]" — empty if unknown.
    var pitchPattern: String?
    /// "very common", "common", "uncommon", "rare".
    var frequency: String?
    var partOfSpeech: String?
    var usageNotes: String?
}
