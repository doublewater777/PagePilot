import SwiftUI

struct AppColors {
    // Background colors
    static let background = Color(.systemGroupedBackground)
    static let cardBackground = Color(.secondarySystemGroupedBackground)

    // Text colors
    static let primaryText = Color(.label)
    static let secondaryText = Color(.secondaryLabel)
    static let tertiaryText = Color(.tertiaryLabel)

    // Accent colors
    static let accentBlue = Color(red: 0.22, green: 0.43, blue: 0.95)
    static let accentTeal = Color(red: 0.16, green: 0.62, blue: 0.58)

    // Accent gradient colors
    static let accentGradientStart = Color(red: 0.12, green: 0.47, blue: 0.85)
    static let accentGradientEnd = Color(red: 0.08, green: 0.66, blue: 0.58)

    // Progress track
    static let progressTrack = Color.primary.opacity(0.06)

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
