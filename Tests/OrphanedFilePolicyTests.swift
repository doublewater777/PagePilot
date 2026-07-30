import Foundation
import ReadiumShared
import XCTest
@testable import PagePilot

final class OrphanedFilePolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeBook(relativeURL: String, coverPath: String? = nil) throws -> Book {
        let anyURL = try XCTUnwrap(AnyURL(string: relativeURL))
        return Book(
            title: "Test",
            type: "application/epub+zip",
            url: anyURL,
            coverPath: coverPath
        )
    }

    func testReferencedFileIsNeverOrphan() throws {
        let book = try makeBook(relativeURL: "novel.epub")
        let referenced = OrphanedFilePolicy.referencedBookFileURLs(for: [book])
        let onDisk = Paths.documents.appendingPath("novel.epub", isDirectory: false).url

        XCTAssertFalse(
            OrphanedFilePolicy.isOrphan(
                fileURL: onDisk,
                referencedURLs: referenced,
                creationDate: now.addingTimeInterval(-7 * 24 * 3600),
                now: now
            )
        )
    }

    /// Regression: cleanup used to compare raw `Book.url` strings against
    /// `lastPathComponent`, so a stored `My%20Book.epub` never matched the
    /// on-disk `My Book.epub` and the book file was deleted.
    func testPercentEscapedRelativeURLMatchesLiteralFileName() throws {
        let book = try makeBook(relativeURL: "My%20Book.epub")
        let referenced = OrphanedFilePolicy.referencedBookFileURLs(for: [book])
        let onDisk = Paths.documents.appendingPath("My Book.epub", isDirectory: false).url

        XCTAssertTrue(referenced.contains(onDisk.standardizedFileURL))
        XCTAssertFalse(
            OrphanedFilePolicy.isOrphan(
                fileURL: onDisk,
                referencedURLs: referenced,
                creationDate: now.addingTimeInterval(-7 * 24 * 3600),
                now: now
            )
        )
    }

    func testUnicodeFileNameMatches() throws {
        // Book.url stores the percent-encoded relative path; the file on
        // disk uses the literal name.
        let fileName = "三体 (全三册) 📚.epub"
        let encoded = try XCTUnwrap(fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed))
        let book = try makeBook(relativeURL: encoded)
        let referenced = OrphanedFilePolicy.referencedBookFileURLs(for: [book])
        let onDisk = Paths.documents.appendingPath(fileName, isDirectory: false).url

        XCTAssertTrue(referenced.contains(onDisk.standardizedFileURL))
    }

    /// Regression: a freshly imported file sits in Documents/ before its
    /// database row exists. The grace period must protect it from cleanup.
    func testYoungUnreferencedFileIsProtectedByGracePeriod() {
        let candidate = URL(fileURLWithPath: "/tmp/just-imported.epub")

        XCTAssertFalse(
            OrphanedFilePolicy.isOrphan(
                fileURL: candidate,
                referencedURLs: [],
                creationDate: now.addingTimeInterval(-60),
                now: now
            )
        )
    }

    func testOldUnreferencedFileIsOrphan() {
        let candidate = URL(fileURLWithPath: "/tmp/ancient.epub")

        XCTAssertTrue(
            OrphanedFilePolicy.isOrphan(
                fileURL: candidate,
                referencedURLs: [],
                creationDate: now.addingTimeInterval(-48 * 3600),
                now: now
            )
        )
    }

    func testUnknownCreationDateIsTreatedAsOld() {
        let candidate = URL(fileURLWithPath: "/tmp/no-date.epub")

        XCTAssertTrue(
            OrphanedFilePolicy.isOrphan(
                fileURL: candidate,
                referencedURLs: [],
                creationDate: nil,
                now: now
            )
        )
    }

    func testReferencedCoverIsProtected() throws {
        let book = try makeBook(relativeURL: "novel.epub", coverPath: "cover-1.png")
        let referenced = OrphanedFilePolicy.referencedCoverURLs(for: [book])
        let onDisk = Paths.covers.appendingPath("cover-1.png", isDirectory: false).url

        XCTAssertTrue(referenced.contains(onDisk.standardizedFileURL))
    }
}
