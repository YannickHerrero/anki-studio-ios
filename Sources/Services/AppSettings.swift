import Foundation

struct ModelPreset: Identifiable, Hashable {
    let id: String    // OpenRouter model id
    let label: String
}

/// User settings: API keys (Keychain) + model / deck name (UserDefaults).
/// Mirrors the desktop settings store (client/src/stores/settings.ts).
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let modelPresets = [
        ModelPreset(id: "google/gemini-2.5-flash", label: "Gemini 2.5 Flash"),
        ModelPreset(id: "anthropic/claude-sonnet-4.6", label: "Claude Sonnet 4.6"),
    ]

    @Published var openrouterKey: String { didSet { Keychain.set(openrouterKey, for: "openrouter") } }
    @Published var openaiKey: String { didSet { Keychain.set(openaiKey, for: "openai") } }
    @Published var model: String { didSet { defaults.set(model, forKey: Keys.model) } }
    @Published var deckName: String { didSet { defaults.set(deckName, forKey: Keys.deckName) } }

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let model = "model"
        static let deckName = "deckName"
    }

    init() {
        openrouterKey = Keychain.get("openrouter")
        openaiKey = Keychain.get("openai")
        model = defaults.string(forKey: Keys.model) ?? AppSettings.modelPresets[0].id
        deckName = defaults.string(forKey: Keys.deckName) ?? "Anki Studio Export"
    }

    /// OpenRouter alone is enough for the LLM features.
    var isConfigured: Bool { !openrouterKey.trimmed.isEmpty }
    /// The YouTube flow also needs OpenAI (Whisper).
    var isYoutubeReady: Bool { !openrouterKey.trimmed.isEmpty && !openaiKey.trimmed.isEmpty }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
