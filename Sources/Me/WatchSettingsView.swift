//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import SwiftUI

// MARK: - Watch Settings View

struct WatchSettingsView: View {
    @State private var doubleTapPageTurn: Bool
    @ObservedObject private var proPurchase = ProPurchaseManager.shared

    init() {
        let settings = WatchPageTurnSettings()
        _doubleTapPageTurn = State(initialValue: settings.doubleTapPageTurn)
    }

    var body: some View {
        List {
            doubleTapSection
        }
        .listStyle(.insetGrouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(NSLocalizedString("watch_settings_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // There is no user-selected page-turn target anymore. Pro users
            // keep nearby iPad discovery warm so Watch commands can fan out to
            // any active Reader automatically.
            if proPurchase.hasProAccess {
                WatchPageTurnService.shared.prepareIPadRelay()
                WatchPageTurnService.shared.probeIPadRelayNow()
            }
        }
    }

    // MARK: - Double Tap

    private var doubleTapSection: some View {
        Section(
            header: Text(NSLocalizedString("watch_double_tap_section", comment: "")),
            footer: Text(NSLocalizedString("watch_double_tap_footer", comment: ""))
        ) {
            Toggle(isOn: Binding(
                get: { doubleTapPageTurn },
                set: { newValue in
                    doubleTapPageTurn = newValue
                    var settings = WatchPageTurnSettings()
                    settings.doubleTapPageTurn = newValue
                    settings.syncToWatch()
                }
            )) {
                Label(
                    NSLocalizedString("watch_double_tap_toggle", comment: ""),
                    systemImage: "hand.point.up.braille"
                )
            }
        }
    }
}

#Preview {
    NavigationView {
        WatchSettingsView()
    }
    .navigationViewStyle(.stack)
}
