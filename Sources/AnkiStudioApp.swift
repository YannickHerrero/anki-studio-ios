import SwiftUI

@main
struct AnkiStudioApp: App {
    init() {
        // Background-continued imports must register before launch finishes.
        if #available(iOS 26.1, *) {
            BackgroundImporter.register()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}
