//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import Foundation
import ReadiumNavigator
import ReadiumShared
import SwiftUI

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
            try! await store.savePreferences(editor.preferences, of: bookId)
        }
    }
}

struct UserPreferences<
    S: ConfigurableSettings,
    P: ConfigurablePreferences,
    E: PreferencesEditor
>: View where E.Preferences == P {
    @ObservedObject var model: UserPreferencesViewModel<S, P, E>
    var onClose: () -> Void

    private let languages: [Language?] = [nil] + Language.all
        .map { $0.removingRegion() }
        .removingDuplicates()
        .sorted { l1, l2 in l1.localizedDescription() <= l2.localizedDescription() }

    var body: some View {
        userPreferences(editor: model.editor, commit: model.commit)
    }

    func userPreferences<PE: PreferencesEditor>(editor: PE, commit: @escaping () -> Void) -> some View {
        NavigationView {
            List {
                switch editor {
                case let editor as PDFPreferencesEditor:
                    fixedLayoutUserPreferences(
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

                case let editor as EPUBPreferencesEditor:
                    switch editor.layout {
                    case .reflowable:
                        reflowableUserPreferences(
                            commit: commit,
                            backgroundColor: editor.backgroundColor,
                            columnCount: editor.columnCount,
                            fontFamily: editor.fontFamily,
                            fontSize: editor.fontSize,
                            fontWeight: editor.fontWeight,
                            hyphens: editor.hyphens,
                            imageFilter: editor.imageFilter,
                            language: editor.language,
                            letterSpacing: editor.letterSpacing,
                            ligatures: editor.ligatures,
                            lineHeight: editor.lineHeight,
                            pageMargins: editor.pageMargins,
                            paragraphIndent: editor.paragraphIndent,
                            paragraphSpacing: editor.paragraphSpacing,
                            publisherStyles: editor.publisherStyles,
                            readingProgression: editor.readingProgression,
                            scroll: editor.scroll,
                            textAlign: editor.textAlign,
                            textColor: editor.textColor,
                            textNormalization: editor.textNormalization,
                            theme: editor.theme,
                            typeScale: editor.typeScale,
                            verticalText: editor.verticalText,
                            wordSpacing: editor.wordSpacing
                        )
                    case .fixed:
                        fixedLayoutUserPreferences(
                            commit: commit,
                            backgroundColor: editor.backgroundColor,
                            fit: editor.fit,
                            language: editor.language,
                            nullableOffsetFirstPage: editor.offsetFirstPage,
                            readingProgression: editor.readingProgression,
                            spread: editor.spread
                        )
                    }

                case let editor as AudioPreferencesEditor:
                    audioUserPreferences(
                        commit: commit,
                        volume: editor.volume,
                        speed: editor.speed
                    )

                default:
                    Text(NSLocalizedString("prefs_no_user_preferences", comment: ""))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(NSLocalizedString("prefs_user_preferences", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SheetCloseButton(
                        accessibilityLabel: NSLocalizedString("prefs_close", comment: ""),
                        action: onClose
                    )
                }

                ToolbarItemGroup(placement: .destructiveAction) {
                    Button(NSLocalizedString("prefs_reset", comment: "")) {
                        editor.clear()
                        commit()
                    }
                }
            }
        }
    }

    private func button(_ label: String, action: @escaping () -> Void) -> some View {
        Button(
            action: action,
            label: { Text(label) }
        ).buttonStyle(.borderless)
    }

    /// User preferences screen for a publication with a fixed layout, such as
    /// fixed-layout EPUB, PDF or comic book.
    @ViewBuilder func fixedLayoutUserPreferences(
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
        if language != nil || readingProgression != nil {
            Section {
                if let language = language {
                    languageRow(
                        title: NSLocalizedString("prefs_language", comment: ""),
                        preference: language,
                        commit: commit
                    )
                }

                if let readingProgression = readingProgression {
                    pickerRow(
                        title: NSLocalizedString("prefs_reading_progression", comment: ""),
                        preference: readingProgression,
                        commit: commit,
                        formatValue: { v in
                            switch v {
                            case .ltr: return NSLocalizedString("prefs_ltr", comment: "")
                            case .rtl: return NSLocalizedString("prefs_rtl", comment: "")
                            }
                        }
                    )
                }
            }
        }

        if let backgroundColor = backgroundColor {
            Section {
                colorRow(
                    title: NSLocalizedString("prefs_background_color", comment: ""),
                    preference: backgroundColor,
                    commit: commit
                )
            }
        }

        if let scroll = scroll {
            Section {
                toggleRow(
                    title: NSLocalizedString("prefs_scroll", comment: ""),
                    preference: scroll,
                    commit: commit
                )

                if let scrollAxis = scrollAxis {
                    pickerRow(
                        title: NSLocalizedString("prefs_scroll_axis", comment: ""),
                        preference: scrollAxis,
                        commit: commit,
                        formatValue: { v in
                            switch v {
                            case .horizontal: return NSLocalizedString("prefs_horizontal", comment: "")
                            case .vertical: return NSLocalizedString("prefs_vertical", comment: "")
                            }
                        }
                    )
                }
            }
        }

        if let spread = spread {
            Section {
                pickerRow(
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

                if let offsetFirstPage = offsetFirstPage {
                    toggleRow(
                        title: NSLocalizedString("prefs_offset_first_page", comment: ""),
                        preference: offsetFirstPage,
                        commit: commit
                    )
                }

                if let nullableOffsetFirstPage = nullableOffsetFirstPage {
                    nullableBoolPickerRow(
                        title: NSLocalizedString("prefs_offset_first_page", comment: ""),
                        preference: nullableOffsetFirstPage,
                        commit: commit
                    )
                }
            }
        }

        if let fit = fit {
            Section {
                pickerRow(
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
        }

        if let pageSpacing = pageSpacing {
            Section {
                stepperRow(
                    title: NSLocalizedString("prefs_page_spacing", comment: ""),
                    preference: pageSpacing,
                    commit: commit
                )
            }
        }
    }

    /// User settings for a publication with adjustable fonts and dimensions,
    /// such as a reflowable EPUB, HTML document or PDF with reflow mode
    /// enabled.
    @ViewBuilder func reflowableUserPreferences(
        commit: @escaping () -> Void,
        backgroundColor: AnyPreference<ReadiumNavigator.Color>? = nil,
        columnCount: AnyEnumPreference<ColumnCount>? = nil,
        fontFamily: AnyPreference<FontFamily?>? = nil,
        fontSize: AnyRangePreference<Double>? = nil,
        fontWeight: AnyRangePreference<Double>? = nil,
        hyphens: AnyPreference<Bool>? = nil,
        imageFilter: AnyEnumPreference<ImageFilter?>? = nil,
        language: AnyPreference<Language?>? = nil,
        letterSpacing: AnyRangePreference<Double>? = nil,
        ligatures: AnyPreference<Bool>? = nil,
        lineHeight: AnyRangePreference<Double>? = nil,
        pageMargins: AnyRangePreference<Double>? = nil,
        paragraphIndent: AnyRangePreference<Double>? = nil,
        paragraphSpacing: AnyRangePreference<Double>? = nil,
        publisherStyles: AnyPreference<Bool>? = nil,
        readingProgression: AnyEnumPreference<ReadiumNavigator.ReadingProgression>? = nil,
        scroll: AnyPreference<Bool>? = nil,
        textAlign: AnyEnumPreference<ReadiumNavigator.TextAlignment?>? = nil,
        textColor: AnyPreference<ReadiumNavigator.Color>? = nil,
        textNormalization: AnyPreference<Bool>? = nil,
        theme: AnyEnumPreference<Theme>? = nil,
        typeScale: AnyRangePreference<Double>? = nil,
        verticalText: AnyPreference<Bool>? = nil,
        wordSpacing: AnyRangePreference<Double>? = nil
    ) -> some View {
        if language != nil || readingProgression != nil || verticalText != nil {
            Section {
                if let language = language {
                    languageRow(
                        title: NSLocalizedString("prefs_language", comment: ""),
                        preference: language,
                        commit: commit
                    )
                }

                if let readingProgression = readingProgression {
                    pickerRow(
                        title: NSLocalizedString("prefs_reading_progression", comment: ""),
                        preference: readingProgression,
                        commit: commit,
                        formatValue: { v in
                            switch v {
                            case .ltr: return NSLocalizedString("prefs_ltr", comment: "")
                            case .rtl: return NSLocalizedString("prefs_rtl", comment: "")
                            }
                        }
                    )
                }

                if let verticalText = verticalText {
                    toggleRow(
                        title: NSLocalizedString("prefs_vertical_text", comment: ""),
                        preference: verticalText,
                        commit: commit
                    )
                }
            }
        }

        if scroll != nil || columnCount != nil || pageMargins != nil {
            Section {
                if let scroll = scroll {
                    toggleRow(
                        title: NSLocalizedString("prefs_scroll", comment: ""),
                        preference: scroll,
                        commit: commit
                    )
                }

                if let columnCount = columnCount {
                    pickerRow(
                        title: NSLocalizedString("prefs_columns", comment: ""),
                        preference: columnCount,
                        commit: commit,
                        formatValue: { v in
                            switch v {
                            case .auto: return NSLocalizedString("prefs_auto", comment: "")
                            case .one: return "1"
                            case .two: return "2"
                            }
                        }
                    )
                }

                if let pageMargins = pageMargins {
                    stepperRow(
                        title: NSLocalizedString("prefs_page_margins", comment: ""),
                        preference: pageMargins,
                        commit: commit
                    )
                }
            }
        }

        if theme != nil || imageFilter != nil || textColor != nil || backgroundColor != nil {
            Section {
                if let theme = theme {
                    pickerRow(
                        title: NSLocalizedString("prefs_theme", comment: ""),
                        preference: theme,
                        commit: commit,
                        formatValue: { v in
                            switch v {
                            case .light: return NSLocalizedString("prefs_light", comment: "")
                            case .dark: return NSLocalizedString("prefs_dark", comment: "")
                            case .sepia: return NSLocalizedString("prefs_sepia", comment: "")
                            }
                        }
                    )
                }

                if let imageFilter = imageFilter {
                    pickerRow(
                        title: NSLocalizedString("prefs_image_filter", comment: ""),
                        preference: imageFilter,
                        commit: commit,
                        formatValue: { v in
                            switch v {
                            case nil: return NSLocalizedString("prefs_none", comment: "")
                            case .darken: return NSLocalizedString("prefs_darken_colors", comment: "")
                            case .invert: return NSLocalizedString("prefs_invert_colors", comment: "")
                            }
                        }
                    )
                }

                if let textColor = textColor {
                    colorRow(
                        title: NSLocalizedString("prefs_text_color", comment: ""),
                        preference: textColor,
                        commit: commit
                    )
                }

                if let backgroundColor = backgroundColor {
                    colorRow(
                        title: NSLocalizedString("prefs_background_color", comment: ""),
                        preference: backgroundColor,
                        commit: commit
                    )
                }
            }
        }

        if fontFamily != nil || fontSize != nil || fontWeight != nil || textNormalization != nil {
            Section {
                if let fontFamily = fontFamily {
                    pickerRow(
                        title: NSLocalizedString("prefs_typeface", comment: ""),
                        preference: fontFamily
                            .with(supportedValues: [
                                nil,
                                .sansSerif,
                                .iaWriterDuospace,
                                .accessibleDfA,
                                .openDyslexic,
                                .literata,
                            ])
                            .eraseToAnyPreference(),
                        commit: commit,
                        formatValue: { ff in
                            if let ff = ff {
                                switch ff {
                                case .sansSerif: return NSLocalizedString("prefs_sans_serif", comment: "")
                                default: return ff.rawValue
                                }
                            } else {
                                return NSLocalizedString("prefs_original", comment: "")
                            }
                        }
                    )
                }

                if let fontSize = fontSize {
                    stepperRow(
                        title: NSLocalizedString("prefs_font_size", comment: ""),
                        preference: fontSize,
                        commit: commit
                    )
                }

                if let fontWeight = fontWeight {
                    stepperRow(
                        title: NSLocalizedString("prefs_font_weight", comment: ""),
                        preference: fontWeight,
                        commit: commit
                    )
                }

                if let textNormalization = textNormalization {
                    toggleRow(
                        title: NSLocalizedString("prefs_text_normalization", comment: ""),
                        preference: textNormalization,
                        commit: commit
                    )
                }
            }
        }

        if let publisherStyles = publisherStyles {
            Section {
                toggleRow(
                    title: NSLocalizedString("prefs_publisher_styles", comment: ""),
                    preference: publisherStyles,
                    commit: commit
                )

                // The following settings all require the publisher styles to
                // be disabled for EPUB. To simplify the interface, they are
                // hidden when the publisher styles are on.
                if !publisherStyles.effectiveValue {
                    if let textAlign = textAlign {
                        pickerRow(
                            title: NSLocalizedString("prefs_text_alignment", comment: ""),
                            preference: textAlign,
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
                    }

                    if let typeScale = typeScale {
                        stepperRow(
                            title: NSLocalizedString("prefs_type_scale", comment: ""),
                            preference: typeScale,
                            commit: commit
                        )
                    }

                    if let lineHeight = lineHeight {
                        stepperRow(
                            title: NSLocalizedString("prefs_line_height", comment: ""),
                            preference: lineHeight,
                            commit: commit
                        )
                    }

                    if let paragraphIndent = paragraphIndent {
                        stepperRow(
                            title: NSLocalizedString("prefs_paragraph_indent", comment: ""),
                            preference: paragraphIndent,
                            commit: commit
                        )
                    }

                    if let paragraphSpacing = paragraphSpacing {
                        stepperRow(
                            title: NSLocalizedString("prefs_paragraph_spacing", comment: ""),
                            preference: paragraphSpacing,
                            commit: commit
                        )
                    }

                    if let wordSpacing = wordSpacing {
                        stepperRow(
                            title: NSLocalizedString("prefs_word_spacing", comment: ""),
                            preference: wordSpacing,
                            commit: commit
                        )
                    }

                    if let letterSpacing = letterSpacing {
                        stepperRow(
                            title: NSLocalizedString("prefs_letter_spacing", comment: ""),
                            preference: letterSpacing,
                            commit: commit
                        )
                    }

                    if let hyphens = hyphens {
                        toggleRow(
                            title: NSLocalizedString("prefs_hyphens", comment: ""),
                            preference: hyphens,
                            commit: commit
                        )
                    }

                    if let ligatures = ligatures {
                        toggleRow(
                            title: NSLocalizedString("prefs_ligatures", comment: ""),
                            preference: ligatures,
                            commit: commit
                        )
                    }
                }
            }
        }
    }

    /// User preferences screen for an audiobook.
    func audioUserPreferences(
        commit: @escaping () -> Void,
        volume: AnyRangePreference<Double>? = nil,
        speed: AnyRangePreference<Double>? = nil
    ) -> some View {
        Section {
            if let volume = volume {
                stepperRow(
                    title: NSLocalizedString("prefs_volume", comment: ""),
                    preference: volume,
                    commit: commit
                )
            }

            if let speed = speed {
                stepperRow(
                    title: NSLocalizedString("prefs_speed", comment: ""),
                    preference: speed,
                    commit: commit
                )
            }
        }
    }

    /// Component for a boolean `Preference` switchable with a `Toggle` button.
    func toggleRow(
        title: String,
        preference: AnyPreference<Bool>,
        commit: @escaping () -> Void
    ) -> some View {
        toggleRow(
            title: title,
            value: preference.binding(onSet: commit),
            isActive: preference.isEffective,
            onClear: { preference.clear(); commit() }
        )
    }

    /// Component for a boolean `Preference` switchable with a `Toggle` button.
    func toggleRow(
        title: String,
        value: Binding<Bool>,
        isActive: Bool,
        onClear: @escaping () -> Void
    ) -> some View {
        preferenceRow(
            isActive: isActive,
            onClear: onClear
        ) {
            Toggle(title, isOn: value)
        }
    }

    /// Component for a nullable boolean `Preference` displayed in a `Picker` view
    /// with three options: Auto, Yes, No.
    func nullableBoolPickerRow(
        title: String,
        preference: AnyPreference<Bool?>,
        commit: @escaping () -> Void
    ) -> some View {
        preferenceRow(
            isActive: preference.isEffective,
            onClear: { preference.clear(); commit() }
        ) {
            Picker(title, selection: Binding(
                get: { preference.value ?? preference.effectiveValue },
                set: { preference.set($0); commit() }
            )) {
                Text(NSLocalizedString("prefs_auto", comment: "")).tag(nil as Bool?)
                Text(NSLocalizedString("prefs_yes", comment: "")).tag(true as Bool?)
                Text(NSLocalizedString("prefs_no", comment: "")).tag(false as Bool?)
            }
        }
    }

    /// Component for an `EnumPreference` displayed in a `Picker` view.
    func pickerRow<V: Hashable>(
        title: String,
        preference: AnyEnumPreference<V>,
        commit: @escaping () -> Void,
        formatValue: @escaping (V) -> String
    ) -> some View {
        pickerRow(
            title: title,
            value: preference.binding(onSet: commit),
            values: preference.supportedValues,
            isActive: preference.isEffective,
            onClear: { preference.clear(); commit() },
            formatValue: formatValue
        )
    }

    /// Component for an `EnumPreference` displayed in a `Picker` view.
    func pickerRow<V: Hashable>(
        title: String,
        value: Binding<V>,
        values: [V],
        isActive: Bool,
        onClear: @escaping () -> Void,
        formatValue: @escaping (V) -> String
    ) -> some View {
        preferenceRow(
            isActive: isActive,
            onClear: onClear
        ) {
            Picker(title, selection: value) {
                ForEach(values, id: \.self) {
                    Text(formatValue($0)).tag($0)
                }
            }
        }
    }

    /// Component for a `RangePreference` modifiable by a `Stepper` view.
    func stepperRow<V: Comparable>(
        title: String,
        preference: AnyRangePreference<V>,
        commit: @escaping () -> Void
    ) -> some View {
        stepperRow(
            title: title,
            value: preference.format(value: preference.value ?? preference.effectiveValue),
            isActive: preference.isEffective,
            onIncrement: { preference.increment(); commit() },
            onDecrement: { preference.decrement(); commit() },
            onClear: { preference.clear(); commit() }
        )
    }

    /// Component for a `RangePreference` modifiable by a `Stepper` view.
    func stepperRow(
        title: String,
        value: String,
        isActive: Bool,
        onIncrement: @escaping () -> Void,
        onDecrement: @escaping () -> Void,
        onClear: @escaping () -> Void
    ) -> some View {
        preferenceRow(
            isActive: isActive,
            onClear: onClear
        ) {
            HStack {
                Stepper(title,
                        onIncrement: onIncrement,
                        onDecrement: onDecrement)

                Text(value)
                    .font(.caption)
            }
        }
    }

    /// Component for a `Preference` holding a `Language` value.
    func languageRow(
        title: String,
        preference: AnyPreference<Language?>,
        commit: @escaping () -> Void
    ) -> some View {
        pickerRow(
            title: title,
            value: Binding(
                get: { preference.value ?? preference.effectiveValue },
                set: { preference.set($0); commit() }
            ),
            values: languages,
            isActive: preference.isEffective,
            onClear: { preference.clear(); commit() },
            formatValue: { language in
                language?.localizedDescription() ?? NSLocalizedString("prefs_original", comment: "")
            }
        )
    }

    /// Component for a `Preference` holding a `Color` value.
    func colorRow(
        title: String,
        preference: AnyPreference<ReadiumNavigator.Color>,
        commit: @escaping () -> Void
    ) -> some View {
        colorRow(
            title: title,
            value: Binding(
                get: { (preference.value ?? preference.effectiveValue).color },
                set: {
                    preference.set(ReadiumNavigator.Color(color: $0))
                    commit()
                }
            ),
            isActive: preference.isEffective,
            onClear: { preference.clear(); commit() }
        )
    }

    /// Component for a `Preference` holding a `Color` value.
    func colorRow(
        title: String,
        value: Binding<SwiftUI.Color>,
        isActive: Bool,
        onClear: @escaping () -> Void
    ) -> some View {
        preferenceRow(
            isActive: isActive,
            onClear: onClear
        ) {
            ColorPicker(title,
                        selection: value,
                        supportsOpacity: false)
        }
    }

    /// Layout for a preference row.
    func preferenceRow<V: View>(
        isActive: Bool,
        onClear: @escaping () -> Void,
        content: @escaping () -> V
    ) -> some View {
        HStack {
            content()
                .foregroundColor(isActive ? nil : .gray)

            Button(action: onClear) {
                Image(systemName: "delete.left")
            }
            .buttonStyle(.plain)
        }
    }
}

extension Preference {
    /// Creates a SwiftUI binding to modify the preference's value.
    ///
    /// This is convenient when paired with a `Toggle` or `Picker`.
    func binding(onSet: @escaping () -> Void = {}) -> Binding<Value> {
        Binding(
            get: { value ?? effectiveValue },
            set: { set($0); onSet() }
        )
    }
}
