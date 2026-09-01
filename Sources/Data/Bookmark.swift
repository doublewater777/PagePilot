//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import Foundation
import GRDB
import ReadiumShared

struct Bookmark: Codable {
    struct Id: EntityId { let rawValue: Int64 }

    let id: Id?
    /// Foreign key to the publication.
    var bookId: Book.Id
    /// Location in the publication.
    var locator: Locator
    /// Progression in the publication, extracted from the locator.
    var progression: Double?
    /// Date of creation.
    var created: Date = .init()
    /// Stable cross-device identity.
    var syncID: String
    /// Domain modification timestamp for conflict resolution.
    var updatedAt: Date
    /// Durable local outbox bit.
    var needsSync: Bool

    init(
        id: Id? = nil,
        bookId: Book.Id,
        locator: Locator,
        created: Date = Date(),
        syncID: String? = nil,
        updatedAt: Date? = nil,
        needsSync: Bool = true
    ) {
        self.id = id
        self.bookId = bookId
        self.locator = locator
        progression = locator.locations.totalProgression
        self.created = created
        self.syncID = syncID ?? CloudSyncIdentifier.bookmark()
        self.updatedAt = updatedAt ?? created
        self.needsSync = needsSync
    }
}

extension Bookmark: TableRecord, FetchableRecord, PersistableRecord {
    enum Columns: String, ColumnExpression {
        case id, bookId, locator, progression, created, syncID, updatedAt, needsSync
    }
}

final class BookmarkRepository {
    private let db: Database

    init(db: Database) {
        self.db = db
    }

    func all(for bookId: Book.Id) -> AnyPublisher<[Bookmark], Error> {
        db.observe { db in
            try Bookmark
                .filter(Bookmark.Columns.bookId == bookId)
                .order(Bookmark.Columns.progression)
                .fetchAll(db)
        }
    }

    @discardableResult
    func add(_ bookmark: Bookmark) async throws -> Bookmark.Id {
        let id = try await db.write { db in
            try bookmark.insert(db)
            return Bookmark.Id(rawValue: db.lastInsertedRowID)
        }
        notifyCloudSync()
        return id
    }

    func remove(_ id: Bookmark.Id) async throws {
        try await db.write { db in
            guard let bookmark = try Bookmark.fetchOne(db, key: id) else { return }
            if !bookmark.syncID.isEmpty {
                try SyncTombstone(
                    recordType: CloudSyncRecordType.bookmark.rawValue,
                    syncID: bookmark.syncID,
                    deletedAt: Date()
                ).save(db)
            }
            try Bookmark.deleteOne(db, key: id)
        }
        notifyCloudSync()
    }

    func distinctBookIds() async throws -> [Book.Id] {
        try await db.read { db in
            try Bookmark
                .select(Bookmark.Columns.bookId, as: Book.Id.self)
                .distinct()
                .fetchAll(db)
        }
    }

    func count(for bookId: Book.Id) async throws -> Int {
        try await db.read { db in
            try Bookmark
                .filter(Bookmark.Columns.bookId == bookId)
                .fetchCount(db)
        }
    }

    private func notifyCloudSync() {
        NotificationCenter.default.post(name: .cloudSyncLocalDataDidChange, object: nil)
    }
}

/// for the default SwiftUI support
extension Bookmark: Hashable {}
