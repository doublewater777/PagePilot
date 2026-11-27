//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import ReadiumNavigator
import SwiftUI
import UIKit

// MARK: - Curated 4-Preset Tactile Paper Themes

/// Four curated reading paper presets tuned for daylight, warm evening,
/// high-contrast e-ink clarity, and low-glare OLED night reading.
enum ReaderPaperPreset: String, CaseIterable, Identifiable {
    case morningPaper
    case sepia
    case eink
    case midnightInk

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .morningPaper:
            return NSLocalizedString("reader_preset_morning_paper", comment: "")
        case .sepia:
            return NSLocalizedString("reader_preset_sepia", comment: "")
        case .eink:
            return NSLocalizedString("reader_preset_eink", comment: "")
        case .midnightInk:
            return NSLocalizedString("reader_preset_midnight_ink", comment: "")
        }
    }

    var iconName: String {
        switch self {
        case .morningPaper: return "sun.max"
        case .sepia: return "book.pages"
        case .eink: return "doc.plaintext"
        case .midnightInk: return "moon.stars.fill"
        }
    }

    var isDark: Bool {
        self == .midnightInk
    }

    var uiBackgroundColor: UIColor {
        switch self {
        case .morningPaper:
            return UIColor(red: 250 / 255, green: 249 / 255, blue: 246 / 255, alpha: 1) // #FAF9F6
        case .sepia:
            return AppColors.readerSepiaBackground // #F4ECD8
        case .eink:
            return UIColor(red: 241 / 255, green: 241 / 255, blue: 238 / 255, alpha: 1) // #F1F1EE
        case .midnightInk:
            return UIColor(red: 19 / 255, green: 20 / 255, blue: 23 / 255, alpha: 1) // #131417
        }
    }

    var uiTextColor: UIColor {
        switch self {
        case .morningPaper:
            return UIColor(red: 30 / 255, green: 31 / 255, blue: 33 / 255, alpha: 1) // #1E1F21
        case .sepia:
            return AppColors.readerSepiaText // #433422
        case .eink:
            return UIColor(red: 14 / 255, green: 14 / 255, blue: 14 / 255, alpha: 1) // #0E0E0E
        case .midnightInk:
            return UIColor(red: 222 / 255, green: 220 / 255, blue: 213 / 255, alpha: 1) // #DEDCD5
        }
    }

    var swiftUIBackground: SwiftUI.Color {
        SwiftUI.Color(uiColor: uiBackgroundColor)
    }

    var swiftUITextColor: SwiftUI.Color {
        SwiftUI.Color(uiColor: uiTextColor)
    }

    var readiumTheme: ReadiumNavigator.Theme {
        switch self {
        case .morningPaper, .eink:
            return .light
        case .sepia:
            return .sepia
        case .midnightInk:
            return .dark
        }
    }

    /// Applies this paper preset to an `EPUBPreferences` value.
    func apply(to preferences: inout EPUBPreferences) {
        preferences.theme = readiumTheme
        switch self {
        case .sepia:
            preferences.backgroundColor = nil
            preferences.textColor = nil
        case .morningPaper, .eink, .midnightInk:
            preferences.backgroundColor = ReadiumNavigator.Color(color: swiftUIBackground)
            preferences.textColor = ReadiumNavigator.Color(color: swiftUITextColor)
        }
    }

    /// Applies this paper preset through Readium's preference editor bindings.
    func apply(
        theme: AnyEnumPreference<ReadiumNavigator.Theme>,
        backgroundColor: AnyPreference<ReadiumNavigator.Color>,
        textColor: AnyPreference<ReadiumNavigator.Color>
    ) {
        theme.set(readiumTheme)
        switch self {
        case .sepia:
            backgroundColor.clear()
            textColor.clear()
        case .morningPaper, .eink, .midnightInk:
            backgroundColor.set(ReadiumNavigator.Color(color: swiftUIBackground))
            textColor.set(ReadiumNavigator.Color(color: swiftUITextColor))
        }
    }

    func next() -> ReaderPaperPreset {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self) else { return .morningPaper }
        return all[(index + 1) % all.count]
    }

    /// Resolves which curated preset best matches the stored EPUB preferences.
    static func matching(
        preferences: EPUBPreferences?,
        systemStyle: UIUserInterfaceStyle
    ) -> ReaderPaperPreset? {
        if let customBg = preferences?.backgroundColor?.color {
            let candidate = UIColor(customBg)
            for preset in allCases where preset.matchesColor(candidate) {
                return preset
            }
            return nil
        }

        switch preferences?.theme {
        case .sepia:
            return .sepia
        case .dark:
            return .midnightInk
        case .light:
            return .morningPaper
        case nil:
            return systemStyle == .dark ? .midnightInk : .morningPaper
        }
    }

    private func matchesColor(_ other: UIColor) -> Bool {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        guard uiBackgroundColor.getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else {
            return false
        }
        return abs(r1 - r2) < 0.02 && abs(g1 - g2) < 0.02 && abs(b1 - b2) < 0.02
    }
}

// MARK: - Hands-Free Bedside Mode Policy

/// Controls the anti-accidental-touch ("Bedside / Hands-Free") reading lock.
/// Touch input on the reading canvas is shielded while Watch & Volume Key page turns stay active.
struct HandsFreeReadingState: Equatable {
    private(set) var isEnabled: Bool = false

    var shouldKeepScreenAwake: Bool { isEnabled }
    var blocksCanvasTouch: Bool { isEnabled }
    var allowsWatchPageTurn: Bool { true }
    var allowsVolumeKeyPageTurn: Bool { true }

    mutating func enable() {
        isEnabled = true
    }

    mutating func disable() {
        isEnabled = false
    }

    @discardableResult
    mutating func toggle() -> Bool {
        isEnabled.toggle()
        return isEnabled
    }
}

// MARK: - Launch Directly to Reader Policy

enum LaunchToReaderPolicy {
    static func shouldAutoOpenLastReadBook(
        hasSeenOnboarding: Bool,
        launchDirectlyEnabled: Bool,
        hasIncomingURL: Bool,
        hasDebugTabOverride: Bool,
        alreadyConsumedThisLaunch: Bool
    ) -> Bool {
        guard hasSeenOnboarding,
              launchDirectlyEnabled,
              !hasIncomingURL,
              !hasDebugTabOverride,
              !alreadyConsumedThisLaunch else {
            return false
        }
        return true
    }
}

// MARK: - Remaining Reading Time Estimator

enum ReadingTimeEstimator {
    /// Average reading pace per Readium reflowable position (~1024 bytes ≈ 180 words ≈ 45 seconds).
    static let defaultSecondsPerPosition: Double = 45

    /// Estimates remaining minutes from current position to a target boundary (chapter end or book end).
    static func remainingMinutes(
        currentPosition: Int,
        targetEndPosition: Int,
        secondsPerPosition: Double = defaultSecondsPerPosition
    ) -> Int? {
        guard targetEndPosition >= currentPosition,
              currentPosition > 0,
              secondsPerPosition > 0 else {
            return nil
        }
        let remainingPositions = max(1, targetEndPosition - currentPosition + 1)
        let minutes = Int(ceil((Double(remainingPositions) * secondsPerPosition) / 60.0))
        return max(1, min(999, minutes))
    }

    /// Formats a localized remaining-time string such as "约剩 12 分钟" or "~12 min left".
    static func localizedRemainingText(minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            let remMinutes = minutes % 60
            if remMinutes == 0 {
                return String(
                    format: NSLocalizedString("reader_remaining_hours_format", comment: ""),
                    hours
                )
            }
            return String(
                format: NSLocalizedString("reader_remaining_hours_minutes_format", comment: ""),
                hours,
                remMinutes
            )
        }
        return String(
            format: NSLocalizedString("reader_remaining_minutes_format", comment: ""),
            max(1, minutes)
        )
    }
}
