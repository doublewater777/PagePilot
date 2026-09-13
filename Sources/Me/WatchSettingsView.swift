//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import SwiftUI
import UIKit

// MARK: - Watch Settings View

struct WatchSettingsView: View {
    @State private var doubleTapPageTurn: Bool
    @ObservedObject private var proPurchase = ProPurchaseManager.shared
    @ObservedObject private var watchService = WatchPageTurnService.shared

    init() {
        let settings = WatchPageTurnSettings()
        _doubleTapPageTurn = State(initialValue: settings.doubleTapPageTurn)
    }

    var body: some View {
        List {
            installSection
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

    // MARK: - Install

    @ViewBuilder
    private var installSection: some View {
        if watchService.watchAvailability == .appNotInstalled {
            Section(
                header: Text("onboarding_watch_install_title"),
                footer: Text("onboarding_watch_install_detail")
            ) {
                Button {
                    UIApplication.shared.open(WatchPageTurnService.watchAppURL)
                } label: {
                    Label(
                        NSLocalizedString("onboarding_watch_install_action", comment: ""),
                        systemImage: "square.and.arrow.down"
                    )
                }
            }
        }
    }

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
