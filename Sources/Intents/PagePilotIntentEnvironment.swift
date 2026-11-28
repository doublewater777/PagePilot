//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import AppIntents
import Foundation
import ReadiumNavigator
import ReadiumShared
import UIKit

// MARK: - Intent Errors

enum PagePilotIntentError: Error, CustomLocalizedStringResourceConvertible, Equatable {
    case appUnavailable
    case noBooksAvailable
    case bookNotFound
    case noHighlightsAvailable
    case bookLimitReached
    case importFailed(String)
    case openFailed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .appUnavailable:
            return LocalizedStringResource(stringLiteral: NSLocalizedString("intent_error_app_unavailable", comment: ""))
        case .noBooksAvailable:
            return LocalizedStringResource(stringLiteral: NSLocalizedString("intent_error_no_books", comment: ""))
        case .bookNotFound:
            return LocalizedStringResource(stringLiteral: NSLocalizedString("intent_error_book_not_found", comment: ""))
        case .noHighlightsAvailable:
            return LocalizedStringResource(stringLiteral: NSLocalizedString("intent_error_no_highlights", comment: ""))
        case .bookLimitReached:
            return LocalizedStringResource(stringLiteral: NSLocalizedString("intent_error_book_limit", comment: ""))
        case let .importFailed(reason):
            let formatted = String(
                format: NSLocalizedString("intent_error_import_failed", comment: ""),
                reason
            )
            return LocalizedStringResource(stringLiteral: formatted)
        case let .openFailed(reason):
            let formatted = String(
                format: NSLocalizedString("intent_error_open_failed", comment: ""),
                reason
            )
            return LocalizedStringResource(stringLiteral: formatted)
        }
    }
}

// MARK: - Foreground Navigation Coordinator

/// Coordinates foreground App Intent navigation (`Continue Reading`, `Open Book`,
/// `Start Quick Read`, `Open Journal`) with cold-launch auto-resume so explicit
/// intent requests always preempt "Launch Directly to Reader" and accurately
/// await publication open results.
@MainActor
final class AppIntentNavigationCoordinator {
    enum Destination: Equatable {
        case openBook(bookId: Book.Id, microReadingMinutes: Int?)
        case openJournal
    }

    static let shared = AppIntentNavigationCoordinator()

    private(set) var pendingDestination: Destination?
    private(set) var hasClaimedExplicitNavigation = false
    private var pendingContinuation: CheckedContinuation<Void, Error>?
    private var pendingTimeoutTask: Task<Void, Never>?
    private var autoResumeTask: Task<Void, Never>?

    var hasPendingDestination: Bool {
        pendingDestination != nil
    }

    /// Cancels any scheduled cold-launch "Launch Directly to Reader" task and marks
    /// that an explicit navigation (App Intent or incoming URL) owns this launch.
    func cancelAutoResume() {
        hasClaimedExplicitNavigation = true
        autoResumeTask?.cancel()
        autoResumeTask = nil
    }

    /// Schedules cold-launch auto-resume unless an explicit navigation already claimed launch.
    /// Re-checks cancellation both after `delaySeconds` and right before opening via `shouldStillOpen`.
    func scheduleAutoResumeIfUnclaimed(
        delaySeconds: Double = 0.18,
        action: @escaping @MainActor (_ shouldStillOpen: @escaping @MainActor () -> Bool) async -> Void
    ) {
        guard !hasClaimedExplicitNavigation, pendingDestination == nil else {
            return
        }
        autoResumeTask?.cancel()
        autoResumeTask = Task { @MainActor [weak self] in
            if delaySeconds > 0 {
                let nanos = UInt64(delaySeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
            }
            guard let self,
                  !Task.isCancelled,
                  !self.hasClaimedExplicitNavigation,
                  self.pendingDestination == nil
            else {
                return
            }
            let shouldStillOpen: @MainActor () -> Bool = { [weak self] in
                guard let self else { return false }
                return !Task.isCancelled
                    && !self.hasClaimedExplicitNavigation
                    && self.pendingDestination == nil
            }
            await action(shouldStillOpen)
        }
    }

    /// Enqueues or immediately executes a fire-and-forget navigation destination (e.g. Open Journal).
    func request(_ destination: Destination) {
        cancelAutoResume()
        replacePending(with: nil, resumingPreviousWith: .success(()))

        if isUIReady {
            Task { @MainActor in
                try? await self.execute(destination)
            }
        } else {
            pendingDestination = destination
        }
    }

    /// Opens a book for an App Intent, validating file availability immediately and awaiting
    /// reader presentation (including across cold launch when the scene connects shortly after).
    func requestOpenBook(
        _ book: Book,
        microReadingMinutes: Int?,
        coldLaunchTimeoutSeconds: Double = 10
    ) async throws {
        guard let bookId = book.id else {
            throw PagePilotIntentError.bookNotFound
        }
        do {
            try book.requireAvailablePublicationFile()
        } catch {
            throw PagePilotIntentError.openFailed(UserError(error).message)
        }

        cancelAutoResume()
        let destination = Destination.openBook(bookId: bookId, microReadingMinutes: microReadingMinutes)

        if isUIReady {
            replacePending(with: nil, resumingPreviousWith: .success(()))
            try await execute(destination)
            return
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            replacePending(with: destination, continuation: continuation)
            pendingTimeoutTask = Task { @MainActor [weak self] in
                let nanos = UInt64(max(0.1, coldLaunchTimeoutSeconds) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                guard let self, !Task.isCancelled else { return }
                self.replacePending(with: nil, resumingPreviousWith: .failure(PagePilotIntentError.appUnavailable))
            }
        }
    }

    /// Called by `SceneDelegate.scene(_:willConnectTo:options:)` once the root window
    /// and tab bar controller are wired up.
    @discardableResult
    func consumePendingIfReady() -> Bool {
        guard isUIReady, let destination = pendingDestination else {
            return false
        }
        let continuation = pendingContinuation
        pendingDestination = nil
        pendingContinuation = nil
        pendingTimeoutTask?.cancel()
        pendingTimeoutTask = nil

        Task { @MainActor in
            do {
                try await self.execute(destination)
                continuation?.resume(returning: ())
            } catch {
                continuation?.resume(throwing: error)
            }
        }
        return true
    }

    func reset() {
        autoResumeTask?.cancel()
        autoResumeTask = nil
        hasClaimedExplicitNavigation = false
        replacePending(with: nil, resumingPreviousWith: .failure(PagePilotIntentError.appUnavailable))
    }

    private var isUIReady: Bool {
        guard let app = AppModule.shared, let tabBar = app.tabBarController else {
            return false
        }
        return tabBar.viewIfLoaded?.window != nil
    }

    private func replacePending(
        with newDestination: Destination?,
        continuation newContinuation: CheckedContinuation<Void, Error>? = nil,
        resumingPreviousWith result: Result<Void, Error> = .success(())
    ) {
        let oldContinuation = pendingContinuation
        pendingTimeoutTask?.cancel()
        pendingTimeoutTask = nil
        pendingDestination = newDestination
        pendingContinuation = newContinuation
        if let oldContinuation {
            oldContinuation.resume(with: result)
        }
    }

    private func execute(_ destination: Destination) async throws {
        guard let app = AppModule.shared else {
            throw PagePilotIntentError.appUnavailable
        }
        await dismissPresentedModalsIfNeeded(from: app.tabBarController)

        switch destination {
        case let .openBook(bookId, microReadingMinutes):
            guard let book = try? await app.books.get(bookId) else {
                throw PagePilotIntentError.bookNotFound
            }
            do {
                try await app.openBookAndAwait(book, microReadingMinutes: microReadingMinutes)
            } catch let error as PagePilotIntentError {
                throw error
            } catch {
                throw PagePilotIntentError.openFailed(UserError(error).message)
            }

        case .openJournal:
            app.tabBarController?.selectedIndex = 1
            PostHogAnalytics.shared.screen("journal")
            #if targetEnvironment(macCatalyst)
            if let scene = app.tabBarController?.viewIfLoaded?.window?.windowScene {
                UIApplication.shared.requestSceneSessionActivation(scene.session, userActivity: nil, options: nil)
            }
            #endif
        }
    }

    private func dismissPresentedModalsIfNeeded(from root: UIViewController?) async {
        guard let root, root.presentedViewController != nil else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            root.dismiss(animated: false) {
                continuation.resume()
            }
        }
    }
}

// MARK: - Testable Intent Store Abstraction

protocol PagePilotIntentStore: Sendable {
    func fetchAllBooks() async throws -> [Book]
    func fetchBook(entityID: String) async throws -> Book?
    func fetchBook(id: Book.Id) async throws -> Book?
    func lastReadBookIds() -> [Int64]
    func fetchHighlights(bookId: Book.Id?) async throws -> [Highlight]
    func todayReadingSeconds() -> Int
    func currentStreakDays() -> Int
    func dailyGoalMinutes() -> Int
    @discardableResult
    func setDailyGoalMinutes(_ minutes: Int) -> Int
    func applyPaperPreset(_ preset: ReaderPaperPreset) async throws
    func importBook(from fileURL: URL) async throws -> Book
    func openBook(_ book: Book, microReadingMinutes: Int?) async throws
    func openJournal() async
}

enum PagePilotIntentEnvironment {
    static var store: any PagePilotIntentStore = LivePagePilotIntentStore()
}

struct LivePagePilotIntentStore: PagePilotIntentStore {
    private func resolveAppModule() throws -> AppModule {
        guard let app = AppModule.shared else {
            throw PagePilotIntentError.appUnavailable
        }
        return app
    }

    func fetchAllBooks() async throws -> [Book] {
        try await resolveAppModule().books.allOnce()
    }

    func fetchBook(entityID: String) async throws -> Book? {
        let books = try resolveAppModule().books
        if let localId = BookAppEntity.localRowID(from: entityID) {
            return try await books.get(localId)
        }
        return try await books.get(syncID: entityID)
    }

    func fetchBook(id: Book.Id) async throws -> Book? {
        try await resolveAppModule().books.get(id)
    }

    func lastReadBookIds() -> [Int64] {
        LastReadBooks.orderedIds
    }

    func fetchHighlights(bookId: Book.Id?) async throws -> [Highlight] {
        try await resolveAppModule().highlightRepository.allOnce(for: bookId)
    }

    func todayReadingSeconds() -> Int {
        ReadingStatsStore.shared.todayReadingSeconds()
    }

    func currentStreakDays() -> Int {
        ReadingStatsStore.shared.snapshot(for: .summary).currentStreakDays
    }

    func dailyGoalMinutes() -> Int {
        ReadingPreferences.dailyGoalMinutes
    }

    @discardableResult
    func setDailyGoalMinutes(_ minutes: Int) -> Int {
        ReadingPreferences.dailyGoalMinutes = minutes
        return ReadingPreferences.dailyGoalMinutes
    }

    func applyPaperPreset(_ preset: ReaderPaperPreset) async throws {
        let store = UserDefaultsUserPreferencesStore<EPUBPreferences>()
        let placeholderBookId = Book.Id(rawValue: 0)
        var sharedPreferences = try await store.preferences(for: placeholderBookId)
        preset.apply(to: &sharedPreferences)
        try await store.savePreferences(sharedPreferences.filterSharedPreferences(), of: placeholderBookId)
    }

    func importBook(from fileURL: URL) async throws -> Book {
        let app = try resolveAppModule()
        guard let absoluteURL = fileURL.anyURL.absoluteURL else {
            throw PagePilotIntentError.importFailed(fileURL.lastPathComponent)
        }
        do {
            return try await app.library.service.importPublication(from: absoluteURL, sender: nil)
        } catch LibraryError.bookLimitReached {
            throw PagePilotIntentError.bookLimitReached
        } catch {
            throw PagePilotIntentError.importFailed(UserError(error).message)
        }
    }

    func openBook(_ book: Book, microReadingMinutes: Int?) async throws {
        try await AppIntentNavigationCoordinator.shared.requestOpenBook(
            book,
            microReadingMinutes: microReadingMinutes
        )
    }

    func openJournal() async {
        await MainActor.run {
            AppIntentNavigationCoordinator.shared.request(.openJournal)
        }
    }
}

// MARK: - Formatting & Ordering Helpers

enum BookHighlightsMarkdownFormatter {
    static func format(book: Book, highlights: [Highlight]) -> String {
        var lines: [String] = []
        lines.append("# \(book.title)")
        if let authors = book.authors?.trimmingCharacters(in: .whitespacesAndNewlines), !authors.isEmpty {
            lines.append("_\(authors)_")
        }
        lines.append("")

        for highlight in highlights {
            let quote = (highlight.locator.text.highlight ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !quote.isEmpty else { continue }

            if let chapter = highlight.locator.title?.trimmingCharacters(in: .whitespacesAndNewlines), !chapter.isEmpty {
                lines.append("## \(chapter)")
            }
            lines.append("> \(quote.replacingOccurrences(of: "\n", with: "\n> "))")
            if let note = highlight.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                lines.append("")
                lines.append(note)
            }
            lines.append("")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum BookEntityOrdering {
    /// Places recently read books first (matching MRU order), then remaining books newest-first.
    static func sortForSuggestions(books: [Book], lastReadIds: [Int64]) -> [Book] {
        var rankById: [Int64: Int] = [:]
        for (index, rawId) in lastReadIds.enumerated() where rankById[rawId] == nil {
            rankById[rawId] = index
        }

        return books.sorted { lhs, rhs in
            let leftRank = lhs.id.flatMap { rankById[$0.rawValue] }
            let rightRank = rhs.id.flatMap { rankById[$0.rawValue] }
            switch (leftRank, rightRank) {
            case let (l?, r?):
                return l < r
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.created > rhs.created
            }
        }
    }

    static func matches(book: Book, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if book.title.localizedStandardContains(trimmed) {
            return true
        }
        if let authors = book.authors, authors.localizedStandardContains(trimmed) {
            return true
        }
        return false
    }
}
