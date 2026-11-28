//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import AppIntents
import SwiftUI

/// Guides users to discover PagePilot's Siri voice commands, App Shortcuts,
/// and Focus / automation workflows directly from Settings.
struct ShortcutsGuideView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private struct ShortcutIdea: Identifiable {
        let id: String
        let icon: String
        let tint: Color
        let titleKey: String
        let subtitleKey: String
    }

    private let ideas: [ShortcutIdea] = [
        ShortcutIdea(
            id: "continue",
            icon: "book.pages.fill",
            tint: AppColors.accentBlue,
            titleKey: "shortcuts_idea_continue_title",
            subtitleKey: "shortcuts_idea_continue_desc"
        ),
        ShortcutIdea(
            id: "micro",
            icon: "timer",
            tint: .orange,
            titleKey: "shortcuts_idea_micro_title",
            subtitleKey: "shortcuts_idea_micro_desc"
        ),
        ShortcutIdea(
            id: "bedtime",
            icon: "moon.stars.fill",
            tint: .indigo,
            titleKey: "shortcuts_idea_bedtime_title",
            subtitleKey: "shortcuts_idea_bedtime_desc"
        ),
        ShortcutIdea(
            id: "quotes",
            icon: "text.quote",
            tint: AppColors.accentTeal,
            titleKey: "shortcuts_idea_quotes_title",
            subtitleKey: "shortcuts_idea_quotes_desc"
        ),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroCard
                actionsList
                siriTipFooter
            }
            .padding(.horizontal, horizontalSizeClass == .regular ? 24 : 16)
            .padding(.vertical, 16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle(NSLocalizedString("settings_shortcuts_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.25, green: 0.32, blue: 0.85), Color(red: 0.14, green: 0.58, blue: 0.72)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(NSLocalizedString("shortcuts_guide_headline", comment: ""))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppColors.primaryText)
                    Text(NSLocalizedString("shortcuts_guide_subtitle", comment: ""))
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            #if !targetEnvironment(macCatalyst)
            ShortcutsLink()
                .shortcutsLinkStyle(colorScheme == .dark ? .lightOutline : .darkOutline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
            #else
            Button {
                if let url = URL(string: "shortcuts://") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label(
                    NSLocalizedString("shortcuts_open_app_button", comment: ""),
                    systemImage: "arrow.up.forward.app"
                )
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(AppColors.accentBlue, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            #endif
        }
        .padding(16)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.1 : 0.06), lineWidth: 0.75)
        )
    }

    private var actionsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("shortcuts_guide_section_ideas", comment: ""))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.secondaryText)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(ideas.enumerated()), id: \.element.id) { index, idea in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: idea.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(idea.tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(NSLocalizedString(idea.titleKey, comment: ""))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppColors.primaryText)
                            Text(NSLocalizedString(idea.subtitleKey, comment: ""))
                                .font(.system(size: 13))
                                .foregroundStyle(AppColors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(14)

                    if index < ideas.count - 1 {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.1 : 0.06), lineWidth: 0.75)
            )
        }
    }

    private var siriTipFooter: some View {
        Text(NSLocalizedString("shortcuts_guide_footer", comment: ""))
            .font(.system(size: 12.5))
            .foregroundStyle(AppColors.secondaryText)
            .padding(.horizontal, 4)
    }
}
