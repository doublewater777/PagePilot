import Combine
import ReadiumShared
import XCTest
@testable import PagePilot

final class HighlightRepositoryTests: XCTestCase {
    func testSavingHighlightWithNoteAndRetrievingIt() async throws {
        let db = try createDatabase()
        let repo = HighlightRepository(db: db)
        let bookId = try await createBook(in: db)

        let locator = Locator(
            href: AnyURL(string: "/test.xhtml")!,
            mediaType: .xhtml,
            locations: Locator.Locations(progression: 0.5, totalProgression: 0.5),
            text: Locator.Text(after: " after", before: "before ", highlight: "highlighted text")
        )
        let highlight = Highlight(
            bookId: bookId,
            locator: locator,
            color: HighlightColor.yellow,
            note: "This is my note about this passage."
        )

        let id = try await repo.add(highlight)
        let saved = try await highlighted(repo.highlight(for: id))
        XCTAssertEqual(saved.note, "This is my note about this passage.")
        XCTAssertEqual(saved.color, HighlightColor.yellow)
    }

    func testUpdatingHighlightNote() async throws {
        let db = try createDatabase()
        let repo = HighlightRepository(db: db)
        let bookId = try await createBook(in: db)

        let locator = Locator(
            href: AnyURL(string: "/test.xhtml")!,
            mediaType: .xhtml,
            locations: Locator.Locations(progression: 0.5, totalProgression: 0.5),
            text: Locator.Text(after: " after", before: "before ", highlight: "text")
        )
        let highlight = Highlight(bookId: bookId, locator: locator, color: HighlightColor.yellow)
        let id = try await repo.add(highlight)

        try await repo.update(id, note: "Updated note")
        let saved = try await highlighted(repo.highlight(for: id))
        XCTAssertEqual(saved.note, "Updated note")
    }

    // MARK: - Helpers

    private func createDatabase() throws -> Database {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("PagePilotTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let dbFile = tmp.appendingPathComponent("test.db")
        return try Database(file: dbFile)
    }

    private func createBook(in db: Database) async throws -> Book.Id {
        try await db.write { db in
            try Book(
                identifier: "test-\(UUID().uuidString)",
                title: "Test Book",
                authors: "Tester",
                type: "application/epub+zip",
                url: AnyURL(string: "https://example.com/book.epub")!
            ).insert(db)
            return Book.Id(rawValue: db.lastInsertedRowID)
        }
    }

    private func highlighted(_ publisher: AnyPublisher<Highlight, Error>) async throws -> Highlight {
        try await withCheckedThrowingContinuation { cont in
            var cancellable: AnyCancellable?
            cancellable = publisher.sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        cont.resume(throwing: error)
                    }
                    cancellable?.cancel()
                },
                receiveValue: { highlight in
                    cont.resume(returning: highlight)
                    cancellable?.cancel()
                }
            )
        }
    }
}
