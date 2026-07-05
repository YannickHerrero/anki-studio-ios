import SwiftUI

/// The "Add from YouTube" screen. The live pipeline (download → transcribe →
/// translate → tokenize) is wired in a later milestone; for now the URL field
/// is present and a demo session can be seeded to exercise review + export.
struct IngestView: View {
    @ObservedObject private var store = SessionStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var url = ""

    private var urlLooksValid: Bool {
        url.contains("youtu.be/") || url.contains("youtube.com/watch")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("YouTube URL", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button {
                        // Live ingest lands in a later milestone.
                    } label: {
                        Label("Import video", systemImage: "arrow.down.circle")
                    }
                    .disabled(!urlLooksValid || !settings.isYoutubeReady)
                } header: {
                    Text("YouTube")
                } footer: {
                    if !settings.isYoutubeReady {
                        Text("Add your OpenAI and OpenRouter keys in Settings to enable import.")
                    } else {
                        Text("Downloads the video and builds cards entirely on-device.")
                    }
                }

                Section("Try it now") {
                    Button {
                        DemoSession.create(into: store)
                    } label: {
                        Label("Load demo session", systemImage: "sparkles")
                    }
                    Text("Seeds a short pre-tokenized session so you can try tapping words, building a pile, and exporting a deck.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !store.sessions.isEmpty {
                    Section("Sessions") {
                        ForEach(store.sessions) { session in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(session.title ?? "Untitled").font(.subheadline)
                                    Text("\(session.cues.count) lines · \(session.picks.count) picked")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            offsets.map { store.sessions[$0].id }.forEach(store.delete)
                        }
                    }
                }
            }
            .navigationTitle("Add")
        }
    }
}
