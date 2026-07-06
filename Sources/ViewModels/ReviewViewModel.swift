import Foundation

/// Drives the review screen: the current cue, tap-selection of tokens, and
/// committing selected words to the pile. Mirrors the desktop ReviewView's
/// pick flow but touch-first.
@MainActor
final class ReviewViewModel: ObservableObject {
    @Published var session: Session
    @Published var index: Int = 0
    @Published private(set) var selection: Set<Int> = []

    private let store: SessionStore

    init(session: Session, store: SessionStore = .shared) {
        self.session = session
        self.store = store
    }

    var current: Cue? {
        session.cues.indices.contains(index) ? session.cues[index] : nil
    }

    var tokens: [RefinedToken] {
        current?.refinedTokens ?? []
    }

    var canPrev: Bool { index > 0 }
    var canNext: Bool { index < session.cues.count - 1 }

    func isSelected(_ i: Int) -> Bool { selection.contains(i) }

    func toggle(_ i: Int) {
        if selection.contains(i) { selection.remove(i) } else { selection.insert(i) }
    }

    func next() {
        guard canNext else { return }
        index += 1
        selection = []
        session.lastCueIndex = index
    }

    func prev() {
        guard canPrev else { return }
        index -= 1
        selection = []
        session.lastCueIndex = index
    }

    /// Persist the reading position (called when leaving the screen, so
    /// navigation taps don't each rewrite the session file).
    func saveProgress() {
        session.lastCueIndex = index
        persist()
    }

    /// Lemmas already in the pile for the current cue (shown as "added").
    var pickedLemmasForCurrent: Set<String> {
        guard let cue = current else { return [] }
        return Set(session.picks.filter { $0.cueIndex == cue.index }.map(\.lemma))
    }

    var selectedCount: Int { selection.count }

    /// Add the selected tokens to the pile, de-duplicating by (cue, lemma).
    func commitPicks() {
        guard let cue = current else { return }
        var changed = false
        for i in selection.sorted() where tokens.indices.contains(i) {
            let token = tokens[i]
            let id = Pick.makeID(cueIndex: cue.index, lemma: token.lemma)
            if session.picks.contains(where: { $0.id == id }) { continue }
            session.picks.append(
                Pick(id: id, cueIndex: cue.index, lemma: token.lemma,
                     surface: token.surface, reading: token.reading, addedAt: Date()))
            changed = true
        }
        selection = []
        if changed { persist() }
    }

    func removePick(_ id: String) {
        session.picks.removeAll { $0.id == id }
        persist()
    }

    /// Cache a generated gloss on its cue so Explain and export reuse it.
    func setGloss(_ gloss: SentenceGloss, forCueIndex cueIndex: Int) {
        guard let i = session.cues.firstIndex(where: { $0.index == cueIndex }) else { return }
        session.cues[i].gloss = gloss
        persist()
    }

    private func persist() {
        if let saved = try? store.save(session) { session = saved }
    }
}
