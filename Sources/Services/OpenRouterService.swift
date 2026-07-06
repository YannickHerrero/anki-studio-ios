import Foundation

enum OpenRouterError: Error, LocalizedError {
    case api(Int, String)
    case emptyContent

    var errorDescription: String? {
        switch self {
        case .api(let status, let body): return "openrouter \(status): \(body)"
        case .emptyContent: return "openrouter returned empty content"
        }
    }
}

/// OpenRouter LLM calls — translate, token refinement, sentence gloss, and
/// mining-value assessment. Prompts and JSON schemas are ported verbatim from
/// server/src/lib/openrouter.ts so cards match the desktop output.
enum OpenRouterService {
    private static let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5 * 60
        config.timeoutIntervalForResource = 10 * 60
        return URLSession(configuration: config)
    }()

    struct Options {
        var apiKey: String
        var model: String
        var appName: String = "Anki Studio iOS"
    }

    // MARK: - Core chat call with a strict JSON schema

    private static func chatJSON(
        system: String, user: String,
        schemaName: String, schema: [String: Any],
        opts: Options
    ) async throws -> Data {
        let body: [String: Any] = [
            "model": opts.model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": ["name": schemaName, "strict": true, "schema": schema],
            ],
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(opts.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("https://ankistudio.app", forHTTPHeaderField: "HTTP-Referer")
        request.setValue(opts.appName, forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw OpenRouterError.api(status, String(decoding: data.prefix(200), as: UTF8.self))
        }

        struct Chat: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { var content: String? }
                var message: Message
            }
            var choices: [Choice]?
        }
        guard let content = try JSONDecoder().decode(Chat.self, from: data)
            .choices?.first?.message.content, !content.isEmpty
        else { throw OpenRouterError.emptyContent }
        return Data(content.utf8)
    }

    // MARK: - Translation (openrouter.ts translateBatch, chunks of 50)

    private static let translateSystem = """
    You translate Japanese anime subtitles into natural English.
    You receive sentences as a numbered list. Use the surrounding sentences as context
    to disambiguate pronouns, register and references, but return EXACTLY ONE translation
    per numbered sentence. Never merge two sentences into one translation and never split
    one sentence into two. For each input sentence, return an object that echoes back its
    number as "index" and gives its "translation". The "index" MUST match the number shown
    to the left of the sentence. Keep translations concise and natural; preserve any named
    entities and proper nouns.
    """

    private static let translateSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "translations": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "index": ["type": "integer"],
                        "translation": ["type": "string"],
                    ],
                    "required": ["index", "translation"],
                    "additionalProperties": false,
                ],
            ],
        ],
        "required": ["translations"],
        "additionalProperties": false,
    ]

    /// Translate every sentence, matched back by explicit index. Failed slots
    /// stay "" rather than shifting the array.
    static func translateBatch(
        _ sentences: [String], opts: Options,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [String] {
        struct Out: Decodable {
            struct Entry: Decodable { var index: Int; var translation: String }
            var translations: [Entry]?
        }

        var out = Array(repeating: "", count: sentences.count)
        let chunkSize = 50
        var start = 0
        while start < sentences.count {
            let chunk = Array(sentences[start..<min(start + chunkSize, sentences.count)])
            let numbered = chunk.enumerated()
                .map { "\(start + $0.offset). \($0.element)" }
                .joined(separator: "\n")
            let data = try await chatJSON(
                system: translateSystem, user: numbered,
                schemaName: "transcript_translation", schema: translateSchema, opts: opts)
            for entry in (try JSONDecoder().decode(Out.self, from: data).translations ?? []) {
                // Match by echoed index, never array position.
                if entry.index >= start, entry.index < start + chunk.count {
                    out[entry.index] = entry.translation
                }
            }
            start += chunk.count
            onProgress?(min(start, sentences.count), sentences.count)
        }
        return out
    }

    // MARK: - Token refinement (openrouter.ts refineTokenBatch)

    private static let refineTokensSystem = """
    You re-tokenize Japanese subtitle sentences into a sequence of meaningful units.

    For each sentence:
    - The concatenation of token surfaces MUST exactly equal the input sentence (no extra characters, no missing characters).
    - Merge inflected verb / adjective forms into ONE token whose surface is the full conjugated form and lemma is the dictionary form. Examples: "食べました" → one token (lemma 食べる); "過ごしてました" → one token (lemma 過ごす); "大きかった" → one token (lemma 大きい).
    - Merge counters with their numbers: "4月" / "3時" / "5人" / "10年" → one token whose lemma equals the surface.
    - Keep proper nouns (names, places, brand names) as single tokens.
    - Particles (は / を / が / と / に / で / の / も / よ / ね / か), punctuation, and auxiliaries that didn't merge into a verb are separate tokens with content=false.

    You also receive an automatic tokenization as a hint. Use it as a starting point but correct over-segmentation, mis-tagged content, and missed proper-noun groupings. Do NOT invent words that aren't in the sentence.

    Return JSON matching the schema. Order: same as input. cueIndex must match the input index for each entry.
    """

    private static let refineTokensSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "cues": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "cueIndex": ["type": "integer"],
                        "tokens": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "surface": ["type": "string", "description": "Exact substring of the input sentence."],
                                    "lemma": ["type": "string", "description": "Dictionary form of the word. For particles / punctuation, copy surface."],
                                    "reading": ["type": "string", "description": "Hiragana reading of the lemma. Empty string if N/A."],
                                    "content": ["type": "boolean", "description": "true for nouns / verbs / adjectives / adverbs / proper nouns / counters that should be clickable as vocab; false for particles, auxiliaries, punctuation."],
                                ],
                                "required": ["surface", "lemma", "reading", "content"],
                                "additionalProperties": false,
                            ],
                        ],
                    ],
                    "required": ["cueIndex", "tokens"],
                    "additionalProperties": false,
                ],
            ],
        ],
        "required": ["cues"],
        "additionalProperties": false,
    ]

    /// Tokenize a batch of cues, feeding the local tokenization as a hint
    /// (as the desktop feeds kuromoji's). Entries whose surfaces don't
    /// re-concatenate to the source sentence are dropped (model corrupted
    /// them); non-Japanese tokens are never content (desktop HAS_JAPANESE).
    static func refineTokenBatch(
        _ items: [(cueIndex: Int, sentence: String, hint: [RefinedToken])], opts: Options
    ) async throws -> [Int: [RefinedToken]] {
        guard !items.isEmpty else { return [:] }

        struct Out: Decodable {
            struct Entry: Decodable { var cueIndex: Int; var tokens: [RefinedToken] }
            var cues: [Entry]?
        }

        let numbered = items
            .map { item in
                let hint = item.hint
                    .map { "\($0.surface)(\($0.content ? "content" : "func"))" }
                    .joined(separator: " ")
                return "cueIndex=\(item.cueIndex)\nsentence=\(item.sentence)\nhint=\(hint)"
            }
            .joined(separator: "\n---\n")
        let data = try await chatJSON(
            system: refineTokensSystem, user: numbered,
            schemaName: "refined_tokens_batch", schema: refineTokensSchema, opts: opts)

        let sourceByIdx = Dictionary(items.map { ($0.cueIndex, $0.sentence) },
                                     uniquingKeysWith: { a, _ in a })
        var out: [Int: [RefinedToken]] = [:]
        for entry in (try JSONDecoder().decode(Out.self, from: data).cues ?? []) {
            guard let source = sourceByIdx[entry.cueIndex], !entry.tokens.isEmpty else { continue }
            let concat = entry.tokens.map(\.surface).joined()
            guard concat == source else { continue } // Drop — surfaces corrupted.
            out[entry.cueIndex] = entry.tokens.map { token in
                var t = token
                let hasJapanese = t.surface.unicodeScalars.contains {
                    (0x3040...0x30FF).contains(Int($0.value)) || (0x4E00...0x9FFF).contains(Int($0.value))
                }
                if !hasJapanese { t.content = false }
                return t
            }
        }
        return out
    }

    // MARK: - Interlinear gloss (openrouter.ts glossSentence — the Explain tab)

    private static let glossSystem = """
    You are a Japanese tutor producing an interlinear gloss for a flashcard.
    Given one Japanese sentence, break it into meaningful chunks. For each chunk give:
    - the chunk exactly as written (phrase) and its kana reading,
    - a short natural translation of just this chunk (translation),
    - a word-by-word breakdown (items), in order.
    For each word in the breakdown:
    - token: the word exactly as it appears in the chunk.
    - reading: kana reading. Empty string for punctuation.
    - base: the dictionary form, ONLY when it differs from the token (conjugated verbs/adjectives). Else empty string.
    - en: the plain English meaning, with no grammar notes. Empty string for pure function words whose role is fully captured by the tag.
    - tag: a short grammatical label when useful — e.g. "topic particle", "object particle", "attributive adj", "honorific · past", "conditional", "nominalizer", "て-form". Else empty string.
    Split compound forms (て-form, たら, させる, …) into separate items rather than glossing them as one unit.
    Then give one natural translation of the whole sentence (naturalTranslation) and a one–two sentence note on what the speaker is trying to convey (intent).
    Use kana for ALL readings — never romaji. Be concise. Return JSON that matches the schema.
    """

    private static let glossSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "chunks": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "phrase": ["type": "string"],
                        "reading": ["type": "string", "description": "Kana reading of the whole chunk. Never romaji."],
                        "items": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "token": ["type": "string"],
                                    "reading": ["type": "string"],
                                    "base": ["type": "string", "description": "Dictionary form when it differs from token, else empty."],
                                    "en": ["type": "string", "description": "Plain English meaning, no grammar notes."],
                                    "tag": ["type": "string", "description": "Short grammatical label, else empty."],
                                ],
                                "required": ["token", "reading", "base", "en", "tag"],
                                "additionalProperties": false,
                            ],
                        ],
                        "translation": ["type": "string"],
                    ],
                    "required": ["phrase", "reading", "items", "translation"],
                    "additionalProperties": false,
                ],
            ],
            "naturalTranslation": ["type": "string"],
            "intent": ["type": "string"],
        ],
        "required": ["chunks", "naturalTranslation", "intent"],
        "additionalProperties": false,
    ]

    static func glossSentence(_ sentence: String, opts: Options) async throws -> SentenceGloss {
        let data = try await chatJSON(
            system: glossSystem, user: sentence,
            schemaName: "sentence_gloss", schema: glossSchema, opts: opts)
        return try JSONDecoder().decode(SentenceGloss.self, from: data)
    }

    // MARK: - Mining-value verdict (openrouter.ts assessMiningValue)

    private static let mineSystem = """
    You help a Japanese learner decide whether a word is worth making an Anki flashcard for.
    You are given one sentence and one target word from it. Judge whether learning this specific word is a good use of study time.
    Set interesting=false when the word is not worth mining: very common function words and particles, trivial words almost every learner already knows, numbers, or proper nouns (names of people/places/brands). Set interesting=true for content words that carry real meaning and are worth adding.
    Give a short (max ~12 words) reason. Return JSON that matches the schema.
    """

    private static let mineSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["interesting", "reason"],
        "properties": [
            "interesting": ["type": "boolean"],
            "reason": ["type": "string"],
        ],
    ]

    struct MineVerdict: Decodable {
        var interesting: Bool
        var reason: String
    }

    static func assessMiningValue(
        sentence: String, word: String, opts: Options
    ) async throws -> MineVerdict {
        let data = try await chatJSON(
            system: mineSystem, user: "Sentence: \(sentence)\nWord: \(word)",
            schemaName: "mine_verdict", schema: mineSchema, opts: opts)
        return try JSONDecoder().decode(MineVerdict.self, from: data)
    }
}
