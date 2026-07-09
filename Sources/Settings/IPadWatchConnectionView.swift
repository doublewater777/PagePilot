//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import SwiftUI

/// iPad-side connection test for Watch page turn.
/// Opens with an active probe: local service self-test + listen window for a real iPhone hit.
struct IPadWatchConnectionView: View {
    @ObservedObject private var service = WatchPageTurnService.shared
    @State private var localIPs: [String] = LocalNetworkInfo.ipv4Addresses()

    @State private var isProbing = false
    @State private var localProbeOK = false
    @State private var phoneProbeOK = false
    @State private var probeStartedAt: Date?
    @State private var probeTask: Task<Void, Never>?

    private let probeListenSeconds: TimeInterval = 12

    private var hasWiFi: Bool { !localIPs.isEmpty }

    private var phoneHitDuringProbe: Bool {
        guard let started = probeStartedAt,
              let remoteHit = service.lastRemoteLANHitAt else { return false }
        return remoteHit >= started
    }

    private var phoneOK: Bool {
        phoneProbeOK || phoneHitDuringProbe || service.isLANWatchConnected
    }

    private var allReady: Bool {
        hasWiFi && localProbeOK && phoneOK
    }

    var body: some View {
        List {
            summarySection
            checklistSection
            testButtonSection
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
            localIPs = LocalNetworkInfo.ipv4Addresses()
            startProbe()
        }
        .onDisappear {
            probeTask?.cancel()
            probeTask = nil
        }
        .onChange(of: service.lastRemoteLANHitAt) { _, _ in
            if phoneHitDuringProbe {
                phoneProbeOK = true
            }
        }
        .onChange(of: service.isLANWatchConnected) { _, connected in
            if connected, probeStartedAt != nil {
                phoneProbeOK = true
            }
        }
    }

    // MARK: - Summary

    private var summarySection: some View {
        Section {
            HStack(spacing: 14) {
                Group {
                    if isProbing {
                        ProgressView()
                            .controlSize(.regular)
                    } else {
                        Image(systemName: summaryIcon)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(summaryColor)
                    }
                }
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
        if hasWiFi && localProbeOK { return "antenna.radiowaves.left.and.right" }
        return "exclamationmark.circle.fill"
    }

    private var summaryColor: Color {
        if allReady { return AppColors.accentTeal }
        if hasWiFi && localProbeOK { return AppColors.accentBlue }
        return .orange
    }

    private var summaryTitle: String {
        if isProbing {
            return NSLocalizedString("ipad_watch_summary_probing", comment: "")
        }
        if allReady {
            return NSLocalizedString("ipad_watch_summary_ready", comment: "")
        }
        if !hasWiFi {
            return NSLocalizedString("ipad_watch_summary_no_wifi", comment: "")
        }
        if !localProbeOK {
            return NSLocalizedString("ipad_watch_summary_service_fail", comment: "")
        }
        if !phoneOK {
            return NSLocalizedString("ipad_watch_summary_waiting_phone", comment: "")
        }
        return NSLocalizedString("ipad_watch_summary_almost", comment: "")
    }

    private var summarySubtitle: String {
        if isProbing {
            return NSLocalizedString("ipad_watch_summary_probing_sub", comment: "")
        }
        if allReady {
            return NSLocalizedString("ipad_watch_summary_ready_sub", comment: "")
        }
        if !hasWiFi {
            return NSLocalizedString("ipad_watch_summary_no_wifi_sub", comment: "")
        }
        if !localProbeOK {
            return NSLocalizedString("ipad_watch_summary_service_fail_sub", comment: "")
        }
        if !phoneOK {
            return NSLocalizedString("ipad_watch_summary_waiting_phone_sub", comment: "")
        }
        return NSLocalizedString("ipad_watch_summary_almost_sub", comment: "")
    }

    // MARK: - Checklist

    private var checklistSection: some View {
        Section {
            checkRow(
                ok: hasWiFi,
                pending: false,
                title: NSLocalizedString("ipad_watch_check_wifi", comment: ""),
                detail: hasWiFi
                    ? NSLocalizedString("ipad_watch_check_wifi_ok", comment: "")
                    : NSLocalizedString("ipad_watch_check_wifi_bad", comment: "")
            )
            checkRow(
                ok: localProbeOK,
                pending: isProbing && !localProbeOK,
                title: NSLocalizedString("ipad_watch_check_ready", comment: ""),
                detail: localProbeDetail
            )
            checkRow(
                ok: phoneOK,
                pending: isProbing && localProbeOK && !phoneOK,
                title: NSLocalizedString("ipad_watch_check_phone", comment: ""),
                detail: phoneDetail
            )
        } header: {
            Text(NSLocalizedString("ipad_watch_checklist_header", comment: ""))
        } footer: {
            Text(NSLocalizedString("ipad_watch_checklist_footer", comment: ""))
        }
    }

    private var localProbeDetail: String {
        if isProbing && !localProbeOK {
            return NSLocalizedString("ipad_watch_check_ready_testing", comment: "")
        }
        if localProbeOK {
            return NSLocalizedString("ipad_watch_check_ready_ok", comment: "")
        }
        return NSLocalizedString("ipad_watch_check_ready_bad", comment: "")
    }

    private var phoneDetail: String {
        if isProbing && !phoneOK {
            return NSLocalizedString("ipad_watch_check_phone_testing", comment: "")
        }
        if phoneOK {
            if let same = LocalNetworkInfo.likelySameSubnet(
                localIPs: localIPs,
                remoteAddress: service.lastLANClientAddress
            ), !same {
                return NSLocalizedString("ipad_watch_check_phone_diff_wifi", comment: "")
            }
            return NSLocalizedString("ipad_watch_check_phone_ok", comment: "")
        }
        return NSLocalizedString("ipad_watch_check_phone_bad", comment: "")
    }

    // MARK: - Retest

    private var testButtonSection: some View {
        Section {
            Button {
                startProbe()
            } label: {
                HStack {
                    Spacer()
                    if isProbing {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text(NSLocalizedString("ipad_watch_probe_running", comment: ""))
                    } else {
                        Image(systemName: "waveform.path.ecg")
                        Text(NSLocalizedString("ipad_watch_probe_button", comment: ""))
                    }
                    Spacer()
                }
                .font(.body.weight(.semibold))
            }
            .disabled(isProbing)
        }
    }

    // MARK: - Next step

    private var nextStep: String? {
        if isProbing || allReady { return nil }
        if !hasWiFi {
            return NSLocalizedString("ipad_watch_next_wifi", comment: "")
        }
        if !localProbeOK {
            return NSLocalizedString("ipad_watch_next_restart", comment: "")
        }
        if !phoneOK {
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

    // MARK: - Probe

    private func startProbe() {
        probeTask?.cancel()
        isProbing = true
        localProbeOK = false
        phoneProbeOK = false
        probeStartedAt = Date()
        localIPs = LocalNetworkInfo.ipv4Addresses()

        WatchPageTurnService.shared.activate()

        probeTask = Task { @MainActor in
            // 1) Active self-test against the local page-turn service.
            let localOK = await WatchPageTurnService.shared.runLocalStatusProbe()
            guard !Task.isCancelled else { return }
            localProbeOK = localOK

            // 2) Listen for a real remote (iPhone) hit during this probe window.
            let deadline = Date().addingTimeInterval(probeListenSeconds)
            while Date() < deadline {
                if Task.isCancelled { return }
                if phoneHitDuringProbe || service.isLANWatchConnected {
                    phoneProbeOK = true
                    break
                }
                try? await Task.sleep(nanoseconds: 400_000_000)
            }

            if !Task.isCancelled {
                isProbing = false
            }
        }
    }

    // MARK: - Rows

    private func checkRow(ok: Bool, pending: Bool, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if pending {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(ok ? AppColors.accentTeal : Color.secondary.opacity(0.45))
                }
            }
            .frame(width: 22, height: 22)
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
}

#Preview {
    NavigationStack {
        IPadWatchConnectionView()
    }
}
