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
    @ObservedObject private var watchService = WatchPageTurnService.shared

    init() {
        let settings = WatchPageTurnSettings()
        _doubleTapPageTurn = State(initialValue: settings.doubleTapPageTurn)
    }

    var body: some View {
        List {
            watchStatusSection
            doubleTapSection
        }
        .listStyle(.insetGrouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(NSLocalizedString("watch_settings_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            watchService.activate()

            // There is no user-selected page-turn target anymore. Pro users
            // keep nearby iPad discovery warm so Watch commands can fan out to
            // any active Reader automatically.
            if proPurchase.hasProAccess {
                WatchPageTurnService.shared.prepareIPadRelay()
                WatchPageTurnService.shared.probeIPadRelayNow()
            }
        }
    }

    // MARK: - Status

    private var watchStatusSection: some View {
        Section {
            Label(statusTitle, systemImage: statusIcon)
            Text(statusDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusIcon: String {
        switch watchService.watchAvailability {
        case .unsupported, .unpaired:
            return "applewatch.slash"
        case .appNotInstalled:
            return "square.and.arrow.down"
        case .unreachable:
            return "applewatch"
        case .ready:
            return "checkmark.circle"
        }
    }

    private var statusTitle: LocalizedStringKey {
        switch watchService.watchAvailability {
        case .unsupported, .unpaired:
            return "onboarding_watch_unpaired_title"
        case .appNotInstalled:
            return "onboarding_watch_install_title"
        case .unreachable:
            return "onboarding_watch_open_title"
        case .ready:
            return "onboarding_watch_ready_title"
        }
    }

    private var statusDetail: LocalizedStringKey {
        switch watchService.watchAvailability {
        case .unsupported, .unpaired:
            return "onboarding_watch_unpaired_detail"
        case .appNotInstalled:
            return "onboarding_watch_install_detail"
        case .unreachable:
            return "onboarding_watch_open_detail"
        case .ready:
            return "onboarding_watch_ready_detail"
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
