//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import Foundation
import GRDB
import ReadiumShared

struct Book: Codable {
    struct Id: EntityId { let rawValue: Int64 }

    let id: Id?
    var identifier: String?
    var title: String
    var authors: String?
    var type: String
    var url: String
    var coverPath: String?
    var locator: Locator? {
        didSet { progression = locator?.locations.totalProgression ?? 0 }
    }
    var progression: Double
    var created: Date
    var preferencesJSON: String?

    /// Stable identity shared by the Book record and all child records.
    var syncID: String
    /// Timestamp for the lightweight ReadingProgress record.
    var updatedAt: Date
    /// Dirty bit for ReadingProgress only.
    var needsSync: Bool
    /// Dirty bit for the publication metadata/file/cover record. Reading
    /// progress updates never flip this bit, avoiding repeated CKAsset uploads.
    var contentNeedsSync: Bool

    var mediaType: MediaType {
        MediaType(type) ?? .binary
    }

    init(
        id: Id? = nil,
        identifier: String? = nil,
        title: String,
        authors: String? = nil,
        type: String,
        url: AnyURL,
        coverPath: String? = nil,
        locator: Locator? = nil,
        created: Date = Date(),
        preferencesJSON: String? = nil,
        syncID: String? = nil,
        updatedAt: Date? = nil,
        needsSync: Bool = true,
        contentNeedsSync: Bool = true
    ) {
        self.id = id
        self.identifier = identifier
        self.title = title
        self.authors = authors
        self.type = type
        self.url = url.string
        self.coverPath = coverPath
        self.locator = locator
        progression = locator?.locations.totalProgression ?? 0
        self.created = created
        self.preferencesJSON = preferencesJSON
        self.syncID = syncID ?? CloudSyncIdentifier.book(identifier: identifier)
        self.updatedAt = updatedAt ?? created
        self.needsSync = needsSync
        self.contentNeedsSync = contentNeedsSync
    }

    var cover: FileURL? {
        coverPath.map { Paths.covers.appendingPath($0, isDirectory: false) }
    }

    func absoluteFileURL() throws -> URL? {
        guard let anyURL = AnyURL(string: url) else { return nil }
        switch anyURL {
        case let .absolute(absURL):
            return absURL.fileURL?.url
        case let .relative(relURL):
            return Paths.documents.resolve(relURL)?.url
        }
    }

    func preferences<P: Decodable>() throws -> P? {
        guard let data = preferencesJSON.flatMap({ $0.data(using: .utf8) }) else {
            return nil
        }
        return try JSONDecoder().decode(P.self, from: data)
    }

    mutating func setPreferences<P: Encodable>(_ preferences: P) throws {
        let data = try JSONEncoder().encode(preferences)
        preferencesJSON = String(data: data, encoding: .utf8)
    }
}

extension Book: TableRecord, FetchableRecord, PersistableRecord {
    enum Columns: String, ColumnExpression {
        case id, identifier, title, authors, type, url, coverPath, locator, progression, created, preferencesJSON
        case syncID, updatedAt, needsSync, contentNeedsSync
    }
}

final class BookRepository {
    private let db: Database

    init(db: Database) {
        self.db = db
    }

    func get(_ id: Book.Id) async throws -> Book? {
        try await db.read { db in
            try Book.fetchOne(db, key: id)
        }
    }

    func getByIdentifier(_ identifier: String) async throws -> Book? {
        guard !identifier.isEmpty else { return nil }
        return try await db.read { db in
            try Book
                .filter(Book.Columns.identifier == identifier)
                .fetchOne(db)
        }
    }

    func observe(_ id: Book.Id) -> AnyPublisher<Book?, Error> {
        db.observe { db in
            try Book.fetchOne(db, key: id)
        }
    }

    func all() -> AnyPublisher<[Book], Error> {
        db.observe { db in
            try Book.order(Book.Columns.created).fetchAll(db)
        }
    }

    func allOnce() async throws -> [Book] {
        try await db.read { db in
            try Book.order(Book.Columns.created).fetchAll(db)
        }
    }

    func count() async throws -> Int {
        try await db.read { db in
            try Book.fetchCount(db)
        }
    }

    @discardableResult
    func add(_ book: Book) async throws -> Book.Id {
        let id = try await db.write { db in
            try book.insert(db)
            return Book.Id(rawValue: db.lastInsertedRowID)
        }
        notifyCloudSync()
        return id
    }

    @discardableResult
    func addIfWithinLimit(_ book: Book, limit: Int, hasProAccess: Bool) async throws -> Book.Id {
        let id = try await db.write { db in
            if !hasProAccess {
                let count = try Book.fetchCount(db)
                guard count + 1 <= limit else {
                    throw LibraryError.bookLimitReached
                }
            }
            try book.insert(db)
            return Book.Id(rawValue: db.lastInsertedRowID)
        }
        notifyCloudSync()
        return id
    }

    func remove(_ id: Book.Id) async throws {
        try await db.write { db in
            guard let book = try Book.fetchOne(db, key: id) else { return }
            let bookmarks = try Bookmark.filter(Bookmark.Columns.bookId == id).fetchAll(db)
            let highlights = try Highlight.filter(Highlight.Columns.bookId == id).fetchAll(db)
            let now = Date()

            for bookmark in bookmarks where !bookmark.syncID.isEmpty {
                try SyncTombstone(
                    recordType: CloudSyncRecordType.bookmark.rawValue,
                    syncID: bookmark.syncID,
                    deletedAt: now
                ).save(db)
            }
            for highlight in highlights where !highlight.syncID.isEmpty {
                try SyncTombstone(
                    recordType: CloudSyncRecordType.highlight.rawValue,
                    syncID: highlight.syncID,
                    deletedAt: now
                ).save(db)
            }
            if !book.syncID.isEmpty {
                try SyncTombstone(
                    recordType: CloudSyncRecordType.progress.rawValue,
                    syncID: CloudSyncIdentifier.progress(forBookSyncID: book.syncID),
                    deletedAt: now
                ).save(db)
                try SyncTombstone(
                    recordType: CloudSyncRecordType.book.rawValue,
                    syncID: book.syncID,
                    deletedAt: now
                ).save(db)
            }
            try Book.deleteOne(db, key: id)
        }
        notifyCloudSync()
    }

    func saveProgress(for id: Book.Id, locator: Locator) async throws {
        let json = try locator.jsonString()
        let now = Date()

        try await db.write { db in
            try db.execute(literal: """
                UPDATE book
                   SET locator = \(json),
                       progression = \(locator.locations.totalProgression ?? 0),
                       updatedAt = \(now),
                       needsSync = 1
                 WHERE id = \(id)
            """)
        }
        notifyCloudSync()
    }

    func savePreferences<Preferences: Encodable>(_ preferences: Preferences, of id: Book.Id) async throws {
        try await db.write { db in
            guard var book = try Book.fetchOne(db, key: id) else { return }
            try book.setPreferences(preferences)
            book.updatedAt = Date()
            book.needsSync = true
            try book.save(db)
        }
        notifyCloudSync()
    }

    private func notifyCloudSync() {
        NotificationCenter.default.post(name: .cloudSyncLocalDataDidChange, object: nil)
    }
}
