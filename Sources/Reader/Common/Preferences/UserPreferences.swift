//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import Foundation
import ReadiumNavigator
import ReadiumShared
import SwiftUI
import UIKit

// MARK: - Reader Theme Appearance Bridge

/// Maps the reader's active EPUB preferences to matching native chrome colors
/// so safe areas, status bar, footer, and footnote popups harmonize seamlessly with the page.
struct ReaderThemeAppearance: Equatable {
    let backgroundColor: UIColor
    let primaryTextColor: UIColor
    let secondaryTextColor: UIColor
    let isDarkSurface: Bool

    static func resolve(
        preferences: EPUBPreferences?,
        systemStyle: UIUserInterfaceStyle
    ) -> ReaderThemeAppearance {
        if let customBg = preferences?.backgroundColor?.color {
            let uiBg = UIColor(customBg)
            let isDark = uiBg.isPerceptuallyDark
            let customFg = preferences?.textColor.map { UIColor($0.color) }
            return ReaderThemeAppearance(
                backgroundColor: uiBg,
                primaryTextColor: customFg ?? (isDark ? AppColors.readerDarkText : .label),
                secondaryTextColor: (customFg ?? (isDark ? AppColors.readerDarkText : .label)).withAlphaComponent(0.55),
                isDarkSurface: isDark
            )
        }

        switch preferences?.theme {
        case .dark:
            return ReaderThemeAppearance(
                backgroundColor: AppColors.readerDarkBackground,
                primaryTextColor: AppColors.readerDarkText,
                secondaryTextColor: AppColors.readerDarkText.withAlphaComponent(0.56),
                isDarkSurface: true
            )
        case .sepia:
            return ReaderThemeAppearance(
                backgroundColor: AppColors.readerSepiaBackground,
                primaryTextColor: AppColors.readerSepiaText,
                secondaryTextColor: AppColors.readerSepiaText.withAlphaComponent(0.62),
                isDarkSurface: false
            )
        case .light:
            return ReaderThemeAppearance(
                backgroundColor: .white,
                primaryTextColor: UIColor(red: 28 / 255, green: 30 / 255, blue: 33 / 255, alpha: 1),
                secondaryTextColor: UIColor(red: 96 / 255, green: 104 / 255, blue: 115 / 255, alpha: 0.78),
                isDarkSurface: false
            )
        case nil:
            if systemStyle == .dark {
                return ReaderThemeAppearance(
                    backgroundColor: AppColors.readerDarkBackground,
                    primaryTextColor: AppColors.readerDarkText,
                    secondaryTextColor: AppColors.readerDarkText.withAlphaComponent(0.56),
                    isDarkSurface: true
                )
            }
            return ReaderThemeAppearance(
                backgroundColor: .white,
                primaryTextColor: UIColor(red: 28 / 255, green: 30 / 255, blue: 33 / 255, alpha: 1),
                secondaryTextColor: UIColor(red: 96 / 255, green: 104 / 255, blue: 115 / 255, alpha: 0.78),
                isDarkSurface: false
            )
        }
    }

    var cssHexBackground: String { backgroundColor.hexRGBString }
    var cssHexText: String { primaryTextColor.hexRGBString }
}

private extension UIColor {
    var isPerceptuallyDark: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return false }
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance < 0.5
    }

    var hexRGBString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let resolved = resolvedColor(with: UITraitCollection.current)
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }
}

// MARK: - ViewModel

final class UserPreferencesViewModel<
    S: ConfigurableSettings,
    P: ConfigurablePreferences,
    E: PreferencesEditor
>: ObservableObject where E.Preferences == P {
    @Published private(set) var editor: E

    private let bookId: Book.Id
    private let configurable: AnyConfigurable<S, P, E>
    private let store: AnyUserPreferencesStore<P>
    private var subscriptions = Set<AnyCancellable>()

    init<C: Configurable, ST: UserPreferencesStore>(
        bookId: Book.Id,
        preferences: P,
        configurable: C,
        store: ST
    ) where C.Settings == S, C.Preferences == P, C.Editor == E, ST.Preferences == P {
        editor = configurable.editor(of: preferences)
        self.bookId = bookId
        self.configurable = configurable.eraseToAnyConfigurable()
        self.store = store.eraseToAnyPreferencesStore()

        let preferences = store.preferencesPublisher(for: bookId)
            .receive(on: DispatchQueue.main)

        preferences
            .compactMap { configurable.editor(of: $0) }
            .assign(to: &$editor)

        preferences
            // First one is dropped to avoid refreshing the navigator when
            // opening the user preferences screen.
            .dropFirst()
            .sink { configurable.submitPreferences($0) }
            .store(in: &subscriptions)
    }

    func commit() {
        Task {
            try? await store.savePreferences(editor.preferences, of: bookId)
        }
    }
}

// MARK: - Modern Visual Reader Preferences Panel

struct UserPreferences<
    S: ConfigurableSettings,
    P: ConfigurablePreferences,
    E: PreferencesEditor
>: View where E.Preferences == P {
    @ObservedObject var model: UserPreferencesViewModel<S, P, E>
    var onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var screenBrightness: Double = Self.currentScreenBrightness()
    @State private var showAdvancedTypography = false

    private let languages: [Language?] = [nil] + Language.all
        .map { $0.removingRegion() }
        .removingDuplicates()
        .sorted { l1, l2 in l1.localizedDescription() <= l2.localizedDescription() }

    var body: some View {
        userPreferences(editor: model.editor, commit: model.commit)
    }

    private static func currentScreenBrightness() -> Double {
        #if targetEnvironment(macCatalyst)
        return 1.0
        #else
        let activeScreen = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .screen
        return Double((activeScreen ?? UIScreen.main).brightness)
        #endif
    }

    private static func applyScreenBrightness(_ value: Double) {
        #if !targetEnvironment(macCatalyst)
        let clamped = CGFloat(min(max(value, 0.02), 1.0))
        let activeScreen = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .screen
        (activeScreen ?? UIScreen.main).brightness = clamped
        #endif
    }

    func userPreferences<PE: PreferencesEditor>(editor: PE, commit: @escaping () -> Void) -> some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    switch editor {
                    case let editor as EPUBPreferencesEditor:
                        switch editor.layout {
                        case .reflowable:
                            reflowableVisualPanel(editor: editor, commit: commit)
                        case .fixed:
                            fixedLayoutPanel(
                                commit: commit,
                                backgroundColor: editor.backgroundColor,
                                fit: editor.fit,
                                language: editor.language,
                                nullableOffsetFirstPage: editor.offsetFirstPage,
                                readingProgression: editor.readingProgression,
                                spread: editor.spread
                            )
                        }

                    case let editor as PDFPreferencesEditor:
                        fixedLayoutPanel(
                            commit: commit,
                            fit: editor.fit,
                            offsetFirstPage: editor.offsetFirstPage,
                            pageSpacing: editor.pageSpacing,
                            readingProgression: editor.readingProgression,
                            scroll: editor.scroll,
                            scrollAxis: editor.scrollAxis,
                            spread: editor.spread,
                            visibleScrollbar: editor.visibleScrollbar
                        )

                    case let editor as AudioPreferencesEditor:
                        audioPanel(
                            commit: commit,
                            volume: editor.volume,
                            speed: editor.speed
                        )

                    default:
                        Text(NSLocalizedString("prefs_no_user_preferences", comment: ""))
                            .foregroundStyle(AppColors.secondaryText)
                            .padding(.vertical, 32)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("reader_prefs_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString("prefs_reset", comment: "")) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        editor.clear()
                        commit()
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.secondaryText)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton(
                        accessibilityLabel: NSLocalizedString("prefs_close", comment: ""),
                        action: onClose
                    )
                }
            }
        }
        .onAppear {
            screenBrightness = Self.currentScreenBrightness()
        }
    }

    // MARK: - Reflowable EPUB Visual Panel (Apple Books + Readest Inspired)

    @ViewBuilder
    private func reflowableVisualPanel(
        editor: EPUBPreferencesEditor,
        commit: @escaping () -> Void
    ) -> some View {
        #if !targetEnvironment(macCatalyst)
        brightnessCard
        #endif

        // 1. Themes (visual color swatch cards)
        themeSwatchesCard(
            theme: editor.theme,
            backgroundColor: editor.backgroundColor,
            textColor: editor.textColor,
            commit: commit
        )

        // 2. Font size large A- / A+ control + Typeface visual strip
        typographyQuickCard(
            fontSize: editor.fontSize,
            fontFamily: editor.fontFamily,
            commit: commit
        )

        // 3. Layout: Paging vs Scroll, Line Spacing, Page Margins, Columns
        layoutQuickCard(
            scroll: editor.scroll,
            lineHeight: editor.lineHeight,
            pageMargins: editor.pageMargins,
            columnCount: editor.columnCount,
            publisherStyles: editor.publisherStyles,
            commit: commit
        )

        // 4. Collapsible Advanced Typography (preserves Readest-level power without clutter)
        advancedTypographyCard(editor: editor, commit: commit)
    }

    private var brightnessCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "sun.min.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.secondaryText)

            Slider(value: $screenBrightness, in: 0.05...1.0)
                .tint(AppColors.accentBlue)
                .onChange(of: screenBrightness) { _, newValue in
                    Self.applyScreenBrightness(newValue)
                }

            Image(systemName: "sun.max.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(AppColors.secondaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .panelCard(colorScheme: colorScheme)
        .accessibilityLabel(NSLocalizedString("reader_prefs_brightness", comment: ""))
    }

    private func themeSwatchesCard(
        theme: AnyEnumPreference<ReadiumNavigator.Theme>,
        backgroundColor: AnyPreference<ReadiumNavigator.Color>,
        textColor: AnyPreference<ReadiumNavigator.Color>,
        commit: @escaping () -> Void
    ) -> some View {
        let previewPrefs = EPUBPreferences(
            backgroundColor: backgroundColor.value,
            textColor: textColor.value,
            theme: theme.value ?? theme.effectiveValue
        )
        let activePreset = ReaderPaperPreset.matching(
            preferences: previewPrefs,
            systemStyle: colorScheme == .dark ? .dark : .light
        )

        return VStack(alignment: .leading, spacing: 10) {
            panelSectionHeader(NSLocalizedString("reader_prefs_theme_section", comment: ""))

            HStack(spacing: 8) {
                ForEach(ReaderPaperPreset.allCases) { preset in
                    let isSelected = activePreset == preset
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        preset.apply(
                            theme: theme,
                            backgroundColor: backgroundColor,
                            textColor: textColor
                        )
                        commit()
                    } label: {
                        VStack(spacing: 6) {
                            Text("Aa")
                                .font(.system(size: 19, weight: .semibold, design: .serif))
                                .foregroundStyle(preset.swiftUITextColor)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(preset.swiftUIBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(
                                            isSelected ? AppColors.accentBlue : SwiftUI.Color.primary.opacity(0.12),
                                            lineWidth: isSelected ? 2.2 : 0.75
                                        )
                                )

                            Text(preset.localizedTitle)
                                .font(.system(size: 11.5, weight: isSelected ? .bold : .medium))
                                .foregroundStyle(isSelected ? AppColors.accentBlue : AppColors.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .panelCard(colorScheme: colorScheme)
    }

    private func typographyQuickCard(
        fontSize: AnyRangePreference<Double>,
        fontFamily: AnyPreference<FontFamily?>,
        commit: @escaping () -> Void
    ) -> some View {
        let supportedFonts: [FontFamily?] = [
            nil,
            .literata,
            .sansSerif,
            .iaWriterDuospace,
            .accessibleDfA,
            .openDyslexic,
        ]
        let currentFont = fontFamily.value ?? fontFamily.effectiveValue

        return VStack(alignment: .leading, spacing: 14) {
            // Font size large A- / A+ control
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    panelSectionHeader(NSLocalizedString("reader_prefs_font_size", comment: ""))
                    Spacer()
                    Text(fontSize.format(value: fontSize.value ?? fontSize.effectiveValue))
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(AppColors.accentBlue)
                }

                HStack(spacing: 0) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        fontSize.decrement()
                        commit()
                    } label: {
                        Text("A")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.primaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(NSLocalizedString("prefs_font_size", comment: "") + " -")

                    Rectangle()
                        .fill(SwiftUI.Color.primary.opacity(0.09))
                        .frame(width: 1, height: 22)

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        fontSize.increment()
                        commit()
                    } label: {
                        Text("A")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(AppColors.primaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(NSLocalizedString("prefs_font_size", comment: "") + " +")
                }
                .background(SwiftUI.Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Divider()

            // Typeface visual cards
            VStack(alignment: .leading, spacing: 8) {
                panelSectionHeader(NSLocalizedString("reader_prefs_typeface", comment: ""))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(supportedFonts.enumerated()), id: \.offset) { _, family in
                            let isSelected = currentFont == family
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                fontFamily.set(family)
                                commit()
                            } label: {
                                VStack(spacing: 4) {
                                    Text("Aa")
                                        .font(previewFont(for: family))
                                        .foregroundStyle(isSelected ? AppColors.accentBlue : AppColors.primaryText)
                                    Text(fontDisplayName(for: family))
                                        .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                        .foregroundStyle(isSelected ? AppColors.accentBlue : AppColors.secondaryText)
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .frame(minWidth: 74)
                                .background(
                                    isSelected
                                        ? AppColors.accentBlue.opacity(colorScheme == .dark ? 0.22 : 0.1)
                                        : SwiftUI.Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.04),
                                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .stroke(isSelected ? AppColors.accentBlue : .clear, lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(14)
        .panelCard(colorScheme: colorScheme)
    }

    private func layoutQuickCard(
        scroll: AnyPreference<Bool>,
        lineHeight: AnyRangePreference<Double>,
        pageMargins: AnyRangePreference<Double>,
        columnCount: AnyEnumPreference<ColumnCount>,
        publisherStyles: AnyPreference<Bool>,
        commit: @escaping () -> Void
    ) -> some View {
        let isScroll = scroll.value ?? scroll.effectiveValue
        let currentLineHeight = lineHeight.value ?? lineHeight.effectiveValue
        let currentMargins = pageMargins.value ?? pageMargins.effectiveValue
        let currentColumns = columnCount.value ?? columnCount.effectiveValue

        let linePresets: [(label: String, value: Double, icon: String)] = [
            (NSLocalizedString("reader_prefs_compact", comment: ""), 1.2, "text.alignleft"),
            (NSLocalizedString("reader_prefs_comfortable", comment: ""), 1.5, "text.justify"),
            (NSLocalizedString("reader_prefs_relaxed", comment: ""), 1.85, "line.3.horizontal"),
        ]

        let marginPresets: [(label: String, value: Double)] = [
            (NSLocalizedString("reader_prefs_compact", comment: ""), 0.75),
            (NSLocalizedString("reader_prefs_comfortable", comment: ""), 1.15),
            (NSLocalizedString("reader_prefs_relaxed", comment: ""), 1.6),
        ]

        return VStack(alignment: .leading, spacing: 14) {
            // Reading mode: Paged vs Scroll
            VStack(alignment: .leading, spacing: 8) {
                panelSectionHeader(NSLocalizedString("reader_prefs_layout", comment: ""))

                HStack(spacing: 8) {
                    modeToggleButton(
                        title: NSLocalizedString("reader_prefs_paging", comment: ""),
                        icon: "book.pages",
                        isSelected: !isScroll
                    ) {
                        scroll.set(false)
                        commit()
                    }
                    modeToggleButton(
                        title: NSLocalizedString("reader_prefs_scrolling", comment: ""),
                        icon: "arrow.up.and.down.text.horizontal",
                        isSelected: isScroll
                    ) {
                        scroll.set(true)
                        commit()
                    }
                }
            }

            Divider()

            // Line spacing presets
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    panelSectionHeader(NSLocalizedString("reader_prefs_line_spacing", comment: ""))
                    Spacer()
                    Text(lineHeight.format(value: currentLineHeight))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(AppColors.secondaryText)
                }

                HStack(spacing: 8) {
                    ForEach(Array(linePresets.enumerated()), id: \.offset) { _, preset in
                        let isSelected = !(publisherStyles.value ?? publisherStyles.effectiveValue)
                            && abs(currentLineHeight - preset.value) < 0.16
                        presetChip(title: preset.label, isSelected: isSelected) {
                            if publisherStyles.effectiveValue {
                                publisherStyles.set(false)
                            }
                            lineHeight.set(preset.value)
                            commit()
                        }
                    }
                }
            }

            // Page margin presets
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    panelSectionHeader(NSLocalizedString("reader_prefs_margins", comment: ""))
                    Spacer()
                    Text(pageMargins.format(value: currentMargins))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(AppColors.secondaryText)
                }

                HStack(spacing: 8) {
                    ForEach(Array(marginPresets.enumerated()), id: \.offset) { _, preset in
                        let isSelected = abs(currentMargins - preset.value) < 0.2
                        presetChip(title: preset.label, isSelected: isSelected) {
                            pageMargins.set(preset.value)
                            commit()
                        }
                    }
                }
            }

            // Column count (especially helpful on iPad / landscape)
            if columnCount.isEffective {
                Divider()
                HStack {
                    Text(NSLocalizedString("prefs_columns", comment: ""))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.primaryText)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { currentColumns },
                        set: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            columnCount.set($0)
                            commit()
                        }
                    )) {
                        Text(NSLocalizedString("prefs_auto", comment: "")).tag(ColumnCount.auto)
                        Text("1").tag(ColumnCount.one)
                        Text("2").tag(ColumnCount.two)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
            }
        }
        .padding(14)
        .panelCard(colorScheme: colorScheme)
    }

    private func advancedTypographyCard(
        editor: EPUBPreferencesEditor,
        commit: @escaping () -> Void
    ) -> some View {
        DisclosureGroup(isExpanded: $showAdvancedTypography) {
            VStack(spacing: 12) {
                Divider().padding(.top, 4)

                cleanToggleRow(
                    title: NSLocalizedString("prefs_publisher_styles", comment: ""),
                    preference: editor.publisherStyles,
                    commit: commit
                )

                if !editor.publisherStyles.effectiveValue {
                    cleanPickerRow(
                        title: NSLocalizedString("prefs_text_alignment", comment: ""),
                        preference: editor.textAlign,
                        commit: commit,
                        formatValue: { v in
                            switch v {
                            case nil: return NSLocalizedString("prefs_default", comment: "")
                            case .center: return NSLocalizedString("prefs_center", comment: "")
                            case .left: return NSLocalizedString("prefs_left", comment: "")
                            case .right: return NSLocalizedString("prefs_right", comment: "")
                            case .justify: return NSLocalizedString("prefs_justify", comment: "")
                            case .start: return NSLocalizedString("prefs_start", comment: "")
                            case .end: return NSLocalizedString("prefs_end", comment: "")
                            }
                        }
                    )

                    cleanStepperRow(title: NSLocalizedString("prefs_line_height", comment: ""), preference: editor.lineHeight, commit: commit)
                    cleanStepperRow(title: NSLocalizedString("prefs_paragraph_spacing", comment: ""), preference: editor.paragraphSpacing, commit: commit)
                    cleanStepperRow(title: NSLocalizedString("prefs_paragraph_indent", comment: ""), preference: editor.paragraphIndent, commit: commit)
                    cleanStepperRow(title: NSLocalizedString("prefs_letter_spacing", comment: ""), preference: editor.letterSpacing, commit: commit)
                    cleanStepperRow(title: NSLocalizedString("prefs_word_spacing", comment: ""), preference: editor.wordSpacing, commit: commit)
                    cleanToggleRow(title: NSLocalizedString("prefs_hyphens", comment: ""), preference: editor.hyphens, commit: commit)
                    cleanToggleRow(title: NSLocalizedString("prefs_ligatures", comment: ""), preference: editor.ligatures, commit: commit)
                }

                Divider()

                cleanStepperRow(title: NSLocalizedString("prefs_font_weight", comment: ""), preference: editor.fontWeight, commit: commit)
                cleanToggleRow(title: NSLocalizedString("prefs_text_normalization", comment: ""), preference: editor.textNormalization, commit: commit)
                cleanToggleRow(title: NSLocalizedString("prefs_vertical_text", comment: ""), preference: editor.verticalText, commit: commit)

                cleanPickerRow(
                    title: NSLocalizedString("prefs_reading_progression", comment: ""),
                    preference: editor.readingProgression,
                    commit: commit,
                    formatValue: { v in
                        switch v {
                        case .ltr: return NSLocalizedString("prefs_ltr", comment: "")
                        case .rtl: return NSLocalizedString("prefs_rtl", comment: "")
                        }
                    }
                )

                cleanPickerRow(
                    title: NSLocalizedString("prefs_image_filter", comment: ""),
                    preference: editor.imageFilter,
                    commit: commit,
                    formatValue: { v in
                        switch v {
                        case nil: return NSLocalizedString("prefs_none", comment: "")
                        case .darken: return NSLocalizedString("prefs_darken_colors", comment: "")
                        case .invert: return NSLocalizedString("prefs_invert_colors", comment: "")
                        }
                    }
                )

                cleanColorRow(title: NSLocalizedString("prefs_text_color", comment: ""), preference: editor.textColor, commit: commit)
                cleanColorRow(title: NSLocalizedString("prefs_background_color", comment: ""), preference: editor.backgroundColor, commit: commit)

                cleanLanguageRow(title: NSLocalizedString("prefs_language", comment: ""), preference: editor.language, commit: commit)
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.accentBlue)
                Text(NSLocalizedString("reader_prefs_advanced", comment: ""))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.primaryText)
            }
        }
        .tint(AppColors.secondaryText)
        .padding(14)
        .panelCard(colorScheme: colorScheme)
    }

    // MARK: - Fixed Layout / PDF Panel

    @ViewBuilder
    private func fixedLayoutPanel(
        commit: @escaping () -> Void,
        backgroundColor: AnyPreference<ReadiumNavigator.Color>? = nil,
        fit: AnyEnumPreference<ReadiumNavigator.Fit>? = nil,
        language: AnyPreference<Language?>? = nil,
        offsetFirstPage: AnyPreference<Bool>? = nil,
        nullableOffsetFirstPage: AnyPreference<Bool?>? = nil,
        pageSpacing: AnyRangePreference<Double>? = nil,
        readingProgression: AnyEnumPreference<ReadiumNavigator.ReadingProgression>? = nil,
        scroll: AnyPreference<Bool>? = nil,
        scrollAxis: AnyEnumPreference<ReadiumNavigator.Axis>? = nil,
        spread: AnyEnumPreference<ReadiumNavigator.Spread>? = nil,
        visibleScrollbar: AnyPreference<Bool>? = nil
    ) -> some View {
        #if !targetEnvironment(macCatalyst)
        brightnessCard
        #endif

        if scroll != nil || fit != nil || spread != nil {
            VStack(alignment: .leading, spacing: 14) {
                if let scroll {
                    let isScroll = scroll.value ?? scroll.effectiveValue
                    HStack(spacing: 8) {
                        modeToggleButton(
                            title: NSLocalizedString("reader_prefs_paging", comment: ""),
                            icon: "book.pages",
                            isSelected: !isScroll
                        ) {
                            scroll.set(false)
                            commit()
                        }
                        modeToggleButton(
                            title: NSLocalizedString("reader_prefs_scrolling", comment: ""),
                            icon: "arrow.up.and.down.text.horizontal",
                            isSelected: isScroll
                        ) {
                            scroll.set(true)
                            commit()
                        }
                    }
                }

                if let scrollAxis, (scroll?.effectiveValue ?? true) {
                    cleanPickerRow(
                        title: NSLocalizedString("prefs_scroll_axis", comment: ""),
                        preference: scrollAxis,
                        commit: commit,
                        formatValue: { $0 == .horizontal ? NSLocalizedString("prefs_horizontal", comment: "") : NSLocalizedString("prefs_vertical", comment: "") }
                    )
                }

                if let fit {
                    cleanPickerRow(
                        title: NSLocalizedString("prefs_fit", comment: ""),
                        preference: fit,
                        commit: commit,
                        formatValue: { v in
                            switch v {
                            case .auto: return NSLocalizedString("prefs_auto", comment: "")
                            case .page: return NSLocalizedString("prefs_page", comment: "")
                            case .width: return NSLocalizedString("prefs_width", comment: "")
                            }
                        }
                    )
                }

                if let spread {
                    cleanPickerRow(
                        title: NSLocalizedString("prefs_spread", comment: ""),
                        preference: spread,
                        commit: commit,
                        formatValue: { v in
                            switch v {
                            case .auto: return NSLocalizedString("prefs_auto", comment: "")
                            case .never: return NSLocalizedString("prefs_never", comment: "")
                            case .always: return NSLocalizedString("prefs_always", comment: "")
                            }
                        }
                    )
                }

                if let offsetFirstPage {
                    cleanToggleRow(title: NSLocalizedString("prefs_offset_first_page", comment: ""), preference: offsetFirstPage, commit: commit)
                }

                if let nullableOffsetFirstPage {
                    HStack {
                        Text(NSLocalizedString("prefs_offset_first_page", comment: ""))
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { nullableOffsetFirstPage.value ?? nullableOffsetFirstPage.effectiveValue },
                            set: { nullableOffsetFirstPage.set($0); commit() }
                        )) {
                            Text(NSLocalizedString("prefs_auto", comment: "")).tag(nil as Bool?)
                            Text(NSLocalizedString("prefs_yes", comment: "")).tag(true as Bool?)
                            Text(NSLocalizedString("prefs_no", comment: "")).tag(false as Bool?)
                        }
                        .pickerStyle(.menu)
                    }
                }

                if let pageSpacing {
                    cleanStepperRow(title: NSLocalizedString("prefs_page_spacing", comment: ""), preference: pageSpacing, commit: commit)
                }
            }
            .padding(14)
            .panelCard(colorScheme: colorScheme)
        }

        if readingProgression != nil || backgroundColor != nil || language != nil {
            VStack(alignment: .leading, spacing: 12) {
                if let readingProgression {
                    cleanPickerRow(
                        title: NSLocalizedString("prefs_reading_progression", comment: ""),
                        preference: readingProgression,
                        commit: commit,
                        formatValue: { $0 == .ltr ? NSLocalizedString("prefs_ltr", comment: "") : NSLocalizedString("prefs_rtl", comment: "") }
                    )
                }
                if let backgroundColor {
                    cleanColorRow(title: NSLocalizedString("prefs_background_color", comment: ""), preference: backgroundColor, commit: commit)
                }
                if let language {
                    cleanLanguageRow(title: NSLocalizedString("prefs_language", comment: ""), preference: language, commit: commit)
                }
            }
            .padding(14)
            .panelCard(colorScheme: colorScheme)
        }
    }

    // MARK: - Audiobook Panel

    private func audioPanel(
        commit: @escaping () -> Void,
        volume: AnyRangePreference<Double>? = nil,
        speed: AnyRangePreference<Double>? = nil
    ) -> some View {
        VStack(spacing: 12) {
            if let volume {
                cleanStepperRow(title: NSLocalizedString("prefs_volume", comment: ""), preference: volume, commit: commit)
            }
            if let speed {
                cleanStepperRow(title: NSLocalizedString("prefs_speed", comment: ""), preference: speed, commit: commit)
            }
        }
        .padding(14)
        .panelCard(colorScheme: colorScheme)
    }

    // MARK: - Clean Row Building Blocks (No Developer Backspace Buttons)

    private func panelSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppColors.secondaryText)
    }

    private func modeToggleButton(
        title: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? .white : AppColors.primaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                isSelected
                    ? AnyShapeStyle(AppColors.horizontalGradient)
                    : AnyShapeStyle(SwiftUI.Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.045)),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private func presetChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? AppColors.accentBlue : AppColors.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    isSelected
                        ? AppColors.accentBlue.opacity(colorScheme == .dark ? 0.22 : 0.1)
                        : SwiftUI.Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.04),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(isSelected ? AppColors.accentBlue : .clear, lineWidth: 1.3)
                )
        }
        .buttonStyle(.plain)
    }

    private func cleanToggleRow(
        title: String,
        preference: AnyPreference<Bool>,
        commit: @escaping () -> Void
    ) -> some View {
        Toggle(title, isOn: preference.binding(onSet: commit))
            .font(.system(size: 14, weight: .medium))
            .tint(AppColors.accentBlue)
            .opacity(preference.isEffective ? 1 : 0.5)
    }

    private func cleanPickerRow<V: Hashable>(
        title: String,
        preference: AnyEnumPreference<V>,
        commit: @escaping () -> Void,
        formatValue: @escaping (V) -> String
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(preference.isEffective ? AppColors.primaryText : AppColors.tertiaryText)
            Spacer()
            Picker("", selection: preference.binding(onSet: commit)) {
                ForEach(preference.supportedValues, id: \.self) { value in
                    Text(formatValue(value)).tag(value)
                }
            }
            .pickerStyle(.menu)
            .tint(AppColors.accentBlue)
        }
        .opacity(preference.isEffective ? 1 : 0.5)
    }

    private func cleanStepperRow<V: Comparable>(
        title: String,
        preference: AnyRangePreference<V>,
        commit: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(preference.isEffective ? AppColors.primaryText : AppColors.tertiaryText)
                Text(preference.format(value: preference.value ?? preference.effectiveValue))
                    .font(.system(size: 11.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(AppColors.secondaryText)
            }
            Spacer()
            Stepper(
                "",
                onIncrement: {
                    preference.increment()
                    commit()
                },
                onDecrement: {
                    preference.decrement()
                    commit()
                }
            )
            .labelsHidden()
        }
        .opacity(preference.isEffective ? 1 : 0.5)
    }

    private func cleanColorRow(
        title: String,
        preference: AnyPreference<ReadiumNavigator.Color>,
        commit: @escaping () -> Void
    ) -> some View {
        ColorPicker(
            title,
            selection: Binding(
                get: { (preference.value ?? preference.effectiveValue).color },
                set: {
                    preference.set(ReadiumNavigator.Color(color: $0))
                    commit()
                }
            ),
            supportsOpacity: false
        )
        .font(.system(size: 14, weight: .medium))
        .opacity(preference.isEffective ? 1 : 0.5)
    }

    private func cleanLanguageRow(
        title: String,
        preference: AnyPreference<Language?>,
        commit: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(preference.isEffective ? AppColors.primaryText : AppColors.tertiaryText)
            Spacer()
            Picker("", selection: Binding(
                get: { preference.value ?? preference.effectiveValue },
                set: { preference.set($0); commit() }
            )) {
                ForEach(languages, id: \.self) { language in
                    Text(language?.localizedDescription() ?? NSLocalizedString("prefs_original", comment: ""))
                        .tag(language)
                }
            }
            .pickerStyle(.menu)
            .tint(AppColors.accentBlue)
        }
        .opacity(preference.isEffective ? 1 : 0.5)
    }

    private func previewFont(for family: FontFamily?) -> Font {
        switch family {
        case .literata:
            return .system(size: 17, weight: .semibold, design: .serif)
        case .sansSerif:
            return .system(size: 17, weight: .semibold, design: .default)
        case .iaWriterDuospace:
            return .system(size: 17, weight: .semibold, design: .monospaced)
        case .accessibleDfA, .openDyslexic:
            return .system(size: 17, weight: .semibold, design: .rounded)
        default:
            return .system(size: 17, weight: .semibold, design: .serif)
        }
    }

    private func fontDisplayName(for family: FontFamily?) -> String {
        guard let family else {
            return NSLocalizedString("prefs_original", comment: "")
        }
        switch family {
        case .sansSerif:
            return NSLocalizedString("prefs_sans_serif", comment: "")
        case .iaWriterDuospace:
            return "iA Writer"
        case .accessibleDfA:
            return "Accessible"
        default:
            return family.rawValue
        }
    }
}

private extension View {
    func panelCard(colorScheme: ColorScheme) -> some View {
        self
            .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(colorScheme == .dark ? SwiftUI.Color.white.opacity(0.06) : SwiftUI.Color.black.opacity(0.04), lineWidth: 1)
            )
    }
}

extension Preference {
    /// Creates a SwiftUI binding to modify the preference's value.
    func binding(onSet: @escaping () -> Void = {}) -> Binding<Value> {
        Binding(
            get: { value ?? effectiveValue },
            set: { set($0); onSet() }
        )
    }
}
