import SwiftUI

/// Bottom sheet for importing a YouTube video, opened from the Library's
/// add button. The IngestRun is owned by the Library so a running import
/// survives dismissing the sheet.
struct AddVideoSheet: View {
    @ObservedObject var run: IngestRun
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
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
                        Haptics.tap()
                        Task { await run.run(urlString: url, settings: settings) }
                    } label: {
                        Label("Import video", systemImage: "arrow.down.circle")
                    }
                    .disabled(!urlLooksValid || !settings.isYoutubeReady || run.isRunning)
                } footer: {
                    if !settings.isYoutubeReady {
                        Text("Add your OpenAI and OpenRouter keys in Settings to enable import.")
                    } else {
                        Text("Downloads the video and builds cards entirely on-device. You can close this sheet — the import keeps running.")
                    }
                }

                if run.phase != .idle {
                    Section("Progress") {
                        IngestProgressRow(run: run)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.page)
            .navigationTitle("Add video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .confirmationDialog(
                "This video has Japanese subtitles",
                isPresented: $run.showsSubsChoice,
                titleVisibility: .visible
            ) {
                Button("Use YouTube subtitles") { run.chooseSubs(useExisting: true) }
                Button("Transcribe with Whisper") { run.chooseSubs(useExisting: false) }
            } message: {
                Text("The uploader's subtitles are free and instant. Whisper re-transcribes with word timing (better sentence splits) but costs OpenAI credits.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// Compact phase/progress display, shared by the sheet and the Library row.
struct IngestProgressRow: View {
    @ObservedObject var run: IngestRun

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
}
