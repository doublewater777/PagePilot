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

        let recentSessions = try await sessions.recent(limit: 1)
        let stored = try XCTUnwrap(recentSessions.first)
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
        let sessionCount = try await sessions.count()
        XCTAssertEqual(sessionCount, 0)
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
        let countBeforeDeletion = try await sessions.count()
        XCTAssertEqual(countBeforeDeletion, 1)

        try await books.remove(bookId)

        let countAfterDeletion = try await sessions.count()
        XCTAssertEqual(countAfterDeletion, 0)
    }

    func testRecentLimitPreservesNewestFirstOrdering() async throws {
        let bookId = try await addBook(title: "Limited")
        let base = Date(timeIntervalSince1970: 20_000)

        for offset in [0.0, 60.0, 120.0] {
            _ = try await sessions.add(
                ReadingSession(
                    bookId: bookId,
                    startedAt: base.addingTimeInterval(offset),
                    endedAt: base.addingTimeInterval(offset + 30),
                    startProgression: offset / 1_000,
                    endProgression: offset / 1_000 + 0.01,
                    watchPageTurns: Int(offset / 60)
                )
            )
        }

        let recentSessions = try await sessions.recent(for: bookId, limit: 2)

        XCTAssertEqual(recentSessions.count, 2)
        XCTAssertEqual(recentSessions.map(\.watchPageTurns), [2, 1])
    }

    func testDeletedBookHasNoPerBookHistoryRows() async throws {
        let bookId = try await addBook(title: "Deleted")
        let start = Date(timeIntervalSince1970: 30_000)

        _ = try await sessions.add(
            ReadingSession(
                bookId: bookId,
                startedAt: start,
                endedAt: start.addingTimeInterval(45),
                startProgression: 0.4,
                endProgression: 0.45,
                watchPageTurns: 0
            )
        )

        try await books.remove(bookId)

        let remainingSessions = try await sessions.recent(for: bookId, limit: 10)
        XCTAssertTrue(remainingSessions.isEmpty)
    }

    func testReadingHistoryAccessMatchesStatsEntitlement() {
        XCTAssertFalse(ReadingStatsScope.day.requiresPro)
        XCTAssertTrue(ReadingStatsScope.summary.requiresPro)
        XCTAssertFalse(ReadingHistoryAccess.canAccess(hasProAccess: false))
        XCTAssertTrue(ReadingHistoryAccess.canAccess(hasProAccess: true))
    }

    func testReadingHistoryUIIncludesRequiredStatesFactsAndAdaptiveLayout() throws {
        let source = try Self.source(named: "Sources/Home/ReadingStatsView.swift")
        guard let historyStart = source.range(of: "private struct ReadingHistoryView: View") else {
            return XCTFail("ReadingHistoryView is missing")
        }
        let historySource = String(source[historyStart.lowerBound...])

        XCTAssertTrue(historySource.contains("case .loading"))
        XCTAssertTrue(historySource.contains("case .empty"))
        XCTAssertTrue(historySource.contains("ProgressView()"))
        XCTAssertTrue(historySource.contains("ReadingHistoryView(book: item.book)"))
        XCTAssertTrue(historySource.contains("ReadingHistoryAccess.canAccess(hasProAccess: proPurchase.hasProAccess)"))
        XCTAssertTrue(historySource.contains(".frame(maxWidth: 680, alignment: .leading)"))
        XCTAssertTrue(historySource.contains("item.book.title"))
        XCTAssertTrue(historySource.contains("item.session.startedAt"))
        XCTAssertTrue(historySource.contains("item.session.durationSeconds"))
        XCTAssertTrue(historySource.contains("item.session.startProgression"))
        XCTAssertTrue(historySource.contains("item.session.endProgression"))
        XCTAssertTrue(historySource.contains("item.session.watchPageTurns"))
        XCTAssertFalse(historySource.contains("UIDevice.current"))
    }


    func testReadingPaceRequiresReliabilityThresholdsAndAcceptsExactBoundary() {
        let base = Date(timeIntervalSince1970: 100_000)

        let sparse = [
            makeSession(start: base, duration: 600, startProgress: 0.10, endProgress: 0.13),
            makeSession(start: base.addingTimeInterval(700), duration: 600, startProgress: 0.13, endProgress: 0.16),
        ]
        guard case .insufficientData = ReadingPaceCalculator.estimate(
            sessions: sparse,
            currentProgression: 0.16,
            now: base
        ) else {
            return XCTFail("Two sessions must remain below the reliability threshold")
        }

        let tooShort = [
            makeSession(start: base, duration: 399, startProgress: 0.10, endProgress: 0.12),
            makeSession(start: base.addingTimeInterval(500), duration: 399, startProgress: 0.12, endProgress: 0.14),
            makeSession(start: base.addingTimeInterval(1_000), duration: 399, startProgress: 0.14, endProgress: 0.16),
        ]
        guard case .insufficientData = ReadingPaceCalculator.estimate(
            sessions: tooShort,
            currentProgression: 0.16,
            now: base
        ) else {
            return XCTFail("Less than twenty active minutes must remain insufficient")
        }

        let tooLittleProgress = [
            makeSession(start: base, duration: 400, startProgress: 0.10, endProgress: 0.116),
            makeSession(start: base.addingTimeInterval(500), duration: 400, startProgress: 0.116, endProgress: 0.132),
            makeSession(start: base.addingTimeInterval(1_000), duration: 400, startProgress: 0.132, endProgress: 0.149),
        ]
        guard case .insufficientData = ReadingPaceCalculator.estimate(
            sessions: tooLittleProgress,
            currentProgression: 0.149,
            now: base
        ) else {
            return XCTFail("Less than five percentage points must remain insufficient")
        }

        let exactBoundary = [
            makeSession(start: base, duration: 400, startProgress: 0.10, endProgress: 0.12),
            makeSession(start: base.addingTimeInterval(500), duration: 400, startProgress: 0.12, endProgress: 0.14),
            makeSession(start: base.addingTimeInterval(1_000), duration: 400, startProgress: 0.14, endProgress: 0.15),
        ]
        guard case let .estimate(estimate) = ReadingPaceCalculator.estimate(
            sessions: exactBoundary,
            currentProgression: 0.50,
            now: base
        ) else {
            return XCTFail("Exact reliability thresholds should produce an estimate")
        }

        XCTAssertEqual(estimate.progressPerActiveMinute, 0.0025, accuracy: 0.000_001)
        XCTAssertEqual(estimate.remainingActiveMinutes, 200, accuracy: 0.001)
    }

    func testReadingPaceHandlesSlowAndFastHistories() {
        let base = Date(timeIntervalSince1970: 200_000)
        let slow = [
            makeSession(start: base, duration: 600, startProgress: 0.10, endProgress: 0.12),
            makeSession(start: base.addingTimeInterval(700), duration: 600, startProgress: 0.12, endProgress: 0.14),
            makeSession(start: base.addingTimeInterval(1_400), duration: 600, startProgress: 0.14, endProgress: 0.16),
        ]
        let fast = [
            makeSession(start: base, duration: 600, startProgress: 0.10, endProgress: 0.20),
            makeSession(start: base.addingTimeInterval(700), duration: 600, startProgress: 0.20, endProgress: 0.30),
            makeSession(start: base.addingTimeInterval(1_400), duration: 600, startProgress: 0.30, endProgress: 0.40),
        ]

        guard case let .estimate(slowEstimate) = ReadingPaceCalculator.estimate(
            sessions: slow,
            currentProgression: 0.50,
            now: base
        ) else {
            return XCTFail("Slow qualifying history should estimate")
        }
        guard case let .estimate(fastEstimate) = ReadingPaceCalculator.estimate(
            sessions: fast,
            currentProgression: 0.40,
            now: base
        ) else {
            return XCTFail("Fast qualifying history should estimate")
        }

        XCTAssertEqual(slowEstimate.progressPerActiveMinute, 0.002, accuracy: 0.000_001)
        XCTAssertEqual(slowEstimate.remainingActiveMinutes, 250, accuracy: 0.001)
        XCTAssertEqual(fastEstimate.progressPerActiveMinute, 0.01, accuracy: 0.000_001)
        XCTAssertEqual(fastEstimate.remainingActiveMinutes, 60, accuracy: 0.001)
    }

    func testBackwardAndNoProgressSessionsDoNotIncreaseForwardVelocity() {
        let base = Date(timeIntervalSince1970: 300_000)
        let forward = [
            makeSession(start: base, duration: 600, startProgress: 0.10, endProgress: 0.12),
            makeSession(start: base.addingTimeInterval(700), duration: 600, startProgress: 0.12, endProgress: 0.14),
            makeSession(start: base.addingTimeInterval(1_400), duration: 600, startProgress: 0.14, endProgress: 0.16),
        ]
        guard case let .estimate(baseline) = ReadingPaceCalculator.estimate(
            sessions: forward,
            currentProgression: 0.50,
            now: base
        ) else {
            return XCTFail("Baseline history should estimate")
        }

        let mixed = forward + [
            makeSession(
                start: base.addingTimeInterval(2_100),
                duration: 900,
                startProgress: 0.30,
                endProgress: 0.20
            ),
            makeSession(
                start: base.addingTimeInterval(3_100),
                duration: 900,
                startProgress: 0.20,
                endProgress: 0.20
            ),
        ]
        guard case let .estimate(mixedEstimate) = ReadingPaceCalculator.estimate(
            sessions: mixed,
            currentProgression: 0.50,
            now: base
        ) else {
            return XCTFail("Mixed history should still estimate")
        }

        XCTAssertEqual(
            mixedEstimate.progressPerActiveMinute,
            baseline.progressPerActiveMinute,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            mixedEstimate.remainingActiveMinutes,
            baseline.remainingActiveMinutes,
            accuracy: 0.001
        )
    }

    func testFinishDateRequiresRecentBehaviorAcrossThreeActiveDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 21, hour: 12)
        )!

        let sameDay = [
            makeSession(start: now.addingTimeInterval(-3_000), duration: 600, startProgress: 0.10, endProgress: 0.12),
            makeSession(start: now.addingTimeInterval(-2_000), duration: 600, startProgress: 0.12, endProgress: 0.14),
            makeSession(start: now.addingTimeInterval(-1_000), duration: 600, startProgress: 0.14, endProgress: 0.16),
        ]
        guard case let .estimate(sameDayEstimate) = ReadingPaceCalculator.estimate(
            sessions: sameDay,
            currentProgression: 0.50,
            now: now,
            calendar: calendar
        ) else {
            return XCTFail("Qualifying pace should still estimate without a finish date")
        }
        XCTAssertNil(sameDayEstimate.approximateFinishDate)

        let threeDays = [
            makeSession(
                start: calendar.date(byAdding: .day, value: -2, to: now)!,
                duration: 600,
                startProgress: 0.10,
                endProgress: 0.12
            ),
            makeSession(
                start: calendar.date(byAdding: .day, value: -1, to: now)!,
                duration: 600,
                startProgress: 0.12,
                endProgress: 0.14
            ),
            makeSession(
                start: now.addingTimeInterval(-1_000),
                duration: 600,
                startProgress: 0.14,
                endProgress: 0.16
            ),
        ]
        guard case let .estimate(threeDayEstimate) = ReadingPaceCalculator.estimate(
            sessions: threeDays,
            currentProgression: 0.50,
            now: now,
            calendar: calendar
        ) else {
            return XCTFail("Three-day qualifying history should estimate")
        }
        XCTAssertNotNil(threeDayEstimate.approximateFinishDate)
    }

    func testReadingPaceUIAndLocalizationContracts() throws {
        let statsSource = try Self.source(named: "Sources/Home/ReadingStatsView.swift")
        guard let historyStart = statsSource.range(of: "private struct ReadingHistoryView: View") else {
            return XCTFail("ReadingHistoryView is missing")
        }
        let historySource = String(statsSource[historyStart.lowerBound...])

        XCTAssertTrue(historySource.contains("ReadingPaceEstimateCard(result: paceResult)"))
        XCTAssertTrue(historySource.contains("ReadingPaceCalculator.estimate("))
        XCTAssertTrue(historySource.contains("currentProgression: currentBook.progression"))
        XCTAssertTrue(historySource.contains("reading_pace_estimate_title"))
        XCTAssertTrue(historySource.contains(".frame(maxWidth: 680)"))
        XCTAssertFalse(historySource.contains("UIDevice.current"))

        let localizationPaths = [
            "Sources/Resources/en.lproj/Localizable.strings",
            "Sources/Resources/zh-Hans.lproj/Localizable.strings",
            "Sources/Resources/es.lproj/Localizable.strings",
            "Sources/Resources/fr.lproj/Localizable.strings",
            "Sources/Resources/de.lproj/Localizable.strings",
        ]
        let requiredKeys = [
            "reading_pace_estimate_title",
            "reading_pace_insufficient_body",
            "reading_pace_remaining_format",
            "reading_pace_velocity_format",
            "reading_pace_finish_format",
            "reading_pace_estimate_basis",
        ]

        for path in localizationPaths {
            let strings = try Self.source(named: path)
            for key in requiredKeys {
                XCTAssertTrue(strings.contains("\"\(key)\""), "\(path) is missing \(key)")
            }
        }
    }

    private func makeSession(
        start: Date,
        duration: Int,
        startProgress: Double,
        endProgress: Double
    ) -> ReadingSession {
        ReadingSession(
            bookId: Book.Id(rawValue: 1),
            startedAt: start,
            endedAt: start.addingTimeInterval(TimeInterval(duration)),
            startProgression: startProgress,
            endProgression: endProgress,
            watchPageTurns: 0
        )
    }

    private static func source(named path: String) throws -> String {
        let repositoryURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryURL.appendingPathComponent(path),
            encoding: .utf8
        )
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
