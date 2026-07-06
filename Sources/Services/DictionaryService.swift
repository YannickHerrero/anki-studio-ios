import Foundation
import SQLite3

/// Offline JMdict lookups from the bundled SQLite (Scripts/build-jmdict.py).
/// This is the yomitan-style popup dictionary: tap a token, get entries.
/// Deinflection is mostly unnecessary because tokens carry their dictionary
/// form (lemma); a longest-prefix fallback covers the rest.
final class DictionaryService {
    struct Sense: Identifiable {
        let id: Int
        var partOfSpeech: String
        var gloss: String
    }

    struct Entry: Identifiable {
        let id: Int
        var kanji: String
        var kana: String
        var isCommon: Bool
        var senses: [Sense]
    }

    static let shared = DictionaryService()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "dictionary.lookup")

    /// `databaseURL` is injectable for tests; the app uses the bundled copy.
    init(databaseURL: URL? = nil) {
        guard let url = databaseURL
            ?? Bundle.main.url(forResource: "jmdict", withExtension: "sqlite") else {
            assertionFailure("jmdict.sqlite missing from bundle — run Scripts/build-jmdict.py")
            return
        }
        var handle: OpaquePointer?
        if sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
            db = handle
        }
    }

    var isAvailable: Bool { db != nil }

    /// Look up a token: exact match on the lemma, then the surface, then
    /// longest matching prefix of the surface (conjugated leftovers).
    /// Common entries sort first.
    func lookup(lemma: String, surface: String) async -> [Entry] {
        await withCheckedContinuation { cont in
            queue.async { [self] in
                var candidates = [lemma, surface]
                var trimmed = surface
                while trimmed.count > 1 {
                    trimmed = String(trimmed.dropLast())
                    candidates.append(trimmed)
                }
                for form in candidates where !form.isEmpty {
                    let found = query(form: form)
                    if !found.isEmpty {
                        cont.resume(returning: found)
                        return
                    }
                }
                cont.resume(returning: [])
            }
        }
    }

    private func query(form: String) -> [Entry] {
        guard let db else { return [] }
        let sql = """
        SELECT e.id, e.kanji, e.kana, e.common, e.senses
        FROM forms f JOIN entries e ON e.id = f.entry_id
        WHERE f.form = ? ORDER BY e.common DESC, e.id LIMIT 8
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, form, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        var entries: [Entry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = Int(sqlite3_column_int64(stmt, 0))
            let kanji = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let kana = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let common = sqlite3_column_int(stmt, 3) == 1
            let sensesBlob = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""

            let senses = sensesBlob.split(separator: "\n").enumerated().map { i, line -> Sense in
                let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
                return Sense(
                    id: i,
                    partOfSpeech: parts.count == 2 ? parts[0] : "",
                    gloss: parts.count == 2 ? parts[1] : parts.first ?? "")
            }
            entries.append(Entry(id: id, kanji: kanji, kana: kana, isCommon: common, senses: senses))
        }
        return entries
    }
}
