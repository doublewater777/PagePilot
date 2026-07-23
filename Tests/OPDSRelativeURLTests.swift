import XCTest
@testable import PagePilot

final class OPDSRelativeURLTests: XCTestCase {
    func testRelativeNextLinkResolvesAgainstCurrentPageURL() {
        let pageURL = URL(string: "https://catalog.example.org/opds/page/1")!
        let relativeNext = URL(string: "page/2", relativeTo: pageURL)?.absoluteURL
        XCTAssertEqual(relativeNext?.absoluteString, "https://catalog.example.org/opds/page/page/2")
    }

    func testQueryStringNextLinkResolvesAgainstCurrentPageURL() {
        let pageURL = URL(string: "https://catalog.example.org/opds?category=fiction")!
        let relativeNext = URL(string: "?page=2", relativeTo: pageURL)?.absoluteURL
        XCTAssertEqual(relativeNext?.absoluteString, "https://catalog.example.org/opds?page=2")
    }

    func testAbsolutePathNextLinkResolvesAgainstCurrentPageURL() {
        let pageURL = URL(string: "https://catalog.example.org/opds/page/1")!
        let relativeNext = URL(string: "/opds/page/2", relativeTo: pageURL)?.absoluteURL
        XCTAssertEqual(relativeNext?.absoluteString, "https://catalog.example.org/opds/page/2")
    }

    func testParentRelativeNextLinkResolvesAgainstCurrentPageURL() {
        let pageURL = URL(string: "https://catalog.example.org/opds/catalog?page=1")!
        let relativeNext = URL(string: "../catalog?page=2", relativeTo: pageURL)?.absoluteURL
        // RFC 3986: ".." resolves against the path segment, which is "/opds/catalog"
        // -> removes "catalog" -> "/opds/" + "../catalog" -> "/catalog"
        XCTAssertEqual(relativeNext?.absoluteString, "https://catalog.example.org/catalog?page=2")
    }

    func testAbsoluteNextLinkIsUnchanged() {
        let pageURL = URL(string: "https://catalog.example.org/opds/page/1")!
        let absoluteNext = URL(string: "https://other.example.org/feed?page=2", relativeTo: pageURL)?.absoluteURL
        XCTAssertEqual(absoluteNext?.absoluteString, "https://other.example.org/feed?page=2")
    }

    func testRelativeThumbnailLinkResolvesAgainstCurrentPageURL() {
        let pageURL = URL(string: "https://catalog.example.org/opds/page/2")!
        let thumb = URL(string: "/covers/123.jpg", relativeTo: pageURL)?.absoluteURL
        XCTAssertEqual(thumb?.absoluteString, "https://catalog.example.org/covers/123.jpg")
    }

    func testRelativeDownloadLinkResolvesAgainstCurrentPageURL() {
        let pageURL = URL(string: "https://catalog.example.org/opds?page=3")!
        let download = URL(string: "downloads/book.epub", relativeTo: pageURL)?.absoluteURL
        // "downloads/book.epub" resolves against path "/opds" -> "/downloads/book.epub"
        XCTAssertEqual(download?.absoluteString, "https://catalog.example.org/downloads/book.epub")
    }
}
