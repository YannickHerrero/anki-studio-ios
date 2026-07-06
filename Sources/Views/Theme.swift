import SwiftUI
import UIKit

/// The Anki card template's palette (Resources/anki/styling.css), as dynamic
/// light/dark colors, so the app looks like the cards it produces.
enum Theme {
    /// Warm paper background (`.card` background).
    static let page = dynamic(0xE7E4DE, 0x141519)
    /// Card body (`--bBg`).
    static let panel = dynamic(0xFBFBFC, 0x16181C)
    /// Inset panels on the card back (`--bPanel`).
    static let panelInset = dynamic(0xF4F5F7, 0x1C1F24)
    /// Primary text (`--bInk`).
    static let ink = dynamic(0x1B1E23, 0xE7E9ED)
    /// Secondary text (`--bMuted`).
    static let muted = dynamic(0x9298A1, 0x787D86)
    /// Hairlines (`--bLine`).
    static let line = dynamic(0xECEDF1, 0x262931)
    /// The template green (`--accent`).
    static let accent = dynamic(0x3F7D5F, 0x84C9A6)
    /// Video letterbox (`--videoBg`).
    static let videoBg = Color(rgb: 0x15140F)
    /// Bottom-sheet background (Explain mock).
    static let sheetBg = dynamic(0xEDEBE6, 0x141519)
    /// Tinted meaning card on the Explain sheet.
    static let meaningBg = dynamic(0xEBF2EE, 0x1B2620)

    /// The card's Japanese face; falls back to the system font if missing.
    static func jp(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "ZenKakuGothicNew-Bold"
        case .medium, .semibold: name = "ZenKakuGothicNew-Medium"
        default: name = "ZenKakuGothicNew-Regular"
        }
        return .custom(name, size: size)
    }

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

/// The card's section header: green bar + uppercase tracking label
/// (`.js-rule` in the template CSS).
struct RuleLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 9) {
            Rectangle()
                .fill(Theme.accent)
                .frame(width: 14, height: 2)
            Text(text.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(2.4)
                .foregroundStyle(Theme.muted)
        }
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1)
    }
}

private extension Color {
    init(rgb: UInt32) {
        self.init(uiColor: UIColor(rgb: rgb))
    }
}
