import Foundation

struct WhisperWord: Codable, Equatable {
    var word: String
    var start: Double
    var end: Double
}

enum WhisperError: Error, LocalizedError {
    case tooLarge(Double)
    case api(Int, String)
    case empty

    var errorDescription: String? {
        switch self {
        case .tooLarge(let mb):
            return String(format: "Audio is %.1f MB — Whisper API limit is 25 MB. Pick a shorter video.", mb)
        case .api(let status, let body): return "whisper \(status): \(body)"
        case .empty: return "Whisper returned no segments."
        }
    }
}

/// OpenAI Whisper transcription. Port of server/src/lib/whisper.ts: uploads
/// the extracted audio as multipart form data, requests word + segment
/// timestamps, then splits each acoustic segment into single sentences using
/// punctuation and pauses.
enum WhisperService {
    private static let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

    // Whisper for long audio can take minutes — allow up to 15 for the request.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15 * 60
        config.timeoutIntervalForResource = 15 * 60
        return URLSession(configuration: config)
    }()

    struct Result {
        var cues: [Cue]
        var words: [WhisperWord]
    }

    private struct Segment: Decodable {
        var start: Double
        var end: Double
        var text: String
        var words: [WhisperWord]?
    }

    private struct VerboseJSON: Decodable {
        var segments: [Segment]?
        var words: [WhisperWord]?
    }

    static func transcribe(
        audio: URL, apiKey: String,
        language: String = "ja", pauseThresholdMs: Int = 400
    ) async throws -> Result {
        let data = try Data(contentsOf: audio)
        let mb = Double(data.count) / 1024 / 1024
        if mb > 25 { throw WhisperError.tooLarge(mb) }

        let boundary = "as-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(audio.lastPathComponent)\"\r\nContent-Type: audio/mp4\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n".utf8))
        field("model", "whisper-1")
        field("response_format", "verbose_json")
        // Word-level timestamps let us split each Whisper segment into single
        // sentences ourselves — Whisper groups by acoustic chunks, not grammar.
        field("timestamp_granularities[]", "word")
        field("timestamp_granularities[]", "segment")
        field("language", language)
        body.append(Data("--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let (responseData, response) = try await session.upload(for: request, from: body)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let text = String(decoding: responseData.prefix(200), as: UTF8.self)
            throw WhisperError.api(status, text)
        }

        let json = try JSONDecoder().decode(VerboseJSON.self, from: responseData)
        let segments = json.segments ?? []

        var cues: [Cue] = []
        var idx = 0
        for seg in segments {
            for s in splitSegmentBySentence(seg, pauseThresholdMs: pauseThresholdMs) {
                cues.append(Cue(index: idx, startMs: s.startMs, endMs: s.endMs, text: s.text))
                idx += 1
            }
        }
        let words = json.words ?? segments.flatMap { $0.words ?? [] }
        return Result(cues: cues, words: words)
    }

    // MARK: - Sentence splitting (whisper.ts splitSegmentBySentence)

    private struct Sentence {
        var startMs: Int
        var endMs: Int
        var text: String
    }

    private static let sentenceEnd: Set<Character> = ["。", "！", "？", "．", "!", "?"]

    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Split a Whisper segment into one-sentence chunks using word timestamps:
    /// on sentence-ending punctuation, or a pause longer than the threshold.
    /// Falls back to the whole segment when no word array is present.
    private static func splitSegmentBySentence(_ seg: Segment, pauseThresholdMs: Int) -> [Sentence] {
        let words = seg.words ?? []
        if words.isEmpty {
            let text = clean(seg.text)
            guard !text.isEmpty else { return [] }
            return [Sentence(
                startMs: max(0, Int((seg.start * 1000).rounded())),
                endMs: max(0, Int((seg.end * 1000).rounded())),
                text: text)]
        }

        var sentences: [Sentence] = []
        var buf: [WhisperWord] = []

        func flush() {
            guard !buf.isEmpty else { return }
            let text = clean(buf.map(\.word).joined())
            guard !text.isEmpty else { buf = []; return }
            let startMs = max(0, Int((buf[0].start * 1000).rounded()))
            let endMs = max(startMs + 1, Int((buf[buf.count - 1].end * 1000).rounded()))
            sentences.append(Sentence(startMs: startMs, endMs: endMs, text: text))
            buf = []
        }

        for (i, w) in words.enumerated() {
            buf.append(w)
            let next = i + 1 < words.count ? words[i + 1] : nil
            let gapMs = next.map { Int((($0.start - w.end) * 1000).rounded()) } ?? 0
            let endsSentence = w.word.trimmingCharacters(in: .whitespaces).last
                .map { sentenceEnd.contains($0) } ?? false
            let longPause = next != nil && gapMs >= pauseThresholdMs
            if endsSentence || longPause { flush() }
        }
        flush()
        return sentences
    }
}
