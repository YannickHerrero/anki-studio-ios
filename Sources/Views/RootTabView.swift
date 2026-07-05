import SwiftUI

/// Top-level tab bar. Mirrors the desktop app's flow: add a source, review &
/// mine, then manage the pile / export. Screens are filled in per milestone.
struct RootTabView: View {
    var body: some View {
        TabView {
            PlaceholderScreen(title: "Add from YouTube", systemImage: "plus.circle")
                .tabItem { Label("Add", systemImage: "plus.circle") }

            PlaceholderScreen(title: "Review & Mine", systemImage: "rectangle.stack")
                .tabItem { Label("Review", systemImage: "rectangle.stack") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

private struct PlaceholderScreen: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text("Coming soon")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    RootTabView()
}
