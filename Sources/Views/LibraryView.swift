import SwiftUI
import UIKit

/// The Library: a resume hero for the newest session, then the remaining
/// sessions as rows with per-item mining progress. Layout follows the
/// "refined list" design mock (Library iOS.html).
struct LibraryView: View {
    @ObservedObject private var store = SessionStore.shared
    @StateObject private var ingestRun = IngestRun()
    @ObservedObject private var settings = AppSettings.shared
    @State private var showsAdd = false
    @State private var showsSettings = false

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
                    sessionList
                }
            }
            .background(Theme.page)
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showsSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
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
            .navigationDestination(isPresented: $showsSettings) {
                SettingsView()
            }
            .onAppear {
                // Headless test hooks: start an import / open Settings.
                if let url = ProcessInfo.processInfo.environment["INGEST_URL"],
                   !ingestRun.isRunning {
                    Task { await ingestRun.run(urlString: url, settings: settings) }
                }
            }
        }
    }

    private var sessionList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // A running import surfaces here once the sheet closes.
                if ingestRun.isRunning, !showsAdd {
                    IngestProgressRow(run: ingestRun)
                        .padding(14)
                        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.bottom, 18)
                }

                if let hero = store.sessions.first {
                    NavigationLink {
                        ReviewView(session: hero).id(hero.id)
                    } label: {
                        ResumeHeroCard(session: hero)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            store.delete(hero.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                let rest = Array(store.sessions.dropFirst())
                if !rest.isEmpty {
                    // Section label — the card template's rule style.
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.accent)
                            .frame(width: 14, height: 3)
                        Text("RECENT")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(2.2)
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.top, 26)
                    .padding(.bottom, 12)
                    .padding(.horizontal, 2)

                    // One rounded card holding all rows.
                    VStack(spacing: 0) {
                        ForEach(Array(rest.enumerated()), id: \.element.id) { i, session in
                            NavigationLink {
                                ReviewView(session: session).id(session.id)
                            } label: {
                                LibraryRow(session: session, showsSeparator: i < rest.count - 1)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    store.delete(session.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .background(Theme.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
    }
}

// MARK: - Resume hero (newest session)

private struct ResumeHeroCard: View {
    let session: Session

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            SessionThumbnail(session: session)
                .frame(height: 196)
                .frame(maxWidth: .infinity)
                .clipped()

            // Dark scrim so the title reads over the still.
            LinearGradient(
                colors: [.clear, Color(red: 10 / 255, green: 9 / 255, blue: 6 / 255).opacity(0.86)],
                startPoint: .center, endPoint: .bottom)

            // CONTINUE chip.
            VStack {
                HStack {
                    Spacer()
                    Text("CONTINUE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
                }
                Spacer()
            }
            .padding(12)

            // Play disc + title + stats.
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "play.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.videoBg)
                    .frame(width: 46, height: 46)
                    .background(Color(red: 132 / 255, green: 201 / 255, blue: 166 / 255), in: Circle())
                    .shadow(color: .black.opacity(0.4), radius: 7, y: 4)

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.title ?? "Untitled")
                        .font(Theme.jp(16, .medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(heroSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)

            // Reading position along the bottom edge.
            GeometryReader { geo in
                VStack {
                    Spacer()
                    ZStack(alignment: .leading) {
                        Rectangle().fill(.white.opacity(0.18))
                        Rectangle()
                            .fill(Color(red: 132 / 255, green: 201 / 255, blue: 166 / 255))
                            .frame(width: geo.size.width * session.positionRatio)
                    }
                    .frame(height: 4)
                }
            }
        }
        .frame(height: 196)
        .background(Theme.videoBg)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color(red: 21 / 255, green: 20 / 255, blue: 15 / 255).opacity(0.28), radius: 11, y: 6)
    }

    private var heroSubtitle: String {
        var parts: [String] = []
        if let d = session.videoDurationMs { parts.append(Session.durationLabel(ms: d)) }
        parts.append("Line \(session.positionLabel)")
        return parts.joined(separator: " · ")
    }
}

// MARK: - Row

private struct LibraryRow: View {
    let session: Session
    var showsSeparator = true

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            SessionThumbnail(session: session)
                .frame(width: 98, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(alignment: .bottomTrailing) {
                    if let d = session.videoDurationMs {
                        Text(Session.durationLabel(ms: d))
                            .font(.system(size: 9, weight: .semibold).monospaced())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                            .padding(5)
                    }
                }

            VStack(alignment: .leading, spacing: 7) {
                Text(session.title ?? "Untitled")
                    .font(Theme.jp(14.5, .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 10) {
                    // Reading position through the session.
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.line)
                            Capsule()
                                .fill(Theme.accent)
                                .frame(width: geo.size.width * session.positionRatio)
                        }
                    }
                    .frame(height: 3)

                    Text(session.positionLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .fixedSize()
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.muted.opacity(0.6))
        }
        .padding(13)
        .overlay(alignment: .bottom) {
            if showsSeparator {
                Rectangle()
                    .fill(Theme.line)
                    .frame(height: 0.5)
                    .padding(.leading, 124)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Shared thumbnail

private struct SessionThumbnail: View {
    let session: Session

    var body: some View {
        Group {
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
    }

    private var youtubeThumbnailURL: URL? {
        guard let raw = session.youtubeURL,
              let id = YouTubeService.videoID(from: raw) else { return nil }
        return URL(string: "https://img.youtube.com/vi/\(id)/mqdefault.jpg")
    }

    private var localScreenshot: UIImage? {
        guard let cue = session.cues.first(where: { $0.screenshotReady }) else { return nil }
        return UIImage(contentsOfFile: Storage.screenshotURL(session.id, cue.index).path)
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(Theme.panelInset)
            Image(systemName: "film").foregroundStyle(Theme.muted)
        }
    }
}

// MARK: - Session display helpers

extension Session {
    /// Reading position through the session, 0…1 (last cue visited).
    var positionRatio: CGFloat {
        guard !cues.isEmpty, let last = lastCueIndex, last > 0 else { return 0 }
        return min(1, CGFloat(last + 1) / CGFloat(cues.count))
    }

    /// "50/223" — the last visited line over the total.
    var positionLabel: String {
        let position = lastCueIndex.map { min($0 + 1, cues.count) } ?? 0
        return "\(position)/\(cues.count)"
    }

    static func durationLabel(ms: Int) -> String {
        let s = ms / 1000
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

#Preview {
    LibraryView()
}
