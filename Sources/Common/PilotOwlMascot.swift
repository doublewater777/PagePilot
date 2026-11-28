//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Mascot Mood & Policy

/// Emotional states of PagePilot's Pilot Owl mascot, adapting calmly to reading
/// progress, time of day, and library state without ever intruding on active reading.
enum MascotMood: String, CaseIterable, Equatable, Sendable {
    case idle
    case reading
    case celebrating
    case nightOwl

    var assetName: String {
        switch self {
        case .idle: return "MascotOwlIdle"
        case .reading: return "MascotOwlReading"
        case .celebrating: return "MascotOwlCelebrating"
        case .nightOwl: return "MascotOwlNight"
        }
    }

    var fallbackSymbol: String {
        switch self {
        case .idle: return "bird.fill"
        case .reading: return "book.pages.fill"
        case .celebrating: return "sparkles"
        case .nightOwl: return "moon.stars.fill"
        }
    }

    var ambientTint: Color {
        switch self {
        case .idle: return AppColors.accentBlue
        case .reading: return AppColors.accentTeal
        case .celebrating: return Color(red: 0.94, green: 0.68, blue: 0.24)
        case .nightOwl: return Color(red: 0.38, green: 0.44, blue: 0.88)
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .idle: return NSLocalizedString("mascot_a11y_idle", comment: "")
        case .reading: return NSLocalizedString("mascot_a11y_reading", comment: "")
        case .celebrating: return NSLocalizedString("mascot_a11y_celebrating", comment: "")
        case .nightOwl: return NSLocalizedString("mascot_a11y_night", comment: "")
        }
    }
}

enum MascotMoodPolicy {
    /// Resolves the mascot mood deterministically from reading progress, streak, and local hour.
    static func resolve(
        todaySeconds: Int,
        dailyGoalMinutes: Int,
        streakDays: Int,
        hour: Int,
        hasBooks: Bool
    ) -> MascotMood {
        guard hasBooks else { return .idle }
        if ReadingGoalPolicy.goalReached(todaySeconds: todaySeconds, goalMinutes: dailyGoalMinutes) {
            return .celebrating
        }
        if hour >= 22 || hour < 5 {
            return .nightOwl
        }
        if todaySeconds >= 60 {
            return .reading
        }
        return .idle
    }

    static func currentHour(date: Date = Date(), calendar: Calendar = .current) -> Int {
        calendar.component(.hour, from: date)
    }

    static func companionTitle(for mood: MascotMood) -> String {
        switch mood {
        case .idle:
            return NSLocalizedString("mascot_status_idle_title", comment: "")
        case .reading:
            return NSLocalizedString("mascot_status_reading_title", comment: "")
        case .celebrating:
            return NSLocalizedString("mascot_status_celebrating_title", comment: "")
        case .nightOwl:
            return NSLocalizedString("mascot_status_night_title", comment: "")
        }
    }

    static func companionSubtitle(
        mood: MascotMood,
        todayMinutes: Int,
        dailyGoalMinutes: Int,
        streakDays: Int
    ) -> String {
        switch mood {
        case .celebrating:
            if streakDays >= 2 {
                return String(
                    format: NSLocalizedString("mascot_status_celebrating_streak_format", comment: ""),
                    todayMinutes,
                    streakDays
                )
            }
            return String(
                format: NSLocalizedString("mascot_status_celebrating_format", comment: ""),
                todayMinutes
            )

        case .nightOwl:
            return NSLocalizedString("mascot_status_night_subtitle", comment: "")

        case .reading:
            let remaining = max(1, dailyGoalMinutes - todayMinutes)
            return String(
                format: NSLocalizedString("mascot_status_reading_format", comment: ""),
                todayMinutes,
                remaining
            )

        case .idle:
            if streakDays >= 2 {
                return String(
                    format: NSLocalizedString("mascot_status_idle_streak_format", comment: ""),
                    streakDays
                )
            }
            return NSLocalizedString("mascot_status_idle_subtitle", comment: "")
        }
    }

    static func tapGreeting(for mood: MascotMood, tapCount: Int) -> String {
        let keys: [String]
        switch mood {
        case .celebrating:
            keys = ["mascot_tap_celebrating_1", "mascot_tap_celebrating_2", "mascot_tap_celebrating_3"]
        case .nightOwl:
            keys = ["mascot_tap_night_1", "mascot_tap_night_2", "mascot_tap_night_3"]
        case .reading:
            keys = ["mascot_tap_reading_1", "mascot_tap_reading_2", "mascot_tap_reading_3"]
        case .idle:
            keys = ["mascot_tap_idle_1", "mascot_tap_idle_2", "mascot_tap_idle_3"]
        }
        let index = abs(tapCount) % keys.count
        return NSLocalizedString(keys[index], comment: "")
    }
}

// MARK: - Core Mascot Figurine View

/// Renders the transparent 3D matte Pilot Owl figurine with soft mood-tinted ambient glow.
/// Stays visually calm at rest (zero idle GPU redraws or animation bleed during launch/rotation).
struct PilotOwlMascotView: View {
    let mood: MascotMood
    var size: CGFloat = 72
    var animated: Bool = true
    var showSoftGlow: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if showSoftGlow {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                mood.ambientTint.opacity(colorScheme == .dark ? 0.30 : 0.18),
                                mood.ambientTint.opacity(0),
                            ],
                            center: .center,
                            startRadius: size * 0.08,
                            endRadius: size * 0.56
                        )
                    )
                    .frame(width: size * 1.08, height: size * 1.08)
            }

            if UIImage(named: mood.assetName) != nil {
                Image(mood.assetName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .shadow(
                        color: Color.black.opacity(colorScheme == .dark ? 0.36 : 0.14),
                        radius: max(3, size * 0.07),
                        y: max(2, size * 0.04)
                    )
            } else {
                ZStack {
                    Circle()
                        .fill(mood.ambientTint.opacity(colorScheme == .dark ? 0.24 : 0.14))
                    Image(systemName: mood.fallbackSymbol)
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(mood.ambientTint)
                }
                .frame(width: size * 0.82, height: size * 0.82)
            }
        }
        .accessibilityLabel(mood.accessibilityLabel)
    }
}

// MARK: - Desk Companion Strip

/// Compact, calm reading companion bar shown on Desk ("书房").
/// Tapping the owl triggers a gentle spring hop and rotates literary micro-encouragements;
/// tapping the trailing cue navigates to Journal ("印记").
struct DeskMascotCompanionBar: View {
    let todaySeconds: Int
    let dailyGoalMinutes: Int
    let streakDays: Int
    let hasBooks: Bool
    var onOpenJournal: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tapCount = 0
    @State private var customGreeting: String?
    @State private var hopOffset: CGFloat = 0

    private var mood: MascotMood {
        MascotMoodPolicy.resolve(
            todaySeconds: todaySeconds,
            dailyGoalMinutes: dailyGoalMinutes,
            streakDays: streakDays,
            hour: MascotMoodPolicy.currentHour(),
            hasBooks: hasBooks
        )
    }

    private var todayMinutes: Int {
        todaySeconds / 60
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                triggerOwlHop()
            } label: {
                PilotOwlMascotView(mood: mood, size: 54, animated: true, showSoftGlow: true)
                    .offset(y: hopOffset)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(MascotMoodPolicy.companionTitle(for: mood))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(AppColors.primaryText)
                        .lineLimit(1)

                    if streakDays > 0 {
                        HStack(spacing: 2.5) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 9.5, weight: .bold))
                            Text("\(streakDays)")
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .monospacedDigit()
                        }
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6.5)
                        .padding(.vertical, 2)
                        .background(
                            Color.orange.opacity(colorScheme == .dark ? 0.18 : 0.12),
                            in: Capsule()
                        )
                    }
                }

                Text(
                    customGreeting ?? MascotMoodPolicy.companionSubtitle(
                        mood: mood,
                        todayMinutes: todayMinutes,
                        dailyGoalMinutes: dailyGoalMinutes,
                        streakDays: streakDays
                    )
                )
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(AppColors.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            }

            Spacer(minLength: 4)

            if let onOpenJournal {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onOpenJournal()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(AppColors.tertiaryText)
                        .frame(width: 28, height: 28)
                        .background(
                            Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.045),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("journal_title", comment: ""))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    mood == .celebrating
                        ? mood.ambientTint.opacity(colorScheme == .dark ? 0.32 : 0.25)
                        : Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05),
                    lineWidth: 0.9
                )
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0 : 0.04), radius: 10, y: 4)
    }

    private func triggerOwlHop() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        let nextTap = tapCount + 1
        tapCount = nextTap
        let greeting = MascotMoodPolicy.tapGreeting(for: mood, tapCount: nextTap)
        withAnimation(.easeInOut(duration: 0.2)) {
            customGreeting = greeting
        }
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) {
            hopOffset = -6
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.58)) {
                hopOffset = 0
            }
        }
    }
}

// MARK: - Postcard Signature Seal

/// Subtle corner stamp featuring the Pilot Owl figurine for Quote Postcards.
struct MascotPostcardSeal: View {
    let accentColor: Color
    let borderColor: Color
    let surfaceColor: Color

    var body: some View {
        HStack(spacing: 5) {
            if UIImage(named: MascotMood.reading.assetName) != nil {
                Image(MascotMood.reading.assetName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "bird.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 22, height: 22)
            }

            Text("PagePilot")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(accentColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(surfaceColor, in: Capsule())
        .overlay(
            Capsule()
                .stroke(borderColor, lineWidth: 0.75)
        )
    }
}
