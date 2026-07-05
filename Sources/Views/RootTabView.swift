import SwiftUI

/// Top-level tab bar. Mirrors the desktop app's flow: add a source, review &
/// mine, then export the pile.
struct RootTabView: View {
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            IngestView()
                .tabItem { Label("Add", systemImage: "plus.circle") }
                .tag(0)

            ReviewTab()
                .tabItem { Label("Review", systemImage: "rectangle.stack") }
                .tag(1)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(2)
        }
        .onAppear {
            // UI-test / screenshot hook: seed a demo session and open Review.
            if ProcessInfo.processInfo.environment["SEED_DEMO"] == "1" {
                if SessionStore.shared.sessions.isEmpty {
                    DemoSession.create(into: .shared)
                }
                selection = 1
            }
        }
    }
}

/// Shows the most recent session for review, or an empty state.
private struct ReviewTab: View {
    @ObservedObject private var store = SessionStore.shared

    var body: some View {
        if let session = store.sessions.first {
            ReviewView(session: session)
                .id(session.id)
        } else {
            ContentUnavailableView(
                "No session yet",
                systemImage: "play.rectangle",
                description: Text("Add a video — or load the demo — from the Add tab.")
            )
        }
    }
}

#Preview {
    RootTabView()
}
