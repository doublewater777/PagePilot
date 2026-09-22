//
//  Copyright 2026 PagePilot. All rights reserved.
//

import CloudKit
import Foundation
import ReadiumShared
import XCTest
@testable import PagePilot

final class CloudSyncSupportTests: XCTestCase {
    func testBookSyncIdentifierIsStableForPublicationIdentifier() {
        let first = CloudSyncIdentifier.book(identifier: "urn:isbn:9780141439518")
        let second = CloudSyncIdentifier.book(identifier: "urn:isbn:9780141439518")

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.hasPrefix("book-"))
    }

    func testAnnotationIdentifiersAreNamespaced() {
        XCTAssertTrue(CloudSyncIdentifier.bookmark().hasPrefix("bookmark-"))
        XCTAssertTrue(CloudSyncIdentifier.highlight().hasPrefix("highlight-"))
    }

    func testCloudSyncPreferenceUsesInjectedDefaults() throws {
        let suiteName = "CloudSyncSupportTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(CloudSyncPreferences.isEnabled(in: defaults))

        CloudSyncPreferences.setEnabled(false, in: defaults, postNotification: false)
        XCTAssertFalse(CloudSyncPreferences.isEnabled(in: defaults))

        CloudSyncPreferences.setEnabled(true, in: defaults, postNotification: false)
        XCTAssertTrue(CloudSyncPreferences.isEnabled(in: defaults))
    }

    func testCloudSyncRequiresBothEnabledPreferenceAndProAccess() {
        XCTAssertFalse(CloudSyncAccessPolicy.canSync(isEnabled: false, hasProAccess: false))
        XCTAssertFalse(CloudSyncAccessPolicy.canSync(isEnabled: true, hasProAccess: false))
        XCTAssertFalse(CloudSyncAccessPolicy.canSync(isEnabled: false, hasProAccess: true))
        XCTAssertTrue(CloudSyncAccessPolicy.canSync(isEnabled: true, hasProAccess: true))
    }

    func testRemoteWinsWhenItIsNewerOrEqual() {
        let local = Date(timeIntervalSince1970: 100)

        XCTAssertFalse(
            CloudSyncMergePolicy.remoteWins(
                localUpdatedAt: local,
                remoteUpdatedAt: Date(timeIntervalSince1970: 99)
            )
        )
        XCTAssertTrue(
            CloudSyncMergePolicy.remoteWins(
                localUpdatedAt: local,
                remoteUpdatedAt: local
            )
        )
        XCTAssertTrue(
            CloudSyncMergePolicy.remoteWins(
                localUpdatedAt: local,
                remoteUpdatedAt: Date(timeIntervalSince1970: 101)
            )
        )
    }

    func testCloudLocatorJSONRoundTrips() throws {
        let locator = Locator(
            href: AnyURL(string: "chapter.xhtml")!,
            mediaType: .xhtml,
            locations: .init(progression: 0.25, totalProgression: 0.5)
        )

        let decoded = try XCTUnwrap(
            CloudSyncStore.decodeLocator(locator.jsonString())
        )

        XCTAssertEqual(decoded, locator)
    }

    func testPortableSourceURLConvertsLocalSandboxPathToRelative() {
        let staleLocalURL = "file:///var/mobile/Containers/Data/Application/E18C15C4-3C91-4495-BDF0-C2B1840A55B5/Documents/Statement_202607%201.pdf"
        let portable = CloudSyncStore.portableSourceURL(from: staleLocalURL)
        XCTAssertEqual(portable, "Statement_202607%201.pdf")
    }

    func testPortableSourceURLPreservesRelativeURL() {
        let relative = "MyBook.epub"
        let portable = CloudSyncStore.portableSourceURL(from: relative)
        XCTAssertEqual(portable, "MyBook.epub")
    }

    func testPortableSourceURLPreservesRemoteURL() {
        let remote = "https://example.com/books/sample.epub"
        let portable = CloudSyncStore.portableSourceURL(from: remote)
        XCTAssertEqual(portable, remote)
    }

    func testPortableSourceURLRejectsArbitraryLocalFileOutsideDocuments() {
        let nonDocLocal = "file:///private/var/tmp/temp_book.epub"
        let portable = CloudSyncStore.portableSourceURL(from: nonDocLocal)
        XCTAssertNil(portable)
    }

    func testReadingSessionSyncIdentifierUsesStableSessionIDWithoutChangingExistingTypes() {
        let sessionID = "9d8f5ec1-c442-49df-b53a-51df5f80e50a"
        let syncID = CloudSyncIdentifier.readingSession(sessionID: sessionID)

        XCTAssertEqual(syncID, "session-\(sessionID)")
        XCTAssertEqual(CloudSyncIdentifier.readingSessionID(from: syncID), sessionID)
        XCTAssertEqual(CloudSyncRecordType.book.rawValue, "Book")
        XCTAssertEqual(CloudSyncRecordType.progress.rawValue, "ReadingProgress")
        XCTAssertEqual(CloudSyncRecordType.bookmark.rawValue, "Bookmark")
        XCTAssertEqual(CloudSyncRecordType.highlight.rawValue, "Highlight")
        XCTAssertEqual(CloudSyncRecordType.readingSession.rawValue, "ReadingSession")
    }

    func testReadingSessionProjectionUsesStableIdentityAndDeleteSelfParent() async throws {
        let context = try makeCloudSyncTestContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }

        let bookID = try await addSyncBook(db: context.db, syncID: "book-parent")
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let sessionID = "stable-session"
        _ = try await ReadingSessionRepository(db: context.db).add(
            ReadingSession(
                sessionID: sessionID,
                bookId: bookID,
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(120),
                startProgression: 0.2,
                endProgression: 0.3,
                watchPageTurns: 7
            )
        )

        let pending = try await context.store.pendingChanges(limit: 20)
        let change = try XCTUnwrap(pending.first { $0.recordType == .readingSession })
        guard case .save = change.kind else {
            return XCTFail("ReadingSession should be projected as a save")
        }
        XCTAssertEqual(change.syncID, CloudSyncIdentifier.readingSession(sessionID: sessionID))

        let recordID = CKRecord.ID(recordName: change.syncID, zoneID: context.zoneID)
        let projected = try await context.store.record(for: recordID)
        let record = try XCTUnwrap(projected)
        XCTAssertEqual(record.recordType, CloudSyncRecordType.readingSession.rawValue)
        XCTAssertEqual(record["sessionID"] as? String, sessionID)
        XCTAssertEqual(record["bookSyncID"] as? String, "book-parent")
        XCTAssertEqual((record["durationSeconds"] as? NSNumber)?.intValue, 120)
        XCTAssertEqual((record["watchPageTurns"] as? NSNumber)?.intValue, 7)
        let parent = try XCTUnwrap(record["book"] as? CKRecord.Reference)
        XCTAssertEqual(parent.recordID.recordName, "book-parent")
        XCTAssertEqual(parent.action, .deleteSelf)
    }

    func testReadingSessionRemoteMergeDeduplicatesBySessionID() async throws {
        let context = try makeCloudSyncTestContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }

        let bookID = try await addSyncBook(db: context.db, syncID: "book-parent")
        let record = makeRemoteSessionRecord(
            sessionID: "dedup-session",
            bookSyncID: "book-parent",
            zoneID: context.zoneID
        )

        let firstLocalWins = try await context.store.applyRemoteRecord(record)
        let secondLocalWins = try await context.store.applyRemoteRecord(record)
        XCTAssertFalse(firstLocalWins)
        XCTAssertFalse(secondLocalWins)

        let sessions = try await ReadingSessionRepository(db: context.db).recent(limit: 10)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.sessionID, "dedup-session")
        XCTAssertEqual(sessions.first?.bookId, bookID)
        XCTAssertEqual(sessions.first?.needsSync, false)
    }

    func testReadingSessionDeferredParentReplaysAfterBookArrives() async throws {
        let context = try makeCloudSyncTestContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }

        let record = makeRemoteSessionRecord(
            sessionID: "deferred-session",
            bookSyncID: "book-late",
            zoneID: context.zoneID
        )
        let localWins = try await context.store.applyRemoteRecord(record)
        let countBeforeBook = try await ReadingSessionRepository(db: context.db).count()
        XCTAssertFalse(localWins)
        XCTAssertEqual(countBeforeBook, 0)

        let bookID = try await addSyncBook(db: context.db, syncID: "book-late")
        _ = try await context.store.replayDeferredRecords()

        let sessions = try await ReadingSessionRepository(db: context.db).recent(limit: 10)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.sessionID, "deferred-session")
        XCTAssertEqual(sessions.first?.bookId, bookID)
    }

    func testRemoteBookDeletionPurgesDeferredReadingSession() async throws {
        let context = try makeCloudSyncTestContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }

        let record = makeRemoteSessionRecord(
            sessionID: "orphan-session",
            bookSyncID: "book-deleted",
            zoneID: context.zoneID
        )
        _ = try await context.store.applyRemoteRecord(record)
        let countBeforeDeletion = try await ReadingSessionRepository(db: context.db).count()
        XCTAssertEqual(countBeforeDeletion, 0)

        try await context.store.applyRemoteDeletion(
            CKRecord.ID(recordName: "book-deleted", zoneID: context.zoneID)
        )
        _ = try await addSyncBook(db: context.db, syncID: "book-deleted")
        _ = try await context.store.replayDeferredRecords()

        let countAfterReplay = try await ReadingSessionRepository(db: context.db).count()
        XCTAssertEqual(countAfterReplay, 0)
    }

    func testDeletingBookCreatesReadingSessionTombstoneBeforeCascade() async throws {
        let context = try makeCloudSyncTestContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }

        let books = BookRepository(db: context.db)
        let bookID = try await addSyncBook(db: context.db, syncID: "book-delete")
        let startedAt = Date(timeIntervalSince1970: 4_000)
        let sessionID = "delete-session"
        _ = try await ReadingSessionRepository(db: context.db).add(
            ReadingSession(
                sessionID: sessionID,
                bookId: bookID,
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(60),
                startProgression: 0.1,
                endProgression: 0.2,
                watchPageTurns: 0
            )
        )

        try await books.remove(bookID)

        let count = try await ReadingSessionRepository(db: context.db).count()
        XCTAssertEqual(count, 0)
        let syncID = CloudSyncIdentifier.readingSession(sessionID: sessionID)
        let pending = try await context.store.pendingChanges(limit: 20)
        XCTAssertTrue(pending.contains { change in
            guard change.recordType == .readingSession, change.syncID == syncID else { return false }
            if case .delete = change.kind { return true }
            return false
        })
    }

    func testBookTombstonePreventsLateReadingSessionFromCreatingBrokenHistory() async throws {
        let context = try makeCloudSyncTestContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }

        let books = BookRepository(db: context.db)
        let bookID = try await addSyncBook(db: context.db, syncID: "book-tombstoned")
        try await books.remove(bookID)

        let record = makeRemoteSessionRecord(
            sessionID: "late-session",
            bookSyncID: "book-tombstoned",
            zoneID: context.zoneID
        )
        _ = try await context.store.applyRemoteRecord(record)

        let count = try await ReadingSessionRepository(db: context.db).count()
        XCTAssertEqual(count, 0)
        let sessionSyncID = CloudSyncIdentifier.readingSession(sessionID: "late-session")
        let pending = try await context.store.pendingChanges(limit: 20)
        XCTAssertTrue(pending.contains { change in
            guard change.recordType == .readingSession, change.syncID == sessionSyncID else { return false }
            if case .delete = change.kind { return true }
            return false
        })
    }

    func testReadingSessionOutboxDoesNotRegressExistingRecordTypes() async throws {
        let context = try makeCloudSyncTestContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }

        let books = BookRepository(db: context.db)
        let bookID = try await books.add(
            Book(
                identifier: UUID().uuidString,
                title: "Dirty",
                type: "application/epub+zip",
                url: AnyURL(string: "dirty.epub")!,
                syncID: "book-dirty"
            )
        )
        let locator = Locator(
            href: AnyURL(string: "chapter.xhtml")!,
            mediaType: .xhtml,
            locations: .init(progression: 0.25, totalProgression: 0.25)
        )
        _ = try await BookmarkRepository(db: context.db).add(
            Bookmark(bookId: bookID, locator: locator, syncID: "bookmark-dirty")
        )
        _ = try await HighlightRepository(db: context.db).add(
            Highlight(
                bookId: bookID,
                locator: locator,
                color: .yellow,
                syncID: "highlight-dirty"
            )
        )
        let startedAt = Date(timeIntervalSince1970: 5_000)
        _ = try await ReadingSessionRepository(db: context.db).add(
            ReadingSession(
                sessionID: "dirty-session",
                bookId: bookID,
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(30),
                startProgression: 0,
                endProgression: 0.01,
                watchPageTurns: 0
            )
        )

        let changes = try await context.store.pendingChanges(limit: 20)
        XCTAssertTrue(changes.contains { $0.recordType == .book })
        XCTAssertTrue(changes.contains { $0.recordType == .progress })
        XCTAssertTrue(changes.contains { $0.recordType == .bookmark })
        XCTAssertTrue(changes.contains { $0.recordType == .highlight })
        XCTAssertTrue(changes.contains { $0.recordType == .readingSession })
    }

    private func makeCloudSyncTestContext() throws -> (
        db: Database,
        store: CloudSyncStore,
        zoneID: CKRecordZone.ID,
        directory: URL
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudSyncSupportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let db = try Database(file: directory.appendingPathComponent("database.sqlite"))
        return (
            db,
            CloudSyncStore(db: db),
            CKRecordZone(zoneName: "CloudSyncSupportTests").zoneID,
            directory
        )
    }

    private func addSyncBook(db: Database, syncID: String) async throws -> Book.Id {
        try await BookRepository(db: db).add(
            Book(
                identifier: UUID().uuidString,
                title: "Synced",
                type: "application/epub+zip",
                url: AnyURL(string: "synced.epub")!,
                syncID: syncID,
                needsSync: false,
                contentNeedsSync: false
            )
        )
    }

    private func makeRemoteSessionRecord(
        sessionID: String,
        bookSyncID: String,
        zoneID: CKRecordZone.ID
    ) -> CKRecord {
        let record = CKRecord(
            recordType: CloudSyncRecordType.readingSession.rawValue,
            recordID: CKRecord.ID(
                recordName: CloudSyncIdentifier.readingSession(sessionID: sessionID),
                zoneID: zoneID
            )
        )
        let startedAt = Date(timeIntervalSince1970: 2_000)
        record["schemaVersion"] = Int64(1)
        record["sessionID"] = sessionID
        record["bookSyncID"] = bookSyncID
        record["book"] = CKRecord.Reference(
            recordID: CKRecord.ID(recordName: bookSyncID, zoneID: zoneID),
            action: .deleteSelf
        )
        record["startedAt"] = startedAt
        record["endedAt"] = startedAt.addingTimeInterval(120)
        record["durationSeconds"] = Int64(120)
        record["startProgression"] = 0.25
        record["endProgression"] = 0.35
        record["watchPageTurns"] = Int64(3)
        record["updatedAt"] = startedAt.addingTimeInterval(120)
        return record
    }

}
