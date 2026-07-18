//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import Foundation
import GRDB

struct OPDSFeed: Codable {
    struct Id: EntityId { let rawValue: Int64 }

    let id: Id?
    var title: String
    var url: String
    var created: Date

    init(id: Id? = nil, title: String, url: String, created: Date = Date()) {
        self.id = id
        self.title = title
        self.url = url
        self.created = created
    }
}

extension OPDSFeed: TableRecord, FetchableRecord, PersistableRecord {
    enum Columns: String, ColumnExpression {
        case id, title, url, created
    }
}

final class OPDSFeedRepository {
    private let db: Database

    init(db: Database) {
        self.db = db
    }

    func observeAll() -> AnyPublisher<[OPDSFeed], Error> {
        db.observe { db in
            try OPDSFeed.order(OPDSFeed.Columns.created).fetchAll(db)
        }
    }

    func allOnce() async throws -> [OPDSFeed] {
        try await db.read { db in
            try OPDSFeed.order(OPDSFeed.Columns.created).fetchAll(db)
        }
    }

    @discardableResult
    func add(_ feed: OPDSFeed) async throws -> OPDSFeed.Id {
        try await db.write { db in
            let f = feed
            try f.insert(db)
            return OPDSFeed.Id(rawValue: db.lastInsertedRowID)
        }
    }

    func update(_ feed: OPDSFeed) async throws {
        try await db.write { db in
            try feed.update(db)
        }
    }

    func remove(_ id: OPDSFeed.Id) async throws {
        try await db.write { db in try OPDSFeed.deleteOne(db, key: id) }
    }
}
