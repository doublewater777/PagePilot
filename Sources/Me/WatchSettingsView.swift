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
    @State private var selectedReaderIcon = "laptopcomputer.and.ipad"
    @State private var isTurningPage = false
    @State private var showPaywall = false
    @ObservedObject private var proPurchase = ProPurchaseManager.shared
    @ObservedObject private var watchService = WatchPageTurnService.shared

    init() {
        let settings = WatchPageTurnSettings()
        _doubleTapPageTurn = State(initialValue: settings.doubleTapPageTurn)
    }

    var body: some View {
        List {
            deviceChainSection
            WatchPageTurnRecentSection(
                entries: watchService.activityLog.entries,
                emptyText: "page_turn_recent_empty_phone",
                onProRequested: {
                    Analytics.shared.log(.paywallViewed(source: "watch_recent_turns_pro_entry"))
                    showPaywall = true
                }
            )
            nearbyIPadSection
            doubleTapSection
        }
        .listStyle(.insetGrouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(NSLocalizedString("watch_settings_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            PaywallView(context: .iPadWatchRelay, analyticsSource: "watch_settings_upgrade")
        }
        .onAppear {
            watchService.activate()
            let target = PagePilotNearbySelectionStore.selectedTarget()
            selectedIPadName = target?.name
            selectedReaderIcon = target?.systemImage ?? "laptopcomputer.and.ipad"

            WatchPageTurnService.shared.prepareIPadRelay()
        }
    }

    // MARK: - Device chain

    /// Watch → iPhone → iPad at a glance; the Watch hint stays until it is ready.
    private var deviceChainSection: some View {
        Section {
            HStack(alignment: .top, spacing: 0) {
                PageTurnChainNode(
                    systemImage: "applewatch",
                    title: "page_turn_chain_watch",
                    detail: watchChainDetail,
                    isReady: watchService.watchAvailability == .ready
                )
                PageTurnChainConnector(isReady: watchService.watchAvailability == .ready)
                PageTurnChainNode(
                    systemImage: "iphone",
                    title: "iPhone",
                    detail: "page_turn_chain_this_device",
                    isReady: true
                )
                PageTurnChainConnector(isReady: iPadReady)
                PageTurnChainNode(
                    systemImage: selectedReaderIcon,
                    title: LocalizedStringKey(selectedIPadName ?? "iPad / Mac"),
                    detail: iPadChainDetail,
                    isReady: iPadReady
                )
            }
            .padding(.vertical, 6)

            if watchService.watchAvailability != .ready {
                Label(statusTitle, systemImage: statusIcon)
                Text(statusDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var iPadReady: Bool {
        selectedIPadName != nil && proPurchase.hasProAccess && watchService.isIPadLinkConnected
    }

    private var watchChainDetail: LocalizedStringKey {
        switch watchService.watchAvailability {
        case .unsupported, .unpaired:
            return "page_turn_chain_watch_unpaired"
        case .appNotInstalled:
            return "page_turn_chain_watch_not_installed"
        case .unreachable:
            return "page_turn_chain_watch_closed"
        case .ready:
            return "nearby_ipad_linked"
        }
    }

    private var iPadChainDetail: LocalizedStringKey {
        guard proPurchase.hasProAccess else { return "page_turn_outcome_pro_required" }
        guard selectedIPadName != nil else { return "page_turn_chain_ipad_none" }
        return watchService.isIPadLinkConnected ? "nearby_ipad_linked" : "nearby_ipad_not_linked"
    }

    // MARK: - iPad

    private var nearbyIPadSection: some View {
        Section {
            NavigationLink {
                NearbyIPadSelectionView()
            } label: {
                HStack {
                    Label(LocalizedStringKey("nearby_ipad_choose"), systemImage: "laptopcomputer.and.ipad")
                    Spacer()
                    if let selectedIPadName {
                        Text(selectedIPadName)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 12) {
                pageTurnButton(.prev, title: "nearby_ipad_prev", systemImage: "chevron.left")
                pageTurnButton(.next, title: "nearby_ipad_next", systemImage: "chevron.right")
            }
            .buttonStyle(.bordered)
        } header: {
            Text(LocalizedStringKey("page_turn_ipad_section"))
        } footer: {
            Text(LocalizedStringKey("nearby_ipad_instructions"))
        }
    }

    private func pageTurnButton(_ command: PageCommand, title: String, systemImage: String) -> some View {
        Button {
            isTurningPage = true
            watchService.turnSelectedIPadPage(command) { _ in
                // The result appears under Recent Turns.
                isTurningPage = false
                if !proPurchase.hasProAccess {
                    showPaywall = true
                }
            }
        } label: {
            Label(LocalizedStringKey(title), systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .disabled(isTurningPage)
    }

    // MARK: - Watch status hint

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

// MARK: - Device chain parts

private struct PageTurnChainNode: View {
    let systemImage: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let isReady: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(isReady ? AppColors.accentTeal : Color.secondary)
                .frame(height: 30)
            Text(title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct PageTurnChainConnector: View {
    let isReady: Bool

    var body: some View {
        Capsule()
            .fill(isReady ? AppColors.accentTeal : Color.secondary.opacity(0.3))
            .frame(width: 24, height: 2)
            .padding(.top, 14)
            .accessibilityHidden(true)
    }
}

// MARK: - Recent turns

/// Live list of the latest page turns. Shared by the iPhone and iPad screens:
/// the newest row flashes when it arrives, so a Watch tap is visibly confirmed.
struct WatchPageTurnRecentSection: View {
    let entries: [WatchPageTurnActivity]
    let emptyText: LocalizedStringKey
    var onProRequested: (() -> Void)? = nil
    @State private var highlightedID: UUID?
    @State private var relativeClock = Date()

    var body: some View {
        Section {
            if entries.isEmpty {
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    row(entry, now: relativeClock)
                        .listRowBackground(
                            highlightedID == entry.id
                                ? AppColors.accentTeal.opacity(0.18)
                                : Color(.secondarySystemGroupedBackground)
                        )
                }
            }
        } header: {
            Text(LocalizedStringKey("page_turn_recent_header"))
        }
        .onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) { date in
            relativeClock = date
        }
        .onChange(of: entries.first?.id) { _, newID in
            relativeClock = Date()
            guard let newID else { return }
            withAnimation(.easeOut(duration: 0.15)) { highlightedID = newID }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                guard highlightedID == newID else { return }
                withAnimation(.easeOut(duration: 0.6)) { highlightedID = nil }
            }
        }
    }

    private func row(_ entry: WatchPageTurnActivity, now: Date) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: entry.direction == .next ? "chevron.right.circle.fill" : "chevron.left.circle.fill")
                .font(.title3)
                .foregroundStyle(entry.isSuccess ? AppColors.accentTeal : Color.orange)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(entry.direction == .next ? "nearby_ipad_next" : "nearby_ipad_prev"))
                    .font(.body.weight(.medium))
                Text(LocalizedStringKey(entry.source == .watch ? "page_turn_route_from_watch" : "page_turn_route_from_iphone"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                ForEach(entry.results, id: \.destination) { result in
                    resultText(result)
                }
                Text(Self.relativeTime(entry.date, now: now))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "iPhone 未打开书" / "iPad 已翻页"; on the iPad itself just the outcome.
    private func resultText(_ result: WatchPageTurnActivity.DeviceResult) -> some View {
        let isProReq = result.outcome == .proRequired
        let outcome = Text(LocalizedStringKey(Self.outcomeKey(result.outcome)))
            .foregroundColor(result.outcome == .turned ? .primary : (isProReq ? AppColors.accentTeal : .orange))
            .underline(isProReq, color: AppColors.accentTeal)
        let line: Text
        switch result.destination {
        case .iPhone: line = Text("iPhone ").foregroundColor(.secondary) + outcome
        case .iPad: line = Text((PagePilotNearbySelectionStore.selectedTarget()?.name ?? "iPad / Mac") + " ").foregroundColor(.secondary) + outcome
        case .thisDevice: line = outcome
        }
        return Group {
            if isProReq, let onProRequested {
                Button(action: onProRequested) {
                    HStack(spacing: 3) {
                        line.font(.subheadline)
                        Image(systemName: "crown.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.yellow)
                    }
                }
                .buttonStyle(.plain)
            } else {
                line.font(.subheadline)
            }
        }
    }

    static func outcomeKey(_ outcome: WatchPageTurnOutcome) -> String {
        switch outcome {
        case .turned: return "page_turn_outcome_turned"
        case .notTurned: return "page_turn_outcome_not_turned"
        case .readerNotReady: return "page_turn_outcome_reader_not_ready"
        case .iPadNotFound: return "page_turn_outcome_ipad_not_found"
        case .unreachable: return "page_turn_outcome_unreachable"
        case .proRequired: return "page_turn_outcome_pro_required"
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        return formatter
    }()

    private static func relativeTime(_ date: Date, now: Date) -> String {
        let elapsed = max(0, now.timeIntervalSince(date))
        if elapsed < 10 {
            return NSLocalizedString("page_turn_just_now", comment: "")
        }
        return relativeFormatter.localizedString(for: date, relativeTo: now)
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
