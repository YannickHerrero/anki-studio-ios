import SwiftUI

/// The pile: picked words with export to a shareable `.apkg`.
struct PileView: View {
    @ObservedObject var vm: ReviewViewModel
    @ObservedObject private var settings = AppSettings.shared

    /// Identifiable wrapper so the share sheet is item-driven — an
    /// isPresented sheet can render against a stale nil URL and stay empty.
    private struct ExportFile: Identifiable {
        let url: URL
        var id: String { url.path }
    }

    @State private var exportFile: ExportFile?
    @State private var exportError: String?
    @State private var showsClearConfirm = false
    @State private var exporting = false
    @State private var exportStage = ""

    var body: some View {
        Group {
            if vm.session.picks.isEmpty {
                ContentUnavailableView(
                    "No cards yet",
                    systemImage: "tray",
                    description: Text("Tap words in review to add them to the pile.")
                )
            } else {
                List {
                    ForEach(vm.session.picks) { pick in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pick.surface).font(.headline)
                                if pick.surface != pick.lemma {
                                    Text("→ \(pick.lemma)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text("cue #\(pick.cueIndex)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { vm.session.picks[$0].id }.forEach(vm.removePick)
                    }
                }
            }
        }
        .navigationTitle("Pile (\(vm.session.picks.count))")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if exporting {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(exportStage).font(.caption)
                    }
                } else {
                    Button("Export") { export() }
                        .disabled(vm.session.picks.isEmpty)
                }
            }
        }
        .sheet(item: $exportFile, onDismiss: {
            // The deck was handed to Anki — offer a fresh pile.
            if !vm.session.picks.isEmpty { showsClearConfirm = true }
        }) { file in
            ShareSheet(items: [file.url])
        }
        .confirmationDialog(
            "Deck exported",
            isPresented: $showsClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear \(vm.session.picks.count) cards from the pile", role: .destructive) {
                Haptics.success()
                vm.clearPile()
            }
            Button("Keep the pile", role: .cancel) {}
        } message: {
            Text("Clear the exported words so the next export starts fresh?")
        }
        .onAppear {
            // Headless test hook: run the export straight away.
            if ProcessInfo.processInfo.environment["AUTO_EXPORT"] == "1", !exporting {
                export()
            }
        }
        .alert("Export failed", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private func export() {
        guard settings.isConfigured else {
            exportError = "Set your OpenRouter key in Settings first."
            return
        }
        exporting = true
        exportStage = "Preparing…"
        Task {
            do {
                let (url, enriched) = try await ExportService.build(
                    session: vm.session,
                    deckName: settings.deckName,
                    llm: .init(apiKey: settings.openrouterKey.trimmed, model: settings.model)
                ) { stage in
                    exportStage = stage.label
                }
                vm.adoptEnriched(enriched)
                Haptics.success()
                exportFile = ExportFile(url: url)
            } catch {
                Haptics.warning()
                exportError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            }
            exporting = false
        }
    }
}
