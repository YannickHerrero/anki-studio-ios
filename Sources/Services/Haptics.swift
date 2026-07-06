import UIKit

/// Centralised haptic feedback for the review flow.
@MainActor
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let notify = UINotificationFeedbackGenerator()

    /// Small tap — opening the dictionary, navigation, replay.
    static func tap() { light.impactOccurred() }

    /// Selecting / deselecting a token for the pile.
    static func select() { medium.impactOccurred() }

    /// Words committed to the pile, export finished.
    static func success() { notify.notificationOccurred(.success) }

    /// Removal or a failed action.
    static func warning() { notify.notificationOccurred(.warning) }
}
