import SwiftUI

/// The pile: picked words with export to a shareable `.apkg`.
struct PileView: View {
    @ObservedObject var vm: ReviewViewModel
    @ObservedObject private var settings = AppSettings.shared

    @State private var exportURL: URL?
    @State private var showShare = false
    @State private var exportError: String?

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
                Button("Export") { export() }
                    .disabled(vm.session.picks.isEmpty)
            }
        }
        .sheet(isPresented: $showShare) {
            if let url = exportURL { ShareSheet(items: [url]) }
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
        do {
            exportURL = try ExportService.build(session: vm.session, deckName: settings.deckName)
            Haptics.success()
            showShare = true
        } catch {
            Haptics.warning()
            exportError = String(describing: error)
        }
    }
}
