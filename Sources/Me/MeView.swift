//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import AVFoundation
import ObjectiveC
import SafariServices
import SwiftUI

// MARK: - Root Me View

struct MeView: View {
    @AppStorage(AppAppearancePreferences.Keys.language) private var selectedLanguage = AppAppearancePreferences.language.rawValue
    @AppStorage(AppAppearancePreferences.Keys.theme) private var selectedTheme = AppTheme.system.rawValue
    @AppStorage(ReadingPreferences.Keys.dailyGoalMinutes) private var dailyGoalMinutes = ReadingPreferences.defaultDailyGoalMinutes
    @AppStorage(ReadingPreferences.Keys.reminderEnabled) private var reminderEnabled = ReadingPreferences.defaultReminderEnabled
    @AppStorage(ReadingPreferences.Keys.launchDirectlyToReader) private var launchDirectlyToReader = ReadingPreferences.defaultLaunchDirectlyToReader
    @AppStorage(VolumeKeyService.volumeKeyEnabledKey) private var volumeKeyEnabled = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var localizationRefreshID = AppAppearancePreferences.language.rawValue
    @State private var showPaywall = false
    @State private var paywallContext: PaywallContext = .general
    @ObservedObject private var proPurchase = ProPurchaseManager.shared
    @ObservedObject private var watchService = WatchPageTurnService.shared
    @ObservedObject private var intelligenceEngine = ReadingIntelligenceEngine.shared
    private static var hasAutoShownPaywall = false

    private var goalSummaryText: String {
        let base = String(format: NSLocalizedString("home_minutes", comment: ""), dailyGoalMinutes)
        if reminderEnabled {
            let time = String(format: "%02d:%02d", ReadingPreferences.reminderHour, ReadingPreferences.reminderMinute)
            return "\(base) · \(time)"
        }
        return base
    }

    private var ttsRateSummary: String {
        let ratio = Double(TTSPreferences().rate / AVSpeechUtteranceDefaultSpeechRate)
        return String(format: "%.1f×", max(0.5, min(2.0, ratio)))
    }

    private var nativeIntelligenceStatusText: String {
        switch intelligenceEngine.nativeAvailability {
        case .available:
            return NSLocalizedString("ai_status_native_available", comment: "")
        case .simulated:
            return NSLocalizedString("ai_badge_simulated_preview", comment: "")
        case .unavailable(let reason):
            return reason
        }
    }

    var body: some View {
        List {
            proSection

            readingExperienceSection
            syncAndAppearanceSection
            supportAndAboutSection
            debugSection
            versionFooterSection
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(14)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 6, for: .scrollContent)
        .contentMargins(.bottom, 28, for: .scrollContent)
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle(NSLocalizedString("settings_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .id(localizationRefreshID)
        .onReceive(NotificationCenter.default.publisher(for: AppAppearancePreferences.languageDidChange)) { _ in
            localizationRefreshID = AppAppearancePreferences.language.rawValue
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(context: paywallContext)
        }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-ShowPaywall") && !Self.hasAutoShownPaywall {
                Self.hasAutoShownPaywall = true
                showPaywall = true
            }
        }
    }

    // MARK: - Sections

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(AppColors.secondaryText)
            .textCase(nil)
    }

    private var readingExperienceSection: some View {
        Section {
            Toggle(isOn: $launchDirectlyToReader) {
                MeRow(
                    icon: "bolt.fill",
                    iconColor: AppColors.accentTeal,
                    title: NSLocalizedString("settings_launch_to_reader", comment: ""),
                    subtitle: NSLocalizedString("settings_launch_to_reader_subtitle", comment: "")
                )
            }
            .tint(AppColors.accentTeal)

            NavigationLink {
                LazyView(ReadingGoalSettingsView())
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                MeRow(
                    icon: "target",
                    iconColor: AppColors.accentBlue,
                    title: NSLocalizedString("settings_goal_reminder", comment: ""),
                    trailingText: goalSummaryText
                )
            }

            if UIDevice.current.userInterfaceIdiom == .phone {
                NavigationLink {
                    LazyView(WatchSettingsView())
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    MeRow(
                        icon: "applewatch",
                        iconColor: Color(uiColor: .label),
                        title: NSLocalizedString("watch_settings_title", comment: ""),
                        trailingText: watchService.watchAvailability == .ready
                            ? NSLocalizedString("settings_watch_connected", comment: "")
                            : nil,
                        trailingTint: AppColors.accentTeal
                    )
                }

                NavigationLink {
                    LazyView(VolumeKeySettingsView())
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    MeRow(
                        icon: "speaker.wave.2",
                        iconColor: .orange,
                        title: NSLocalizedString("settings_volume_key_turn_page", comment: ""),
                        trailingText: NSLocalizedString(volumeKeyEnabled ? "settings_status_on" : "settings_status_off", comment: ""),
                        trailingTint: volumeKeyEnabled ? AppColors.accentTeal : nil
                    )
                }
            } else {
                // iPad / Mac receives Watch page turns through the iPhone; same entry name as on iPhone.
                NavigationLink {
                    LazyView(IPadWatchConnectionView())
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    MeRow(
                        icon: "applewatch",
                        iconColor: Color(uiColor: .label),
                        title: NSLocalizedString("watch_settings_title", comment: ""),
                        trailingText: watchService.peerHostState.connectedPeerCount > 0
                            ? NSLocalizedString("settings_watch_connected", comment: "")
                            : nil,
                        trailingTint: AppColors.accentTeal
                    )
                }
            }

            NavigationLink {
                LazyView(TTSSettingsView())
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                MeRow(
                    icon: "waveform",
                    iconColor: .indigo,
                    title: NSLocalizedString("settings_tts_voice", comment: ""),
                    trailingText: ttsRateSummary
                )
            }
        } header: {
            sectionHeader(NSLocalizedString("settings_reading_section", comment: ""))
        }
    }

    private var syncAndAppearanceSection: some View {
        Section {
            if proPurchase.hasProAccess {
                NavigationLink {
                    CloudSyncSettingsView(service: AppModule.shared?.cloudSync)
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    CloudSyncRow(
                        showsChevron: false,
                        showsProBadge: false,
                        isEnabled: CloudSyncPreferences.isEnabled
                    )
                }
            } else {
                Button {
                    Analytics.shared.log(.paywallViewed(source: "settings_cloud_sync"))
                    paywallContext = .cloudSync
                    showPaywall = true
                } label: {
                    CloudSyncRow(
                        showsChevron: true,
                        showsProBadge: true,
                        isEnabled: false
                    )
                }
                .buttonStyle(.plain)
            }

            Picker(selection: languageBinding) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.localizedName).tag(language.rawValue)
                }
            } label: {
                MeRow(
                    icon: "globe",
                    iconColor: AppColors.accentBlue,
                    title: NSLocalizedString("settings_language", comment: "")
                )
            }
            .tint(AppColors.secondaryText)

            Picker(selection: themeBinding) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.localizedName).tag(theme.rawValue)
                }
            } label: {
                MeRow(
                    icon: "circle.lefthalf.filled",
                    iconColor: .indigo,
                    title: NSLocalizedString("settings_theme", comment: "")
                )
            }
            .tint(AppColors.secondaryText)
        } header: {
            sectionHeader(NSLocalizedString("settings_sync_appearance_section", comment: ""))
        }
    }

    @ViewBuilder
    private var proSection: some View {
        if proPurchase.hasProAccess {
            Section {
                ProEntitlementCard()
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }
        } else {
            Section {
                Button(action: {
                    Analytics.shared.log(.paywallViewed(source: "settings_upgrade_row"))
                    paywallContext = .general
                    showPaywall = true
                }) {
                    HStack(spacing: 14) {
                        if UIImage(named: "PaywallHeroArt") != nil {
                            Color.clear
                                .frame(width: 52, height: 52)
                                .overlay {
                                    Image("PaywallHeroArt")
                                        .resizable()
                                        .scaledToFill()
                                }
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.white.opacity(0.28), lineWidth: 0.8)
                                )
                                .shadow(color: Color.black.opacity(0.22), radius: 8, y: 4)
                        } else {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 7) {
                                Text(NSLocalizedString("settings_upgrade_pro", comment: ""))
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.9)
                                Text("PRO")
                                    .font(.system(size: 10, weight: .heavy))
                                    .tracking(0.5)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2.5)
                                    .background(Color.white.opacity(0.22), in: Capsule())
                                    .overlay(
                                        Capsule().stroke(Color.white.opacity(0.32), lineWidth: 0.6)
                                    )
                            }
                            Text(CloudSyncL10n.text("pro_settings_upgrade_body"))
                                .font(.system(size: 12.5, weight: .regular))
                                .foregroundStyle(Color.white.opacity(0.84))
                                .lineSpacing(1.5)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 4)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    ZStack {
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(red: 28/255, green: 52/255, blue: 108/255), Color(red: 22/255, green: 84/255, blue: 92/255)]
                                : [Color(red: 33/255, green: 68/255, blue: 148/255), Color(red: 28/255, green: 116/255, blue: 122/255)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        RadialGradient(
                            colors: [Color.white.opacity(0.16), Color.clear],
                            center: .topTrailing,
                            startRadius: 8,
                            endRadius: 190
                        )
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var debugSection: some View {
        if proPurchase.isDeveloperModeEnabled {
            Section {
                Picker(
                    selection: Binding(
                        get: { proPurchase.overrideMode },
                        set: { proPurchase.setOverrideMode($0) }
                    )
                ) {
                    ForEach(ProAccessOverride.allCases) { mode in
                        Text(mode.localizedTitle).tag(mode)
                    }
                } label: {
                    MeRow(
                        icon: "wrench.and.screwdriver.fill",
                        iconColor: .purple,
                        title: NSLocalizedString("settings_pro_status_switch", comment: "")
                    )
                }

                Button(action: {
                    paywallContext = .general
                    showPaywall = true
                }) {
                    HStack {
                        MeRow(
                            icon: "cart.fill",
                            iconColor: AppColors.accentTeal,
                            title: NSLocalizedString("settings_open_paywall", comment: "")
                        )
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Toggle(
                    isOn: Binding(
                        get: { intelligenceEngine.simulationEnabled },
                        set: { intelligenceEngine.setSimulationEnabled($0) }
                    )
                ) {
                    MeRow(
                        icon: "sparkles",
                        iconColor: AppColors.accentTeal,
                        title: NSLocalizedString("settings_debug_simulate_ai", comment: ""),
                        subtitle: nativeIntelligenceStatusText
                    )
                }
                .tint(AppColors.accentTeal)

                Button(role: .destructive, action: {
                    proPurchase.resetLocalPurchaseState()
                }) {
                    MeRow(
                        icon: "arrow.counterclockwise",
                        iconColor: .red,
                        title: NSLocalizedString("settings_reset_purchase_cache", comment: "")
                    )
                }
            } header: {
                sectionHeader(NSLocalizedString("settings_developer_testing_section", comment: ""))
            } footer: {
                Text(NSLocalizedString("settings_developer_testing_footer", comment: ""))
            }
        }
    }

    private var supportAndAboutSection: some View {
        Section {
            NavigationLink {
                FeedbackView()
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                MeRow(
                    icon: "envelope.fill",
                    iconColor: AppColors.accentTeal,
                    title: NSLocalizedString("settings_feedback_section", comment: "")
                )
            }

            RateAppRow()
            ShareAppRow()

            NavigationLink {
                AboutDetailView()
                    .navigationTitle(NSLocalizedString("settings_about", comment: ""))
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                MeRow(
                    icon: "info.circle.fill",
                    iconColor: .secondary,
                    title: NSLocalizedString("settings_about", comment: "")
                )
            }
        } header: {
            sectionHeader(NSLocalizedString("settings_support_about_section", comment: ""))
        }
    }

    private var versionFooterSection: some View {
        Section {
            VStack(spacing: 4) {
                Text("PagePilot \(Bundle.main.appVersion)")
                    .font(.system(size: 12.5, weight: .semibold, design: .serif))
                    .foregroundStyle(AppColors.secondaryText)
                Text(NSLocalizedString("about_tagline", comment: ""))
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppColors.tertiaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
            .padding(.bottom, 12)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
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

// MARK: - Reading Goal & Reminder

private struct ReadingGoalSettingsView: View {
    @AppStorage(ReadingPreferences.Keys.dailyGoalMinutes) private var dailyGoalMinutes = ReadingPreferences.defaultDailyGoalMinutes
    @AppStorage(ReadingPreferences.Keys.reminderEnabled) private var reminderEnabled = ReadingPreferences.defaultReminderEnabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var showNotificationDeniedAlert = false

    private let quickPresets = [15, 30, 45, 60]

    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Text(String(format: NSLocalizedString("home_minutes", comment: ""), dailyGoalMinutes))
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(AppColors.primaryText)

                        Text(NSLocalizedString("settings_daily_goal", comment: ""))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColors.secondaryText)
                    }
                    .padding(.top, 6)

                    HStack(spacing: 8) {
                        ForEach(quickPresets, id: \.self) { preset in
                            let isSelected = dailyGoalMinutes == preset
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                    dailyGoalMinutes = preset
                                }
                            } label: {
                                Text(String(format: NSLocalizedString("home_minutes", comment: ""), preset))
                                    .font(.system(size: 13, weight: isSelected ? .bold : .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(isSelected ? .white : AppColors.primaryText)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                                    .background(
                                        isSelected
                                            ? AnyShapeStyle(AppColors.horizontalGradient)
                                            : AnyShapeStyle(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.045)),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Stepper(
                        value: $dailyGoalMinutes,
                        in: ReadingPreferences.dailyGoalRange,
                        step: 5
                    ) {
                        Text(NSLocalizedString("settings_goal_presets", comment: ""))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppColors.secondaryText)
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                Toggle(isOn: $reminderEnabled) {
                    MeRow(
                        icon: "bell.fill",
                        iconColor: .orange,
                        title: NSLocalizedString("settings_reminder", comment: "")
                    )
                }

                if reminderEnabled {
                    DatePicker(
                        NSLocalizedString("settings_reminder_time", comment: ""),
                        selection: reminderTimeBinding,
                        displayedComponents: .hourAndMinute
                    )
                }
            } footer: {
                if reminderEnabled {
                    Text(NSLocalizedString("settings_reminder_footer", comment: ""))
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle(NSLocalizedString("settings_goal_reminder", comment: ""))
        .alert(
            NSLocalizedString("settings_reminder_denied_title", comment: ""),
            isPresented: $showNotificationDeniedAlert
        ) {
            Button(NSLocalizedString("cancel_button", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("settings_reminder_open_settings", comment: "")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text(NSLocalizedString("settings_reminder_denied_body", comment: ""))
        }
        .onChange(of: dailyGoalMinutes) { _, newValue in
            NotificationCenter.default.post(name: ReadingPreferences.dailyGoalDidChange, object: newValue)
        }
        .onChange(of: reminderEnabled) { _, newValue in
            Task {
                if newValue {
                    ensureReminderTimeDefaults()
                    let granted = await ReadingReminderScheduler.shared.requestAuthorization()
                    if granted {
                        await ReadingReminderScheduler.shared.reschedule()
                    } else {
                        await MainActor.run {
                            reminderEnabled = false
                            showNotificationDeniedAlert = true
                        }
                    }
                } else {
                    await ReadingReminderScheduler.shared.reschedule()
                }
            }
        }
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = ReadingPreferences.reminderHour
                components.minute = ReadingPreferences.reminderMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                ReadingPreferences.reminderHour = components.hour ?? ReadingPreferences.defaultReminderHour
                ReadingPreferences.reminderMinute = components.minute ?? ReadingPreferences.defaultReminderMinute
                Task { await ReadingReminderScheduler.shared.reschedule() }
            }
        )
    }

    private func ensureReminderTimeDefaults() {
        if UserDefaults.standard.object(forKey: ReadingPreferences.Keys.reminderHour) == nil {
            ReadingPreferences.reminderHour = ReadingPreferences.defaultReminderHour
        }
        if UserDefaults.standard.object(forKey: ReadingPreferences.Keys.reminderMinute) == nil {
            ReadingPreferences.reminderMinute = ReadingPreferences.defaultReminderMinute
        }
    }
}

private struct CloudSyncRow: View {
    let showsChevron: Bool
    let showsProBadge: Bool
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            MeRow(
                icon: "icloud.fill",
                iconColor: AppColors.accentBlue,
                title: CloudSyncL10n.text("cloud_sync_section"),
                trailingText: showsProBadge
                    ? nil
                    : NSLocalizedString(isEnabled ? "settings_status_on" : "settings_status_off", comment: ""),
                trailingTint: (!showsProBadge && isEnabled) ? AppColors.accentTeal : nil
            )
            if showsProBadge {
                Spacer(minLength: 8)
                ProBadge()
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(AppColors.horizontalGradient)
            .clipShape(Capsule())
    }
}

// MARK: - App Appearance Preferences

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case spanish = "es"
    case french = "fr"
    case german = "de"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .english:
            return NSLocalizedString("settings_language_english", comment: "")
        case .simplifiedChinese:
            return NSLocalizedString("settings_language_chinese", comment: "")
        case .spanish:
            return NSLocalizedString("settings_language_spanish", comment: "")
        case .french:
            return NSLocalizedString("settings_language_french", comment: "")
        case .german:
            return NSLocalizedString("settings_language_german", comment: "")
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
            let preferredLanguage = Locale.preferredLanguages.first ?? ""
            if preferredLanguage.hasPrefix("zh") {
                return .simplifiedChinese
            }
            if preferredLanguage.hasPrefix("es") {
                return .spanish
            }
            if preferredLanguage.hasPrefix("fr") {
                return .french
            }
            if preferredLanguage.hasPrefix("de") {
                return .german
            }
            return .english
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

// MARK: - Pro Entitlement Card

/// Presents owned Pro benefits as a reading perk block inside a normal Me-tab section
/// (same width as other list rows — no nested card inset).
private struct ProEntitlementCard: View {
    @Environment(\.colorScheme) private var colorScheme

    private var benefits: [(icon: String, title: String)] {
        [
            ("icloud.fill", CloudSyncL10n.text("cloud_sync_section")),
            ("books.vertical.fill", NSLocalizedString("settings_pro_benefit_library", comment: "")),
            ("highlighter", NSLocalizedString("settings_pro_benefit_notes", comment: "")),
            ("applewatch", NSLocalizedString("settings_pro_benefit_watch", comment: "")),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(AppColors.horizontalGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("settings_pro_unlocked", comment: ""))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(CloudSyncL10n.text("pro_settings_active_body"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Text(NSLocalizedString("settings_pro_badge", comment: ""))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppColors.horizontalGradient)
                    .clipShape(Capsule())
            }

            Divider()

            HStack(spacing: 0) {
                ForEach(Array(benefits.enumerated()), id: \.offset) { _, benefit in
                    VStack(spacing: 4) {
                        Image(systemName: benefit.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppColors.accentTeal)
                            .frame(width: 28, height: 28)
                            .background(AppColors.accentTeal.opacity(colorScheme == .dark ? 0.2 : 0.12))
                            .clipShape(Circle())

                        Text(benefit.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Reusable Row

private struct MeRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var subtitle: String? = nil
    var trailingText: String? = nil
    var trailingTint: Color? = nil

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconColor.opacity(0.13))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15.5, weight: .medium))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)
                }
            }

            if let trailingText {
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    if let trailingTint {
                        Circle()
                            .fill(trailingTint)
                            .frame(width: 6, height: 6)
                    }
                    Text(trailingText)
                        .font(.system(size: 14, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(trailingTint ?? .secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, subtitle == nil ? 0 : 2)
    }
}

// MARK: - Rate App

private struct RateAppRow: View {
    var body: some View {
        Button(action: AppStoreReviewLink.open) {
            HStack {
                MeRow(
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
                MeRow(
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
        MeView()
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
    @State private var safariURL: IdentifiableURL?
    @State private var versionTapCount = 0
    @State private var showDeveloperModeAlert = false
    @ObservedObject private var proPurchase = ProPurchaseManager.shared

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(AppColors.accentGradient)
                            .frame(width: 68, height: 68)
                            .shadow(color: AppColors.accentBlue.opacity(0.26), radius: 14, y: 6)
                        Image(systemName: "book.pages.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    Text("PagePilot")
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundStyle(AppColors.primaryText)

                    Text(NSLocalizedString("about_tagline", comment: ""))
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .listRowBackground(Color.clear)

            Section {
                HStack {
                    MeRow(
                        icon: "number",
                        iconColor: .secondary,
                        title: NSLocalizedString("settings_version", comment: "")
                    )
                    Spacer()
                    Text("\(Bundle.main.appVersion) (\(Bundle.main.buildVersion))")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    versionTapCount += 1
                    if versionTapCount >= 5 {
                        versionTapCount = 0
                        proPurchase.toggleDeveloperMode()
                        showDeveloperModeAlert = true
                    }
                }

                HStack {
                    MeRow(
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
                    safariURL = IdentifiableURL(url: URL(string: "https://pagepilot.doublewaterapps.com/privacy.html")!)
                }) {
                    HStack {
                        MeRow(
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
                    safariURL = IdentifiableURL(url: URL(string: "https://pagepilot.doublewaterapps.com/terms.html")!)
                }) {
                    HStack {
                        MeRow(
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
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background.ignoresSafeArea())
        .sheet(item: $safariURL) { identifiableURL in
            SafariView(url: identifiableURL.url)
        }
        .alert(
            proPurchase.isDeveloperModeEnabled
                ? NSLocalizedString("settings_developer_mode_enabled_title", comment: "")
                : NSLocalizedString("settings_developer_mode_disabled_title", comment: ""),
            isPresented: $showDeveloperModeAlert
        ) {
            Button(NSLocalizedString("ok_button", comment: ""), role: .cancel) {}
        }
    }
}

// MARK: - Identifiable URL Wrapper
struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - SFSafariViewController Wrapper

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
