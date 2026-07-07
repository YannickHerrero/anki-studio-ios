import Foundation

/// Builds the deck from a session's picks — after enriching them with the
/// LLM, like the desktop export route: word details for every pick (batched)
/// and an interlinear gloss for every unique cue that doesn't have one yet.
/// Enrichment results are persisted so re-exports and the Explain sheet
/// reuse them for free.
enum ExportService {
    enum Stage {
        case words(done: Int, total: Int)
        case glosses(done: Int, total: Int)
        case packaging

        var label: String {
            switch self {
            case .words(let d, let t): return "Word details \(d)/\(t)"
            case .glosses(let d, let t): return "Explanations \(d)/\(t)"
            case .packaging: return "Building deck"
            }
        }
    }

    /// Enrich + build. Returns the deck URL and the enriched session (the
    /// caller persists it). Gloss failures are non-fatal — that card just
    /// ships without a Grammar section.
    @MainActor
    static func build(
        session: Session,
        deckName: String,
        llm: OpenRouterService.Options,
        onProgress: @escaping (Stage) -> Void
    ) async throws -> (url: URL, session: Session) {
        var session = session
        let cueByIndex = Dictionary(session.cues.map { ($0.index, $0) },
                                    uniquingKeysWith: { a, _ in a })

        // 1. Word details, ~20 picks per call, skipping already-enriched ones.
        let needing = session.picks.enumerated().filter { $0.element.details == nil }
        let batchSize = 20
        var done = 0
        onProgress(.words(done: 0, total: needing.count))
        var start = 0
        while start < needing.count {
            let slice = Array(needing[start..<min(start + batchSize, needing.count)])
            let items = slice.map { (
                lemma: $0.element.lemma,
                surface: $0.element.surface,
                sentence: cueByIndex[$0.element.cueIndex]?.text ?? ""
            ) }
            let details = try await OpenRouterService.enrichWordBatch(items, opts: llm)
            for (offset, entry) in slice.enumerated() where offset < details.count {
                session.picks[entry.offset].details = details[offset]
            }
            start += slice.count
            done += slice.count
            onProgress(.words(done: done, total: needing.count))
        }

        // 2. Glosses for unique cues that were never explained.
        let uniqueCues = Array(Set(session.picks.map(\.cueIndex))).sorted()
        let missingGloss = uniqueCues.filter { idx in
            session.cues.first(where: { $0.index == idx })?.gloss == nil
        }
        done = 0
        onProgress(.glosses(done: 0, total: missingGloss.count))
        for cueIndex in missingGloss {
            guard let i = session.cues.firstIndex(where: { $0.index == cueIndex }) else { continue }
            if let gloss = try? await OpenRouterService.glossSentence(
                session.cues[i].text, opts: llm) {
                session.cues[i].gloss = gloss
            }
            done += 1
            onProgress(.glosses(done: done, total: missingGloss.count))
        }

        // 3. Package.
        onProgress(.packaging)
        let templates = AnkiAssets.load()
        let safeName = deckName.trimmed.isEmpty ? "Anki Studio Export" : deckName.trimmed
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName).apkg")
        try? FileManager.default.removeItem(at: out)
        try ApkgService.build(
            deckName: safeName,
            notes: notes(for: session),
            front: templates.front,
            back: templates.back,
            css: templates.css,
            outURL: out
        )
        return (out, session)
    }

    static func notes(for session: Session) -> [ApkgNote] {
        let cueByIndex = Dictionary(session.cues.map { ($0.index, $0) },
                                    uniquingKeysWith: { a, _ in a })
        let sid8 = String(session.id.replacingOccurrences(of: "-", with: "").prefix(8))

        return session.picks.map { pick in
            let cue = cueByIndex[pick.cueIndex]
            let sentence = cue.map {
                AnkiFieldHTML.highlightTarget(in: $0.text, target: pick.surface)
            } ?? ""
            let translation = cue?.translation ?? cue?.gloss?.naturalTranslation ?? ""

            let audioURL = Storage.audioURL(session.id, pick.cueIndex)
            let shotURL = Storage.screenshotURL(session.id, pick.cueIndex)
            let hasAudio = FileManager.default.fileExists(atPath: audioURL.path)
            let hasShot = FileManager.default.fileExists(atPath: shotURL.path)

            return ApkgNote(
                targetWord: pick.surface,
                sentence: sentence,
                sentenceTranslation: translation,
                wordDetails: AnkiFieldHTML.wordDetails(
                    lemma: pick.lemma, reading: pick.reading, details: pick.details),
                grammar: cue?.gloss.map(AnkiFieldHTML.gloss) ?? "",
                noteText: cue?.note ?? "",
                guidSeed: "\(session.id):\(pick.id)",
                audioFilename: hasAudio ? "as_\(sid8)_\(pick.cueIndex).m4a" : nil,
                audioURL: hasAudio ? audioURL : nil,
                screenshotFilename: hasShot ? "as_\(sid8)_\(pick.cueIndex).jpg" : nil,
                screenshotURL: hasShot ? shotURL : nil
            )
        }
    }
}
