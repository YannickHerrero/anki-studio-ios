import SwiftUI
import UIKit

/// The Library: every saved mining session as a browsable gallery — YouTube
/// thumbnail, title, and quick stats — newest first. Tapping an entry opens
/// its review session; this is the main navigation between videos.
struct LibraryView: View {
    @ObservedObject private var store = SessionStore.shared
    @StateObject private var ingestRun = IngestRun()
    @ObservedObject private var settings = AppSettings.shared
    @State private var showsAdd = false

    var body: some View {
        NavigationStack {
            Group {
                if store.sessions.isEmpty, !ingestRun.isRunning {
                    ContentUnavailableView {
                        Label("No videos yet", systemImage: "books.vertical")
                    } description: {
                        Text("Import a YouTube video to start mining.")
                    } actions: {
                        Button("Add video") { showsAdd = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        // A running import surfaces here once the sheet closes.
                        if ingestRun.isRunning, !showsAdd {
                            Section {
                                IngestProgressRow(run: ingestRun)
                            }
                        }
                        ForEach(store.sessions) { session in
                            NavigationLink {
                                ReviewView(session: session)
                                    .id(session.id)
                            } label: {
                                LibraryRow(session: session)
                            }
                        }
                        .onDelete { offsets in
                            offsets.map { store.sessions[$0].id }.forEach(store.delete)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Theme.page)
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Haptics.tap()
                        showsAdd = true
                    } label: {
                        Label("Add video", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showsAdd) {
                AddVideoSheet(run: ingestRun)
            }
            .onAppear {
                // Headless test hook: start an import straight from launch env.
                if let url = ProcessInfo.processInfo.environment["INGEST_URL"],
                   !ingestRun.isRunning {
                    Task { await ingestRun.run(urlString: url, settings: settings) }
                }
            }
        }
    }
}

private struct LibraryRow: View {
    let session: Session

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 112, height: 63)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(session.title ?? "Untitled")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Text("\(session.cues.count) lines")
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(session.picks.count) picked")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = youtubeThumbnailURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
        } else if let local = localScreenshot {
            Image(uiImage: local).resizable().scaledToFill()
        } else {
            placeholder
        }
    }

    /// YouTube's mqdefault thumbnail for the source video.
    private var youtubeThumbnailURL: URL? {
        guard let raw = session.youtubeURL,
              let id = YouTubeService.videoID(from: raw) else { return nil }
        return URL(string: "https://img.youtube.com/vi/\(id)/mqdefault.jpg")
    }

    /// Fallback: the first cue's extracted screenshot.
    private var localScreenshot: UIImage? {
        guard let cue = session.cues.first(where: { $0.screenshotReady }) else { return nil }
        return UIImage(contentsOfFile: Storage.screenshotURL(session.id, cue.index).path)
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            Image(systemName: "film").foregroundStyle(.secondary)
        }
    }
}

#Preview {
    LibraryView()
}
