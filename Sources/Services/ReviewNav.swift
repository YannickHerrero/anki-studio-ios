import Foundation

/// Bridges the currently visible review session to the tab bar's bottom
/// accessory: ReviewView registers its view model while on screen so the
/// glass prev/next capsule can drive it.
@MainActor
final class ReviewNav: ObservableObject {
    static let shared = ReviewNav()

    @Published var active: ReviewViewModel?
}
