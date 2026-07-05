import Foundation
import SQLite3
import CryptoKit

/// One Anki note to ship in the deck. Mirrors `ApkgNote` (server apkg.ts).
struct ApkgNote {
    var targetWord: String
    var sentence: String
    var sentenceTranslation: String
    var wordDetails: String
    var grammar: String
    var noteText: String = ""
    /// Stable guid seed — keeps the same Anki note across re-exports.
    var guidSeed: String
    var audioFilename: String?
    var audioURL: URL?
    var screenshotFilename: String?
    var screenshotURL: URL?
}

enum ApkgError: Error {
    case sqlite(String)
}

/// Builds an Anki `.apkg` entirely on-device: a `collection.anki2` SQLite DB
/// plus the legacy media zip (numeric-key files + a `media` JSON manifest).
/// Faithful port of server/src/lib/apkg.ts (no genanki, no AnkiConnect).
enum ApkgService {
    static let modelName = "Japanese Vocab Card"
    static let stableModelId: Int64 = 1_750_000_000_001

    static let fields = [
        "TargetWord", "Sentence", "SentenceTranslation", "Audio",
        "Screenshot", "WordDetails", "Grammar", "Notes",
    ]

    /// Build the deck at `outURL`. Returns nothing; throws on failure.
    static func build(
        deckName: String,
        notes: [ApkgNote],
        front: String,
        back: String,
        css: String,
        outURL: URL
    ) throws {
        let dbURL = outURL.appendingPathExtension("sqlite")
        try? FileManager.default.removeItem(at: dbURL)

        var handle: OpaquePointer?
        guard sqlite3_open(dbURL.path, &handle) == SQLITE_OK, let db = handle else {
            throw ApkgError.sqlite("open failed")
        }
        defer { sqlite3_close(db) }

        try exec(db, AnkiCollection.schema)

        let nowS = Int64(Date().timeIntervalSince1970)
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let modelId = stableModelId
        let deckId = nowMs

        let confJSON = try jsonString(AnkiCollection.defaultConf)
        let modelsJSON = try jsonString([
            String(modelId): AnkiCollection.model(
                id: modelId, deckId: deckId, name: modelName,
                fields: fields, front: front, back: back, css: css, mod: nowS),
        ])
        let decksJSON = try jsonString([
            "1": AnkiCollection.deck(id: 1, name: "Default", mod: nowS),
            String(deckId): AnkiCollection.deck(id: deckId, name: deckName, mod: nowS),
        ])
        let dconfJSON = try jsonString(AnkiCollection.defaultDconf)

        let colSQL = "INSERT INTO col VALUES (1, ?, ?, ?, 11, 0, 0, 0, ?, ?, ?, ?, '{}')"
        try run(db, colSQL) { stmt in
            sqlite3_bind_int64(stmt, 1, nowS)
            sqlite3_bind_int64(stmt, 2, nowMs)
            sqlite3_bind_int64(stmt, 3, nowMs)
            bindText(stmt, 4, confJSON)
            bindText(stmt, 5, modelsJSON)
            bindText(stmt, 6, decksJSON)
            bindText(stmt, 7, dconfJSON)
        }

        // Register media as numeric keys → real filenames (legacy apkg format).
        var mediaMap: [String: String] = [:]
        var mediaToCopy: [(key: String, url: URL)] = []
        var mediaIndex = 0
        func register(_ url: URL?, _ filename: String?) {
            guard let url, let filename else { return }
            let key = String(mediaIndex); mediaIndex += 1
            mediaMap[key] = filename
            mediaToCopy.append((key, url))
        }

        let noteSQL = "INSERT INTO notes VALUES (?, ?, ?, ?, -1, '', ?, ?, ?, 0, '')"
        let cardSQL = "INSERT INTO cards VALUES (?, ?, ?, 0, ?, -1, 0, 0, ?, 0, 0, 0, 0, 0, 0, 0, 0, '')"

        for (i, note) in notes.enumerated() {
            let noteId = nowMs + 100 + Int64(i) * 2
            let cardId = noteId + 1
            let guid = makeGuid(note.guidSeed)

            register(note.audioURL, note.audioFilename)
            register(note.screenshotURL, note.screenshotFilename)

            let audioField = note.audioFilename.map { "[sound:\($0)]" } ?? ""
            let screenshotField = note.screenshotFilename.map { "<img src=\"\($0)\" />" } ?? ""

            let flds = [
                note.targetWord, note.sentence, note.sentenceTranslation,
                audioField, screenshotField, note.wordDetails, note.grammar, note.noteText,
            ].joined(separator: "\u{1f}")

            try run(db, noteSQL) { stmt in
                sqlite3_bind_int64(stmt, 1, noteId)
                bindText(stmt, 2, guid)
                sqlite3_bind_int64(stmt, 3, modelId)
                sqlite3_bind_int64(stmt, 4, nowS)
                bindText(stmt, 5, flds)
                bindText(stmt, 6, note.targetWord)
                sqlite3_bind_int64(stmt, 7, fieldChecksum(note.targetWord))
            }
            try run(db, cardSQL) { stmt in
                sqlite3_bind_int64(stmt, 1, cardId)
                sqlite3_bind_int64(stmt, 2, noteId)
                sqlite3_bind_int64(stmt, 3, deckId)
                sqlite3_bind_int64(stmt, 4, nowS)
                sqlite3_bind_int64(stmt, 5, Int64(i))
            }
        }

        // Flush the DB to disk before zipping (no WAL: each INSERT auto-commits
        // to the main file, so it is already consistent here). The handle is
        // closed by the `defer` after zipping.
        sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_FULL, nil, nil)

        // Zip: collection.anki2 + media manifest + media files under numeric keys.
        let zip = try ZipWriter(url: outURL)
        try zip.addFile(name: "collection.anki2", fileURL: dbURL)
        let mediaJSON = try jsonString(mediaMap)
        try zip.addFile(name: "media", data: Data(mediaJSON.utf8))
        for entry in mediaToCopy {
            try zip.addFile(name: entry.key, fileURL: entry.url)
        }
        try zip.finish()

        try? FileManager.default.removeItem(at: dbURL)
        try? FileManager.default.removeItem(at: dbURL.appendingPathExtension("wal"))
        try? FileManager.default.removeItem(at: dbURL.appendingPathExtension("shm"))
    }

    // MARK: - Guid / checksum (port of apkg.ts makeGuid / fieldChecksum)

    private static let guidAlphabet = Array(
        "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%&()*+,-./:;<=>?@[]^_`{|}~")

    static func makeGuid(_ seed: String) -> String {
        let hash = Array(Insecure.SHA1.hash(data: Data(seed.utf8)))
        var n: UInt64 = 0
        for i in 0..<8 { n = (n << 8) | UInt64(hash[i]) }
        var out = ""
        let base = UInt64(guidAlphabet.count)
        for _ in 0..<10 {
            out = String(guidAlphabet[Int(n % base)]) + out
            n /= base
        }
        return out
    }

    static func fieldChecksum(_ value: String) -> Int64 {
        let stripped = value
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[sound:[^\\]]+\\]", with: "", options: .regularExpression)
        let hash = Array(Insecure.SHA1.hash(data: Data(stripped.utf8)))
        var v: Int64 = 0
        for i in 0..<4 { v = (v << 8) | Int64(hash[i]) }
        return v
    }

    // MARK: - SQLite helpers

    private static func exec(_ db: OpaquePointer, _ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "exec failed"
            sqlite3_free(err)
            throw ApkgError.sqlite(msg)
        }
    }

    private static func run(_ db: OpaquePointer, _ sql: String, bind: (OpaquePointer) -> Void) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw ApkgError.sqlite("prepare failed: \(String(cString: sqlite3_errmsg(db)))")
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw ApkgError.sqlite("step failed: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    private static func jsonString(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [])
        return String(decoding: data, as: UTF8.self)
    }
}

// SQLITE_TRANSIENT tells SQLite to copy bound text (Swift strings are transient).
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func bindText(_ stmt: OpaquePointer, _ index: Int32, _ value: String) {
    sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
}
