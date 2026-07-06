import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("OpenRouter API key", text: $settings.openrouterKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("OpenAI API key", text: $settings.openaiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("API keys")
                } footer: {
                    Text("OpenRouter powers translation and word analysis. OpenAI (Whisper) transcribes the video. Keys are stored in the Keychain.")
                }

                Section("LLM model") {
                    Picker("Model", selection: $settings.model) {
                        ForEach(AppSettings.modelPresets) { preset in
                            Text(preset.label).tag(preset.id)
                        }
                    }
                }

                Section("Export") {
                    TextField("Deck name", text: $settings.deckName)
                        .autocorrectionDisabled()
                }

                Section {
                    Text("Dictionary data from [JMdict](https://www.edrdg.org/jmdict/j_jmdict.html), property of the Electronic Dictionary Research and Development Group, used under the Group's licence.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("About")
                }

                Section("Status") {
                    LabeledContent("OpenRouter") {
                        StatusBadge(ok: settings.isConfigured,
                                    okText: "Ready", badText: "Missing key")
                    }
                    LabeledContent("YouTube flow") {
                        StatusBadge(ok: settings.isYoutubeReady,
                                    okText: "Ready", badText: "Needs both keys")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

private struct StatusBadge: View {
    let ok: Bool
    let okText: String
    let badText: String

    var body: some View {
        Text(ok ? okText : badText)
            .font(.subheadline)
            .foregroundStyle(ok ? Color.green : Color.orange)
    }
}

#Preview {
    SettingsView()
}
