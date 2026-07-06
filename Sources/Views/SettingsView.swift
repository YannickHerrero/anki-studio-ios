import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var usage: Storage.DiskUsage?

    var body: some View {
        // Pushed from the Library's gear button, so no NavigationStack of its own.
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
                    NavigationLink {
                        SessionStorageView()
                    } label: {
                        LabeledContent("Sessions" + (usage.map { " (\($0.sessionCount))" } ?? "")) {
                            sizeText(usage?.sessionsBytes)
                        }
                    }
                    LabeledContent("App data") {
                        sizeText(usage?.appDataBytes)
                    }
                    LabeledContent("App itself") {
                        sizeText(usage?.bundleBytes)
                    }
                } header: {
                    Text("Storage")
                } footer: {
                    Text("Sessions hold the downloaded videos, audio clips and screenshots — delete a video in the Library to reclaim its space. The app itself includes the offline dictionary.")
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
        .scrollContentBackground(.hidden)
        .background(Theme.page)
        .navigationTitle("Settings")
        .task {
            // Directory walks touch every media file — keep them off-main.
            usage = await Task.detached(priority: .utility) {
                Storage.diskUsage()
            }.value
        }
    }

    @ViewBuilder
    private func sizeText(_ bytes: Int64?) -> some View {
        if let bytes {
            Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                .foregroundStyle(Theme.muted)
        } else {
            ProgressView().controlSize(.small)
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
