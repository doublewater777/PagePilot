//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import AVFoundation
import ObjectiveC
import SwiftUI

// MARK: - Root Settings View

struct SettingsView: View {
    @AppStorage(AppAppearancePreferences.Keys.language) private var selectedLanguage = AppAppearancePreferences.language.rawValue
    @AppStorage(AppAppearancePreferences.Keys.theme) private var selectedTheme = AppTheme.system.rawValue
    @AppStorage(ReadingPreferences.Keys.dailyGoalMinutes) private var dailyGoalMinutes = ReadingPreferences.defaultDailyGoalMinutes
    @State private var localizationRefreshID = AppAppearancePreferences.language.rawValue
    @State private var showPaywall = false
    @State private var hasProAccess = ProPurchaseManager.shared.hasProAccess
    private static var hasAutoShownPaywall = false

    var body: some View {
        List {
            proSection
            
            readingSection
            statsSection
            
            if UIDevice.current.userInterfaceIdiom == .phone {
                watchSection
            }
            ttsSection
            
            appearanceSection
            
            feedbackSection
            aboutSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(NSLocalizedString("settings_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(uiColor: .systemGroupedBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .id(localizationRefreshID)
        .onReceive(NotificationCenter.default.publisher(for: AppAppearancePreferences.languageDidChange)) { _ in
            localizationRefreshID = AppAppearancePreferences.language.rawValue
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .onReceive(NotificationCenter.default.publisher(for: ProPurchaseManager.proAccessDidChange)) { _ in
            hasProAccess = ProPurchaseManager.shared.hasProAccess
        }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-ShowPaywall") && !Self.hasAutoShownPaywall {
                Self.hasAutoShownPaywall = true
                showPaywall = true
            }
        }
        .onChange(of: dailyGoalMinutes) { _, newValue in
            NotificationCenter.default.post(name: ReadingPreferences.dailyGoalDidChange, object: newValue)
        }
    }

    // MARK: - Sections

    private var appearanceSection: some View {
        Section(NSLocalizedString("settings_appearance_section", comment: "")) {
            Picker(selection: languageBinding) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.localizedName).tag(language.rawValue)
                }
            } label: {
                SettingsRow(
                    icon: "globe",
                    iconColor: .blue,
                    title: NSLocalizedString("settings_language", comment: "")
                )
            }

            Picker(selection: themeBinding) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.localizedName).tag(theme.rawValue)
                }
            } label: {
                SettingsRow(
                    icon: "circle.lefthalf.filled",
                    iconColor: .purple,
                    title: NSLocalizedString("settings_theme", comment: "")
                )
            }
        }
    }

    private var readingSection: some View {
        Section(NSLocalizedString("settings_reading_section", comment: "")) {
            Picker(selection: $dailyGoalMinutes) {
                ForEach(Array(stride(
                    from: ReadingPreferences.dailyGoalRange.lowerBound,
                    through: ReadingPreferences.dailyGoalRange.upperBound,
                    by: 5
                )), id: \.self) { minute in
                    Text(String(format: NSLocalizedString("home_minutes", comment: ""), minute)).tag(minute)
                }
            } label: {
                SettingsRow(
                    icon: "target",
                    iconColor: .blue,
                    title: NSLocalizedString("settings_daily_goal", comment: "")
                )
            }
            .pickerStyle(.menu)
        }
    }

    private var watchSection: some View {
        Section(NSLocalizedString("settings_watch_section", comment: "")) {
            NavigationLink {
                LazyView(WatchSettingsView())
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                SettingsRow(
                    icon: "applewatch",
                    iconColor: Color(uiColor: .label),
                    title: NSLocalizedString("settings_watch_page_turn", comment: "")
                )
            }
        }
    }

    private var ttsSection: some View {
        Section(NSLocalizedString("settings_tts_section", comment: "")) {
            NavigationLink {
                LazyView(TTSSettingsView())
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

    private var proSection: some View {
        if hasProAccess {
            // State 1: Pro access active (either active subscription or legacy buyer)
            return AnyView(Section {
                HStack {
                    SettingsRow(
                        icon: "crown.fill",
                        iconColor: .yellow,
                        title: NSLocalizedString("settings_pro_unlocked", comment: "")
                    )
                    Spacer()
                    Text(NSLocalizedString("settings_pro_badge", comment: ""))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.38, green: 0.56, blue: 1.0),
                                    Color(red: 0.56, green: 0.44, blue: 0.96)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(6)
                }
            })
        } else {
            // State 2: Pro access inactive
            return AnyView(Section {
                Button(action: {
                    Analytics.shared.log(.paywallViewed(source: "settings_upgrade_row"))
                    showPaywall = true
                }) {
                    HStack {
                        SettingsRow(
                            icon: "crown.fill",
                            iconColor: .yellow,
                            title: NSLocalizedString("settings_upgrade_pro", comment: "")
                        )
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            })
        }
    }

    private var statsSection: some View {
        Section(NSLocalizedString("settings_stats_section", comment: "")) {
            NavigationLink {
                LazyView(ReadingStatsView())
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                SettingsRow(
                    icon: "chart.bar.xaxis",
                    iconColor: .blue,
                    title: NSLocalizedString("settings_stats", comment: "")
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
            RateAppRow()
            ShareAppRow()
        }
    }

    private var aboutSection: some View {
        Section(NSLocalizedString("settings_about_section", comment: "")) {
            NavigationLink {
                AboutDetailView()
                    .navigationTitle(NSLocalizedString("settings_about", comment: ""))
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                SettingsRow(
                    icon: "info.circle.fill",
                    iconColor: .gray,
                    title: NSLocalizedString("settings_about", comment: "")
                )
            }
        }
    }

    private var languageBinding: Binding<String> {
        Binding(
            get: { selectedLanguage },
            set: { newValue in
                selectedLanguage = newValue
                AppAppearancePreferences.language = AppLanguage(rawValue: newValue) ?? .english
            }
        )
    }

    private var themeBinding: Binding<String> {
        Binding(
            get: { selectedTheme },
            set: { newValue in
                selectedTheme = newValue
                AppAppearancePreferences.theme = AppTheme(rawValue: newValue) ?? .system
            }
        )
    }

}

// MARK: - App Appearance Preferences

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .english:
            return NSLocalizedString("settings_language_english", comment: "")
        case .simplifiedChinese:
            return NSLocalizedString("settings_language_chinese", comment: "")
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .system:
            return NSLocalizedString("settings_theme_system", comment: "")
        case .light:
            return NSLocalizedString("settings_theme_light", comment: "")
        case .dark:
            return NSLocalizedString("settings_theme_dark", comment: "")
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system:
            return .unspecified
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

enum AppAppearancePreferences {
    enum Keys {
        static let language = "app_language"
        static let theme = "app_theme"
    }

    static let languageDidChange = Notification.Name("AppAppearancePreferencesLanguageDidChange")
    static let themeDidChange = Notification.Name("AppAppearancePreferencesThemeDidChange")

    static var language: AppLanguage {
        get {
            if let raw = UserDefaults.standard.string(forKey: Keys.language),
               let language = AppLanguage(rawValue: raw) {
                return language
            }
            return Locale.preferredLanguages.first?.hasPrefix("zh") == true ? .simplifiedChinese : .english
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Keys.language)
            NotificationCenter.default.post(name: languageDidChange, object: newValue)
        }
    }

    static var theme: AppTheme {
        get {
            if let raw = UserDefaults.standard.string(forKey: Keys.theme),
               let theme = AppTheme(rawValue: raw) {
                return theme
            }
            return .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Keys.theme)
            NotificationCenter.default.post(name: themeDidChange, object: newValue)
        }
    }

    static func configureLocalization() {
        Bundle.installAppLanguageOverride()
    }

    static func applyTheme(to window: UIWindow?) {
        window?.overrideUserInterfaceStyle = theme.interfaceStyle
    }

    static var locale: Locale {
        Locale(identifier: language.rawValue)
    }
}

private extension Bundle {
    static func installAppLanguageOverride() {
        _ = appLanguageOverrideInstalled
    }

    static let appLanguageOverrideInstalled: Void = {
        guard
            let original = class_getInstanceMethod(Bundle.self, #selector(Bundle.localizedString(forKey:value:table:))),
            let replacement = class_getInstanceMethod(Bundle.self, #selector(Bundle.appLocalizedString(forKey:value:table:)))
        else { return }

        method_exchangeImplementations(original, replacement)
    }()

    @objc func appLocalizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        guard self == Bundle.main,
              let path = Bundle.main.path(forResource: AppAppearancePreferences.language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            return appLocalizedString(forKey: key, value: value, table: tableName)
        }

        return bundle.appLocalizedString(forKey: key, value: value, table: tableName)
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
        case .bug: return NSLocalizedString("feedback_subject_bug", comment: "")
        case .feature: return NSLocalizedString("feedback_subject_feature", comment: "")
        case .other: return NSLocalizedString("feedback_subject_other", comment: "")
        }
    }

    var bodyTemplate: String {
        let device = UIDevice.current
        let appVersion = Bundle.main.appVersion
        let buildVersion = Bundle.main.buildVersion
        let systemInfo = "\(device.model), iOS \(device.systemVersion), App \(appVersion) (\(buildVersion))"

        let deviceInfoHeader = NSLocalizedString("feedback_body_device_info", comment: "")

        switch self {
        case .bug:
            let descHeader = NSLocalizedString("feedback_body_description", comment: "")
            let stepsHeader = NSLocalizedString("feedback_body_reproduce_steps", comment: "")
            let expectedHeader = NSLocalizedString("feedback_body_expected", comment: "")
            let actualHeader = NSLocalizedString("feedback_body_actual", comment: "")
            return "\n\n\n---\n\(deviceInfoHeader): \(systemInfo)\n\n\(descHeader):\n\n\(stepsHeader):\n1. \n2. \n3. \n\n\(expectedHeader):\n\n\(actualHeader):\n"
        case .feature:
            let descHeader = NSLocalizedString("feedback_body_feature_description", comment: "")
            let useCasesHeader = NSLocalizedString("feedback_body_use_cases", comment: "")
            return "\n\n\n---\n\(deviceInfoHeader): \(systemInfo)\n\n\(descHeader):\n\n\(useCasesHeader):\n"
        case .other:
            return "\n\n\n---\n\(deviceInfoHeader): \(systemInfo)\n"
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

// MARK: - Rate App

private struct RateAppRow: View {
    var body: some View {
        Button(action: AppStoreReviewLink.open) {
            HStack {
                SettingsRow(
                    icon: "star.bubble.fill",
                    iconColor: .orange,
                    title: NSLocalizedString("settings_rate_app", comment: "")
                )
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private enum AppStoreReviewLink {
    private static let nativeURL = URL(string: "itms-apps://apps.apple.com/app/id6760964443?action=write-review")
    private static let webURL = URL(string: "https://apps.apple.com/app/id6760964443?action=write-review")

    static func open() {
        guard let nativeURL else { return }

        UIApplication.shared.open(nativeURL) { success in
            guard !success, let webURL else { return }
            UIApplication.shared.open(webURL)
        }
    }
}

// MARK: - Share App

private struct ShareAppRow: View {
    @State private var showShareSheet = false

    var body: some View {
        Button(action: { showShareSheet = true }) {
            HStack {
                SettingsRow(
                    icon: "square.and.arrow.up",
                    iconColor: .blue,
                    title: NSLocalizedString("settings_share_app", comment: "")
                )
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showShareSheet) {
            ActivityViewController(
                activityItems: [
                    NSLocalizedString("settings_share_app_message", comment: "")
                ]
            )
        }
    }
}

private struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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

// MARK: - LazyView Helper
struct LazyView<Content: View>: View {
    private let build: () -> Content
    
    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }
    
    var body: Content {
        build()
    }
}

// MARK: - About Us Detail Page (二级页)
private struct AboutDetailView: View {
    var body: some View {
        List {
            Section {
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

                HStack {
                    SettingsRow(
                        icon: "doc.text",
                        iconColor: .secondary,
                        title: NSLocalizedString("settings_icp_filing", comment: "")
                    )
                    Spacer()
                    Text("浙ICP备2026041359号-1A")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                // 隐私政策
                Button(action: {
                    if let url = URL(string: "https://pagepilot.doublewaterapps.com/privacy.html") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack {
                        SettingsRow(
                            icon: "lock.shield",
                            iconColor: .blue,
                            title: NSLocalizedString("paywall_privacy_policy", comment: "")
                        )
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // 使用条款
                Button(action: {
                    if let url = URL(string: "https://pagepilot.doublewaterapps.com/terms.html") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack {
                        SettingsRow(
                            icon: "doc.text",
                            iconColor: .blue,
                            title: NSLocalizedString("paywall_terms_of_use", comment: "")
                        )
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}
