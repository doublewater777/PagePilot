//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import CloudKit
import Foundation
import GRDB
import ReadiumShared

struct PendingCloudChange: Sendable {
    enum Kind: Sendable {
        case save
        case delete
    }

    let recordType: CloudSyncRecordType
    let syncID: String
    let kind: Kind
}

final class CloudSyncStore {
    private let db: Database

    init(db: Database) {
        self.db = db
    }

    // MARK: - Bootstrap / durable outbox

    func prepareStableIDs() async throws {
        try await db.write { db in
            var usedBookIDs = Set(try String.fetchAll(
                db,
                sql: "SELECT syncID FROM book WHERE syncID <> ''"
            ))

            var books = try Book.filter(Book.Columns.syncID == "").fetchAll(db)
            for index in books.indices {
                guard let id = books[index].id else { continue }
                var candidate = CloudSyncIdentifier.stableBook(
                    identifier: books[index].identifier,
                    fallbackID: id.rawValue
                )
                if usedBookIDs.contains(candidate) {
                    candidate += "-\(id.rawValue)"
                }
                usedBookIDs.insert(candidate)
                books[index].syncID = candidate
                books[index].needsSync = true
                books[index].contentNeedsSync = true
                try books[index].save(db)
            }

            var bookmarks = try Bookmark.filter(Bookmark.Columns.syncID == "").fetchAll(db)
            for index in bookmarks.indices {
                bookmarks[index].syncID = CloudSyncIdentifier.bookmark()
                bookmarks[index].needsSync = true
                try bookmarks[index].save(db)
            }

            var highlights = try Highlight.filter(Highlight.Columns.syncID == "").fetchAll(db)
            for index in highlights.indices {
                highlights[index].syncID = CloudSyncIdentifier.highlight()
                highlights[index].needsSync = true
                try highlights[index].save(db)
            }
        }
    }

    func markEverythingDirtyAndClearServerMetadata() async throws {
        try await db.write { db in
            try db.execute(sql: "UPDATE book SET needsSync = 1, contentNeedsSync = 1")
            try db.execute(sql: "UPDATE bookmark SET needsSync = 1")
            try db.execute(sql: "UPDATE highlight SET needsSync = 1")
            try CloudRecordMetadata.deleteAll(db)
        }
    }

    func pendingChanges(limit: Int = 400) async throws -> [PendingCloudChange] {
        try await db.read { db in
            var remaining = max(0, limit)
            var result: [PendingCloudChange] = []

            if remaining > 0 {
                let tombstones = try SyncTombstone
                    .order(Column("deletedAt"))
                    .limit(remaining)
                    .fetchAll(db)
                result.append(contentsOf: tombstones.compactMap { tombstone in
                    guard let type = CloudSyncRecordType(rawValue: tombstone.recordType) else { return nil }
                    return PendingCloudChange(recordType: type, syncID: tombstone.syncID, kind: .delete)
                })
                remaining = max(0, remaining - result.count)
            }

            if remaining > 0 {
                let books = try Book
                    .filter(Book.Columns.contentNeedsSync == true && Book.Columns.syncID != "")
                    .order(Book.Columns.created)
                    .limit(remaining)
                    .fetchAll(db)
                result.append(contentsOf: books.map {
                    PendingCloudChange(recordType: .book, syncID: $0.syncID, kind: .save)
                })
                remaining -= books.count
            }

            if remaining > 0 {
                let books = try Book
                    .filter(Book.Columns.needsSync == true && Book.Columns.syncID != "")
                    .order(Book.Columns.updatedAt)
                    .limit(remaining)
                    .fetchAll(db)
                result.append(contentsOf: books.map {
                    PendingCloudChange(
                        recordType: .progress,
                        syncID: CloudSyncIdentifier.progress(forBookSyncID: $0.syncID),
                        kind: .save
                    )
                })
                remaining -= books.count
            }

            if remaining > 0 {
                let bookmarks = try Bookmark
                    .filter(Bookmark.Columns.needsSync == true && Bookmark.Columns.syncID != "")
                    .order(Bookmark.Columns.updatedAt)
                    .limit(remaining)
                    .fetchAll(db)
                result.append(contentsOf: bookmarks.map {
                    PendingCloudChange(recordType: .bookmark, syncID: $0.syncID, kind: .save)
                })
                remaining -= bookmarks.count
            }

            if remaining > 0 {
                let highlights = try Highlight
                    .filter(Highlight.Columns.needsSync == true && Highlight.Columns.syncID != "")
                    .order(Highlight.Columns.updatedAt)
                    .limit(remaining)
                    .fetchAll(db)
                result.append(contentsOf: highlights.map {
                    PendingCloudChange(recordType: .highlight, syncID: $0.syncID, kind: .save)
                })
            }

            return result
        }
    }

    // MARK: - Local -> CloudKit projection

    func record(for recordID: CKRecord.ID) async throws -> CKRecord? {
        let syncID = recordID.recordName
        if syncID.hasPrefix("progress-") {
            return try await progressRecord(syncID: syncID, recordID: recordID)
        }
        if syncID.hasPrefix("bookmark-") {
            return try await bookmarkRecord(syncID: syncID, recordID: recordID)
        }
        if syncID.hasPrefix("highlight-") {
            return try await highlightRecord(syncID: syncID, recordID: recordID)
        }
        if syncID.hasPrefix("book-") {
            return try await bookRecord(syncID: syncID, recordID: recordID)
        }
        return nil
    }

    private func baseRecord(
        type: CloudSyncRecordType,
        syncID: String,
        recordID: CKRecord.ID
    ) async throws -> CKRecord {
        if let metadata = try await metadata(type: type, syncID: syncID),
           let record = try CKRecord.fromSystemFields(metadata.systemFields),
           record.recordID == recordID,
           record.recordType == type.rawValue
        {
            return record
        }
        return CKRecord(recordType: type.rawValue, recordID: recordID)
    }

    private func parentReference(bookSyncID: String, zoneID: CKRecordZone.ID) -> CKRecord.Reference {
        let bookID = CKRecord.ID(recordName: bookSyncID, zoneID: zoneID)
        return CKRecord.Reference(recordID: bookID, action: .deleteSelf)
    }

    private func bookRecord(syncID: String, recordID: CKRecord.ID) async throws -> CKRecord? {
        guard let book = try await db.read({ db in
            try Book.filter(Book.Columns.syncID == syncID).fetchOne(db)
        }) else { return nil }

        let record = try await baseRecord(type: .book, syncID: syncID, recordID: recordID)
        record["schemaVersion"] = Int64(1)
        record["identifier"] = book.identifier
        record["title"] = book.title
        record["authors"] = book.authors
        record["mediaType"] = book.type
        record["sourceURL"] = book.url
        record["created"] = book.created

        if let fileURL = try book.absoluteFileURL(), FileManager.default.fileExists(atPath: fileURL.path) {
            record["publication"] = CKAsset(fileURL: fileURL)
            record["fileName"] = fileURL.lastPathComponent
        } else {
            record["publication"] = nil
            record["fileName"] = nil
        }

        if let coverURL = book.cover?.url, FileManager.default.fileExists(atPath: coverURL.path) {
            record["cover"] = CKAsset(fileURL: coverURL)
            record["coverName"] = coverURL.lastPathComponent
        } else {
            record["cover"] = nil
            record["coverName"] = nil
        }
        return record
    }

    private func progressRecord(syncID: String, recordID: CKRecord.ID) async throws -> CKRecord? {
        let bookSyncID = String(syncID.dropFirst("progress-".count))
        guard !bookSyncID.isEmpty,
              let book = try await db.read({ db in
                  try Book.filter(Book.Columns.syncID == bookSyncID).fetchOne(db)
              })
        else { return nil }

        let record = try await baseRecord(type: .progress, syncID: syncID, recordID: recordID)
        record["schemaVersion"] = Int64(1)
        record["bookSyncID"] = bookSyncID
        record["book"] = parentReference(bookSyncID: bookSyncID, zoneID: recordID.zoneID)
        record["locatorJSON"] = try book.locator?.jsonString()
        record["progression"] = book.progression
        record["preferencesJSON"] = book.preferencesJSON
        record["updatedAt"] = book.updatedAt
        return record
    }

    private func bookmarkRecord(syncID: String, recordID: CKRecord.ID) async throws -> CKRecord? {
        guard let payload = try await db.read({ db -> (Bookmark, String)? in
            guard let bookmark = try Bookmark.filter(Bookmark.Columns.syncID == syncID).fetchOne(db),
                  let book = try Book.fetchOne(db, key: bookmark.bookId)
            else { return nil }
            return (bookmark, book.syncID)
        }) else { return nil }

        let record = try await baseRecord(type: .bookmark, syncID: syncID, recordID: recordID)
        record["schemaVersion"] = Int64(1)
        record["bookSyncID"] = payload.1
        record["book"] = parentReference(bookSyncID: payload.1, zoneID: recordID.zoneID)
        record["locatorJSON"] = try payload.0.locator.jsonString()
        record["progression"] = payload.0.progression
        record["created"] = payload.0.created
        record["updatedAt"] = payload.0.updatedAt
        return record
    }

    private func highlightRecord(syncID: String, recordID: CKRecord.ID) async throws -> CKRecord? {
        guard let payload = try await db.read({ db -> (Highlight, String)? in
            guard let highlight = try Highlight.filter(Highlight.Columns.syncID == syncID).fetchOne(db),
                  let book = try Book.fetchOne(db, key: highlight.bookId)
            else { return nil }
            return (highlight, book.syncID)
        }) else { return nil }

        let record = try await baseRecord(type: .highlight, syncID: syncID, recordID: recordID)
        record["schemaVersion"] = Int64(1)
        record["bookSyncID"] = payload.1
        record["book"] = parentReference(bookSyncID: payload.1, zoneID: recordID.zoneID)
        record["locatorJSON"] = try payload.0.locator.jsonString()
        record["progression"] = payload.0.progression
        record["color"] = Int64(payload.0.color.rawValue)
        record["note"] = payload.0.note
        record["created"] = payload.0.created
        record["updatedAt"] = payload.0.updatedAt
        return record
    }

    // MARK: - CloudKit -> local merge

    func applyFetchedRecords(_ records: [CKRecord]) async throws -> [CKRecord.ID] {
        let ordered = records.sorted { rank($0.recordType) < rank($1.recordType) }
        var localWins: [CKRecord.ID] = []
        for record in ordered where try await applyRemoteRecord(record) {
            localWins.append(record.recordID)
        }
        localWins.append(contentsOf: try await replayDeferredRecords())
        return localWins
    }

    /// Returns true when a newer local value wins and should be sent back.
    func applyRemoteRecord(_ record: CKRecord) async throws -> Bool {
        guard let type = CloudSyncRecordType(rawValue: record.recordType) else { return false }
        if try await deletionWins(over: record, type: type) {
            return false
        }

        let localWins: Bool
        switch type {
        case .book:
            localWins = try await applyBook(record)
        case .progress:
            localWins = try await applyProgress(record)
        case .bookmark:
            localWins = try await applyBookmark(record)
        case .highlight:
            localWins = try await applyHighlight(record)
        }

        // Child records may be durably deferred until their Book arrives.
        if try await isDeferred(type: type, syncID: record.recordID.recordName) {
            return false
        }

        try await saveMetadata(record, type: type)
        try await removeDeferred(type: type, syncID: record.recordID.recordName)
        return localWins
    }

    private func deletionWins(over record: CKRecord, type: CloudSyncRecordType) async throws -> Bool {
        guard let tombstone = try await tombstone(type: type, syncID: record.recordID.recordName) else {
            return false
        }
        let remoteUpdatedAt = record["updatedAt"] as? Date ?? record.modificationDate ?? .distantPast
        if tombstone.deletedAt >= remoteUpdatedAt {
            return true
        }
        try await db.write { db in
            try SyncTombstone
                .filter(Column("recordType") == type.rawValue && Column("syncID") == record.recordID.recordName)
                .deleteAll(db)
        }
        return false
    }

    private func applyBook(_ record: CKRecord) async throws -> Bool {
        let syncID = record.recordID.recordName
        guard let title = record["title"] as? String,
              let mediaType = record["mediaType"] as? String,
              let created = record["created"] as? Date
        else { return false }

        let identifier = record["identifier"] as? String
        let existing = try await db.read { db -> Book? in
            if let exact = try Book.filter(Book.Columns.syncID == syncID).fetchOne(db) {
                return exact
            }
            guard let identifier, !identifier.isEmpty else { return nil }
            return try Book.filter(Book.Columns.identifier == identifier).fetchOne(db)
        }

        var resolvedURL = existing?.url
        var newPublicationURL: URL?
        if !hasReachableFile(existing),
           let asset = record["publication"] as? CKAsset,
           let assetURL = asset.fileURL
        {
            let name = safeFilename((record["fileName"] as? String) ?? UUID().uuidString)
            let destination = Paths.documents.appendingUniquePathComponent(name)
            try FileManager.default.copyItem(at: assetURL, to: destination.url)
            resolvedURL = destination.anyURL.string
            newPublicationURL = destination.url
        }
        if resolvedURL == nil {
            resolvedURL = record["sourceURL"] as? String
        }
        guard let resolvedURL, let anyURL = AnyURL(string: resolvedURL) else {
            if let newPublicationURL { try? FileManager.default.removeItem(at: newPublicationURL) }
            return false
        }

        var coverPath = existing?.coverPath
        var newCoverURL: URL?
        if !hasReachableCover(existing),
           let asset = record["cover"] as? CKAsset,
           let assetURL = asset.fileURL
        {
            let name = safeFilename((record["coverName"] as? String) ?? UUID().uuidString)
            let destination = Paths.covers.appendingUniquePathComponent(name)
            try FileManager.default.copyItem(at: assetURL, to: destination.url)
            coverPath = destination.lastPathSegment
            newCoverURL = destination.url
        }

        do {
            try await db.write { db in
                let localBySyncID = try Book.filter(Book.Columns.syncID == syncID).fetchOne(db)
                let localByIdentifier: Book? = if let identifier, !identifier.isEmpty {
                    try Book.filter(Book.Columns.identifier == identifier).fetchOne(db)
                } else {
                    nil
                }

                if var local = localBySyncID ?? localByIdentifier {
                    let oldSyncID = local.syncID
                    local.identifier = identifier
                    local.title = title
                    local.authors = record["authors"] as? String
                    local.type = mediaType
                    local.url = anyURL.string
                    local.coverPath = coverPath
                    local.syncID = syncID
                    local.contentNeedsSync = false
                    try local.save(db)

                    if oldSyncID != syncID, !oldSyncID.isEmpty {
                        let now = Date()
                        try SyncTombstone(
                            recordType: CloudSyncRecordType.book.rawValue,
                            syncID: oldSyncID,
                            deletedAt: now
                        ).save(db)
                        try SyncTombstone(
                            recordType: CloudSyncRecordType.progress.rawValue,
                            syncID: CloudSyncIdentifier.progress(forBookSyncID: oldSyncID),
                            deletedAt: now
                        ).save(db)
                        if let localID = local.id {
                            try Bookmark.filter(Bookmark.Columns.bookId == localID)
                                .updateAll(db, Bookmark.Columns.needsSync.set(to: true))
                            try Highlight.filter(Highlight.Columns.bookId == localID)
                                .updateAll(db, Highlight.Columns.needsSync.set(to: true))
                        }
                        local.needsSync = true
                        try local.save(db)
                    }
                } else {
                    let book = Book(
                        identifier: identifier,
                        title: title,
                        authors: record["authors"] as? String,
                        type: mediaType,
                        url: anyURL,
                        coverPath: coverPath,
                        created: created,
                        syncID: syncID,
                        updatedAt: created,
                        needsSync: false,
                        contentNeedsSync: false
                    )
                    try book.insert(db)
                }
            }
        } catch {
            if let newPublicationURL { try? FileManager.default.removeItem(at: newPublicationURL) }
            if let newCoverURL { try? FileManager.default.removeItem(at: newCoverURL) }
            throw error
        }
        return false
    }

    private func applyProgress(_ record: CKRecord) async throws -> Bool {
        guard let bookSyncID = record["bookSyncID"] as? String else { return false }
        let syncID = record.recordID.recordName
        guard try await hasBook(syncID: bookSyncID) else {
            try await deferRemoteRecord(record)
            return false
        }

        let remoteUpdatedAt = record["updatedAt"] as? Date ?? record.modificationDate ?? .distantPast
        let locator = try Self.decodeLocator(record["locatorJSON"] as? String)
        let progression = (record["progression"] as? NSNumber)?.doubleValue
            ?? locator?.locations.totalProgression
            ?? 0

        return try await db.write { db in
            guard var local = try Book.filter(Book.Columns.syncID == bookSyncID).fetchOne(db) else {
                return false
            }
            if !CloudSyncMergePolicy.remoteWins(
                localUpdatedAt: local.updatedAt,
                remoteUpdatedAt: remoteUpdatedAt
            ) {
                local.needsSync = true
                try local.save(db)
                return true
            }

            local.locator = locator
            local.progression = progression
            local.preferencesJSON = record["preferencesJSON"] as? String
            local.updatedAt = remoteUpdatedAt
            local.needsSync = false
            try local.save(db)
            return false
        }
    }

    private func applyBookmark(_ record: CKRecord) async throws -> Bool {
        let syncID = record.recordID.recordName
        guard let bookSyncID = record["bookSyncID"] as? String,
              let locator = try Self.decodeLocator(record["locatorJSON"] as? String),
              let created = record["created"] as? Date
        else { return false }
        guard try await hasBook(syncID: bookSyncID) else {
            try await deferRemoteRecord(record)
            return false
        }

        let remoteUpdatedAt = record["updatedAt"] as? Date ?? record.modificationDate ?? created
        return try await db.write { db in
            guard let book = try Book.filter(Book.Columns.syncID == bookSyncID).fetchOne(db),
                  let bookID = book.id
            else { return false }

            if var local = try Bookmark.filter(Bookmark.Columns.syncID == syncID).fetchOne(db) {
                if !CloudSyncMergePolicy.remoteWins(localUpdatedAt: local.updatedAt, remoteUpdatedAt: remoteUpdatedAt) {
                    local.needsSync = true
                    try local.save(db)
                    return true
                }
                local.bookId = bookID
                local.locator = locator
                local.progression = (record["progression"] as? NSNumber)?.doubleValue
                    ?? locator.locations.totalProgression
                local.created = created
                local.updatedAt = remoteUpdatedAt
                local.needsSync = false
                try local.save(db)
            } else {
                var bookmark = Bookmark(
                    bookId: bookID,
                    locator: locator,
                    created: created,
                    syncID: syncID,
                    updatedAt: remoteUpdatedAt,
                    needsSync: false
                )
                bookmark.progression = (record["progression"] as? NSNumber)?.doubleValue
                    ?? locator.locations.totalProgression
                try bookmark.insert(db)
            }
            return false
        }
    }

    private func applyHighlight(_ record: CKRecord) async throws -> Bool {
        let syncID = record.recordID.recordName
        guard let bookSyncID = record["bookSyncID"] as? String,
              let locator = try Self.decodeLocator(record["locatorJSON"] as? String),
              let colorRaw = (record["color"] as? NSNumber)?.uint8Value,
              let color = HighlightColor(rawValue: colorRaw),
              let created = record["created"] as? Date
        else { return false }
        guard try await hasBook(syncID: bookSyncID) else {
            try await deferRemoteRecord(record)
            return false
        }

        let remoteUpdatedAt = record["updatedAt"] as? Date ?? record.modificationDate ?? created
        return try await db.write { db in
            guard let book = try Book.filter(Book.Columns.syncID == bookSyncID).fetchOne(db),
                  let bookID = book.id
            else { return false }

            if var local = try Highlight.filter(Highlight.Columns.syncID == syncID).fetchOne(db) {
                if !CloudSyncMergePolicy.remoteWins(localUpdatedAt: local.updatedAt, remoteUpdatedAt: remoteUpdatedAt) {
                    local.needsSync = true
                    try local.save(db)
                    return true
                }
                local.bookId = bookID
                local.locator = locator
                local.progression = (record["progression"] as? NSNumber)?.doubleValue
                    ?? locator.locations.totalProgression
                local.color = color
                local.note = record["note"] as? String
                local.created = created
                local.updatedAt = remoteUpdatedAt
                local.needsSync = false
                try local.save(db)
            } else {
                var highlight = Highlight(
                    bookId: bookID,
                    locator: locator,
                    color: color,
                    created: created,
                    note: record["note"] as? String,
                    syncID: syncID,
                    updatedAt: remoteUpdatedAt,
                    needsSync: false
                )
                highlight.progression = (record["progression"] as? NSNumber)?.doubleValue
                    ?? locator.locations.totalProgression
                try highlight.insert(db)
            }
            return false
        }
    }

    // MARK: - Deferred child records

    func replayDeferredRecords() async throws -> [CKRecord.ID] {
        let archived = try await db.read { db in
            try DeferredCloudRecord.order(Column("receivedAt")).fetchAll(db)
        }
        let records = try archived.compactMap { try CKRecord.fromDeferredArchive($0.payload) }
            .sorted { rank($0.recordType) < rank($1.recordType) }

        var localWins: [CKRecord.ID] = []
        for record in records {
            guard let bookSyncID = record["bookSyncID"] as? String,
                  try await hasBook(syncID: bookSyncID)
            else { continue }
            if try await applyRemoteRecord(record) {
                localWins.append(record.recordID)
            }
        }
        return localWins
    }

    private func deferRemoteRecord(_ record: CKRecord) async throws {
        let payload = try record.archivedForDeferredMerge()
        try await db.write { db in
            try DeferredCloudRecord(
                recordType: record.recordType,
                syncID: record.recordID.recordName,
                payload: payload,
                receivedAt: Date()
            ).save(db)
        }
    }

    private func isDeferred(type: CloudSyncRecordType, syncID: String) async throws -> Bool {
        try await db.read { db in
            try DeferredCloudRecord
                .filter(Column("recordType") == type.rawValue && Column("syncID") == syncID)
                .fetchCount(db) > 0
        }
    }

    private func removeDeferred(type: CloudSyncRecordType, syncID: String) async throws {
        try await db.write { db in
            try DeferredCloudRecord
                .filter(Column("recordType") == type.rawValue && Column("syncID") == syncID)
                .deleteAll(db)
        }
    }

    // MARK: - Deletions / acknowledgements

    func applyRemoteDeletion(_ recordID: CKRecord.ID) async throws {
        let syncID = recordID.recordName
        guard let type = type(for: syncID) else { return }

        var filesToDelete: [URL] = []
        try await db.write { db in
            switch type {
            case .book:
                if let book = try Book.filter(Book.Columns.syncID == syncID).fetchOne(db) {
                    if let file = try book.absoluteFileURL() {
                        filesToDelete.append(file)
                    }
                    if let cover = book.cover?.url {
                        filesToDelete.append(cover)
                    }
                    if let id = book.id {
                        let bookmarkIDs = try Bookmark
                            .filter(Bookmark.Columns.bookId == id)
                            .select(Bookmark.Columns.syncID, as: String.self)
                            .fetchAll(db)
                        let highlightIDs = try Highlight
                            .filter(Highlight.Columns.bookId == id)
                            .select(Highlight.Columns.syncID, as: String.self)
                            .fetchAll(db)
                        try Book.deleteOne(db, key: id)
                        for childID in bookmarkIDs {
                            try self.deleteMetadata(db: db, type: .bookmark, syncID: childID)
                        }
                        for childID in highlightIDs {
                            try self.deleteMetadata(db: db, type: .highlight, syncID: childID)
                        }
                    }
                }
                try self.deleteMetadata(
                    db: db,
                    type: .progress,
                    syncID: CloudSyncIdentifier.progress(forBookSyncID: syncID)
                )

            case .progress:
                let bookSyncID = String(syncID.dropFirst("progress-".count))
                try Book.filter(Book.Columns.syncID == bookSyncID)
                    .updateAll(db, Book.Columns.needsSync.set(to: true))

            case .bookmark:
                try Bookmark.filter(Bookmark.Columns.syncID == syncID).deleteAll(db)

            case .highlight:
                try Highlight.filter(Highlight.Columns.syncID == syncID).deleteAll(db)
            }

            try SyncTombstone
                .filter(Column("recordType") == type.rawValue && Column("syncID") == syncID)
                .deleteAll(db)
            try self.deleteMetadata(db: db, type: type, syncID: syncID)
            try DeferredCloudRecord
                .filter(Column("recordType") == type.rawValue && Column("syncID") == syncID)
                .deleteAll(db)
        }

        for file in filesToDelete where isInsideAppSandbox(file) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    func acknowledgeSavedRecord(_ record: CKRecord) async throws {
        guard let type = CloudSyncRecordType(rawValue: record.recordType) else { return }
        let syncID = record.recordID.recordName
        let sentUpdatedAt = record["updatedAt"] as? Date ?? .distantPast
        let fields = try record.encodedSystemFields()

        try await db.write { db in
            try CloudRecordMetadata(
                recordType: type.rawValue,
                syncID: syncID,
                systemFields: fields
            ).save(db)

            switch type {
            case .book:
                if var local = try Book.filter(Book.Columns.syncID == syncID).fetchOne(db) {
                    local.contentNeedsSync = false
                    try local.save(db)
                }

            case .progress:
                let bookSyncID = String(syncID.dropFirst("progress-".count))
                if var local = try Book.filter(Book.Columns.syncID == bookSyncID).fetchOne(db),
                   local.updatedAt <= sentUpdatedAt
                {
                    local.needsSync = false
                    try local.save(db)
                }

            case .bookmark:
                if var local = try Bookmark.filter(Bookmark.Columns.syncID == syncID).fetchOne(db),
                   local.updatedAt <= sentUpdatedAt
                {
                    local.needsSync = false
                    try local.save(db)
                }

            case .highlight:
                if var local = try Highlight.filter(Highlight.Columns.syncID == syncID).fetchOne(db),
                   local.updatedAt <= sentUpdatedAt
                {
                    local.needsSync = false
                    try local.save(db)
                }
            }
        }
    }

    func acknowledgeDeletedRecord(_ recordID: CKRecord.ID) async throws {
        let syncID = recordID.recordName
        guard let type = type(for: syncID) else { return }
        try await db.write { db in
            try SyncTombstone
                .filter(Column("recordType") == type.rawValue && Column("syncID") == syncID)
                .deleteAll(db)
            try self.deleteMetadata(db: db, type: type, syncID: syncID)
        }
    }

    func clearMetadata(for recordID: CKRecord.ID) async throws {
        let syncID = recordID.recordName
        guard let type = type(for: syncID) else { return }
        try await db.write { db in
            try self.deleteMetadata(db: db, type: type, syncID: syncID)
        }
    }

    func isDeletePending(_ recordID: CKRecord.ID) async throws -> Bool {
        let syncID = recordID.recordName
        guard let type = type(for: syncID) else { return false }
        return try await db.read { db in
            try SyncTombstone
                .filter(Column("recordType") == type.rawValue && Column("syncID") == syncID)
                .fetchCount(db) > 0
        }
    }

    // MARK: - Helpers

    private func metadata(type: CloudSyncRecordType, syncID: String) async throws -> CloudRecordMetadata? {
        try await db.read { db in
            try CloudRecordMetadata
                .filter(Column("recordType") == type.rawValue && Column("syncID") == syncID)
                .fetchOne(db)
        }
    }

    private func tombstone(type: CloudSyncRecordType, syncID: String) async throws -> SyncTombstone? {
        try await db.read { db in
            try SyncTombstone
                .filter(Column("recordType") == type.rawValue && Column("syncID") == syncID)
                .fetchOne(db)
        }
    }

    private func saveMetadata(_ record: CKRecord, type: CloudSyncRecordType) async throws {
        let fields = try record.encodedSystemFields()
        try await db.write { db in
            try CloudRecordMetadata(
                recordType: type.rawValue,
                syncID: record.recordID.recordName,
                systemFields: fields
            ).save(db)
        }
    }

    private func deleteMetadata(db: GRDB.Database, type: CloudSyncRecordType, syncID: String) throws {
        try CloudRecordMetadata
            .filter(Column("recordType") == type.rawValue && Column("syncID") == syncID)
            .deleteAll(db)
    }

    private func hasBook(syncID: String) async throws -> Bool {
        try await db.read { db in
            try Book.filter(Book.Columns.syncID == syncID).fetchCount(db) > 0
        }
    }

    private func type(for syncID: String) -> CloudSyncRecordType? {
        if syncID.hasPrefix("progress-") { return .progress }
        if syncID.hasPrefix("bookmark-") { return .bookmark }
        if syncID.hasPrefix("highlight-") { return .highlight }
        if syncID.hasPrefix("book-") { return .book }
        return nil
    }

    private func rank(_ recordType: String) -> Int {
        switch CloudSyncRecordType(rawValue: recordType) {
        case .book: return 0
        case .progress: return 1
        case .bookmark: return 2
        case .highlight: return 3
        case nil: return 4
        }
    }

    static func decodeLocator(_ json: String?) throws -> Locator? {
        guard let json else { return nil }
        return try Locator(jsonString: json)
    }

    private func hasReachableFile(_ book: Book?) -> Bool {
        guard let book else { return false }
        do {
            guard let fileURL = try book.absoluteFileURL() else { return false }
            return FileManager.default.fileExists(atPath: fileURL.path)
        } catch {
            return false
        }
    }

    private func hasReachableCover(_ book: Book?) -> Bool {
        guard let url = book?.cover?.url else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func safeFilename(_ filename: String) -> String {
        let value = URL(fileURLWithPath: filename).lastPathComponent
        return value.isEmpty ? UUID().uuidString : value
    }

    private func isInsideAppSandbox(_ url: URL) -> Bool {
        let home = Paths.home.url.standardizedFileURL.path
        let candidate = url.standardizedFileURL.path
        return candidate == home || candidate.hasPrefix(home + "/")
    }
}
