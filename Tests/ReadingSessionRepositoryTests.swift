import ReadiumShared
import XCTest
@testable import PagePilot

final class ReadingSessionRepositoryTests: XCTestCase {
    private var db: PagePilot.Database!
    private var books: BookRepository!
    private var sessions: ReadingSessionRepository!
    private var tmpDir: URL!

    override func setUp() async throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PagePilotReadingSessionTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        db = try Database(file: tmpDir.appendingPathComponent("test.db"))
        books = BookRepository(db: db)
        sessions = ReadingSessionRepository(db: db)
    }

    override func tearDown() async throws {
        sessions = nil
        books = nil
        db = nil
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testSessionCapturesDurationProgressAndWatchTurns() async throws {
        let bookId = try await addBook(title: "One")
        let start = Date(timeIntervalSince1970: 1_000)
        let end = start.addingTimeInterval(125)

        let session = ReadingSession(
            bookId: bookId,
            startedAt: start,
            endedAt: end,
            startProgression: 0.2,
            endProgression: 0.35,
            watchPageTurns: 17
        )

        _ = try await sessions.add(session)

        let stored = try XCTUnwrap(try await sessions.recent(limit: 1).first)
        XCTAssertEqual(stored.bookId, bookId)
        XCTAssertEqual(stored.durationSeconds, 125)
        XCTAssertEqual(stored.startProgression, 0.2, accuracy: 0.0001)
        XCTAssertEqual(stored.endProgression, 0.35, accuracy: 0.0001)
        XCTAssertEqual(stored.progressDelta, 0.15, accuracy: 0.0001)
        XCTAssertEqual(stored.watchPageTurns, 17)
        XCTAssertFalse(stored.sessionID.isEmpty)
    }

    func testProgressAndWatchTurnsAreClamped() {
        let start = Date(timeIntervalSince1970: 1_000)
        let session = ReadingSession(
            bookId: Book.Id(rawValue: 1),
            startedAt: start,
            endedAt: start.addingTimeInterval(60),
            startProgression: -0.5,
            endProgression: 1.5,
            watchPageTurns: -3
        )

        XCTAssertEqual(session.startProgression, 0)
        XCTAssertEqual(session.endProgression, 1)
        XCTAssertEqual(session.progressDelta, 1)
        XCTAssertEqual(session.watchPageTurns, 0)
    }

    func testRecentSessionsAreNewestFirstAndFilterByBook() async throws {
        let firstBook = try await addBook(title: "First")
        let secondBook = try await addBook(title: "Second")
        let base = Date(timeIntervalSince1970: 10_000)

        _ = try await sessions.add(
            ReadingSession(
                bookId: firstBook,
                startedAt: base,
                endedAt: base.addingTimeInterval(60),
                startProgression: 0.1,
                endProgression: 0.2,
                watchPageTurns: 1
            )
        )
        _ = try await sessions.add(
            ReadingSession(
                bookId: secondBook,
                startedAt: base.addingTimeInterval(120),
                endedAt: base.addingTimeInterval(180),
                startProgression: 0.3,
                endProgression: 0.4,
                watchPageTurns: 2
            )
        )
        _ = try await sessions.add(
            ReadingSession(
                bookId: firstBook,
                startedAt: base.addingTimeInterval(240),
                endedAt: base.addingTimeInterval(300),
                startProgression: 0.2,
                endProgression: 0.25,
                watchPageTurns: 3
            )
        )

        let all = try await sessions.recent(limit: 10)
        XCTAssertEqual(all.map(\.bookId), [firstBook, secondBook, firstBook])
        XCTAssertEqual(all.map(\.watchPageTurns), [3, 2, 1])

        let firstBookSessions = try await sessions.recent(for: firstBook, limit: 10)
        XCTAssertEqual(firstBookSessions.count, 2)
        XCTAssertEqual(firstBookSessions.map(\.watchPageTurns), [3, 1])
    }

    func testZeroDurationSessionIsNotPersisted() async throws {
        let bookId = try await addBook(title: "Zero")
        let now = Date()

        let id = try await sessions.add(
            ReadingSession(
                bookId: bookId,
                startedAt: now,
                endedAt: now,
                startProgression: 0.2,
                endProgression: 0.2,
                watchPageTurns: 0
            )
        )

        XCTAssertNil(id)
        XCTAssertEqual(try await sessions.count(), 0)
    }

    func testDeletingBookCascadesReadingSessions() async throws {
        let bookId = try await addBook(title: "Cascade")
        let start = Date()

        _ = try await sessions.add(
            ReadingSession(
                bookId: bookId,
                startedAt: start,
                endedAt: start.addingTimeInterval(90),
                startProgression: 0,
                endProgression: 0.1,
                watchPageTurns: 4
            )
        )
        XCTAssertEqual(try await sessions.count(), 1)

        try await books.remove(bookId)

        XCTAssertEqual(try await sessions.count(), 0)
    }

    private func addBook(title: String) async throws -> Book.Id {
        try await books.add(
            Book(
                identifier: UUID().uuidString,
                title: title,
                type: "application/epub+zip",
                url: AnyURL(string: "/\(UUID().uuidString).epub")!
            )
        )
    }
}
