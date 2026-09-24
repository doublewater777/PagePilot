//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation

enum OnboardingSamplePublication {
    private struct ChapterSource {
        let title: String
        let markdown: String
    }

    private static let identifier = "urn:pagepilot:onboarding-sample:v1"
    private static let chapterDefinitions = [
        ("onboarding_sample_chapter1_title", "A Quiet Beginning", "onboarding_sample_chapter1_body", """
        The room was quiet enough to hear the soft turn of a page. Morning light rested on the table, and the next paragraph waited without asking for attention.

        Reading often begins this simply. One line leads to another, and the world outside keeps its pace while a book gives you a little room to breathe.
        """),
        ("onboarding_sample_chapter2_title", "The Next Page", "onboarding_sample_chapter2_body", """
        A good reading rhythm is easy to recognize. Your eyes reach the final sentence, your attention leans ahead, and the next page arrives almost before you think about it.

        That is the idea behind PagePilot. Read on iPhone or iPad and, when it helps, use Apple Watch as a small remote from your wrist.
        """),
        ("onboarding_sample_chapter3_title", "A Few Minutes More", "onboarding_sample_chapter3_body", """
        A few pages can be enough to leave the room for a moment. The important part is continuity: the text remains available whenever you have a spare minute.

        Your publications live in your bookshelf, your reading position follows the book, and the reader is ready whenever you return. When you are ready, bring in a publication from Files, Wi-Fi transfer, or an OPDS catalog.
        """),
        ("onboarding_sample_chapter4_title", "Your Library", "onboarding_sample_chapter4_body", """
        The best sample is eventually the book you actually want to read. It might be a novel, a long article, a draft, or a reference document you return to often.

        Import one when it is convenient. Until then, this short publication is a safe place to explore the reader and try a Watch page turn.
        """),
    ]

    private static var chapterSources: [ChapterSource] {
        chapterDefinitions.map { titleKey, titleFallback, bodyKey, bodyFallback in
            ChapterSource(
                title: localized(titleKey, fallback: titleFallback),
                markdown: "# \(localized(titleKey, fallback: titleFallback))\n\n\(localized(bodyKey, fallback: bodyFallback))"
            )
        }
    }

    private static var localizedTitle: String {
        localized("onboarding_sample_title", fallback: "PagePilot Sample")
    }

    private static var languageCode: String {
        AppAppearancePreferences.language.rawValue
    }

    private static func localized(_ key: String, fallback: String) -> String {
        NSLocalizedString(key, tableName: "Onboarding", value: fallback, comment: "Onboarding sample publication copy")
    }

    static var chapterCount: Int {
        chapterSources.count
    }

    static func makeURL() async throws -> URL {
        let chapters = try chapterSources.map {
            MinimalEPUBPackager.Chapter(
                title: $0.title,
                bodyHTML: try MarkdownToEPUBConverter.renderAndSanitize($0.markdown)
            )
        }
        return try await MinimalEPUBPackager.package(
            title: localizedTitle,
            language: languageCode,
            chapters: chapters,
            identifier: identifier
        )
    }
}
