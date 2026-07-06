import SwiftUI

/// Top-level tab bar: add a source, browse the library of sessions (the main
/// navigation between videos), and settings.
struct RootTabView: View {
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            IngestView()
                .tabItem { Label("Add", systemImage: "plus.circle") }
                .tag(0)

            LibraryTab()
                .tabItem { Label("Library", systemImage: "books.vertical") }
                .tag(1)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(2)
        }
        .onAppear {
            // UI-test / screenshot hook: seed a demo session and open Library.
            if ProcessInfo.processInfo.environment["SEED_DEMO"] == "1" {
                if SessionStore.shared.sessions.isEmpty {
                    DemoSession.create(into: .shared)
                }
                selection = 1
            }
        }
    }
}

/// Library wrapper that supports the REVIEW_INDEX screenshot hook: when set,
/// it pushes straight into review for the newest session on launch.
private struct LibraryTab: View {
    @State private var autoOpened = false

    var body: some View {
        if ProcessInfo.processInfo.environment["REVIEW_INDEX"] != nil,
           !autoOpened, let first = SessionStore.shared.sessions.first {
            NavigationStack {
                ReviewView(session: first)
                    .id(first.id)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Library") { autoOpened = true }
                        }
                    }
            }
        } else {
            LibraryView()
        }
    }
}

#Preview {
    RootTabView()
}
