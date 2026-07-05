import Foundation

/// Seeds a small demo session with pre-tokenized cues so the review + pile +
/// export flow is usable before the live YouTube pipeline is wired in.
enum DemoSession {
    @discardableResult
    @MainActor
    static func create(into store: SessionStore) -> Session {
        var session = Session(source: .youtube, title: "Demo — 日本語の練習",
                              youtubeURL: "https://youtu.be/demo")
        session.status = .ready
        session.videoDurationMs = 12_000
        session.cues = [
            Cue(index: 0, startMs: 0, endMs: 3200,
                text: "毎日 日本語を 勉強します。",
                translation: "I study Japanese every day.",
                refinedTokens: [
                    RefinedToken(surface: "毎日", lemma: "毎日", reading: "まいにち", content: true),
                    RefinedToken(surface: " ", lemma: " ", reading: "", content: false),
                    RefinedToken(surface: "日本語", lemma: "日本語", reading: "にほんご", content: true),
                    RefinedToken(surface: "を", lemma: "を", reading: "", content: false),
                    RefinedToken(surface: " ", lemma: " ", reading: "", content: false),
                    RefinedToken(surface: "勉強", lemma: "勉強", reading: "べんきょう", content: true),
                    RefinedToken(surface: "します", lemma: "する", reading: "します", content: true),
                    RefinedToken(surface: "。", lemma: "。", reading: "", content: false),
                ]),
            Cue(index: 1, startMs: 3200, endMs: 7000,
                text: "昨日 面白い 映画を 見ました。",
                translation: "Yesterday I watched an interesting movie.",
                refinedTokens: [
                    RefinedToken(surface: "昨日", lemma: "昨日", reading: "きのう", content: true),
                    RefinedToken(surface: " ", lemma: " ", reading: "", content: false),
                    RefinedToken(surface: "面白い", lemma: "面白い", reading: "おもしろい", content: true),
                    RefinedToken(surface: " ", lemma: " ", reading: "", content: false),
                    RefinedToken(surface: "映画", lemma: "映画", reading: "えいが", content: true),
                    RefinedToken(surface: "を", lemma: "を", reading: "", content: false),
                    RefinedToken(surface: " ", lemma: " ", reading: "", content: false),
                    RefinedToken(surface: "見ました", lemma: "見る", reading: "みました", content: true),
                    RefinedToken(surface: "。", lemma: "。", reading: "", content: false),
                ]),
        ]
        return (try? store.save(session)) ?? session
    }
}
