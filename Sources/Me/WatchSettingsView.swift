//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import SwiftUI

// MARK: - Watch Settings View

struct WatchSettingsView: View {
    @State private var doubleTapPageTurn: Bool
    @State private var selectedIPadName: String?
    @State private var isTurningPage = false
    @State private var pageTurnFailed = false
    @ObservedObject private var proPurchase = ProPurchaseManager.shared
    @ObservedObject private var watchService = WatchPageTurnService.shared

    init() {
        let settings = WatchPageTurnSettings()
        _doubleTapPageTurn = State(initialValue: settings.doubleTapPageTurn)
    }

    var body: some View {
        List {
            watchStatusSection
            nearbyIPadSection
            doubleTapSection
        }
        .listStyle(.insetGrouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(NSLocalizedString("watch_settings_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            watchService.activate()
            selectedIPadName = PagePilotNearbySelectionStore.selectedTarget()?.name

            if proPurchase.hasProAccess {
                WatchPageTurnService.shared.prepareIPadRelay()
            }
        }
    }

    private var nearbyIPadSection: some View {
        Section {
            NavigationLink {
                NearbyIPadSelectionView()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Label(LocalizedStringKey("nearby_ipad_choose"), systemImage: "ipad")
                    if let selectedIPadName {
                        HStack(spacing: 6) {
                            Text(selectedIPadName)
                            Text("·")
                            Text(LocalizedStringKey(
                                watchService.isIPadLinkConnected ? "nearby_ipad_linked" : "nearby_ipad_not_linked"
                            ))
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(!proPurchase.hasProAccess)

            if selectedIPadName != nil, proPurchase.hasProAccess {
                HStack(spacing: 12) {
                    pageTurnButton(.prev, title: "nearby_ipad_prev", systemImage: "chevron.left")
                    pageTurnButton(.next, title: "nearby_ipad_next", systemImage: "chevron.right")
                }
                .buttonStyle(.bordered)
                if pageTurnFailed {
                    Text(LocalizedStringKey("nearby_ipad_turn_failed"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text(LocalizedStringKey("nearby_ipad_instructions"))
        }
    }

    private func pageTurnButton(_ command: PageCommand, title: String, systemImage: String) -> some View {
        Button {
            isTurningPage = true
            pageTurnFailed = false
            watchService.turnSelectedIPadPage(command) { turned in
                isTurningPage = false
                pageTurnFailed = !turned
            }
        } label: {
            Label(LocalizedStringKey(title), systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .disabled(isTurningPage)
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

private struct NearbyIPadSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var targets: [PagePilotNearbyTarget] = []
    @State private var isScanning = false
    @State private var connectingIdentifier: String?
    @State private var errorKey: String?
    @State private var selectedIdentifier = PagePilotNearbySelectionStore.selectedTarget()?.id

    var body: some View {
        List {
            Section {
                ForEach(targets) { target in
                    Button {
                        connect(target)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(target.name)
                                if !target.bookTitle.isEmpty {
                                    Text(target.bookTitle)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if connectingIdentifier == target.id {
                                ProgressView()
                            } else if selectedIdentifier == target.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .disabled(connectingIdentifier != nil || isScanning)
                }
                if isScanning {
                    HStack {
                        ProgressView()
                        Text(LocalizedStringKey("nearby_ipad_searching"))
                    }
                } else if targets.isEmpty, errorKey == nil {
                    Text(LocalizedStringKey("nearby_ipad_empty"))
                        .foregroundStyle(.secondary)
                }
                if let errorKey {
                    Text(LocalizedStringKey(errorKey))
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text(LocalizedStringKey("nearby_ipad_instructions"))
            }
            Section {
                Button(LocalizedStringKey("nearby_ipad_refresh"), action: scan)
                    .disabled(isScanning || connectingIdentifier != nil)
            }
        }
        .listStyle(.insetGrouped)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(LocalizedStringKey("nearby_ipad_choose"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: scan)
        .onDisappear { PagePilotPeerClient.shared.cancelDiscovery() }
    }

    private func scan() {
        guard ProPurchaseManager.shared.hasProAccess else {
            errorKey = "nearby_ipad_pro_required"
            return
        }
        isScanning = true
        targets = []
        errorKey = nil
        PagePilotPeerClient.shared.discoverTargets { result in
            isScanning = false
            switch result {
            case .success(let discovered):
                targets = discovered
            case .failure:
                errorKey = "nearby_ipad_search_failed"
            }
        }
    }

    private func connect(_ target: PagePilotNearbyTarget) {
        connectingIdentifier = target.id
        errorKey = nil
        WatchPageTurnService.shared.connectNearbyIPad(target) { connected in
            connectingIdentifier = nil
            if connected {
                selectedIdentifier = target.id
                dismiss()
            } else {
                errorKey = "nearby_ipad_connect_failed"
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
