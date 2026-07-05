import Foundation

/// Maps a session's picks into Anki notes and builds the `.apkg`. Ports the
/// field mapping from server/src/routes/export.ts.
enum ExportService {
    /// Build a deck for all (or only unexported) picks and return the file URL.
    static func build(session: Session, deckName: String) throws -> URL {
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
        return out
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
