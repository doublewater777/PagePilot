import Foundation
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

    private func makeBook(url: String) throws -> Book {
        Book(
            title: "Test",
            type: "application/epub+zip",
            url: try XCTUnwrap(AnyURL(string: url))
        )
    }
}
