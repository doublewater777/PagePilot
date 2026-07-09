//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import SwiftUI
import UIKit

// MARK: - Watch Settings View

struct WatchSettingsView: View {
    @State private var controlTarget: WatchPageTurnSettings.ControlTarget
    @State private var doubleTapPageTurn: Bool
    @State private var hasProAccess = ProPurchaseManager.shared.hasProAccess
    @State private var showsPaywall = false
    @State private var showSetupGuide = false

    init() {
        let settings = WatchPageTurnSettings()
        _controlTarget = State(initialValue: settings.controlTarget)
        _doubleTapPageTurn = State(initialValue: settings.doubleTapPageTurn)
    }

    var body: some View {
        List {
            guideSection
            targetSection
            guidanceSection
            doubleTapSection
        }
        .listStyle(.insetGrouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(NSLocalizedString("watch_settings_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showSetupGuide) {
            WatchSetupGuideView {
                showSetupGuide = false
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
        .onAppear {
            if controlTarget == .iPad {
                WatchPageTurnService.shared.prepareIPadRelay()
                WatchPageTurnService.shared.probeIPadRelayNow()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ProPurchaseManager.proAccessDidChange)) { _ in
            hasProAccess = ProPurchaseManager.shared.hasProAccess
        }
    }

    // MARK: - Setup guide entry

    private var guideSection: some View {
        Section {
            Button {
                showSetupGuide = true
            } label: {
                Label(
                    NSLocalizedString("watch_setup_guide_button", comment: ""),
                    systemImage: "questionmark.circle"
                )
            }
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
                        if newValue == .iPad {
                            WatchPageTurnService.shared.prepareIPadRelay()
                            // Kick an immediate status probe so an open iPad diagnostics page can pass “iPhone test”.
                            WatchPageTurnService.shared.probeIPadRelayNow()
                        }
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

// MARK: - First-time setup guide

private struct WatchSetupGuideView: View {
    let onFinish: () -> Void

    private let steps: [(icon: String, titleKey: String, bodyKey: String)] = [
        ("applewatch", "watch_setup_step1_title", "watch_setup_step1_body"),
        ("ipad.and.iphone", "watch_setup_step2_title", "watch_setup_step2_body"),
        ("book.closed", "watch_setup_step3_title", "watch_setup_step3_body"),
    ]

    /// Fits header + 3 steps + CTA without scrolling on typical phones.
    private static let sheetHeight: CGFloat = 500

    var body: some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            VStack(spacing: 6) {
                Image(systemName: "applewatch.watchface")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppColors.accentBlue)
                    .frame(width: 44, height: 44)
                    .background(AppColors.accentBlue.opacity(0.12))
                    .clipShape(Circle())

                Text(NSLocalizedString("watch_setup_title", comment: ""))
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(AppColors.primaryText)
                    .multilineTextAlignment(.center)

                Text(NSLocalizedString("watch_setup_subtitle", comment: ""))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppColors.accentBlue)
                            .frame(width: 24, height: 24)
                            .background(AppColors.accentBlue.opacity(0.12))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString(step.titleKey, comment: ""))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppColors.primaryText)
                            Text(NSLocalizedString(step.bodyKey, comment: ""))
                                .font(.system(size: 13))
                                .foregroundStyle(AppColors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(
                        AppColors.cardBackground,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
            }

            Button(action: onFinish) {
                Text(NSLocalizedString("watch_setup_done_button", comment: ""))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(AppColors.horizontalGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(WatchGuidePressStyle())
            .padding(.top, 2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground))
        .presentationDetents([.height(Self.sheetHeight)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color(.systemGroupedBackground))
    }
}

private struct WatchGuidePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    NavigationView {
        WatchSettingsView()
    }
    .navigationViewStyle(.stack)
}
