import Foundation

/// Loads, saves, lists and deletes sessions as JSON under Documents. Dates are
/// encoded as epoch-millis to match the desktop app's `number` timestamps.
@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [Session] = []

    static let shared = SessionStore()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }()

    init() {
        try? Storage.ensureDir(Storage.sessionsRoot)
        reload()
    }

    func reload() {
        let root = Storage.sessionsRoot
        let dirs = (try? Storage.fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil)) ?? []
        var loaded: [Session] = []
        for dir in dirs {
            let file = dir.appendingPathComponent("session.json")
            guard let data = try? Data(contentsOf: file),
                  let session = try? decoder.decode(Session.self, from: data)
            else { continue }
            loaded.append(session)
        }
        sessions = loaded.sorted { $0.createdAt > $1.createdAt }
    }

    /// Persist a session atomically and update the in-memory list.
    @discardableResult
    func save(_ session: Session) throws -> Session {
        var updated = session
        updated.updatedAt = Date()
        try Storage.ensureSessionDirs(updated.id)
        let data = try encoder.encode(updated)
        try data.write(to: Storage.sessionFile(updated.id), options: .atomic)
        if let i = sessions.firstIndex(where: { $0.id == updated.id }) {
            sessions[i] = updated
        } else {
            sessions.insert(updated, at: 0)
        }
        return updated
    }

    func session(_ sid: String) -> Session? {
        sessions.first { $0.id == sid }
    }

    func delete(_ sid: String) {
        try? Storage.fm.removeItem(at: Storage.sessionDir(sid))
        sessions.removeAll { $0.id == sid }
    }
}
