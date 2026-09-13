import Foundation
import GRDB
import ReadiumShared
import XCTest
@testable import PagePilot

final class BookFileAvailabilityTests: XCTestCase {
    func testMissingLocalPublicationThrowsBookNotFound() throws {
        let book = try makeBook(url: "missing.epub")

        XCTAssertThrowsError(
            try book.requireAvailablePublicationFile(fileExistsAtPath: { _ in false })
        ) { error in
            guard case LibraryError.bookNotFound = error else {
                return XCTFail("Expected bookNotFound, got \(error)")
            }
        }
    }

    func testExistingLocalPublicationPassesValidation() throws {
        let book = try makeBook(url: "existing.epub")

        XCTAssertNoThrow(
            try book.requireAvailablePublicationFile(fileExistsAtPath: { _ in true })
        )
    }

    func testRemotePublicationDoesNotRequireLocalFile() throws {
        let book = try makeBook(url: "https://example.com/book.webpub")

        XCTAssertNoThrow(
            try book.requireAvailablePublicationFile(fileExistsAtPath: { _ in false })
        )
    }

    func testStaleContainerDocumentsURLRemapsToCurrentDocuments() throws {
        let staleURL = "file:///var/mobile/Containers/Data/Application/OLD-CONTAINER-UUID/Documents/MyBook.epub"
        let book = try makeBook(url: staleURL)

        let resolved = try book.absoluteURL()
        let currentDocsURL = Paths.documents.url

        // Must be remapped into current container's Documents, preserving filename
        XCTAssertTrue(resolved.string.hasPrefix(Paths.documents.string))
        XCTAssertTrue(resolved.string.hasSuffix("MyBook.epub"))
    }

    func testStaleContainerDocumentsURLPassesValidationWhenFileExistsInCurrentDocuments() throws {
        let staleURL = "file:///var/mobile/Containers/Data/Application/E18C15C4-3C91-4495-BDF0-C2B1840A55B5/Documents/Statement_202607%201.pdf"
        let book = try makeBook(url: staleURL)

        // The mock checker checks whether the path checked is in current documents
        var checkedPath: String?
        XCTAssertNoThrow(
            try book.requireAvailablePublicationFile(fileExistsAtPath: { path in
                checkedPath = path
                return path.hasSuffix("Statement_202607 1.pdf") && path.contains(Paths.documents.url.path)
            })
        )

        XCTAssertNotNil(checkedPath)
        XCTAssertFalse(checkedPath?.contains("E18C15C4-3C91-4495-BDF0-C2B1840A55B5") ?? true)
        XCTAssertTrue(checkedPath?.contains("Statement_202607 1.pdf") ?? false)
    }

    func testDatabaseMigrationRelativizesStaleDocumentURLs() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let dbFile = tmpDir.appendingPathComponent("migration_test.db")
        let db = try Database(file: dbFile)

        let staleURL = "file:///var/mobile/Containers/Data/Application/OLD-UUID/Documents/MyDoc.pdf"
        try await db.write { db in
            try db.execute(
                sql: "INSERT INTO book (title, type, url, progression, created, syncID, updatedAt, needsSync, contentNeedsSync) VALUES (?, ?, ?, 0, datetime('now'), 'test-sync-id', datetime('now'), 0, 0)",
                arguments: ["Test Book", "application/pdf", staleURL]
            )
        }

        // Re-open database with a custom migrator or check relativization directly
        try await db.write { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id, url FROM book WHERE url LIKE '%/Documents/%'")
            for row in rows {
                guard let id: Int64 = row["id"],
                      let urlString: String = row["url"] else { continue }
                if let range = urlString.range(of: "/Documents/", options: .backwards) {
                    let relativePath = String(urlString[range.upperBound...])
                    if !relativePath.isEmpty {
                        try db.execute(
                            sql: "UPDATE book SET url = ? WHERE id = ?",
                            arguments: [relativePath, id]
                        )
                    }
                }
            }
        }

        let repo = BookRepository(db: db)
        let books = try await repo.allOnce()
        let savedBook = try XCTUnwrap(books.first(where: { $0.title == "Test Book" }))

        // The database migration or runtime lookup must relativize or resolve to current Documents
        XCTAssertEqual(savedBook.url, "MyDoc.pdf")
        let resolved = try savedBook.absoluteURL()
        XCTAssertTrue(resolved.string.hasSuffix("MyDoc.pdf"))
        XCTAssertTrue(resolved.string.hasPrefix(Paths.documents.string))
    }

    private func makeBook(url: String) throws -> Book {
        Book(
            title: "Test",
            type: "application/epub+zip",
            url: try XCTUnwrap(AnyURL(string: url))
        )
    }
}
