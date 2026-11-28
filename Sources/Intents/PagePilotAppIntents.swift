//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import AppIntents
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 1. Continue Reading

struct ContinueReadingIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource(
        "intent_continue_reading_title",
        defaultValue: "Continue Reading"
    )

    static var description = IntentDescription(
        LocalizedStringResource(
            "intent_continue_reading_desc",
            defaultValue: "Resume the book you were reading most recently in PagePilot."
        ),
        categoryName: LocalizedStringResource("intent_category_reading", defaultValue: "Reading")
    )

    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ReturnsValue<BookAppEntity> & ProvidesDialog {
        let store = PagePilotIntentEnvironment.store
        let allBooks = try await store.fetchAllBooks()
        guard let selected = ContinueReadingSelector.select(
            from: allBooks,
            lastReadIds: store.lastReadBookIds()
        ) ?? allBooks.last else {
            throw PagePilotIntentError.noBooksAvailable
        }

        try await store.openBook(selected, microReadingMinutes: nil)
        let entity = BookAppEntity(book: selected)
        return .result(
            value: entity,
            dialog: localizedIntentDialog("intent_continue_reading_dialog", selected.title)
        )
    }
}

// MARK: - 2. Start Quick / Micro Reading

struct StartMicroReadingIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource(
        "intent_micro_reading_title",
        defaultValue: "Start Quick Read"
    )

    static var description = IntentDescription(
        LocalizedStringResource(
            "intent_micro_reading_desc",
            defaultValue: "Start a timed 3, 5, or 10 minute micro-reading session in PagePilot."
        ),
        categoryName: LocalizedStringResource("intent_category_reading", defaultValue: "Reading")
    )

    static var openAppWhenRun: Bool = true

    @Parameter(
        title: LocalizedStringResource("intent_param_duration", defaultValue: "Duration"),
        default: .fiveMinutes
    )
    var duration: MicroReadingDurationOption

    @Parameter(title: LocalizedStringResource("intent_param_book_optional", defaultValue: "Book"))
    var book: BookAppEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Start \(\.$duration) reading session") {
            \.$book
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<BookAppEntity> & ProvidesDialog {
        let store = PagePilotIntentEnvironment.store
        let targetBook: Book
        if let bookEntity = book {
            guard let resolved = try await store.fetchBook(entityID: bookEntity.id) else {
                throw PagePilotIntentError.bookNotFound
            }
            targetBook = resolved
        } else {
            let allBooks = try await store.fetchAllBooks()
            guard let selected = ContinueReadingSelector.select(
                from: allBooks,
                lastReadIds: store.lastReadBookIds()
            ) ?? allBooks.last else {
                throw PagePilotIntentError.noBooksAvailable
            }
            targetBook = selected
        }

        try await store.openBook(targetBook, microReadingMinutes: duration.rawValue)
        let entity = BookAppEntity(book: targetBook)
        return .result(
            value: entity,
            dialog: localizedIntentDialog("intent_micro_reading_dialog", Int64(duration.rawValue), targetBook.title)
        )
    }
}

// MARK: - 3. Open Specific Book

struct OpenBookIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource(
        "intent_open_book_title",
        defaultValue: "Open Book"
    )

    static var description = IntentDescription(
        LocalizedStringResource(
            "intent_open_book_desc",
            defaultValue: "Open a specific book from your PagePilot library."
        ),
        categoryName: LocalizedStringResource("intent_category_reading", defaultValue: "Reading")
    )

    static var openAppWhenRun: Bool = true

    @Parameter(
        title: LocalizedStringResource("intent_param_book", defaultValue: "Book"),
        requestValueDialog: IntentDialog(
            LocalizedStringResource("intent_prompt_choose_book", defaultValue: "Which book would you like to read?")
        )
    )
    var book: BookAppEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$book)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<BookAppEntity> & ProvidesDialog {
        let store = PagePilotIntentEnvironment.store
        guard let resolved = try await store.fetchBook(entityID: book.id) else {
            throw PagePilotIntentError.bookNotFound
        }

        try await store.openBook(resolved, microReadingMinutes: nil)
        let entity = BookAppEntity(book: resolved)
        return .result(
            value: entity,
            dialog: localizedIntentDialog("intent_open_book_dialog", resolved.title)
        )
    }
}

// MARK: - 4. Check Today's Reading Progress

struct GetReadingProgressIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource(
        "intent_reading_progress_title",
        defaultValue: "Check Reading Progress"
    )

    static var description = IntentDescription(
        LocalizedStringResource(
            "intent_reading_progress_desc",
            defaultValue: "Check how many minutes you have read today, your reading streak, and your current book progress."
        ),
        categoryName: LocalizedStringResource("intent_category_stats", defaultValue: "Reading Journal")
    )

    static var openAppWhenRun: Bool = false

    static func buildStatusEntity() async throws -> ReadingStatusAppEntity {
        let store = PagePilotIntentEnvironment.store
        let todaySeconds = store.todayReadingSeconds()
        let todayMinutes = todaySeconds / 60
        let goalMinutes = store.dailyGoalMinutes()
        let goalReached = ReadingGoalPolicy.goalReached(todaySeconds: todaySeconds, goalMinutes: goalMinutes)
        let streakDays = store.currentStreakDays()

        let allBooks = (try? await store.fetchAllBooks()) ?? []
        let currentBook = ContinueReadingSelector.select(
            from: allBooks,
            lastReadIds: store.lastReadBookIds()
        )
        let progressPercent = currentBook.map { max(0, min(100, Int(($0.progression * 100).rounded()))) } ?? 0

        let summaryText = String(
            format: NSLocalizedString("intent_progress_summary_format", comment: ""),
            todayMinutes,
            goalMinutes,
            streakDays
        )

        return ReadingStatusAppEntity(
            todayMinutes: todayMinutes,
            dailyGoalMinutes: goalMinutes,
            goalReached: goalReached,
            streakDays: streakDays,
            currentBookTitle: currentBook?.title,
            currentBookProgressPercent: progressPercent,
            summaryText: summaryText
        )
    }

    func perform() async throws -> some IntentResult & ReturnsValue<ReadingStatusAppEntity> & ProvidesDialog & ShowsSnippetView {
        let status = try await Self.buildStatusEntity()
        let dialog: IntentDialog
        if status.goalReached {
            dialog = localizedIntentDialog(
                "intent_progress_dialog_complete",
                Int64(status.todayMinutes),
                Int64(status.dailyGoalMinutes),
                Int64(status.streakDays)
            )
        } else {
            let remaining = max(1, status.dailyGoalMinutes - status.todayMinutes)
            dialog = localizedIntentDialog(
                "intent_progress_dialog_remaining",
                Int64(status.todayMinutes),
                Int64(status.dailyGoalMinutes),
                Int64(remaining)
            )
        }

        return .result(
            value: status,
            dialog: dialog,
            view: ReadingProgressSnippetView(status: status)
        )
    }
}

// MARK: - 5. Random Reading Quote

struct GetRandomQuoteIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource(
        "intent_random_quote_title",
        defaultValue: "Get Random Quote"
    )

    static var description = IntentDescription(
        LocalizedStringResource(
            "intent_random_quote_desc",
            defaultValue: "Surface a random saved highlight from your PagePilot reading journal."
        ),
        categoryName: LocalizedStringResource("intent_category_stats", defaultValue: "Reading Journal")
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: LocalizedStringResource("intent_param_book_optional", defaultValue: "Book"))
    var book: BookAppEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Get a random quote") {
            \.$book
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<QuoteAppEntity> & ProvidesDialog & ShowsSnippetView {
        let store = PagePilotIntentEnvironment.store
        let resolvedBook: Book?
        if let book {
            guard let found = try await store.fetchBook(entityID: book.id) else {
                throw PagePilotIntentError.bookNotFound
            }
            resolvedBook = found
        } else {
            resolvedBook = nil
        }

        let targetBookId = resolvedBook?.id
        let highlights = try await store.fetchHighlights(bookId: targetBookId)
            .filter { !($0.locator.text.highlight ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard let picked = highlights.randomElement() else {
            throw PagePilotIntentError.noHighlightsAvailable
        }

        let bookTitle: String
        if let resolvedBook {
            bookTitle = resolvedBook.title
        } else if let resolved = try await store.fetchBook(id: picked.bookId) {
            bookTitle = resolved.title
        } else {
            bookTitle = "PagePilot"
        }

        let quote = QuoteAppEntity(highlight: picked, bookTitle: bookTitle)
        return .result(
            value: quote,
            dialog: localizedIntentDialog("intent_random_quote_dialog", quote.bookTitle, quote.quoteText),
            view: QuoteSnippetView(quote: quote)
        )
    }
}

// MARK: - 6. Export Book Highlights (Markdown)

struct GetBookHighlightsIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource(
        "intent_export_highlights_title",
        defaultValue: "Export Book Highlights"
    )

    static var description = IntentDescription(
        LocalizedStringResource(
            "intent_export_highlights_desc",
            defaultValue: "Export all highlights and notes from a book as Markdown for Notes, Obsidian, or Notion."
        ),
        categoryName: LocalizedStringResource("intent_category_stats", defaultValue: "Reading Journal")
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: LocalizedStringResource("intent_param_book_optional", defaultValue: "Book"))
    var book: BookAppEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Export highlights as Markdown") {
            \.$book
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let store = PagePilotIntentEnvironment.store
        let resolvedBook: Book
        if let book {
            guard let found = try await store.fetchBook(entityID: book.id) else {
                throw PagePilotIntentError.bookNotFound
            }
            resolvedBook = found
        } else {
            let allBooks = try await store.fetchAllBooks()
            guard let current = ContinueReadingSelector.select(
                from: allBooks,
                lastReadIds: store.lastReadBookIds()
            ) ?? allBooks.last else {
                throw PagePilotIntentError.noBooksAvailable
            }
            resolvedBook = current
        }

        guard let bookId = resolvedBook.id else {
            throw PagePilotIntentError.bookNotFound
        }

        let highlights = try await store.fetchHighlights(bookId: bookId)
            .filter { !($0.locator.text.highlight ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !highlights.isEmpty else {
            throw PagePilotIntentError.noHighlightsAvailable
        }

        let markdown = BookHighlightsMarkdownFormatter.format(book: resolvedBook, highlights: highlights)
        return .result(
            value: markdown,
            dialog: localizedIntentDialog("intent_export_highlights_dialog", Int64(highlights.count), resolvedBook.title)
        )
    }
}

// MARK: - 7. Set Daily Reading Goal

struct SetDailyReadingGoalIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource(
        "intent_set_goal_title",
        defaultValue: "Set Daily Reading Goal"
    )

    static var description = IntentDescription(
        LocalizedStringResource(
            "intent_set_goal_desc",
            defaultValue: "Change your daily reading goal in minutes (5 to 180 minutes)."
        ),
        categoryName: LocalizedStringResource("intent_category_settings", defaultValue: "Preferences")
    )

    static var openAppWhenRun: Bool = false

    @Parameter(
        title: LocalizedStringResource("intent_param_goal_minutes", defaultValue: "Minutes"),
        default: 30,
        inclusiveRange: (5, 180)
    )
    var minutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Set daily reading goal to \(\.$minutes) minutes")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let applied = PagePilotIntentEnvironment.store.setDailyGoalMinutes(minutes)
        return .result(
            value: applied,
            dialog: localizedIntentDialog("intent_set_goal_dialog", Int64(applied))
        )
    }
}

// MARK: - 8. Switch Reading Paper Theme

struct SetReadingPaperPresetIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource(
        "intent_set_paper_preset_title",
        defaultValue: "Set Reading Paper Theme"
    )

    static var description = IntentDescription(
        LocalizedStringResource(
            "intent_set_paper_preset_desc",
            defaultValue: "Switch PagePilot's reading paper preset — ideal for Bedtime or Morning Focus automations."
        ),
        categoryName: LocalizedStringResource("intent_category_settings", defaultValue: "Preferences")
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: LocalizedStringResource("intent_param_paper_preset", defaultValue: "Paper Theme"))
    var preset: PaperPresetAppOption

    static var parameterSummary: some ParameterSummary {
        Summary("Set paper theme to \(\.$preset)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let targetPreset = preset.readerPaperPreset
        try await PagePilotIntentEnvironment.store.applyPaperPreset(targetPreset)
        return .result(
            dialog: localizedIntentDialog("intent_set_paper_preset_dialog", targetPreset.localizedTitle)
        )
    }
}

// MARK: - 9. Open Reading Journal

struct OpenJournalIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource(
        "intent_open_journal_title",
        defaultValue: "Open Reading Journal"
    )

    static var description = IntentDescription(
        LocalizedStringResource(
            "intent_open_journal_desc",
            defaultValue: "Jump straight to your PagePilot reading rhythm and saved quotes."
        ),
        categoryName: LocalizedStringResource("intent_category_stats", defaultValue: "Reading Journal")
    )

    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await PagePilotIntentEnvironment.store.openJournal()
        return .result(
            dialog: localizedIntentDialog("intent_open_journal_dialog")
        )
    }
}

// MARK: - 10. Import Book File

struct ImportBookFileIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource(
        "intent_import_book_title",
        defaultValue: "Import Book"
    )

    static var description = IntentDescription(
        LocalizedStringResource(
            "intent_import_book_desc",
            defaultValue: "Import an EPUB, PDF, TXT, or Markdown file directly into your PagePilot bookshelf."
        ),
        categoryName: LocalizedStringResource("intent_category_reading", defaultValue: "Reading")
    )

    static var openAppWhenRun: Bool = false

    @Parameter(
        title: LocalizedStringResource("intent_param_book_file", defaultValue: "Book File"),
        supportedTypeIdentifiers: [
            "org.idpf.epub-container",
            "com.adobe.pdf",
            "public.plain-text",
        ]
    )
    var file: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Import \(\.$file) to PagePilot")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<BookAppEntity> & ProvidesDialog {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PagePilotIntentImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let filename = file.filename.isEmpty ? "ImportedBook.epub" : file.filename
        let safeFilename = (filename as NSString).lastPathComponent
        let stagedURL = tempDir.appendingPathComponent(safeFilename)

        if let sourceURL = file.fileURL {
            let accessed = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessed { sourceURL.stopAccessingSecurityScopedResource() }
            }
            try FileManager.default.copyItem(at: sourceURL, to: stagedURL)
        } else {
            try file.data.write(to: stagedURL, options: .atomic)
        }

        let imported = try await PagePilotIntentEnvironment.store.importBook(from: stagedURL)
        let entity = BookAppEntity(book: imported)
        return .result(
            value: entity,
            dialog: localizedIntentDialog("intent_import_book_dialog", imported.title)
        )
    }
}

private func localizedIntentDialog(_ key: String, _ arguments: CVarArg...) -> IntentDialog {
    let format = NSLocalizedString(key, comment: "")
    let text = arguments.isEmpty ? format : String(format: format, arguments: arguments)
    return IntentDialog(stringLiteral: text)
}

// MARK: - App Shortcuts Provider (Siri, Spotlight, Action Button, Shortcuts Gallery)

struct PagePilotShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .navy

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ContinueReadingIntent(),
            phrases: [
                "Continue reading in \(.applicationName)",
                "Resume reading in \(.applicationName)",
                "Open my current book in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("intent_continue_reading_title", defaultValue: "Continue Reading"),
            systemImageName: "book.pages"
        )

        AppShortcut(
            intent: StartMicroReadingIntent(),
            phrases: [
                "Start \(\.$duration) reading in \(.applicationName)",
                "Quick read in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("intent_micro_reading_title", defaultValue: "Quick Read"),
            systemImageName: "timer"
        )

        AppShortcut(
            intent: OpenBookIntent(),
            phrases: [
                "Open \(\.$book) in \(.applicationName)",
                "Read \(\.$book) in \(.applicationName)",
                "Open a book in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("intent_open_book_title", defaultValue: "Open Book"),
            systemImageName: "books.vertical"
        )

        AppShortcut(
            intent: GetReadingProgressIntent(),
            phrases: [
                "Check reading progress in \(.applicationName)",
                "How much did I read today in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("intent_reading_progress_short", defaultValue: "Today's Reading"),
            systemImageName: "chart.bar.doc.horizontal"
        )

        AppShortcut(
            intent: GetRandomQuoteIntent(),
            phrases: [
                "Show a random quote in \(.applicationName)",
                "Review a reading highlight in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource("intent_random_quote_short", defaultValue: "Random Quote"),
            systemImageName: "text.quote"
        )
    }
}

// MARK: - Rich Siri & Shortcuts Snippet Views

private struct ReadingProgressSnippetView: View {
    let status: ReadingStatusAppEntity

    private var progressFraction: Double {
        guard status.dailyGoalMinutes > 0 else { return 0 }
        return min(1.0, Double(status.todayMinutes) / Double(status.dailyGoalMinutes))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.12), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: progressFraction)
                        .stroke(
                            status.goalReached ? Color.teal : Color.indigo,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Image(systemName: status.goalReached ? "checkmark" : "book.pages")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(status.goalReached ? Color.teal : Color.indigo)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(status.todayMinutes) / \(status.dailyGoalMinutes) \(NSLocalizedString("stats_minutes_unit", comment: ""))")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(
                        String(
                            format: NSLocalizedString("intent_snippet_streak_format", comment: ""),
                            status.streakDays
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)
            }

            if let bookTitle = status.currentBookTitle, !bookTitle.isEmpty {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "book.closed.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(bookTitle)
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(status.currentBookProgressPercent)%")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
    }
}

private struct QuoteSnippetView: View {
    let quote: QuoteAppEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "quote.opening")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.indigo)
                Text(quote.bookTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(quote.quoteText)
                .font(.system(size: 15, weight: .regular, design: .serif))
                .foregroundStyle(.primary)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)

            if let note = quote.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }
}
