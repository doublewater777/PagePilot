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

    /// Light `#F6F8FC` / Dark `#0F1013`
    static let background = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 15 / 255, green: 16 / 255, blue: 19 / 255, alpha: 1)
        }
        return UIColor(red: 246 / 255, green: 248 / 255, blue: 252 / 255, alpha: 1)
    })

    /// Light `#FFFFFF` / Dark `#1A1C20`
    static let cardBackground = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            return UIColor(red: 26 / 255, green: 28 / 255, blue: 32 / 255, alpha: 1)
        }
        return .white
    })

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
