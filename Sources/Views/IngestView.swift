import SwiftUI

/// The "Add from YouTube" screen: paste a URL and run the full on-device
/// pipeline (download → transcribe → translate → tokenize → cut media).
struct IngestView: View {
    @ObservedObject private var store = SessionStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var run = IngestRun()
    @State private var url = ""

    private var urlLooksValid: Bool {
        YouTubeService.videoID(from: url) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("YouTube URL", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .disabled(run.isRunning)
                    Button {
                        Task { await run.run(urlString: url, settings: settings) }
                    } label: {
                        Label("Import video", systemImage: "arrow.down.circle")
                    }
                    .disabled(!urlLooksValid || !settings.isYoutubeReady || run.isRunning)
                } header: {
                    Text("YouTube")
                } footer: {
                    if !settings.isYoutubeReady {
                        Text("Add your OpenAI and OpenRouter keys in Settings to enable import.")
                    } else {
                        Text("Downloads the video and builds cards entirely on-device.")
                    }
                }

                if run.isRunning || run.phase == .failed {
                    Section("Progress") {
                        HStack {
                            if run.isRunning { ProgressView().padding(.trailing, 6) }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(run.phase.rawValue).font(.subheadline)
                                if !run.detail.isEmpty {
                                    Text(run.detail).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        if let p = run.progress, run.isRunning {
                            ProgressView(value: p)
                        }
                        if let err = run.errorMessage {
                            Text(err).font(.caption).foregroundStyle(.red)
                        }
                    }
                }

                Section("Try it now") {
                    Button {
                        DemoSession.create(into: store)
                    } label: {
                        Label("Load demo session", systemImage: "sparkles")
                    }
                    .disabled(run.isRunning)
                    Text("Seeds a short pre-tokenized session so you can try tapping words, building a pile, and exporting a deck.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !store.sessions.isEmpty {
                    Section("Sessions") {
                        ForEach(store.sessions) { session in
                            VStack(alignment: .leading) {
                                Text(session.title ?? "Untitled").font(.subheadline)
                                Text("\(session.cues.count) lines · \(session.picks.count) picked · \(session.status.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
