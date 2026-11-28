//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import AppIntents
import Foundation
import ImageIO
import ReadiumShared
import UIKit

// MARK: - Book AppEntity

struct BookAppEntity: AppEntity, Hashable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("intent_entity_book_name", defaultValue: "Book")
    )

    static var defaultQuery = BookAppEntityQuery()

    private static let localIDPrefix = "local:"
    /// Cap cover thumbnail decoding during bulk suggestion indexing so large libraries
    /// stay memory-light while still exposing every book title to Siri.
    fileprivate static let coverThumbnailSuggestionLimit = 25

    let id: String

    @Property(title: LocalizedStringResource("intent_prop_book_title", defaultValue: "Title"))
    var title: String

    @Property(title: LocalizedStringResource("intent_prop_book_authors", defaultValue: "Authors"))
    var authors: String?

    @Property(title: LocalizedStringResource("intent_prop_book_progress", defaultValue: "Progress (%)"))
    var progressPercent: Int

    @Property(title: LocalizedStringResource("intent_prop_book_format", defaultValue: "Format"))
    var format: String

    let coverThumbnailData: Data?

    /// Returns a cross-device stable identifier (`syncID`) whenever available so iCloud-synced
    /// Shortcuts always target the same book across iPhone, iPad, and Mac regardless of local
    /// SQLite rowid order. Falls back to `local:<rowid>` only for unmigrated rows with empty `syncID`.
    static func entityIdentifier(for book: Book) -> String {
        if !book.syncID.isEmpty {
            return book.syncID
        }
        if let localId = book.id {
            return "\(localIDPrefix)\(localId.rawValue)"
        }
        return book.identifier ?? book.title
    }

    static func localRowID(from entityID: String) -> Book.Id? {
        guard entityID.hasPrefix(localIDPrefix) else { return nil }
        let suffix = String(entityID.dropFirst(localIDPrefix.count))
        return Int64(suffix).map(Book.Id.init(rawValue:))
    }

    init(book: Book, loadCoverThumbnail: Bool = true) {
        self.id = Self.entityIdentifier(for: book)
        self.coverThumbnailData = loadCoverThumbnail ? Self.makeCoverThumbnailData(for: book) : nil
        self.title = book.title
        self.authors = book.authors?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.progressPercent = max(0, min(100, Int((book.progression * 100).rounded())))
        self.format = Self.formatLabel(for: book.mediaType)
    }

    init(
        id: String,
        title: String,
        authors: String? = nil,
        progressPercent: Int = 0,
        format: String = "EPUB",
        coverThumbnailData: Data? = nil
    ) {
        self.id = id
        self.coverThumbnailData = coverThumbnailData
        self.title = title
        self.authors = authors
        self.progressPercent = progressPercent
        self.format = format
    }

    var displayRepresentation: DisplayRepresentation {
        let subtitleText: String
        if let authors, !authors.isEmpty {
            subtitleText = "\(authors) · \(progressPercent)%"
        } else {
            subtitleText = "\(progressPercent)%"
        }

        let image: DisplayRepresentation.Image
        if let coverThumbnailData {
            image = DisplayRepresentation.Image(data: coverThumbnailData)
        } else {
            image = DisplayRepresentation.Image(systemName: "book.closed.fill")
        }

        return DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(subtitleText)",
            image: image
        )
    }

    static func == (lhs: BookAppEntity, rhs: BookAppEntity) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    private static func formatLabel(for mediaType: MediaType) -> String {
        if mediaType.matches(.epub) { return "EPUB" }
        if mediaType.matches(.pdf) { return "PDF" }
        if mediaType.matches(.cbz) { return "CBZ" }
        if mediaType.matches(.readiumAudiobook) || mediaType.matches(.lcpProtectedAudiobook) {
            return "Audiobook"
        }
        return mediaType.string.uppercased()
    }

    private static func makeCoverThumbnailData(for book: Book) -> Data? {
        guard let coverURL = book.cover?.url,
              FileManager.default.fileExists(atPath: coverURL.path),
              let source = CGImageSourceCreateWithURL(coverURL as CFURL, nil)
        else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 180,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.78)
    }
}

struct BookAppEntityQuery: EntityStringQuery {
    func entities(for identifiers: [BookAppEntity.ID]) async throws -> [BookAppEntity] {
        let store = PagePilotIntentEnvironment.store
        let allBooks = try await store.fetchAllBooks()
        let idSet = Set(identifiers)
        var byEntityId: [String: Book] = [:]
        for book in allBooks {
            let key = BookAppEntity.entityIdentifier(for: book)
            if idSet.contains(key), byEntityId[key] == nil {
                byEntityId[key] = book
            }
        }
        return identifiers.compactMap { id in
            byEntityId[id].map { BookAppEntity(book: $0) }
        }
    }

    func entities(matching string: String) async throws -> [BookAppEntity] {
        let store = PagePilotIntentEnvironment.store
        let allBooks = try await store.fetchAllBooks()
        let ordered = BookEntityOrdering.sortForSuggestions(
            books: allBooks,
            lastReadIds: store.lastReadBookIds()
        )
        return ordered
            .filter { BookEntityOrdering.matches(book: $0, query: string) }
            .enumerated()
            .map { index, book in
                BookAppEntity(
                    book: book,
                    loadCoverThumbnail: index < BookAppEntity.coverThumbnailSuggestionLimit
                )
            }
    }

    func suggestedEntities() async throws -> [BookAppEntity] {
        let store = PagePilotIntentEnvironment.store
        let allBooks = try await store.fetchAllBooks()
        let ordered = BookEntityOrdering.sortForSuggestions(
            books: allBooks,
            lastReadIds: store.lastReadBookIds()
        )
        return ordered.enumerated().map { index, book in
            BookAppEntity(
                book: book,
                loadCoverThumbnail: index < BookAppEntity.coverThumbnailSuggestionLimit
            )
        }
    }
}

// MARK: - Quote AppEntity

struct QuoteAppEntity: AppEntity, Hashable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("intent_entity_quote_name", defaultValue: "Reading Quote")
    )

    static var defaultQuery = QuoteAppEntityQuery()

    private static let localIDPrefix = "local:"

    let id: String

    @Property(title: LocalizedStringResource("intent_prop_quote_text", defaultValue: "Quote"))
    var quoteText: String

    @Property(title: LocalizedStringResource("intent_prop_quote_note", defaultValue: "Note"))
    var note: String?

    @Property(title: LocalizedStringResource("intent_prop_quote_book", defaultValue: "Book Title"))
    var bookTitle: String

    @Property(title: LocalizedStringResource("intent_prop_quote_chapter", defaultValue: "Chapter"))
    var chapterTitle: String?

    @Property(title: LocalizedStringResource("intent_prop_quote_date", defaultValue: "Saved Date"))
    var createdAt: Date

    static func entityIdentifier(for highlight: Highlight) -> String {
        if !highlight.syncID.isEmpty {
            return highlight.syncID
        }
        if let localId = highlight.id {
            return "\(localIDPrefix)\(localId.rawValue)"
        }
        return UUID().uuidString
    }

    init(highlight: Highlight, bookTitle: String) {
        self.id = Self.entityIdentifier(for: highlight)
        self.quoteText = (highlight.locator.text.highlight ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.note = highlight.note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.bookTitle = bookTitle
        self.chapterTitle = highlight.locator.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.createdAt = highlight.created
    }

    var displayRepresentation: DisplayRepresentation {
        let preview = quoteText.count > 80 ? String(quoteText.prefix(79)) + "…" : quoteText
        return DisplayRepresentation(
            title: "\(preview)",
            subtitle: "\(bookTitle)",
            image: DisplayRepresentation.Image(systemName: "text.quote")
        )
    }

    static func == (lhs: QuoteAppEntity, rhs: QuoteAppEntity) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct QuoteAppEntityQuery: EntityQuery {
    func entities(for identifiers: [QuoteAppEntity.ID]) async throws -> [QuoteAppEntity] {
        let store = PagePilotIntentEnvironment.store
        let books = try await store.fetchAllBooks()
        let bookTitles = Dictionary(uniqueKeysWithValues: books.compactMap { book -> (Book.Id, String)? in
            guard let id = book.id else { return nil }
            return (id, book.title)
        })
        let highlights = try await store.fetchHighlights(bookId: nil)
        let idSet = Set(identifiers)
        var byEntityId: [String: Highlight] = [:]
        for highlight in highlights {
            let key = QuoteAppEntity.entityIdentifier(for: highlight)
            if idSet.contains(key), byEntityId[key] == nil {
                byEntityId[key] = highlight
            }
        }
        return identifiers.compactMap { id in
            guard let highlight = byEntityId[id] else { return nil }
            return QuoteAppEntity(highlight: highlight, bookTitle: bookTitles[highlight.bookId] ?? "")
        }
    }

    func suggestedEntities() async throws -> [QuoteAppEntity] {
        let store = PagePilotIntentEnvironment.store
        let books = try await store.fetchAllBooks()
        let bookTitles = Dictionary(uniqueKeysWithValues: books.compactMap { book -> (Book.Id, String)? in
            guard let id = book.id else { return nil }
            return (id, book.title)
        })
        let highlights = try await store.fetchHighlights(bookId: nil)
        return highlights
            .sorted { $0.created > $1.created }
            .prefix(20)
            .compactMap { highlight in
                let text = (highlight.locator.text.highlight ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return QuoteAppEntity(highlight: highlight, bookTitle: bookTitles[highlight.bookId] ?? "")
            }
    }
}

// MARK: - Reading Status AppEntity

struct ReadingStatusAppEntity: AppEntity, Hashable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("intent_entity_status_name", defaultValue: "Reading Progress")
    )

    static var defaultQuery = ReadingStatusAppEntityQuery()

    let id: String

    @Property(title: LocalizedStringResource("intent_prop_today_minutes", defaultValue: "Minutes Read Today"))
    var todayMinutes: Int

    @Property(title: LocalizedStringResource("intent_prop_goal_minutes", defaultValue: "Daily Goal (Minutes)"))
    var dailyGoalMinutes: Int

    @Property(title: LocalizedStringResource("intent_prop_goal_reached", defaultValue: "Daily Goal Reached"))
    var goalReached: Bool

    @Property(title: LocalizedStringResource("intent_prop_streak_days", defaultValue: "Reading Streak (Days)"))
    var streakDays: Int

    @Property(title: LocalizedStringResource("intent_prop_current_book", defaultValue: "Current Book"))
    var currentBookTitle: String?

    @Property(title: LocalizedStringResource("intent_prop_current_progress", defaultValue: "Current Book Progress (%)"))
    var currentBookProgressPercent: Int

    @Property(title: LocalizedStringResource("intent_prop_summary", defaultValue: "Summary"))
    var summaryText: String

    init(
        todayMinutes: Int,
        dailyGoalMinutes: Int,
        goalReached: Bool,
        streakDays: Int,
        currentBookTitle: String?,
        currentBookProgressPercent: Int,
        summaryText: String
    ) {
        self.id = "today"
        self.todayMinutes = todayMinutes
        self.dailyGoalMinutes = dailyGoalMinutes
        self.goalReached = goalReached
        self.streakDays = streakDays
        self.currentBookTitle = currentBookTitle
        self.currentBookProgressPercent = currentBookProgressPercent
        self.summaryText = summaryText
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(summaryText)",
            image: DisplayRepresentation.Image(systemName: goalReached ? "checkmark.circle.fill" : "book.pages.fill")
        )
    }

    static func == (lhs: ReadingStatusAppEntity, rhs: ReadingStatusAppEntity) -> Bool {
        lhs.id == rhs.id && lhs.todayMinutes == rhs.todayMinutes && lhs.dailyGoalMinutes == rhs.dailyGoalMinutes
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(todayMinutes)
        hasher.combine(dailyGoalMinutes)
    }
}

struct ReadingStatusAppEntityQuery: EntityQuery {
    func entities(for identifiers: [ReadingStatusAppEntity.ID]) async throws -> [ReadingStatusAppEntity] {
        guard identifiers.contains("today") else { return [] }
        return [try await GetReadingProgressIntent.buildStatusEntity()]
    }

    func suggestedEntities() async throws -> [ReadingStatusAppEntity] {
        [try await GetReadingProgressIntent.buildStatusEntity()]
    }
}

// MARK: - AppEnums

enum MicroReadingDurationOption: Int, AppEnum, CaseIterable {
    case threeMinutes = 3
    case fiveMinutes = 5
    case tenMinutes = 10

    static var typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("intent_enum_duration_name", defaultValue: "Reading Duration")
    )

    static var caseDisplayRepresentations: [MicroReadingDurationOption: DisplayRepresentation] = [
        .threeMinutes: DisplayRepresentation(
            title: LocalizedStringResource("intent_duration_3_min", defaultValue: "3 Minutes")
        ),
        .fiveMinutes: DisplayRepresentation(
            title: LocalizedStringResource("intent_duration_5_min", defaultValue: "5 Minutes")
        ),
        .tenMinutes: DisplayRepresentation(
            title: LocalizedStringResource("intent_duration_10_min", defaultValue: "10 Minutes")
        ),
    ]
}

enum PaperPresetAppOption: String, AppEnum, CaseIterable {
    case morningPaper
    case sepia
    case eink
    case midnightInk

    static var typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("intent_enum_paper_preset_name", defaultValue: "Paper Theme")
    )

    static var caseDisplayRepresentations: [PaperPresetAppOption: DisplayRepresentation] = [
        .morningPaper: DisplayRepresentation(
            title: LocalizedStringResource("reader_preset_morning_paper", defaultValue: "Morning Paper"),
            image: DisplayRepresentation.Image(systemName: "sun.max")
        ),
        .sepia: DisplayRepresentation(
            title: LocalizedStringResource("reader_preset_sepia", defaultValue: "Sepia"),
            image: DisplayRepresentation.Image(systemName: "book.pages")
        ),
        .eink: DisplayRepresentation(
            title: LocalizedStringResource("reader_preset_eink", defaultValue: "E-Ink"),
            image: DisplayRepresentation.Image(systemName: "doc.plaintext")
        ),
        .midnightInk: DisplayRepresentation(
            title: LocalizedStringResource("reader_preset_midnight_ink", defaultValue: "Midnight Ink"),
            image: DisplayRepresentation.Image(systemName: "moon.stars.fill")
        ),
    ]

    var readerPaperPreset: ReaderPaperPreset {
        switch self {
        case .morningPaper: return .morningPaper
        case .sepia: return .sepia
        case .eink: return .eink
        case .midnightInk: return .midnightInk
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
