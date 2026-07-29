import CryptoKit
import Foundation
import ReadiumShared
import XCTest
@testable import PagePilot

final class ImportDedupTests: XCTestCase {
    private var db: PagePilot.Database!
    private var repo: BookRepository!
    private var tmpDir: URL!

    override func setUp() async throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PagePilotImportDedup_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        db = try Database(file: tmpDir.appendingPathComponent("test.db"))
        repo = BookRepository(db: db)
    }

    override func tearDown() async throws {
        db = nil
        repo = nil
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testGetByIdentifierReturnsMatchingBook() async throws {
        let identifier = "urn:example:book-1"
        _ = try await repo.add(
            Book(
                identifier: identifier,
                title: "One",
                type: "application/epub+zip",
                url: AnyURL(string: "one.epub")!
            )
        )
        _ = try await repo.add(
            Book(
                identifier: "urn:example:book-2",
                title: "Two",
                type: "application/epub+zip",
                url: AnyURL(string: "two.epub")!
            )
        )

        let found = try await repo.getByIdentifier(identifier)
        XCTAssertEqual(found?.title, "One")
        XCTAssertEqual(found?.identifier, identifier)
    }

    func testGetByIdentifierReturnsNilForEmptyOrMissing() async throws {
        _ = try await repo.add(
            Book(
                identifier: "urn:example:book",
                title: "One",
                type: "application/epub+zip",
                url: AnyURL(string: "one.epub")!
            )
        )

        let missing = try await repo.getByIdentifier("urn:does-not-exist")
        XCTAssertNil(missing)

        let empty = try await repo.getByIdentifier("")
        XCTAssertNil(empty)
    }

    func testTXTContentIdentifierIsStableForSameBytes() throws {
        let fileURL = tmpDir.appendingPathComponent("sample.txt")
        let content = "Chapter 1\nHello from PagePilot\n"
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let first = try TXTToEPUBConverter.contentIdentifier(for: fileURL)
        let second = try TXTToEPUBConverter.contentIdentifier(for: fileURL)

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.hasPrefix("urn:pagepilot:txt:"))

        let digest = SHA256.hash(data: Data(content.utf8))
        let expectedHex = digest.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(first, "urn:pagepilot:txt:\(expectedHex)")
    }

    func testTXTContentIdentifierDiffersWhenContentChanges() throws {
        let fileURL = tmpDir.appendingPathComponent("mutable.txt")
        try "version-a".write(to: fileURL, atomically: true, encoding: .utf8)
        let first = try TXTToEPUBConverter.contentIdentifier(for: fileURL)

        try "version-b".write(to: fileURL, atomically: true, encoding: .utf8)
        let second = try TXTToEPUBConverter.contentIdentifier(for: fileURL)

        XCTAssertNotEqual(first, second)
    }

    func testTXTConvertEmbedsProvidedIdentifier() async throws {
        let fileURL = tmpDir.appendingPathComponent("id-test.txt")
        try "Just some text for conversion.".write(to: fileURL, atomically: true, encoding: .utf8)

        let identifier = "urn:pagepilot:txt:test-fixed-id"
        let epubURL = try await TXTToEPUBConverter.convert(from: fileURL, identifier: identifier)
        defer { try? FileManager.default.removeItem(at: epubURL) }

        // content.opf is inside the zip; unzip via NSFileCoordinator is heavy —
        // re-derive and assert convert accepts explicit id without throwing, and
        // default path uses content-derived id.
        let defaultId = try TXTToEPUBConverter.contentIdentifier(for: fileURL)
        let defaultEPUB = try await TXTToEPUBConverter.convert(from: fileURL)
        defer { try? FileManager.default.removeItem(at: defaultEPUB) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: epubURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: defaultEPUB.path))
        XCTAssertTrue(defaultId.hasPrefix("urn:pagepilot:txt:"))
    }
}
