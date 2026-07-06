import SwiftUI

/// Per-session storage breakdown, pushed from the Settings storage section.
struct SessionStorageView: View {
    @ObservedObject private var store = SessionStore.shared
    @State private var usages: [Storage.SessionUsage]?

    var body: some View {
        Group {
            if let usages {
                if usages.isEmpty {
                    ContentUnavailableView(
                        "No sessions",
                        systemImage: "internaldrive",
                        description: Text("Imported videos will show their footprint here.")
                    )
                } else {
                    List(usages) { usage in
                        row(usage)
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.page)
        .navigationTitle("Session storage")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            usages = await Task.detached(priority: .utility) {
                Storage.sessionUsages()
            }.value
        }
    }

    private func row(_ usage: Storage.SessionUsage) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(store.session(usage.id)?.title ?? "Untitled session")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Spacer()
                Text(Self.size(usage.totalBytes))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize()
            }
            Text(breakdown(usage))
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 2)
    }

    private func breakdown(_ usage: Storage.SessionUsage) -> String {
        var parts: [String] = []
        if usage.videoBytes > 0 { parts.append("video \(Self.size(usage.videoBytes))") }
        if usage.audioBytes > 0 { parts.append("audio \(Self.size(usage.audioBytes))") }
        if usage.imageBytes > 0 { parts.append("images \(Self.size(usage.imageBytes))") }
        if usage.otherBytes > 0 { parts.append("data \(Self.size(usage.otherBytes))") }
        return parts.joined(separator: " · ")
    }

    private static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
