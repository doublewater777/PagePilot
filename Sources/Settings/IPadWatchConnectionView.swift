//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import SwiftUI

/// iPad-side status for Watch page turn — plain language, not a network console.
struct IPadWatchConnectionView: View {
    @ObservedObject private var service = WatchPageTurnService.shared
    @State private var localIPs: [String] = LocalNetworkInfo.ipv4Addresses()

    private let timer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()

    private var hasWiFi: Bool { !localIPs.isEmpty }

    private var phoneLooksNearby: Bool {
        guard !service.lastLANClientAddress.isEmpty else { return false }
        if let same = LocalNetworkInfo.likelySameSubnet(
            localIPs: localIPs,
            remoteAddress: service.lastLANClientAddress
        ) {
            return same
        }
        // Received a hit recently even if subnet heuristic is unknown.
        return service.isLANWatchConnected || service.lastLANHitAt != nil
    }

    /// Connection readiness only — book-open is not listed here (user is on Settings).
    private var allReady: Bool {
        hasWiFi && service.lanServerRunning && service.isLANWatchConnected
    }

    var body: some View {
        List {
            summarySection
            checklistSection
            if let nextStep {
                nextStepSection(nextStep)
            }
            howItWorksSection
        }
        .listStyle(.insetGrouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(NSLocalizedString("ipad_watch_status_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            WatchPageTurnService.shared.activate()
            refreshLocalNetwork()
        }
        .onReceive(timer) { _ in
            refreshLocalNetwork()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    refreshLocalNetwork()
                    WatchPageTurnService.shared.activate()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel(NSLocalizedString("ipad_watch_status_refresh", comment: ""))
            }
        }
    }

    // MARK: - Summary

    private var summarySection: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: summaryIcon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(summaryColor)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(summaryTitle)
                        .font(.headline)
                    Text(summarySubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
        }
    }

    private var summaryIcon: String {
        if allReady { return "checkmark.circle.fill" }
        if hasWiFi && service.lanServerRunning { return "antenna.radiowaves.left.and.right" }
        return "exclamationmark.circle.fill"
    }

    private var summaryColor: Color {
        if allReady { return AppColors.accentTeal }
        if hasWiFi && service.lanServerRunning { return AppColors.accentBlue }
        return .orange
    }

    private var summaryTitle: String {
        if allReady {
            return NSLocalizedString("ipad_watch_summary_ready", comment: "")
        }
        if !hasWiFi {
            return NSLocalizedString("ipad_watch_summary_no_wifi", comment: "")
        }
        if !service.isLANWatchConnected {
            return NSLocalizedString("ipad_watch_summary_waiting_phone", comment: "")
        }
        return NSLocalizedString("ipad_watch_summary_almost", comment: "")
    }

    private var summarySubtitle: String {
        if allReady {
            return NSLocalizedString("ipad_watch_summary_ready_sub", comment: "")
        }
        if !hasWiFi {
            return NSLocalizedString("ipad_watch_summary_no_wifi_sub", comment: "")
        }
        if !service.isLANWatchConnected {
            return NSLocalizedString("ipad_watch_summary_waiting_phone_sub", comment: "")
        }
        return NSLocalizedString("ipad_watch_summary_almost_sub", comment: "")
    }

    // MARK: - Checklist

    private var checklistSection: some View {
        Section {
            checkRow(
                ok: hasWiFi,
                title: NSLocalizedString("ipad_watch_check_wifi", comment: ""),
                detail: hasWiFi
                    ? NSLocalizedString("ipad_watch_check_wifi_ok", comment: "")
                    : NSLocalizedString("ipad_watch_check_wifi_bad", comment: "")
            )
            checkRow(
                ok: service.lanServerRunning,
                title: NSLocalizedString("ipad_watch_check_ready", comment: ""),
                detail: service.lanServerRunning
                    ? NSLocalizedString("ipad_watch_check_ready_ok", comment: "")
                    : NSLocalizedString("ipad_watch_check_ready_bad", comment: "")
            )
            checkRow(
                ok: service.isLANWatchConnected,
                title: NSLocalizedString("ipad_watch_check_phone", comment: ""),
                detail: phoneDetail
            )
        } header: {
            Text(NSLocalizedString("ipad_watch_checklist_header", comment: ""))
        }
    }

    private var phoneDetail: String {
        if service.isLANWatchConnected {
            if phoneLooksNearby,
               LocalNetworkInfo.likelySameSubnet(
                   localIPs: localIPs,
                   remoteAddress: service.lastLANClientAddress
               ) == false {
                return NSLocalizedString("ipad_watch_check_phone_diff_wifi", comment: "")
            }
            return NSLocalizedString("ipad_watch_check_phone_ok", comment: "")
        }
        if service.lastLANHitAt != nil {
            return NSLocalizedString("ipad_watch_check_phone_recent", comment: "")
        }
        return NSLocalizedString("ipad_watch_check_phone_bad", comment: "")
    }

    // MARK: - Next step

    private var nextStep: String? {
        if allReady { return nil }
        if !hasWiFi {
            return NSLocalizedString("ipad_watch_next_wifi", comment: "")
        }
        if !service.lanServerRunning {
            return NSLocalizedString("ipad_watch_next_restart", comment: "")
        }
        if !service.isLANWatchConnected {
            return NSLocalizedString("ipad_watch_next_phone", comment: "")
        }
        return nil
    }

    private func nextStepSection(_ text: String) -> some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(AppColors.accentBlue)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        } header: {
            Text(NSLocalizedString("ipad_watch_next_header", comment: ""))
        }
    }

    // MARK: - How it works

    private var howItWorksSection: some View {
        Section {
            Text(NSLocalizedString("ipad_watch_how_body", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text(NSLocalizedString("ipad_watch_how_header", comment: ""))
        }
    }

    // MARK: - Rows

    private func checkRow(ok: Bool, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(ok ? AppColors.accentTeal : Color.secondary.opacity(0.45))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func refreshLocalNetwork() {
        localIPs = LocalNetworkInfo.ipv4Addresses()
    }
}

#Preview {
    NavigationStack {
        IPadWatchConnectionView()
    }
}
