//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import SwiftUI

// MARK: - Watch Settings View

struct WatchSettingsView: View {
    @State private var hapticFeedback: Bool
    @State private var controlTarget: WatchPageTurnSettings.ControlTarget
    @State private var hasProAccess = ProPurchaseManager.shared.hasProAccess
    @State private var showsPaywall = false

    init() {
        let settings = WatchPageTurnSettings()
        _hapticFeedback = State(initialValue: settings.hapticFeedback)
        _controlTarget = State(initialValue: settings.controlTarget)
    }

    var body: some View {
        HStack {
            if UIDevice.current.userInterfaceIdiom == .pad {
                Spacer()
            }
            
            List {
                targetSection
                guidanceSection
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
        .sheet(isPresented: $showsPaywall) {
            PaywallView()
        }
        .onReceive(NotificationCenter.default.publisher(for: ProPurchaseManager.proAccessDidChange)) { _ in
            hasProAccess = ProPurchaseManager.shared.hasProAccess
        }
    }

    // MARK: - Target

    private var targetSection: some View {
        Section(
            header: Text(NSLocalizedString("watch_target_section", comment: "")),
            footer: Text(NSLocalizedString("watch_target_footer", comment: ""))
        ) {
            Picker(
                NSLocalizedString("watch_target_picker", comment: ""),
                selection: Binding(
                    get: { controlTarget },
                    set: { newValue in
                        guard newValue != .iPad || hasProAccess else {
                            showsPaywall = true
                            return
                        }

                        controlTarget = newValue
                        var settings = WatchPageTurnSettings()
                        settings.controlTarget = newValue
                        settings.syncToWatch()
                    }
                )
            ) {
                ForEach(WatchPageTurnSettings.ControlTarget.allCases) { target in
                    Text(targetName(for: target))
                        .tag(target)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func targetName(for target: WatchPageTurnSettings.ControlTarget) -> String {
        guard target == .iPad, !hasProAccess else {
            return target.localizedName
        }
        return String(format: NSLocalizedString("watch_target_ipad_pro", comment: ""), target.localizedName)
    }

    // MARK: - Guidance

    private var guidanceSection: some View {
        let footerKey = controlTarget == .iPad ? "watch_guidance_ipad_footer" : "watch_guidance_iphone_footer"

        return Section(
            header: Text(NSLocalizedString("watch_guidance_header", comment: "")),
            footer: Text(NSLocalizedString(footerKey, comment: ""))
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if controlTarget == .iPad {
                    stepRow(number: 1, textKey: "watch_guidance_ipad_step1")
                    stepRow(number: 2, textKey: "watch_guidance_ipad_step2")
                    stepRow(number: 3, textKey: "watch_guidance_ipad_step3")
                } else {
                    stepRow(number: 1, textKey: "watch_guidance_iphone_step1")
                    stepRow(number: 2, textKey: "watch_guidance_iphone_step2")
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func stepRow(number: Int, textKey: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 24, height: 24)
                Text("\(number)")
                    .font(.caption2.bold())
                    .foregroundColor(.accentColor)
            }
            Text(NSLocalizedString(textKey, comment: ""))
                .font(.subheadline)
            Spacer()
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
