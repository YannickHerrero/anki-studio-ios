import Foundation
import NaturalLanguage

/// On-device Japanese tokenization fallback, mirroring the desktop kuromoji
/// pipeline (server/src/lib/tokenizer.ts):
///  - segment with CFStringTokenizer (MeCab-backed, supplies readings),
///  - re-glue auxiliary suffixes onto verb/adjective stems (食べ+まし+た →
///    食べました) and numbers onto counters (4+月 → 4月),
///  - POS-style content filter: nouns/verbs/adjectives/adverbs/interjections/
///    demonstratives plus a copula whitelist; must contain Japanese; bare
///    numbers excluded.
/// The pipeline's primary tokenizer is still the LLM refineTokenBatch — this
/// output also feeds it as the tokenization hint (as kuromoji does on desktop).
enum TokenizerService {
    // MARK: - Public API

    static func tokenize(_ sentence: String) -> [RefinedToken] {
        guard !sentence.isEmpty else { return [] }
        let raw = segment(sentence)
        let merged = fuseCompoundParticles(mergeAuxiliaries(raw))
        return merged.map { piece in
            RefinedToken(
                surface: piece.surface,
                lemma: piece.lemma.isEmpty ? piece.surface : piece.lemma,
                reading: piece.reading,
                content: isContent(piece))
        }
    }

    // MARK: - Segmentation

    private struct Piece {
        var surface: String
        var lemma: String
        var reading: String
        var tag: NLTag?
        var wasMergedInto = false
    }

    /// CFStringTokenizer word segmentation + Latin transcription → hiragana
    /// readings; NLTagger supplies lexical class + lemma per token.
    private static func segment(_ sentence: String) -> [Piece] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma])
        tagger.string = sentence
        tagger.setLanguage(.japanese, range: sentence.startIndex..<sentence.endIndex)

        let cf = sentence as CFString
        let tokenizer = CFStringTokenizerCreate(
            nil, cf, CFRange(location: 0, length: CFStringGetLength(cf)),
            kCFStringTokenizerUnitWordBoundary,
            Locale(identifier: "ja") as CFLocale)

        var pieces: [Piece] = []
        var cursor = sentence.startIndex

        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            guard let swiftRange = Range(NSRange(location: range.location, length: range.length), in: sentence)
            else { continue }

            // Preserve skipped characters (spaces, some punctuation) so the
            // surfaces always re-concatenate to the exact sentence.
            if cursor < swiftRange.lowerBound {
                let gap = String(sentence[cursor..<swiftRange.lowerBound])
                pieces.append(Piece(surface: gap, lemma: gap, reading: "", tag: nil))
            }

            let surface = String(sentence[swiftRange])
            let latin = CFStringTokenizerCopyCurrentTokenAttribute(
                tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String
            let reading = hiragana(fromLatin: latin, surface: surface)

            let (tag, _) = tagger.tag(at: swiftRange.lowerBound, unit: .word, scheme: .lexicalClass)
            let (lemmaTag, _) = tagger.tag(at: swiftRange.lowerBound, unit: .word, scheme: .lemma)

            pieces.append(Piece(
                surface: surface,
                lemma: lemmaTag?.rawValue ?? surface,
                reading: reading,
                tag: tag))
            cursor = swiftRange.upperBound
        }

        if cursor < sentence.endIndex {
            let tail = String(sentence[cursor...])
            pieces.append(Piece(surface: tail, lemma: tail, reading: "", tag: nil))
        }
        return pieces
    }

    /// Reading via the tokenizer's Latin transcription, converted to hiragana.
    /// Skipped for non-Japanese tokens (romaji of ASCII is noise).
    private static func hiragana(fromLatin latin: String?, surface: String) -> String {
        guard containsJapanese(surface), let latin, !latin.isEmpty else { return "" }
        let kana = latin.applyingTransform(.latinToHiragana, reverse: false) ?? ""
        // Keep only clean kana output; drop mixed garbage.
        return kana.allSatisfy { $0.isHiragana || $0 == "ー" } ? kana : ""
    }

    // MARK: - Auxiliary / counter merging (tokenizer.ts mergeAuxiliaries)

    /// Grammar suffixes that glue onto a preceding verb/adjective stem —
    /// the IPADIC 助動詞 + non-independent verb set, by surface.
    private static let auxSurfaces: Set<String> = [
        "ます", "まし", "ました", "ましょ", "ましょう", "ません", "た", "だ", "て", "で",
        "ない", "なかっ", "なく", "ぬ", "ん", "う", "よう", "れ", "られ",
        "せ", "させ", "たい", "たく", "たかっ", "そう", "まい",
        "ちゃっ", "ちゃう", "じゃっ", "だっ", "でし",
    ]
    /// て/で are 助詞 in IPADIC and stay separate on desktop.
    private static let neverMerge: Set<String> = ["て", "で"]

    /// Name/person suffixes that glue onto the preceding noun (皆+さん).
    private static let nounSuffixes: Set<String> = ["さん", "ちゃん", "くん", "様", "たち", "達"]

    /// Multi-char particles kuromoji emits as ONE token but CFStringTokenizer
    /// splits (では / には / とは / ので) — re-fuse the pairs.
    private static let particleFusions: Set<String> = ["では", "には", "とは", "ので"]

    /// Common counters for number+counter re-gluing (4月, 3時, 5人 …).
    private static let counters: Set<String> = [
        "月", "時", "分", "秒", "人", "年", "日", "回", "個", "本", "枚",
        "台", "円", "歳", "才", "杯", "冊", "匹", "頭", "羽", "着", "足",
        "軒", "階", "番", "度", "点", "名", "件", "歩",
    ]

    private static func mergeAuxiliaries(_ pieces: [Piece]) -> [Piece] {
        guard pieces.count >= 2 else { return pieces }
        var out: [Piece] = []
        for piece in pieces {
            if let prev = out.last, shouldMerge(prev: prev, next: piece) {
                var merged = prev
                let isCounter = isNumber(prev.surface) && counters.contains(piece.surface)
                let isKatakanaRun = isKatakana(prev.surface) && isKatakana(piece.surface)
                merged.surface = prev.surface + piece.surface
                merged.reading = prev.reading.isEmpty && piece.reading.isEmpty
                    ? "" : prev.reading + piece.reading
                if isCounter || isKatakanaRun {
                    // The fused form IS the dictionary form (4月 / ガジェットポーチ),
                    // and stays a noun — it must NOT start absorbing auxiliaries.
                    merged.lemma = merged.surface
                    merged.tag = .noun
                } else {
                    // Verb/adjective chains keep absorbing suffixes (まし+た).
                    merged.wasMergedInto = true
                }
                out[out.count - 1] = merged
            } else {
                out.append(piece)
            }
        }
        return out
    }

    private static func shouldMerge(prev: Piece, next: Piece) -> Bool {
        // 4 + 月 / 3 + 時 — number + counter.
        if isNumber(prev.surface), counters.contains(next.surface) { return true }
        // Adjacent katakana runs form one word (ガジェット+ポーチ) — kuromoji's
        // unknown-word handling does the same.
        if isKatakana(prev.surface), isKatakana(next.surface) { return true }
        // 皆 + さん — noun + person suffix.
        if nounSuffixes.contains(next.surface), containsJapanese(prev.surface),
           !isParticle(prev.surface), !auxSurfaces.contains(prev.surface) {
            return true
        }
        // で + は → では etc. — particles kuromoji keeps fused.
        if particleFusions.contains(prev.surface + next.surface) { return true }
        // です merges onto adjectives (ほしいです) but stays separate after
        // nouns (トバログです) — kuromoji's stem rule.
        if next.surface == "です" || next.surface == "でし" {
            return prev.tag == .adjective
        }
        // Verb/adjective stem + auxiliary suffix (or a chain of them).
        guard auxSurfaces.contains(next.surface), !neverMerge.contains(next.surface) else {
            return false
        }
        if neverMerge.contains(prev.surface) || isParticle(prev.surface) { return false }
        let prevIsStem = prev.tag == .verb || prev.tag == .adjective || prev.wasMergedInto
        // Conjugated stems the tagger missed: kanji + trailing hiragana (思い,
        // 見せ) — kuromoji knows these are verb stems; approximate by shape.
        let prevLooksConjugated = containsKanji(prev.surface)
            && (prev.surface.last?.isHiragana ?? false)
        // Single/double-hiragana non-independent verbs (い of ている, し of する).
        let prevIsTinyVerb = prev.surface.count <= 2
            && prev.surface.allSatisfy(\.isHiragana)
            && containsJapanese(prev.surface)
            && !auxSurfaces.contains(prev.surface)
        return prevIsStem || prevLooksConjugated || prevIsTinyVerb
    }

    /// Compound function phrases IPADIC keeps as one token (という, について)
    /// but CFStringTokenizer splits — greedily re-fuse runs of up to three
    /// adjacent pieces. Fused results are function words (non-content).
    private static let compoundParticles: Set<String> = [
        "という", "について", "にとって", "によって", "としては", "としても",
        "に対して", "を通して",
    ]

    private static func fuseCompoundParticles(_ pieces: [Piece]) -> [Piece] {
        var out: [Piece] = []
        var i = 0
        while i < pieces.count {
            var fused = false
            for span in stride(from: min(3, pieces.count - i), through: 2, by: -1) {
                let joined = pieces[i..<(i + span)].map(\.surface).joined()
                if compoundParticles.contains(joined) {
                    var piece = pieces[i]
                    piece.surface = joined
                    piece.lemma = joined
                    piece.reading = ""
                    piece.tag = .particle
                    piece.wasMergedInto = false
                    out.append(piece)
                    i += span
                    fused = true
                    break
                }
            }
            if !fused {
                out.append(pieces[i])
                i += 1
            }
        }
        return out
    }

    // MARK: - Content filter (tokenizer.ts CONTENT_POS + rules)

    private static let contentClasses: Set<NLTag> = [
        .noun, .verb, .adjective, .adverb, .otherWord, .interjection,
        .pronoun, .determiner, .personalName, .placeName, .organizationName,
    ]

    /// Copulas that ARE vocab when standing alone (tokenizer.ts COPULA_LEMMAS).
    /// な is the adnominal form of だ — desktop surfaces it as content too.
    private static let copulas: Set<String> = [
        "です", "だ", "な", "だっ", "でし", "だろう", "でしょう", "らしい",
        "ようだ", "みたいだ",
    ]

    /// Conjunctions (接続詞) — kuromoji's CONTENT_POS excludes them.
    private static let conjunctions: Set<String> = [
        "じゃあ", "じゃ", "そして", "しかし", "だから", "それで", "それでは",
        "でも", "また", "つまり", "ただ", "なので",
    ]

    /// Particles are never content, whatever NL tags them as.
    private static let particles: Set<String> = [
        "は", "が", "を", "に", "で", "と", "も", "の", "へ", "や", "か",
        "よ", "ね", "さ", "ぞ", "ぜ", "わ", "から", "まで", "より",
        "ので", "のに", "けど", "けれど", "って", "ば", "たら", "ながら",
        "て", "たり", "とか", "でも", "には", "では", "とは", "への",
    ]

    private static func isContent(_ piece: Piece) -> Bool {
        let s = piece.surface.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return false }
        // Desktop HAS_JAPANESE rule: ASCII brand names / numbers aren't vocab.
        guard containsJapanese(s) else { return false }
        if isNumber(s) { return false }
        if copulas.contains(s) || copulas.contains(piece.lemma) { return true }
        if particles.contains(s) || conjunctions.contains(s) { return false }
        if compoundParticles.contains(s) { return false }
        if auxSurfaces.contains(s) && !piece.wasMergedInto { return false }
        // Lone hiragana (honorific お, stray し, sentence particles) — never
        // vocab unless whitelisted above.
        if s.count == 1, s.allSatisfy(\.isHiragana) { return false }
        // Merged verb forms (食べました) are content even if the stem tag got lost.
        if piece.wasMergedInto { return true }
        if let tag = piece.tag { return contentClasses.contains(tag) }
        // Untagged: kanji/katakana words count, lone hiragana doesn't.
        return s.unicodeScalars.contains { $0.value >= 0x30A0 || $0.value >= 0x4E00 }
    }

    // MARK: - Character helpers

    private static func containsJapanese(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x3040...0x30FF).contains(Int($0.value)) || (0x4E00...0x9FFF).contains(Int($0.value)) }
    }

    private static func containsKanji(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x4E00...0x9FFF).contains(Int($0.value)) }
    }

    private static func isNumber(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { "0123456789０１２３４５６７８９一二三四五六七八九十百千万".contains($0) }
    }

    private static func isParticle(_ s: String) -> Bool {
        particles.contains(s)
    }

    private static func isKatakana(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy {
            (0x30A0...0x30FF).contains(Int($0.value)) || $0 == "ー"
        }
    }
}

private extension Character {
    var isHiragana: Bool {
        unicodeScalars.allSatisfy { (0x3040...0x309F).contains(Int($0.value)) }
    }
}
