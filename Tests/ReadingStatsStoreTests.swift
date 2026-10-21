import XCTest
@testable import PagePilot

final class ReadingStatsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var storageURL: URL!
    private var calendar: Calendar!

    override func setUpWithError() throws {
        try super.setUpWithError()

        defaults = UserDefaults(suiteName: "ReadingStatsStoreTests-\(UUID().uuidString)")!
        storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReadingStatsStoreTests-\(UUID().uuidString)")
            .appendingPathComponent("daily-stats-v1.json")
        calendar = Calendar(identifier: .gregorian)
    }

    override func tearDownWithError() throws {
        if let storageURL {
            try? FileManager.default.removeItem(at: storageURL.deletingLastPathComponent())
        }
        defaults = nil
        storageURL = nil
        calendar = nil

        try super.tearDownWithError()
    }

    func testEmptyStatsSnapshot() {
        let store = makeStore()

        XCTAssertEqual(store.snapshot(for: .summary, referenceDate: date(2026, 6, 4)).totalSeconds, 0)
        XCTAssertEqual(store.snapshot(for: .day, referenceDate: date(2026, 6, 4)).activeDays, 0)
        XCTAssertEqual(store.todayReadingSeconds(referenceDate: date(2026, 6, 4)), 0)
    }

    func testReadingSessionCrossingMidnightIsSplitAcrossDays() {
        let store = makeStore()

        store.recordReadingSession(
            startDate: date(2026, 6, 3, 23, 59, 30),
            endDate: date(2026, 6, 4, 0, 1, 0),
            bookId: Book.Id(rawValue: 1)
        )

        XCTAssertEqual(store.snapshot(for: .day, referenceDate: date(2026, 6, 3)).totalSeconds, 30)
        XCTAssertEqual(store.snapshot(for: .day, referenceDate: date(2026, 6, 4)).totalSeconds, 60)
        XCTAssertEqual(store.snapshot(for: .summary, referenceDate: date(2026, 6, 4)).activeDays, 2)
    }

    func testSingleDayAndMultiDayStats() {
        let store = makeStore()

        store.recordReadingSession(seconds: 120, bookId: Book.Id(rawValue: 1), date: date(2026, 6, 2))
        store.recordReadingSession(seconds: 180, bookId: Book.Id(rawValue: 2), date: date(2026, 6, 4))

        let singleDay = store.snapshot(for: .day, referenceDate: date(2026, 6, 2))
        XCTAssertEqual(singleDay.totalSeconds, 120)
        XCTAssertEqual(singleDay.distinctBooks, 1)

        let summary = store.snapshot(for: .summary, referenceDate: date(2026, 6, 4))
        XCTAssertEqual(summary.totalSeconds, 300)
        XCTAssertEqual(summary.activeDays, 2)
        XCTAssertEqual(summary.sessions, 2)
        XCTAssertEqual(summary.distinctBooks, 2)
    }

    func testCurrentStreakWhenUserReadToday() {
        let store = makeStore()
        store.recordReadingSession(seconds: 60, bookId: Book.Id(rawValue: 1), date: date(2026, 6, 3))
        store.recordReadingSession(seconds: 60, bookId: Book.Id(rawValue: 1), date: date(2026, 6, 4))
        XCTAssertEqual(store.snapshot(for: .summary, referenceDate: date(2026, 6, 4)).currentStreakDays, 2)
    }

    func testCurrentStreakWhenUserReadYesterday() {
        let store = makeStore()
        store.recordReadingSession(seconds: 60, bookId: Book.Id(rawValue: 1), date: date(2026, 6, 3))
        XCTAssertEqual(store.snapshot(for: .summary, referenceDate: date(2026, 6, 4)).currentStreakDays, 1)
    }

    func testCurrentStreakWhenUserReadNeither() {
        let store = makeStore()
        store.recordReadingSession(seconds: 60, bookId: Book.Id(rawValue: 1), date: date(2026, 6, 2))
        XCTAssertEqual(store.snapshot(for: .summary, referenceDate: date(2026, 6, 4)).currentStreakDays, 0)
    }

    func testWeekMonthYearAndSummarySnapshots() {
        let store = makeStore()

        store.recordReadingSession(seconds: 100, bookId: Book.Id(rawValue: 1), date: date(2026, 6, 1))
        store.recordReadingSession(seconds: 200, bookId: Book.Id(rawValue: 1), date: date(2026, 6, 4))
        store.recordReadingSession(seconds: 300, bookId: Book.Id(rawValue: 1), date: date(2026, 5, 28))
        store.recordReadingSession(seconds: 400, bookId: Book.Id(rawValue: 1), date: date(2025, 6, 4))

        XCTAssertEqual(store.snapshot(for: .week, referenceDate: date(2026, 6, 4)).totalSeconds, 300)
        XCTAssertEqual(store.snapshot(for: .month, referenceDate: date(2026, 6, 4)).totalSeconds, 300)
        XCTAssertEqual(store.snapshot(for: .year, referenceDate: date(2026, 6, 4)).totalSeconds, 600)
        XCTAssertEqual(store.snapshot(for: .summary, referenceDate: date(2026, 6, 4)).totalSeconds, 1_000)
    }

    func testPerBookAccumulatedReadingSeconds() {
        let store = makeStore()

        store.recordReadingSession(seconds: 100, bookId: Book.Id(rawValue: 1), date: date(2026, 6, 4))
        store.recordReadingSession(seconds: 80, bookId: Book.Id(rawValue: 1), date: date(2026, 6, 4))
        store.recordReadingSession(seconds: 60, bookId: Book.Id(rawValue: 2), date: date(2026, 6, 4))

        let stat = store.snapshot(for: .day, referenceDate: date(2026, 6, 4)).dailyStats.first
        XCTAssertEqual(stat?.bookSeconds?["1"], 180)
        XCTAssertEqual(stat?.bookSeconds?["2"], 60)
    }

    func testMigratesExistingUserDefaultsStatsOnce() throws {
        let oldStats = [
            "2026-06-04": DailyReadingStat(
                dateKey: "2026-06-04",
                seconds: 300,
                sessions: 1,
                bookIds: ["1"],
                bookSeconds: ["1": 300]
            ),
        ]
        defaults.set(try JSONEncoder().encode(oldStats), forKey: "readingStats_dailyStats")

        let store = makeStore()

        XCTAssertEqual(store.snapshot(for: .day, referenceDate: date(2026, 6, 4)).totalSeconds, 300)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageURL.path))
    }

    func testBadgeCalculations() {
        let store = makeStore()

        // 1. Record morning reading (6:00 AM) on 5 different days
        store.recordReadingSession(seconds: 100, bookId: Book.Id(rawValue: 1), date: date(2026, 6, 1, 6, 0, 0))
        store.recordReadingSession(seconds: 100, bookId: Book.Id(rawValue: 1), date: date(2026, 6, 2, 7, 0, 0))
        store.recordReadingSession(seconds: 100, bookId: Book.Id(rawValue: 1), date: date(2026, 6, 3, 8, 0, 0))
        store.recordReadingSession(seconds: 100, bookId: Book.Id(rawValue: 1), date: date(2026, 6, 4, 5, 30, 0))
        store.recordReadingSession(seconds: 100, bookId: Book.Id(rawValue: 1), date: date(2026, 6, 5, 6, 15, 0))

        // 2. Record night reading (11:00 PM) on 2 different days
        store.recordReadingSession(seconds: 100, bookId: Book.Id(rawValue: 1), date: date(2026, 6, 1, 23, 0, 0))
        store.recordReadingSession(seconds: 100, bookId: Book.Id(rawValue: 1), date: date(2026, 6, 2, 22, 15, 0))

        // 3. Record deep reading session on 1 day (seconds: 2800 >= 2700)
        store.recordReadingSession(seconds: 2800, bookId: Book.Id(rawValue: 1), date: date(2026, 6, 5, 12, 0, 0))

        // 4. Record 3 distinct books (bookId: 1, 2, 3)
        store.recordReadingSession(seconds: 60, bookId: Book.Id(rawValue: 2), date: date(2026, 6, 6))
        store.recordReadingSession(seconds: 60, bookId: Book.Id(rawValue: 3), date: date(2026, 6, 7))

        let snapshot = store.snapshot(for: .summary, referenceDate: date(2026, 6, 7))
        let badges = snapshot.badges

        // Verify Early Bird (unlocked)
        let earlyBird = badges.first { $0.id == "early_bird" }
        XCTAssertNotNil(earlyBird)
        XCTAssertEqual(earlyBird?.isUnlocked, true)
        XCTAssertEqual(earlyBird?.progress, 1.0)
        XCTAssertEqual(earlyBird?.currentValue, 5)

        // Verify Night Owl (locked, 2/5)
        let nightOwl = badges.first { $0.id == "night_owl" }
        XCTAssertNotNil(nightOwl)
        XCTAssertEqual(nightOwl?.isUnlocked, false)
        XCTAssertEqual(nightOwl?.progress, 0.4)
        XCTAssertEqual(nightOwl?.currentValue, 2)

        // Verify Deep Reader (unlocked, max daily > 2700)
        let deepReader = badges.first { $0.id == "deep_reader" }
        XCTAssertNotNil(deepReader)
        XCTAssertEqual(deepReader?.isUnlocked, true)
        XCTAssertEqual(deepReader?.progress, 1.0)

        // Verify Book Collector (unlocked, 3 books)
        let collector = badges.first { $0.id == "book_collector" }
        XCTAssertNotNil(collector)
        XCTAssertEqual(collector?.isUnlocked, true)
        XCTAssertEqual(collector?.progress, 1.0)
        XCTAssertEqual(collector?.currentValue, 3)
    }

    func testCheckpointsAreIdempotentAndSurviveStoreRecreation() {
        let book = Book.Id(rawValue: 1)
        let startedAt = date(2026, 6, 4, 10, 0, 0)
        let sessionID = "checkpoint-recovery-1"
        let store = makeStore()

        store.recordReadingCheckpoint(sessionID: sessionID, startedAt: startedAt, elapsedSeconds: 15, recordedAt: startedAt.addingTimeInterval(15), bookId: book)
        store.recordReadingCheckpoint(sessionID: sessionID, startedAt: startedAt, elapsedSeconds: 15, recordedAt: startedAt.addingTimeInterval(15), bookId: book)
        store.recordReadingCheckpoint(sessionID: sessionID, startedAt: startedAt, elapsedSeconds: 30, recordedAt: startedAt.addingTimeInterval(30), bookId: book)
        store.recordReadingCheckpoint(sessionID: sessionID, startedAt: startedAt, elapsedSeconds: 12, recordedAt: startedAt.addingTimeInterval(12), bookId: book)

        let original = store.snapshot(for: .day, referenceDate: startedAt)
        XCTAssertEqual(original.totalSeconds, 30)
        XCTAssertEqual(original.sessions, 1)
        XCTAssertEqual(original.dailyStats.first?.bookSeconds?["1"], 30)

        // Simulate a fresh launch: only already committed time can be restored.
        let relaunched = makeStore()
        relaunched.recordReadingCheckpoint(sessionID: sessionID, startedAt: startedAt, elapsedSeconds: 30, recordedAt: startedAt.addingTimeInterval(30), bookId: book)
        XCTAssertEqual(relaunched.todayReadingSeconds(referenceDate: startedAt), 30)

        relaunched.recordReadingCheckpoint(sessionID: sessionID, startedAt: startedAt, elapsedSeconds: 45, recordedAt: startedAt.addingTimeInterval(45), bookId: book)
        XCTAssertEqual(relaunched.todayReadingSeconds(referenceDate: startedAt), 45)
        XCTAssertEqual(relaunched.snapshot(for: .day, referenceDate: startedAt).sessions, 1)
    }

    func testCheckpointsSplitMidnightAndDoNotInflateSessionCount() {
        let startedAt = date(2026, 6, 3, 23, 59, 30)
        let book = Book.Id(rawValue: 2)
        let store = makeStore()

        store.recordReadingCheckpoint(sessionID: "midnight", startedAt: startedAt, elapsedSeconds: 20, recordedAt: startedAt.addingTimeInterval(20), bookId: book)
        store.recordReadingCheckpoint(sessionID: "midnight", startedAt: startedAt, elapsedSeconds: 90, recordedAt: startedAt.addingTimeInterval(90), bookId: book)
        store.recordReadingCheckpoint(sessionID: "midnight", startedAt: startedAt, elapsedSeconds: 120, recordedAt: startedAt.addingTimeInterval(120), bookId: book)

        let yesterday = store.snapshot(for: .day, referenceDate: date(2026, 6, 3))
        let today = store.snapshot(for: .day, referenceDate: date(2026, 6, 4))
        XCTAssertEqual(yesterday.totalSeconds, 30)
        XCTAssertEqual(today.totalSeconds, 90)
        XCTAssertEqual(yesterday.sessions, 1)
        XCTAssertEqual(today.sessions, 1)
        XCTAssertEqual(yesterday.dailyStats.first?.hourlySeconds?[23], 30)
        XCTAssertEqual(today.dailyStats.first?.hourlySeconds?[0], 90)
    }

    func testCheckpointSplitsAcrossHoursWithoutDoubleCountingDays() {
        let startedAt = date(2026, 6, 4, 10, 59, 45)
        let store = makeStore()
        let book = Book.Id(rawValue: 3)

        store.recordReadingCheckpoint(sessionID: "hourly", startedAt: startedAt, elapsedSeconds: 45, recordedAt: startedAt.addingTimeInterval(45), bookId: book)
        store.recordReadingCheckpoint(sessionID: "hourly", startedAt: startedAt, elapsedSeconds: 75, recordedAt: startedAt.addingTimeInterval(75), bookId: book)

        let stats = store.snapshot(for: .day, referenceDate: startedAt)
        XCTAssertEqual(stats.totalSeconds, 75)
        XCTAssertEqual(stats.sessions, 1)
        XCTAssertEqual(stats.dailyStats.first?.hourlySeconds?[10], 15)
        XCTAssertEqual(stats.dailyStats.first?.hourlySeconds?[11], 60)
    }

    func testExistingLegacyTotalsRemainAfterFirstCheckpoint() {
        let startedAt = date(2026, 6, 4, 12, 0, 0)
        let store = makeStore()

        store.recordReadingSession(seconds: 120, bookId: Book.Id(rawValue: 4), date: startedAt)
        store.recordReadingCheckpoint(sessionID: "new-session", startedAt: startedAt, elapsedSeconds: 15, recordedAt: startedAt.addingTimeInterval(15), bookId: Book.Id(rawValue: 4))
        let snapshot = store.snapshot(for: .day, referenceDate: startedAt)
        XCTAssertEqual(snapshot.totalSeconds, 135)
        XCTAssertEqual(snapshot.sessions, 2)
    }


    func testProcessKilledAtSecond44RestoresOnlyCommitted30Seconds() {
        let startedAt = date(2026, 6, 4, 12, 0, 0)
        let book = Book.Id(rawValue: 17)
        let store = makeStore()

        for elapsed in [15, 30] {
            XCTAssertTrue(store.recordReadingCheckpoint(
                sessionID: "interrupted",
                startedAt: startedAt,
                elapsedSeconds: elapsed,
                recordedAt: startedAt.addingTimeInterval(TimeInterval(elapsed)),
                bookId: book
            ))
        }
        // No final commit at second 44: simulate a killed process by dropping
        // the original store and reading the same file from a fresh instance.
        let restarted = makeStore()
        XCTAssertEqual(restarted.todayReadingSeconds(referenceDate: startedAt), 30)
        XCTAssertEqual(restarted.snapshot(for: .day, referenceDate: startedAt).sessions, 1)
        // An already committed cursor can be replayed without duplication.
        XCTAssertTrue(restarted.recordReadingCheckpoint(
            sessionID: "interrupted",
            startedAt: startedAt,
            elapsedSeconds: 30,
            recordedAt: startedAt.addingTimeInterval(30),
            bookId: book
        ))
        XCTAssertEqual(restarted.todayReadingSeconds(referenceDate: startedAt), 30)
    }

    func testConcurrentWritersNeverLoseSecondsOrCursors() {
        let start = date(2026, 6, 4, 13, 0, 0)
        let store = makeStore()
        let first = Book.Id(rawValue: 11)
        let second = Book.Id(rawValue: 12)
        let group = DispatchGroup()
        let workQueue = DispatchQueue(label: "ReadingStatsStoreTests.concurrent", attributes: .concurrent)

        for id in 0..<2 {
            group.enter()
            workQueue.async {
                for elapsed in [15, 30, 45, 60] {
                    let success = store.recordReadingCheckpoint(
                        sessionID: "concurrent-\(id)",
                        startedAt: start,
                        elapsedSeconds: elapsed,
                        recordedAt: start.addingTimeInterval(TimeInterval(elapsed)),
                        bookId: id == 0 ? first : second
                    )
                    XCTAssertTrue(success)
                }
                group.leave()
            }
        }
        group.wait()
        XCTAssertEqual(store.todayReadingSeconds(referenceDate: start), 120)
        let day = store.snapshot(for: .day, referenceDate: start)
        XCTAssertEqual(day.sessions, 2)
        XCTAssertEqual(day.dailyStats.first?.bookSeconds?["11"], 60)
        XCTAssertEqual(day.dailyStats.first?.bookSeconds?["12"], 60)

        // Even independent instances share a process-wide single writer.
        let secondInstance = makeStore()
        XCTAssertTrue(secondInstance.recordReadingCheckpoint(
            sessionID: "concurrent-0", startedAt: start, elapsedSeconds: 75,
            recordedAt: start.addingTimeInterval(75), bookId: first
        ))
        XCTAssertEqual(store.todayReadingSeconds(referenceDate: start), 135)
    }

    func testFailedWriteCanBeRetriedWithoutAdvancingCursor() throws {
        let root = storageURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // A directory cannot be atomically replaced by a JSON file.
        try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
        let start = date(2026, 6, 4, 12, 0, 0)
        let store = makeStore()
        XCTAssertFalse(store.recordReadingCheckpoint(
            sessionID: "retry", startedAt: start, elapsedSeconds: 15,
            recordedAt: start.addingTimeInterval(15), bookId: Book.Id(rawValue: 5)
        ))
        XCTAssertEqual(store.todayReadingSeconds(referenceDate: start), 0)
        try FileManager.default.removeItem(at: storageURL)
        XCTAssertTrue(store.recordReadingCheckpoint(
            sessionID: "retry", startedAt: start, elapsedSeconds: 15,
            recordedAt: start.addingTimeInterval(15), bookId: Book.Id(rawValue: 5)
        ))
        XCTAssertEqual(store.todayReadingSeconds(referenceDate: start), 15)
    }

    func testEncoderFailureDoesNotEmitStoredCursor() {
        enum SyntheticEncodingError: Error { case rejected }
        let start = date(2026, 6, 4, 12, 0, 0)
        let failing = ReadingStatsStore(
            defaults: defaults, calendar: calendar, storageURL: storageURL,
            encodeStats: { _ in throw SyntheticEncodingError.rejected }
        )
        XCTAssertFalse(failing.recordReadingCheckpoint(
            sessionID: "encode", startedAt: start, elapsedSeconds: 15,
            recordedAt: start.addingTimeInterval(15), bookId: Book.Id(rawValue: 5)
        ))
        XCTAssertEqual(makeStore().todayReadingSeconds(referenceDate: start), 0)
        XCTAssertTrue(makeStore().recordReadingCheckpoint(
            sessionID: "encode", startedAt: start, elapsedSeconds: 15,
            recordedAt: start.addingTimeInterval(15), bookId: Book.Id(rawValue: 5)
        ))
        XCTAssertEqual(makeStore().todayReadingSeconds(referenceDate: start), 15)
    }

    func testClockMovesBackwardsAcrossMidnightWithoutFabricatedNextDay() {
        let start = date(2026, 6, 4, 23, 59, 50)
        let store = makeStore()
        let book = Book.Id(rawValue: 1)
        // After 20 monotonic seconds, the wall clock is an hour earlier.
        XCTAssertTrue(store.recordReadingCheckpoint(
            sessionID: "backwards", startedAt: start, elapsedSeconds: 20,
            recordedAt: date(2026, 6, 4, 23, 0, 10), bookId: book
        ))
        XCTAssertEqual(store.snapshot(for: .day, referenceDate: date(2026, 6, 4)).totalSeconds, 20)
        XCTAssertEqual(store.snapshot(for: .day, referenceDate: date(2026, 6, 5)).totalSeconds, 0)
        XCTAssertEqual(store.snapshot(for: .day, referenceDate: start).sessions, 1)
    }

    func testClockMovesForwardAcrossMidnightUsingObservedCheckpointDay() {
        let start = date(2026, 6, 4, 22, 59, 50)
        let store = makeStore()
        // At 20s, the real wall clock is 00:00:10 after a +1h jump.
        XCTAssertTrue(store.recordReadingCheckpoint(
            sessionID: "forwards", startedAt: start, elapsedSeconds: 20,
            recordedAt: date(2026, 6, 5, 0, 0, 10), bookId: Book.Id(rawValue: 1)
        ))
        XCTAssertEqual(store.snapshot(for: .day, referenceDate: date(2026, 6, 4)).totalSeconds, 0)
        XCTAssertEqual(store.snapshot(for: .day, referenceDate: date(2026, 6, 5)).totalSeconds, 20)
    }

    func testRepeatedCrossMidnightCheckpointKeepsOnlyOneSessionPerDay() {
        let start = date(2026, 6, 3, 23, 59, 45)
        let store = makeStore()
        for elapsed in [10, 20, 30, 40, 45, 45, 60] {
            XCTAssertTrue(store.recordReadingCheckpoint(
                sessionID: "multi-midnight", startedAt: start, elapsedSeconds: elapsed,
                recordedAt: start.addingTimeInterval(TimeInterval(elapsed)),
                bookId: Book.Id(rawValue: 1)
            ))
        }
        XCTAssertEqual(store.snapshot(for: .day, referenceDate: date(2026, 6, 3)).totalSeconds, 15)
        XCTAssertEqual(store.snapshot(for: .day, referenceDate: date(2026, 6, 4)).totalSeconds, 45)
        XCTAssertEqual(store.snapshot(for: .day, referenceDate: date(2026, 6, 3)).sessions, 1)
        XCTAssertEqual(store.snapshot(for: .day, referenceDate: date(2026, 6, 4)).sessions, 1)
    }

    func testDaylightSavingTransitionsAndNonHourOffsetZone() {
        let book = Book.Id(rawValue: 5)
        for zoneName in ["America/Los_Angeles", "Asia/Kathmandu"] {
            var configured = Calendar(identifier: .gregorian)
            configured.timeZone = TimeZone(identifier: zoneName)!
            let path = FileManager.default.temporaryDirectory
                .appendingPathComponent("ReadingStatsDST-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: path) }
            let store = ReadingStatsStore(defaults: defaults, calendar: configured, storageURL: path)
            let transitions: [Date]
            if zoneName == "America/Los_Angeles" {
                transitions = [
                    ISO8601DateFormatter().date(from: "2026-03-08T09:59:30Z")!,
                    ISO8601DateFormatter().date(from: "2026-11-01T08:59:30Z")!
                ]
            } else {
                transitions = [ISO8601DateFormatter().date(from: "2026-06-04T18:14:30Z")!]
            }
            for (index, start) in transitions.enumerated() {
                let id = "transition-\(index)"
                for elapsed in [30, 60, 90, 120] {
                    XCTAssertTrue(store.recordReadingCheckpoint(
                        sessionID: id, startedAt: start, elapsedSeconds: elapsed,
                        recordedAt: start.addingTimeInterval(TimeInterval(elapsed)), bookId: book
                    ))
                }
            }
            XCTAssertEqual(store.snapshot(for: .summary).totalSeconds, transitions.count * 120)
            XCTAssertEqual(store.snapshot(for: .summary).sessions, transitions.count + (zoneName == "Asia/Kathmandu" ? 1 : 0))
        }
    }

    private func makeStore() -> ReadingStatsStore {
        ReadingStatsStore(defaults: defaults, calendar: calendar, storageURL: storageURL)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, _ second: Int = 0) -> Date {
        DateComponents(
            calendar: calendar,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        ).date!
    }
}
