//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import SwiftUI

/// iPad side of Watch Page Turn: live state instead of a self-test. Shows
/// whether this iPad is receiving, whether an iPhone holds a link right now,
/// and the latest turns as they arrive.
struct IPadWatchConnectionView: View {
    @State private var showPaywall = false
    @ObservedObject private var service = WatchPageTurnService.shared
    @ObservedObject private var proPurchase = ProPurchaseManager.shared

    private var isReceiving: Bool {
        proPurchase.hasProAccess && service.peerHostState.isListening
    }

    private var isPhoneLinked: Bool {
        isReceiving && service.peerHostState.connectedPeerCount > 0
    }

    var body: some View {
        List {
            statusSection
            WatchPageTurnRecentSection(
                entries: service.activityLog.entries,
                emptyText: "page_turn_recent_empty_ipad",
                onProRequested: {
                    Analytics.shared.log(.paywallViewed(source: "ipad_watch_recent_pro_entry"))
                    showPaywall = true
                }
            )
        }
        .listStyle(.insetGrouped)
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(NSLocalizedString("watch_settings_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            PaywallView(context: .iPadWatchRelay, analyticsSource: "ipad_watch_settings_upgrade")
        }
        .onAppear {
            service.activate()
        }
    }

    private var statusSection: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: statusIcon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(isPhoneLinked ? AppColors.accentTeal : Color.secondary)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(statusTitle))
                        .font(.headline)
                    Text(LocalizedStringKey(statusDetail))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)

            if !proPurchase.hasProAccess {
                VStack(alignment: .leading, spacing: 10) {
                    Text(LocalizedStringKey("ipad_page_turn_pro_required"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        Analytics.shared.log(.paywallViewed(source: "ipad_watch_status_pro_button"))
                        showPaywall = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "crown.fill")
                                .foregroundColor(.yellow)
                            Text(NSLocalizedString("settings_upgrade_pro", comment: ""))
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.accentTeal)
                    .padding(.top, 2)
                }
                .padding(.vertical, 4)
            } else if !isPhoneLinked {
                Text(LocalizedStringKey("ipad_page_turn_hint"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusIcon: String {
        if isPhoneLinked { return "checkmark.circle.fill" }
        return isReceiving ? "antenna.radiowaves.left.and.right" : "pause.circle"
    }

    private var statusTitle: String {
        guard proPurchase.hasProAccess else { return "ipad_page_turn_not_receiving" }
        return isReceiving ? "ipad_page_turn_receiving" : "ipad_page_turn_starting"
    }

    private var statusDetail: String {
        isPhoneLinked ? "ipad_page_turn_phone_linked" : "ipad_page_turn_phone_waiting"
    }
}

#Preview {
    NavigationStack {
        IPadWatchConnectionView()
    }
}
