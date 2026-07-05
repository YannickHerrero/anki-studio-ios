import SwiftUI
import UIKit

/// Thin wrapper over UIActivityViewController so a built `.apkg` can be handed
/// to AnkiMobile (or Files / AirDrop) via the system share sheet.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
