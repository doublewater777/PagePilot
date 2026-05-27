//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import AVFoundation
import SwiftUI

// MARK: - Root Settings View

struct SettingsView: View {
    var body: some View {
        HStack {
            if UIDevice.current.userInterfaceIdiom == .pad {
                Spacer()
            }
            
            List {
                watchSection
                ttsSection
                feedbackSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? 600 : .infinity)
            
            if UIDevice.current.userInterfaceIdiom == .pad {
                Spacer()
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(NSLocalizedString("settings_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var watchSection: some View {
        Section(NSLocalizedString("settings_watch_section", comment: "")) {
            NavigationLink {
                WatchSettingsView()
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                SettingsRow(
                    icon: "applewatch",
                    iconColor: .black,
                    title: NSLocalizedString("settings_watch_page_turn", comment: "")
                )
            }
        }
    }

    private var ttsSection: some View {
        Section(NSLocalizedString("settings_tts_section", comment: "")) {
            NavigationLink {
                TTSSettingsView()
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                SettingsRow(
                    icon: "speaker.wave.2.fill",
                    iconColor: .blue,
                    title: NSLocalizedString("settings_tts_voice", comment: "")
                )
            }
        }
    }

    private var feedbackSection: some View {
        Section(NSLocalizedString("settings_feedback_section", comment: "")) {
            FeedbackRow(
                type: .bug,
                icon: "ladybug.fill",
                iconColor: .red,
                title: NSLocalizedString("settings_feedback_bug", comment: "")
            )
            FeedbackRow(
                type: .feature,
                icon: "lightbulb.fill",
                iconColor: .yellow,
                title: NSLocalizedString("settings_feedback_feature", comment: "")
            )
            FeedbackRow(
                type: .other,
                icon: "envelope.fill",
                iconColor: .green,
                title: NSLocalizedString("settings_feedback_other", comment: "")
            )
        }
    }

    private var aboutSection: some View {
        Section(NSLocalizedString("settings_about_section", comment: "")) {
            NavigationLink {
                AboutView()
                    .navigationTitle(NSLocalizedString("about_title", comment: ""))
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                SettingsRow(
                    icon: "info.circle.fill",
                    iconColor: .gray,
                    title: NSLocalizedString("settings_about", comment: "")
                )
            }

            HStack {
                SettingsRow(
                    icon: "number",
                    iconColor: .secondary,
                    title: NSLocalizedString("settings_version", comment: "")
                )
                Spacer()
                Text("\(Bundle.main.appVersion) (\(Bundle.main.buildVersion))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Reusable Row

private struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            Text(title)
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Feedback

private enum FeedbackType {
    case bug, feature, other

    var subject: String {
        switch self {
        case .bug: return "[Bug] PagePilot 反馈"
        case .feature: return "[Feature Request] PagePilot 功能建议"
        case .other: return "[Feedback] PagePilot 反馈"
        }
    }

    var bodyTemplate: String {
        let device = UIDevice.current
        let appVersion = Bundle.main.appVersion
        let buildVersion = Bundle.main.buildVersion
        let systemInfo = "\(device.model), iOS \(device.systemVersion), App \(appVersion) (\(buildVersion))"

        switch self {
        case .bug:
            return "\n\n\n---\n设备信息：\(systemInfo)\n\n问题描述：\n\n复现步骤：\n1. \n2. \n3. \n\n期望行为：\n\n实际行为：\n"
        case .feature:
            return "\n\n\n---\n设备信息：\(systemInfo)\n\n功能描述：\n\n使用场景：\n"
        case .other:
            return "\n\n\n---\n设备信息：\(systemInfo)\n"
        }
    }
}

private struct FeedbackRow: View {
    let type: FeedbackType
    let icon: String
    let iconColor: Color
    let title: String

    @State private var showMailError = false

    private static let feedbackEmail = "return_panyang@163.com"

    var body: some View {
        Button(action: sendFeedback) {
            HStack {
                SettingsRow(icon: icon, iconColor: iconColor, title: title)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .alert(
            NSLocalizedString("settings_feedback_mail_error_title", comment: ""),
            isPresented: $showMailError
        ) {
            Button(NSLocalizedString("settings_feedback_copy_email", comment: "")) {
                UIPasteboard.general.string = Self.feedbackEmail
            }
            Button(NSLocalizedString("ok_button", comment: ""), role: .cancel) {}
        } message: {
            Text(String(
                format: NSLocalizedString("settings_feedback_mail_error_message", comment: ""),
                Self.feedbackEmail
            ))
        }
    }

    private func sendFeedback() {
        let allowed = CharacterSet.urlQueryAllowed
        let subject = type.subject.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        let body = type.bodyTemplate.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        let mailto = "mailto:\(Self.feedbackEmail)?subject=\(subject)&body=\(body)"

        guard let url = URL(string: mailto), UIApplication.shared.canOpenURL(url) else {
            showMailError = true
            return
        }

        UIApplication.shared.open(url)
    }
}

// MARK: - Helpers

private extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var buildVersion: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }
}

#Preview {
    NavigationView {
        SettingsView()
    }
    .navigationViewStyle(.stack)
}
