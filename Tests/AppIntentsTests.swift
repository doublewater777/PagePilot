//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import AppIntents
import Foundation
import ReadiumShared
import UniformTypeIdentifiers
import XCTest
@testable import PagePilot

final class AppIntentsTests: XCTestCase {
    private var previousStore: (any PagePilotIntentStore)!
    private var mockStore: MockPagePilotIntentStore!

    override func setUp() async throws {
        try await super.setUp()
        previousStore = PagePilotIntentEnvironment.store
        mockStore = MockPagePilotIntentStore()
        PagePilotIntentEnvironment.store = mockStore
        await MainActor.run {
            AppIntentNavigationCoordinator.shared.reset()
        }
    }

    override func tearDown() async throws {
        PagePilotIntentEnvironment.store = previousStore
        await MainActor.run {
            AppIntentNavigationCoordinator.shared.reset()
        }
        try await super.tearDown()
    }

    // MARK: - Entity Query, Stable syncID & Full Library Ordering

    func testBookEntityOrderingPutsMostRecentlyReadFirstAndUsesSyncID() async throws {
        let b1 = makeBook(id: 1, title: "Alpha", authors: "Alice", progression: 0.10, createdOffset: -300, syncID: "sync-alpha")
        let b2 = makeBook(id: 2, title: "Beta", authors: "Bob", progression: 0.55, createdOffset: -200, syncID: "sync-beta")
        let b3 = makeBook(id: 3, title: "Gamma", authors: "Clara", progression: 0.0, createdOffset: -100, syncID: "sync-gamma")
        mockStore.books = [b1, b2, b3]
        mockStore.lastReadIds = [2, 1]

        let query = BookAppEntityQuery()
        let suggestions = try await query.suggestedEntities()
        XCTAssertEqual(suggestions.map(\.id), ["sync-beta", "sync-alpha", "sync-gamma"])
        XCTAssertEqual(suggestions[0].progressPercent, 55)
        XCTAssertEqual(suggestions[0].format, "EPUB")
    }

    func testSuggestedEntitiesCoversLibraryBeyond25Books() async throws {
        mockStore.books = (1...32).map { index in
            makeBook(
                id: Int64(index),
                title: "Book \(index)",
                createdOffset: TimeInterval(index),
                syncID: "sync-book-\(index)"
            )
        }
        let suggestions = try await BookAppEntityQuery().suggestedEntities()
        XCTAssertEqual(suggestions.count, 32)
        XCTAssertTrue(suggestions.contains(where: { $0.id == "sync-book-1" }))
        XCTAssertTrue(suggestions.contains(where: { $0.id == "sync-book-32" }))
    }

    func testCrossDeviceShortcutResolvesBookBySyncIDNotLocalRowID() async throws {
        // Device A (iPhone): Alpha has SQLite rowid 1, syncID "sync-alpha".
        let alphaOnPhone = makeBook(id: 1, title: "Alpha", authors: "Alice", syncID: "sync-alpha")
        let syncedShortcutEntity = BookAppEntity(book: alphaOnPhone, loadCoverThumbnail: false)

        // Device B (iPad/Mac): rowid 1 belongs to Beta; Alpha was imported later as rowid 9.
        let betaOnIPad = makeBook(id: 1, title: "Beta", authors: "Bob", syncID: "sync-beta")
        let alphaOnIPad = makeBook(id: 9, title: "Alpha", authors: "Alice", syncID: "sync-alpha")
        mockStore.books = [betaOnIPad, alphaOnIPad]
        mockStore.highlights = [
            makeHighlight(id: 1, bookId: Book.Id(rawValue: 1), quote: "Beta quote", chapter: nil, note: nil, syncID: "hl-beta"),
            makeHighlight(id: 2, bookId: Book.Id(rawValue: 9), quote: "Alpha quote", chapter: "Ch 1", note: nil, syncID: "hl-alpha"),
        ]

        // Opening via synced entity must open Alpha (rowid 9), never Beta (rowid 1).
        let openIntent = OpenBookIntent()
        openIntent.book = syncedShortcutEntity
        let openResult = try await openIntent.perform()
        XCTAssertEqual(openResult.value?.id, "sync-alpha")
        XCTAssertEqual(mockStore.openedBookId, Book.Id(rawValue: 9))

        // Exporting highlights via synced entity must export Alpha's highlights, never Beta's.
        let exportIntent = GetBookHighlightsIntent()
        exportIntent.book = syncedShortcutEntity
        let exportResult = try await exportIntent.perform()
        let markdown = try XCTUnwrap(exportResult.value)
        XCTAssertTrue(markdown.contains("# Alpha"))
        XCTAssertTrue(markdown.contains("Alpha quote"))
        XCTAssertFalse(markdown.contains("Beta quote"))
    }

    func testBookEntityStringSearchMatchesTitleAndAuthor() async throws {
        let b1 = makeBook(id: 10, title: "The Three-Body Problem", authors: "Liu Cixin", progression: 0.4, syncID: "sync-3body")
        let b2 = makeBook(id: 11, title: "Dune", authors: "Frank Herbert", progression: 0.7, syncID: "sync-dune")
        mockStore.books = [b1, b2]

        let query = BookAppEntityQuery()
        let byAuthor = try await query.entities(matching: "herbert")
        XCTAssertEqual(byAuthor.map(\.title), ["Dune"])

        let byTitle = try await query.entities(matching: "three-body")
        XCTAssertEqual(byTitle.map(\.title), ["The Three-Body Problem"])

        let byId = try await query.entities(for: ["sync-dune", "sync-missing"])
        XCTAssertEqual(byId.map(\.id), ["sync-dune"])
    }

    // MARK: - Foreground Reading Intents & Error Propagation

    func testContinueReadingOpensMostRecentBook() async throws {
        let b1 = makeBook(id: 1, title: "First Book", progression: 0.25, syncID: "sync-1")
        let b2 = makeBook(id: 2, title: "Latest Book", progression: 0.62, syncID: "sync-2")
        mockStore.books = [b1, b2]
        mockStore.lastReadIds = [2]

        let intent = ContinueReadingIntent()
        let result = try await intent.perform()
        XCTAssertEqual(result.value?.id, "sync-2")
        XCTAssertEqual(mockStore.openedBookId, Book.Id(rawValue: 2))
        XCTAssertNil(mockStore.openedMicroMinutes)
    }

    func testContinueReadingThrowsWhenLibraryIsEmpty() async {
        mockStore.books = []
        let intent = ContinueReadingIntent()
        do {
            _ = try await intent.perform()
            XCTFail("Expected noBooksAvailable error")
        } catch let error as PagePilotIntentError {
            XCTAssertEqual(error, .noBooksAvailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStartMicroReadingPassesDurationAndOptionalBook() async throws {
        let b1 = makeBook(id: 7, title: "Focused Mind", progression: 0.3, syncID: "sync-7")
        mockStore.books = [b1]

        let intent = StartMicroReadingIntent()
        intent.duration = .tenMinutes
        intent.book = BookAppEntity(book: b1, loadCoverThumbnail: false)
        let result = try await intent.perform()

        XCTAssertEqual(result.value?.id, "sync-7")
        XCTAssertEqual(mockStore.openedBookId, Book.Id(rawValue: 7))
        XCTAssertEqual(mockStore.openedMicroMinutes, 10)
    }

    func testReadingIntentsPropagateOpenFailuresInsteadOfSucceeding() async {
        let b1 = makeBook(id: 7, title: "Missing File Book", progression: 0.3, syncID: "sync-missing-file")
        mockStore.books = [b1]
        mockStore.openBookError = PagePilotIntentError.openFailed("Book file not found")

        let microIntent = StartMicroReadingIntent()
        microIntent.duration = .fiveMinutes
        microIntent.book = BookAppEntity(book: b1, loadCoverThumbnail: false)
        do {
            _ = try await microIntent.perform()
            XCTFail("Expected openFailed error")
        } catch let error as PagePilotIntentError {
            XCTAssertEqual(error, .openFailed("Book file not found"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let openIntent = OpenBookIntent()
        openIntent.book = BookAppEntity(book: b1, loadCoverThumbnail: false)
        do {
            _ = try await openIntent.perform()
            XCTFail("Expected openFailed error")
        } catch let error as PagePilotIntentError {
            XCTAssertEqual(error, .openFailed("Book file not found"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testCoordinatorFailsFastWhenPublicationFileIsMissing() async {
        let missingBook = makeBook(
            id: 99,
            title: "Deleted File",
            urlString: "file:///tmp/definitely-missing-pagepilot-\(UUID().uuidString).epub",
            syncID: "sync-deleted"
        )
        do {
            try await AppIntentNavigationCoordinator.shared.requestOpenBook(
                missingBook,
                microReadingMinutes: 5,
                coldLaunchTimeoutSeconds: 0.2
            )
            XCTFail("Expected openFailed error for missing publication file")
        } catch let error as PagePilotIntentError {
            if case .openFailed = error {
                // Expected
            } else {
                XCTFail("Expected openFailed, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOpenBookIntentThrowsWhenBookMissing() async {
        mockStore.books = []
        let intent = OpenBookIntent()
        intent.book = BookAppEntity(id: "sync-404", title: "Ghost")

        do {
            _ = try await intent.perform()
            XCTFail("Expected bookNotFound error")
        } catch let error as PagePilotIntentError {
            XCTAssertEqual(error, .bookNotFound)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOpenJournalIntentRoutesToJournal() async throws {
        let intent = OpenJournalIntent()
        _ = try await intent.perform()
        XCTAssertTrue(mockStore.didOpenJournal)
    }

    // MARK: - Stats, Quotes, Export & Preferences Intents

    func testGetReadingProgressReportsGoalAndStreak() async throws {
        let b1 = makeBook(id: 5, title: "Deep Work", progression: 0.48, syncID: "sync-5")
        mockStore.books = [b1]
        mockStore.lastReadIds = [5]
        mockStore.todaySecondsValue = 35 * 60
        mockStore.dailyGoalValue = 30
        mockStore.streakDaysValue = 12

        let intent = GetReadingProgressIntent()
        let result = try await intent.perform()
        let status = try XCTUnwrap(result.value)

        XCTAssertEqual(status.todayMinutes, 35)
        XCTAssertEqual(status.dailyGoalMinutes, 30)
        XCTAssertTrue(status.goalReached)
        XCTAssertEqual(status.streakDays, 12)
        XCTAssertEqual(status.currentBookTitle, "Deep Work")
        XCTAssertEqual(status.currentBookProgressPercent, 48)
    }

    func testGetRandomQuoteUsesSyncIDAndThrowsWhenEmpty() async throws {
        let b1 = makeBook(id: 1, title: "Meditations", authors: "Marcus Aurelius", syncID: "sync-meditations")
        mockStore.books = [b1]

        let emptyIntent = GetRandomQuoteIntent()
        do {
            _ = try await emptyIntent.perform()
            XCTFail("Expected noHighlightsAvailable")
        } catch let error as PagePilotIntentError {
            XCTAssertEqual(error, .noHighlightsAvailable)
        }

        mockStore.highlights = [
            makeHighlight(
                id: 100,
                bookId: Book.Id(rawValue: 1),
                quote: "You have power over your mind - not outside events.",
                chapter: "Book IV",
                note: "Stoic reminder",
                syncID: "sync-hl-100"
            )
        ]
        let intent = GetRandomQuoteIntent()
        let result = try await intent.perform()
        let quote = try XCTUnwrap(result.value)
        XCTAssertEqual(quote.id, "sync-hl-100")
        XCTAssertEqual(quote.bookTitle, "Meditations")
        XCTAssertEqual(quote.chapterTitle, "Book IV")
        XCTAssertEqual(quote.note, "Stoic reminder")
        XCTAssertTrue(quote.quoteText.contains("power over your mind"))
    }

    func testExportHighlightsFormatsCleanMarkdown() async throws {
        let b1 = makeBook(id: 3, title: "Atomic Habits", authors: "James Clear", syncID: "sync-atomic")
        mockStore.books = [b1]
        mockStore.highlights = [
            makeHighlight(
                id: 1,
                bookId: Book.Id(rawValue: 3),
                quote: "You do not rise to the level of your goals.",
                chapter: "Chapter 1",
                note: "Build systems.",
                syncID: "sync-hl-1"
            )
        ]

        let intent = GetBookHighlightsIntent()
        intent.book = BookAppEntity(book: b1, loadCoverThumbnail: false)
        let result = try await intent.perform()
        let markdown = try XCTUnwrap(result.value)

        XCTAssertTrue(markdown.contains("# Atomic Habits"))
        XCTAssertTrue(markdown.contains("_James Clear_"))
        XCTAssertTrue(markdown.contains("## Chapter 1"))
        XCTAssertTrue(markdown.contains("> You do not rise to the level of your goals."))
        XCTAssertTrue(markdown.contains("Build systems."))
    }

    func testSetDailyGoalClampsRange() async throws {
        let intent = SetDailyReadingGoalIntent()
        intent.minutes = 240
        let result = try await intent.perform()
        XCTAssertEqual(result.value, 180)
        XCTAssertEqual(mockStore.dailyGoalValue, 180)
    }

    func testSetReadingPaperPresetAppliesPreset() async throws {
        let intent = SetReadingPaperPresetIntent()
        intent.preset = .midnightInk
        _ = try await intent.perform()
        XCTAssertEqual(mockStore.appliedPaperPreset, .midnightInk)
    }

    func testImportBookFileStagesDataAndImportsBook() async throws {
        let expected = makeBook(id: 88, title: "Quick Notes", progression: 0, syncID: "sync-88")
        mockStore.importedBookToReturn = expected

        let intent = ImportBookFileIntent()
        intent.file = IntentFile(
            data: Data("# Hello\nWorld".utf8),
            filename: "QuickNotes.md",
            type: .plainText
        )
        let result = try await intent.perform()

        XCTAssertEqual(result.value?.id, "sync-88")
        XCTAssertEqual(mockStore.importedFileName, "QuickNotes.md")
    }

    // MARK: - Cold-Launch Navigation Coordinator & Auto-Resume Preemption

    func testPendingIntentSuppressesLaunchDirectlyToReader() {
        let shouldAutoOpen = LaunchToReaderPolicy.shouldAutoOpenLastReadBook(
            hasSeenOnboarding: true,
            launchDirectlyEnabled: true,
            hasIncomingURL: false,
            hasDebugTabOverride: false,
            alreadyConsumedThisLaunch: false,
            hasPendingIntent: true
        )
        XCTAssertFalse(shouldAutoOpen)
    }

    @MainActor
    func testExplicitIntentCancelsScheduledAutoResumeOnColdLaunch() async {
        let previousShared = AppModule.shared
        AppModule.shared = nil
        defer { AppModule.shared = previousShared }

        var autoResumeExecuted = false
        AppIntentNavigationCoordinator.shared.scheduleAutoResumeIfUnclaimed(delaySeconds: 0.05) { shouldStillOpen in
            if shouldStillOpen() {
                autoResumeExecuted = true
            }
        }

        // Simulate App Intent perform() arriving after SceneDelegate already scheduled auto-resume.
        AppIntentNavigationCoordinator.shared.request(.openJournal)
        XCTAssertTrue(AppIntentNavigationCoordinator.shared.hasClaimedExplicitNavigation)
        XCTAssertEqual(AppIntentNavigationCoordinator.shared.pendingDestination, .openJournal)

        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertFalse(autoResumeExecuted, "Auto-resume must not preempt an explicit App Intent")
    }

    @MainActor
    func testAutoResumeRechecksCancellationAfterAsyncLookup() async {
        var openedAfterLookup = false
        AppIntentNavigationCoordinator.shared.scheduleAutoResumeIfUnclaimed(delaySeconds: 0.0) { shouldStillOpen in
            // Simulate async DB lookup during which an explicit App Intent arrives.
            try? await Task.sleep(nanoseconds: 40_000_000)
            if shouldStillOpen() {
                openedAfterLookup = true
            }
        }

        try? await Task.sleep(nanoseconds: 10_000_000)
        AppIntentNavigationCoordinator.shared.cancelAutoResume()

        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertFalse(openedAfterLookup, "Auto-resume must re-check cancellation after async book fetch")
    }

    // MARK: - Fixtures

    private func makeBook(
        id: Int64,
        title: String,
        authors: String? = nil,
        progression: Double = 0,
        createdOffset: TimeInterval = 0,
        urlString: String? = nil,
        syncID: String? = nil
    ) -> Book {
        let locator = Locator(
            href: AnyURL(string: "chapter1.xhtml")!,
            mediaType: .xhtml,
            locations: Locator.Locations(totalProgression: progression)
        )
        return Book(
            id: Book.Id(rawValue: id),
            identifier: "urn:test:book:\(id)",
            title: title,
            authors: authors,
            type: MediaType.epub.string,
            url: AnyURL(string: urlString ?? "file:///tmp/book-\(id).epub")!,
            locator: locator,
            created: Date().addingTimeInterval(createdOffset),
            syncID: syncID ?? "sync-book-\(id)"
        )
    }

    private func makeHighlight(
        id: Int64,
        bookId: Book.Id,
        quote: String,
        chapter: String?,
        note: String?,
        syncID: String? = nil
    ) -> Highlight {
        let locator = Locator(
            href: AnyURL(string: "chapter1.xhtml")!,
            mediaType: .xhtml,
            title: chapter,
            locations: Locator.Locations(totalProgression: 0.2),
            text: Locator.Text(highlight: quote)
        )
        return Highlight(
            id: Highlight.Id(rawValue: id),
            bookId: bookId,
            locator: locator,
            color: .yellow,
            note: note,
            syncID: syncID ?? "sync-highlight-\(id)"
        )
    }
}

// MARK: - Mock Store

private final class MockPagePilotIntentStore: PagePilotIntentStore, @unchecked Sendable {
    var books: [Book] = []
    var lastReadIds: [Int64] = []
    var highlights: [Highlight] = []
    var todaySecondsValue: Int = 0
    var streakDaysValue: Int = 0
    var dailyGoalValue: Int = 30
    var appliedPaperPreset: ReaderPaperPreset?
    var openedBookId: Book.Id?
    var openedMicroMinutes: Int?
    var openBookError: Error?
    var didOpenJournal = false
    var importedBookToReturn: Book?
    var importedFileName: String?

    func fetchAllBooks() async throws -> [Book] { books }

    func fetchBook(entityID: String) async throws -> Book? {
        if let localId = BookAppEntity.localRowID(from: entityID) {
            return books.first { $0.id == localId }
        }
        return books.first { $0.syncID == entityID }
    }

    func fetchBook(id: Book.Id) async throws -> Book? {
        books.first { $0.id == id }
    }

    func lastReadBookIds() -> [Int64] { lastReadIds }

    func fetchHighlights(bookId: Book.Id?) async throws -> [Highlight] {
        guard let bookId else { return highlights }
        return highlights.filter { $0.bookId == bookId }
    }

    func todayReadingSeconds() -> Int { todaySecondsValue }

    func currentStreakDays() -> Int { streakDaysValue }

    func dailyGoalMinutes() -> Int { dailyGoalValue }

    @discardableResult
    func setDailyGoalMinutes(_ minutes: Int) -> Int {
        dailyGoalValue = min(max(minutes, ReadingPreferences.dailyGoalRange.lowerBound), ReadingPreferences.dailyGoalRange.upperBound)
        return dailyGoalValue
    }

    func applyPaperPreset(_ preset: ReaderPaperPreset) async throws {
        appliedPaperPreset = preset
    }

    func importBook(from fileURL: URL) async throws -> Book {
        importedFileName = fileURL.lastPathComponent
        guard let book = importedBookToReturn else {
            throw PagePilotIntentError.importFailed("Missing mock")
        }
        return book
    }

    func openBook(_ book: Book, microReadingMinutes: Int?) async throws {
        if let openBookError {
            throw openBookError
        }
        openedBookId = book.id
        openedMicroMinutes = microReadingMinutes
    }

    func openJournal() async {
        didOpenJournal = true
    }
}
