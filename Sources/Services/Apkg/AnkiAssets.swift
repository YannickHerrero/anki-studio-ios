import Foundation

/// Loads the Anki card templates + CSS bundled under Resources/anki. Mirrors
/// the desktop `readAnkiAssets()` (server/src/lib/ankiAssets.ts).
enum AnkiAssets {
    struct Templates {
        let front: String
        let back: String
        let css: String
    }

    static func load() -> Templates {
        Templates(
            front: read("front", "html"),
            back: read("back", "html"),
            css: read("styling", "css")
        )
    }

    private static func read(_ name: String, _ ext: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            assertionFailure("Missing bundled Anki asset: \(name).\(ext)")
            return ""
        }
        return text
    }
}
