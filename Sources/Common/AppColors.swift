import SwiftUI
import UIKit

/// Brand colors aligned with `docs/design-system.md`
/// (静谧 / 流畅 / 领航 / 纯粹).
struct AppColors {
    // MARK: Brand

    /// PagePilot Blue `#386EF2`
    static let accentBlue = Color(red: 56 / 255, green: 110 / 255, blue: 242 / 255)
    /// PagePilot Teal `#299E94`
    static let accentTeal = Color(red: 41 / 255, green: 158 / 255, blue: 148 / 255)

    /// Accent gradient start/end (same as brand pair for 135° 领航渐变).
    static let accentGradientStart = accentBlue
    static let accentGradientEnd = accentTeal

    // MARK: Surfaces

    /// UIKit equivalent of `background` (`#F6F8FC` / `#0F1013`).
    static let uiBackground = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 15 / 255, green: 16 / 255, blue: 19 / 255, alpha: 1)
        }
        return UIColor(red: 246 / 255, green: 248 / 255, blue: 252 / 255, alpha: 1)
    }

    /// UIKit equivalent of `cardBackground` (`#FFFFFF` / `#1A1C20`).
    static let uiCardBackground = UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 26 / 255, green: 28 / 255, blue: 32 / 255, alpha: 1)
        }
        return .white
    }

    /// UIKit equivalent of `accentBlue` (`#386EF2`).
    static let uiAccentBlue = UIColor(red: 56 / 255, green: 110 / 255, blue: 242 / 255, alpha: 1)

    /// UIKit equivalent of `accentTeal` (`#299E94`).
    static let uiAccentTeal = UIColor(red: 41 / 255, green: 158 / 255, blue: 148 / 255, alpha: 1)

    /// Light `#F6F8FC` / Dark `#0F1013`
    static let background = Color(uiColor: uiBackground)

    /// Light `#FFFFFF` / Dark `#1A1C20`
    static let cardBackground = Color(uiColor: uiCardBackground)

    /// Reader theme surfaces (aligned with `docs/design-system.md`).
    static let readerSepiaBackground = UIColor(red: 244 / 255, green: 236 / 255, blue: 216 / 255, alpha: 1)
    static let readerSepiaText = UIColor(red: 67 / 255, green: 52 / 255, blue: 34 / 255, alpha: 1)
    static let readerDarkBackground = UIColor(red: 18 / 255, green: 19 / 255, blue: 22 / 255, alpha: 1)
    static let readerDarkText = UIColor(red: 235 / 255, green: 237 / 255, blue: 242 / 255, alpha: 1)

    // MARK: Text

    /// Prefer system labels for Dynamic Type / accessibility; design-system
    /// hex values are close enough via semantic system colors.
    static let primaryText = Color(.label)
    static let secondaryText = Color(.secondaryLabel)
    static let tertiaryText = Color(.tertiaryLabel)

    // MARK: Components

    static let progressTrack = Color.primary.opacity(0.06)

    /// Major card corner radius from design system.
    static let cardCornerRadius: CGFloat = 16

    static let accentGradient = LinearGradient(
        colors: [accentGradientStart, accentGradientEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let horizontalGradient = LinearGradient(
        colors: [accentGradientStart, accentGradientEnd],
        startPoint: .leading,
        endPoint: .trailing
    )
}
