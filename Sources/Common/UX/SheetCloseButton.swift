//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import SwiftUI

/// Circular × control for dismissing sheets (no text label).
struct SheetCloseButton: View {
    var accessibilityLabel: String = NSLocalizedString("close_button", comment: "")
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Color(.secondarySystemFill))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}


/// PagePilot presentation levels for first-party sheets.
/// System-owned presentations such as share sheets and Safari keep their native behavior.
enum AppSheetStyle {
    /// Short, focused tasks start compact and can expand when content needs more room.
    case compact
    /// Navigation or content-heavy tasks use the system large sheet.
    case content
}

private struct AppSheetStyleModifier: ViewModifier {
    let style: AppSheetStyle

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .compact:
            content
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        case .content:
            content
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

extension View {
    func appSheetStyle(_ style: AppSheetStyle) -> some View {
        modifier(AppSheetStyleModifier(style: style))
    }
}
