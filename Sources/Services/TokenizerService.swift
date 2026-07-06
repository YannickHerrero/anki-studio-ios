import Foundation
import NaturalLanguage

/// On-device Japanese tokenization fallback. The pipeline's primary tokenizer
/// is the LLM refineTokenBatch (as on desktop, where kuromoji was only the
/// fallback); this uses Apple's NaturalLanguage framework instead of bundling
/// a mecab dictionary. Surfaces are exact substrings; lemmas fall back to the
/// surface when unavailable; content-ness comes from the lexical class.
enum TokenizerService {
    static func tokenize(_ sentence: String) -> [RefinedToken] {
        guard !sentence.isEmpty else { return [] }

        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.setLanguage(.japanese)
        tokenizer.string = sentence

        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma])
        tagger.string = sentence
        tagger.setLanguage(.japanese, range: sentence.startIndex..<sentence.endIndex)

        var tokens: [RefinedToken] = []
        var cursor = sentence.startIndex

        tokenizer.enumerateTokens(in: sentence.startIndex..<sentence.endIndex) { range, _ in
            // Preserve any inter-token characters (spaces, punctuation the
            // tokenizer skipped) so surfaces re-concatenate to the sentence.
            if cursor < range.lowerBound {
                let gap = String(sentence[cursor..<range.lowerBound])
                tokens.append(RefinedToken(surface: gap, lemma: gap, reading: "", content: false))
            }

            let surface = String(sentence[range])
            let (lexClass, _) = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lexicalClass)
            let (lemmaTag, _) = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma)
            let lemma = lemmaTag?.rawValue ?? surface

            tokens.append(RefinedToken(
                surface: surface,
                lemma: lemma.isEmpty ? surface : lemma,
                reading: "",
                content: isContent(lexClass, surface: surface)))
            cursor = range.upperBound
            return true
        }

        // Trailing punctuation after the last token.
        if cursor < sentence.endIndex {
            let tail = String(sentence[cursor...])
            tokens.append(RefinedToken(surface: tail, lemma: tail, reading: "", content: false))
        }
        return tokens
    }

    private static let contentClasses: Set<NLTag> = [
        .noun, .verb, .adjective, .adverb, .otherWord, .personalName, .placeName, .organizationName,
    ]

    /// Common particles / auxiliaries / copulas that should never be clickable
    /// vocab — the intent of kuromoji's POS filter on desktop (tokenizer.ts).
    private static let functionWords: Set<String> = [
        "は", "が", "を", "に", "で", "と", "も", "の", "へ", "や", "か", "よ",
        "ね", "な", "さ", "ぞ", "ぜ", "わ", "し", "て", "ば", "たら", "ん",
        "だ", "です", "ます", "まし", "ました", "た", "だっ", "でし", "う",
        "れ", "られ", "せ", "させ", "ない", "たい", "から", "まで", "より",
        "など", "って", "じゃ", "ちゃ", "けど", "けれど", "ながら", "のに",
        "ので", "こと", "もの",
    ]

    private static func isContent(_ tag: NLTag?, surface: String) -> Bool {
        let trimmed = surface.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if functionWords.contains(trimmed) { return false }
        // Pure punctuation / symbols are never content.
        let letters = trimmed.unicodeScalars.filter {
            !CharacterSet.punctuationCharacters.contains($0)
                && !CharacterSet.symbols.contains($0)
        }
        guard !letters.isEmpty else { return false }
        // Single pure-hiragana characters are function words in practice.
        let isHiragana: (Unicode.Scalar) -> Bool = { (0x3040...0x309F).contains(Int($0.value)) }
        if trimmed.count == 1, trimmed.unicodeScalars.allSatisfy(isHiragana) { return false }
        if let tag { return contentClasses.contains(tag) }
        return letters.contains { $0.value >= 0x3040 }
    }
}
