//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import Foundation
import GRDB
import ReadiumNavigator
import ReadiumShared
import UIKit

enum HighlightColor: UInt8, Codable, SQLExpressible {
    case red = 1
    case green = 2
    case blue = 3
    case yellow = 4
}

extension HighlightColor {
    var uiColor: UIColor {
        switch self {
        case .red:
            return .red
        case .green:
            return .green
        case .blue:
            return .blue
        case .yellow:
            return .yellow
        }
    }
}

struct Highlight: Codable {
    struct Id: EntityId { let rawValue: Int64 }

    let id: Id?
    /// Foreign key to the publication.
    var bookId: Book.Id
    /// Location in the publication.
    var locator: Locator
    /// Color of the highlight.
    var color: HighlightColor
    /// Date of creation.
    var created: Date = .init()
    /// Total progression in the publication.
    var progression: Double?
    /// Optional user note attached to this highlight.
    var note: String?
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
        color: HighlightColor,
        created: Date = Date(),
        note: String? = nil,
        syncID: String? = nil,
        updatedAt: Date? = nil,
        needsSync: Bool = true
    ) {
        self.id = id
        self.bookId = bookId
        self.locator = locator
        progression = locator.locations.totalProgression
        self.color = color
        self.created = created
        self.note = note
        self.syncID = syncID ?? CloudSyncIdentifier.highlight()
        self.updatedAt = updatedAt ?? created
        self.needsSync = needsSync
    }
}

extension Highlight: TableRecord, FetchableRecord, PersistableRecord {
    enum Columns: String, ColumnExpression {
        case id, bookId, locator, color, created, progression, note, syncID, updatedAt, needsSync
    }
}

struct HighlightNotFoundError: Error {}

final class HighlightRepository {
    private let db: Database

    init(db: Database) {
        self.db = db
    }

    func all(for bookId: Book.Id) -> AnyPublisher<[Highlight], Error> {
        db.observe { db in
            try Highlight
                .filter(Highlight.Columns.bookId == bookId)
                .order(Highlight.Columns.progression)
                .fetchAll(db)
        }
    }

    func highlight(for highlightId: Highlight.Id) -> AnyPublisher<Highlight, Error> {
        db.observe { db in
            try Highlight
                .filter(Highlight.Columns.id == highlightId)
                .fetchOne(db)
                .orThrow(HighlightNotFoundError())
        }
    }

    @discardableResult
    func add(_ highlight: Highlight) async throws -> Highlight.Id {
        let id = try await db.write { db in
            try highlight.insert(db)
            return Highlight.Id(rawValue: db.lastInsertedRowID)
        }
        notifyCloudSync()
        return id
    }

    func update(_ id: Highlight.Id, color: HighlightColor) async throws {
        try await db.write { db in
            let filtered = Highlight.filter(Highlight.Columns.id == id)
            try filtered.updateAll(
                db,
                onConflict: nil,
                Highlight.Columns.color.set(to: color),
                Highlight.Columns.updatedAt.set(to: Date()),
                Highlight.Columns.needsSync.set(to: true)
            )
        }
        notifyCloudSync()
    }

    func update(_ id: Highlight.Id, note: String?) async throws {
        try await db.write { db in
            let filtered = Highlight.filter(Highlight.Columns.id == id)
            try filtered.updateAll(
                db,
                onConflict: nil,
                Highlight.Columns.note.set(to: note),
                Highlight.Columns.updatedAt.set(to: Date()),
                Highlight.Columns.needsSync.set(to: true)
            )
        }
        notifyCloudSync()
    }

    func remove(_ id: Highlight.Id) async throws {
        try await db.write { db in
            guard let highlight = try Highlight.fetchOne(db, key: id) else { return }
            if !highlight.syncID.isEmpty {
                try SyncTombstone(
                    recordType: CloudSyncRecordType.highlight.rawValue,
                    syncID: highlight.syncID,
                    deletedAt: Date()
                ).save(db)
            }
            try Highlight.deleteOne(db, key: id)
        }
        notifyCloudSync()
    }

    func distinctBookIds() async throws -> [Book.Id] {
        try await db.read { db in
            try Highlight
                .select(Highlight.Columns.bookId, as: Book.Id.self)
                .distinct()
                .fetchAll(db)
        }
    }

    func count(for bookId: Book.Id) async throws -> Int {
        try await db.read { db in
            try Highlight
                .filter(Highlight.Columns.bookId == bookId)
                .fetchCount(db)
        }
    }

    func totalCount() async throws -> Int {
        try await db.read { db in
            try Highlight.fetchCount(db)
        }
    }

    private func notifyCloudSync() {
        NotificationCenter.default.post(name: .cloudSyncLocalDataDidChange, object: nil)
    }
}

/// for the default SwiftUI support
extension Highlight: Hashable {}
