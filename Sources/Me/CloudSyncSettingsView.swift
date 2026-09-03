//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import SwiftUI

struct CloudSyncSettingsView: View {
    let service: CloudSyncService?

    @State private var isEnabled = CloudSyncAccessPolicy.canSync(
        isEnabled: CloudSyncPreferences.isEnabled,
        hasProAccess: ProPurchaseManager.shared.hasProAccess
    )
    @State private var status: CloudSyncStatus = CloudSyncAccessPolicy.canSync(
        isEnabled: CloudSyncPreferences.isEnabled,
        hasProAccess: ProPurchaseManager.shared.hasProAccess
    ) ? .starting : .disabled
    @State private var lastSuccessfulSync = UserDefaults.standard.object(
        forKey: CloudSyncPreferences.lastSuccessfulSyncKey
    ) as? Date
    @State private var showPaywall = false
    @ObservedObject private var proPurchase = ProPurchaseManager.shared

    var body: some View {
        List {
            if proPurchase.hasProAccess {
                syncControlsSection
            } else {
                previewHeroSection
                previewFeaturesSection
                upgradeSection
                previewDetailsSections
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(CloudSyncL10n.text("cloud_sync_section"))
        .toolbarBackground(Color(uiColor: .systemGroupedBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            if proPurchase.hasProAccess {
                status = await service?.currentStatus() ?? .unavailable(
                    CloudSyncL10n.text("cloud_sync_service_unavailable")
                )
                refreshLastSuccessfulSync()
            } else {
                isEnabled = false
                status = .disabled
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cloudSyncStatusDidChange)) { notification in
            guard proPurchase.hasProAccess,
                  let newStatus = notification.object as? CloudSyncStatus
            else { return }
            status = newStatus
            if case .synced(let date) = newStatus {
                lastSuccessfulSync = date
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cloudSyncPreferenceDidChange)) { _ in
            isEnabled = proPurchase.hasProAccess && CloudSyncPreferences.isEnabled
            if !isEnabled {
                status = .disabled
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .proAccessDidChange)) { notification in
            let hasProAccess = notification.object as? Bool ?? proPurchase.hasProAccess
            isEnabled = hasProAccess && CloudSyncPreferences.isEnabled
            if !hasProAccess {
                status = .disabled
            } else {
                Task {
                    status = await service?.currentStatus() ?? .unavailable(
                        CloudSyncL10n.text("cloud_sync_service_unavailable")
                    )
                    refreshLastSuccessfulSync()
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(context: .cloudSync)
        }
    }

    private var syncControlsSection: some View {
        Section {
            Toggle(isOn: enabledBinding) {
                Label {
                    Text(CloudSyncL10n.text("cloud_sync_toggle"))
                } icon: {
                    Image(systemName: "icloud")
                        .foregroundStyle(.blue)
                }
            }

            HStack(spacing: 12) {
                Text(CloudSyncL10n.text("cloud_sync_status"))
                Spacer(minLength: 12)
                statusIndicator
            }

            HStack(spacing: 12) {
                Text(CloudSyncL10n.text("cloud_sync_last_success"))
                Spacer(minLength: 12)
                Text(lastSuccessText)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            Button {
                Task {
                    await service?.syncNow()
                }
            } label: {
                Label(
                    CloudSyncL10n.text("cloud_sync_sync_now"),
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
            .disabled(!isEnabled || status.isBusy)

            NavigationLink {
                CloudSyncInfoView()
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label(CloudSyncL10n.text("cloud_sync_learn_more"), systemImage: "info.circle")
            }
        } footer: {
            Text(statusDetail)
                .foregroundStyle(statusDetailColor)
        }
    }

    private var previewHeroSection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "icloud.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 68, height: 68)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(Circle())

                Text(CloudSyncL10n.text("cloud_sync_preview_title"))
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)

                Text(CloudSyncL10n.text("cloud_sync_preview_subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("PRO")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(AppColors.horizontalGradient)
                    .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    private var previewFeaturesSection: some View {
        Section(CloudSyncL10n.text("cloud_sync_preview_features_title")) {
            previewFeatureRow(
                icon: "books.vertical.fill",
                color: .cyan,
                titleKey: "cloud_sync_feature_books_title",
                subtitleKey: "cloud_sync_feature_books_subtitle"
            )
            previewFeatureRow(
                icon: "book.pages.fill",
                color: .blue,
                titleKey: "cloud_sync_feature_progress_title",
                subtitleKey: "cloud_sync_feature_progress_subtitle"
            )
            previewFeatureRow(
                icon: "highlighter",
                color: .orange,
                titleKey: "cloud_sync_feature_annotations_title",
                subtitleKey: "cloud_sync_feature_annotations_subtitle"
            )
            previewFeatureRow(
                icon: "lock.shield.fill",
                color: .green,
                titleKey: "cloud_sync_feature_private_title",
                subtitleKey: "cloud_sync_feature_private_subtitle"
            )
        }
    }

    private var upgradeSection: some View {
        Section {
            Button {
                Analytics.shared.log(.paywallViewed(source: "cloud_sync_preview_upgrade"))
                showPaywall = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(AppColors.horizontalGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(CloudSyncL10n.text("cloud_sync_pro_title"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(CloudSyncL10n.text("cloud_sync_pro_body"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var previewDetailsSections: some View {
        Section(CloudSyncL10n.text("cloud_sync_first_sync_title")) {
            Text(CloudSyncL10n.text("cloud_sync_first_sync_body"))
        }

        Section(CloudSyncL10n.text("cloud_sync_conflicts_title")) {
            Text(CloudSyncL10n.text("cloud_sync_conflicts_body"))
        }

        Section(CloudSyncL10n.text("cloud_sync_deletions_title")) {
            Text(CloudSyncL10n.text("cloud_sync_deletions_body"))
        }

        Section(CloudSyncL10n.text("cloud_sync_privacy_title")) {
            Text(CloudSyncL10n.text("cloud_sync_privacy_body"))
        }
    }

    private func previewFeatureRow(
        icon: String,
        color: Color,
        titleKey: String,
        subtitleKey: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(CloudSyncL10n.text(titleKey))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(CloudSyncL10n.text(subtitleKey))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { newValue in
                guard proPurchase.hasProAccess else {
                    isEnabled = false
                    showPaywall = true
                    return
                }
                isEnabled = newValue
                status = newValue ? .starting : .disabled
                CloudSyncPreferences.setEnabled(newValue, in: .standard)
            }
        )
    }

    @ViewBuilder
    private var statusIndicator: some View {
        HStack(spacing: 7) {
            if status.isBusy {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: status.iconName)
                    .foregroundStyle(status.color)
            }
            Text(status.title)
                .foregroundStyle(status.color)
                .multilineTextAlignment(.trailing)
        }
    }

    private var lastSuccessText: String {
        guard let lastSuccessfulSync else {
            return CloudSyncL10n.text("cloud_sync_never_synced")
        }
        let formatter = DateFormatter()
        formatter.locale = AppAppearancePreferences.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: lastSuccessfulSync)
    }

    private var statusDetail: String {
        switch status {
        case .disabled:
            return CloudSyncL10n.text("cloud_sync_disabled_detail")
        case .starting, .syncing:
            return CloudSyncL10n.text("cloud_sync_syncing_detail")
        case .synced:
            return CloudSyncL10n.text("cloud_sync_synced_detail")
        case .unavailable(let reason):
            return CloudSyncL10n.text("cloud_sync_unavailable_detail") + "\n" + reason
        case .failed(let reason):
            return CloudSyncL10n.text("cloud_sync_failed_detail") + "\n" + reason
        }
    }

    private var statusDetailColor: Color {
        switch status {
        case .unavailable, .failed:
            return .red
        default:
            return .secondary
        }
    }

    private func refreshLastSuccessfulSync() {
        if case .synced(let date) = status {
            lastSuccessfulSync = date
        } else {
            lastSuccessfulSync = UserDefaults.standard.object(
                forKey: CloudSyncPreferences.lastSuccessfulSyncKey
            ) as? Date
        }
    }
}

private struct CloudSyncInfoView: View {
    var body: some View {
        List {
            Section(CloudSyncL10n.text("cloud_sync_first_sync_title")) {
                Text(CloudSyncL10n.text("cloud_sync_first_sync_body"))
            }

            Section(CloudSyncL10n.text("cloud_sync_conflicts_title")) {
                Text(CloudSyncL10n.text("cloud_sync_conflicts_body"))
            }

            Section(CloudSyncL10n.text("cloud_sync_deletions_title")) {
                Text(CloudSyncL10n.text("cloud_sync_deletions_body"))
            }

            Section(CloudSyncL10n.text("cloud_sync_privacy_title")) {
                Text(CloudSyncL10n.text("cloud_sync_privacy_body"))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(CloudSyncL10n.text("cloud_sync_info_title"))
        .toolbarBackground(Color(uiColor: .systemGroupedBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

enum CloudSyncL10n {
    static func text(_ key: String) -> String {
        NSLocalizedString(
            key,
            tableName: "CloudSync",
            bundle: .main,
            value: key,
            comment: "iCloud sync settings"
        )
    }
}

private extension CloudSyncStatus {
    var isBusy: Bool {
        switch self {
        case .starting, .syncing:
            return true
        case .disabled, .synced, .unavailable, .failed:
            return false
        }
    }

    var title: String {
        switch self {
        case .disabled:
            return CloudSyncL10n.text("cloud_sync_status_off")
        case .starting:
            return CloudSyncL10n.text("cloud_sync_status_connecting")
        case .syncing:
            return CloudSyncL10n.text("cloud_sync_status_syncing")
        case .synced:
            return CloudSyncL10n.text("cloud_sync_status_synced")
        case .unavailable:
            return CloudSyncL10n.text("cloud_sync_status_unavailable")
        case .failed:
            return CloudSyncL10n.text("cloud_sync_status_failed")
        }
    }

    var iconName: String {
        switch self {
        case .disabled:
            return "icloud.slash"
        case .starting, .syncing:
            return "arrow.triangle.2.circlepath"
        case .synced:
            return "checkmark.circle.fill"
        case .unavailable, .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .disabled:
            return .secondary
        case .starting, .syncing:
            return .blue
        case .synced:
            return .green
        case .unavailable, .failed:
            return .red
        }
    }
}
