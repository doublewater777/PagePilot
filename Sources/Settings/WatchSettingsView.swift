//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import SwiftUI
import WatchConnectivity

// MARK: - Watch Settings View

struct WatchSettingsView: View {
    @State private var crownSensitivity: WatchPageTurnSettings.CrownSensitivity
    @State private var pageTurnAnimation: WatchPageTurnSettings.PageTurnAnimation
    @State private var hapticFeedback: Bool

    @State private var isWatchConnected = WatchPageTurnService.shared.isWatchConnected
    @State private var isLANWatchConnected = WatchPageTurnService.shared.isLANWatchConnected

    init() {
        let settings = WatchPageTurnSettings()
        _crownSensitivity = State(initialValue: settings.crownSensitivity)
        _pageTurnAnimation = State(initialValue: settings.pageTurnAnimation)
        _hapticFeedback = State(initialValue: settings.hapticFeedback)
    }

    private var isConnected: Bool {
        isWatchConnected || isLANWatchConnected
    }

    var body: some View {
        HStack {
            if UIDevice.current.userInterfaceIdiom == .pad {
                Spacer()
            }
            
            List {
                connectionStatusSection
                crownSection
                animationSection
                hapticSection
            }
            .listStyle(.insetGrouped)
            .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? 600 : .infinity)
            
            if UIDevice.current.userInterfaceIdiom == .pad {
                Spacer()
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(NSLocalizedString("watch_settings_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(WatchPageTurnService.shared.$isWatchConnected) { connected in
            isWatchConnected = connected
        }
        .onReceive(WatchPageTurnService.shared.$isLANWatchConnected) { connected in
            isLANWatchConnected = connected
        }
    }

    // MARK: - Connection Status

    private var connectionStatusSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "applewatch")
                    .font(.title2)
                    .foregroundStyle(isConnected ? .green : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("watch_connection_status", comment: ""))
                        .font(.subheadline)
                    
                    let statusText: String = {
                        if isLANWatchConnected {
                            return "已连接 (LAN)"
                        } else if isWatchConnected {
                            return NSLocalizedString("watch_status_connected", comment: "")
                        } else {
                            return NSLocalizedString("watch_status_disconnected", comment: "")
                        }
                    }()
                    
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(isConnected ? .green : .secondary)
                }

                Spacer()

                Circle()
                    .fill(isConnected ? Color.green : Color.red.opacity(0.6))
                    .frame(width: 10, height: 10)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Crown Sensitivity

    private var crownSection: some View {
        Section(
            header: Text(NSLocalizedString("watch_crown_section", comment: "")),
            footer: Text(NSLocalizedString("watch_crown_footer", comment: ""))
        ) {
            ForEach(WatchPageTurnSettings.CrownSensitivity.allCases) { sensitivity in
                Button {
                    crownSensitivity = sensitivity
                    var settings = WatchPageTurnSettings()
                    settings.crownSensitivity = sensitivity
                    settings.syncToWatch()
                } label: {
                    HStack {
                        Text(sensitivity.localizedName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if crownSensitivity == sensitivity {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Page Turn Animation

    private var animationSection: some View {
        Section(
            header: Text(NSLocalizedString("watch_animation_section", comment: "")),
            footer: Text(NSLocalizedString("watch_animation_footer", comment: ""))
        ) {
            ForEach(WatchPageTurnSettings.PageTurnAnimation.allCases) { animation in
                Button {
                    pageTurnAnimation = animation
                    var settings = WatchPageTurnSettings()
                    settings.pageTurnAnimation = animation
                    settings.syncToWatch()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: animation.icon)
                            .font(.body)
                            .frame(width: 28)
                            .foregroundStyle(.tint)

                        Text(animation.localizedName)
                            .foregroundStyle(.primary)

                        Spacer()

                        if pageTurnAnimation == animation {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Haptic Feedback

    private var hapticSection: some View {
        Section(
            header: Text(NSLocalizedString("watch_haptic_section", comment: "")),
            footer: Text(NSLocalizedString("watch_haptic_footer", comment: ""))
        ) {
            Toggle(isOn: Binding(
                get: { hapticFeedback },
                set: { newValue in
                    hapticFeedback = newValue
                    var settings = WatchPageTurnSettings()
                    settings.hapticFeedback = newValue
                    settings.syncToWatch()
                }
            )) {
                Label(
                    NSLocalizedString("watch_haptic_toggle", comment: ""),
                    systemImage: "hand.tap"
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
