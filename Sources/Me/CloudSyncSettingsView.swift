//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import SwiftUI

extension MeView {
    @ViewBuilder
    var cloudSyncSection: some View {
        if let service = AppModule.shared?.cloudSync {
            CloudSyncSettingsSection(service: service)
        }
    }
}

private struct CloudSyncSettingsSection: View {
    let service: CloudSyncService

    @State private var isEnabled = CloudSyncPreferences.isEnabled
    @State private var status: CloudSyncStatus = CloudSyncPreferences.isEnabled ? .starting : .disabled
    @State private var lastSuccessfulSync = UserDefaults.standard.object(
        forKey: CloudSyncPreferences.lastSuccessfulSyncKey
    ) as? Date

    var body: some View {
        Section {
            Toggle(isOn: enabledBinding) {
                Label {
                    Text(L10n.text("cloud_sync_toggle"))
                } icon: {
                    Image(systemName: "icloud")
                        .foregroundStyle(.blue)
                }
            }

            HStack(spacing: 12) {
                Text(L10n.text("cloud_sync_status"))
                Spacer(minLength: 12)
                statusIndicator
            }

            HStack(spacing: 12) {
                Text(L10n.text("cloud_sync_last_success"))
                Spacer(minLength: 12)
                Text(lastSuccessText)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            Button {
                Task {
                    await service.syncNow()
                }
            } label: {
                Label(L10n.text("cloud_sync_sync_now"), systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!isEnabled || status.isBusy)

            NavigationLink {
                CloudSyncInfoView()
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label(L10n.text("cloud_sync_learn_more"), systemImage: "info.circle")
            }
        } header: {
            Text(L10n.text("cloud_sync_section"))
        } footer: {
            Text(statusDetail)
                .foregroundStyle(statusDetailColor)
        }
        .task {
            status = await service.currentStatus()
            refreshLastSuccessfulSync()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cloudSyncStatusDidChange)) { notification in
            guard let newStatus = notification.object as? CloudSyncStatus else { return }
            status = newStatus
            if case .synced(let date) = newStatus {
                lastSuccessfulSync = date
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cloudSyncPreferenceDidChange)) { _ in
            isEnabled = CloudSyncPreferences.isEnabled
            if !isEnabled {
                status = .disabled
            }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { newValue in
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
            return L10n.text("cloud_sync_never_synced")
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
            return L10n.text("cloud_sync_disabled_detail")
        case .starting, .syncing:
            return L10n.text("cloud_sync_syncing_detail")
        case .synced:
            return L10n.text("cloud_sync_synced_detail")
        case .unavailable(let reason):
            return L10n.text("cloud_sync_unavailable_detail") + "\n" + reason
        case .failed(let reason):
            return L10n.text("cloud_sync_failed_detail") + "\n" + reason
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
            Section(L10n.text("cloud_sync_first_sync_title")) {
                Text(L10n.text("cloud_sync_first_sync_body"))
            }

            Section(L10n.text("cloud_sync_conflicts_title")) {
                Text(L10n.text("cloud_sync_conflicts_body"))
            }

            Section(L10n.text("cloud_sync_deletions_title")) {
                Text(L10n.text("cloud_sync_deletions_body"))
            }

            Section(L10n.text("cloud_sync_privacy_title")) {
                Text(L10n.text("cloud_sync_privacy_body"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.text("cloud_sync_info_title"))
    }
}

private enum L10n {
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
            return L10n.text("cloud_sync_status_off")
        case .starting:
            return L10n.text("cloud_sync_status_connecting")
        case .syncing:
            return L10n.text("cloud_sync_status_syncing")
        case .synced:
            return L10n.text("cloud_sync_status_synced")
        case .unavailable:
            return L10n.text("cloud_sync_status_unavailable")
        case .failed:
            return L10n.text("cloud_sync_status_failed")
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
