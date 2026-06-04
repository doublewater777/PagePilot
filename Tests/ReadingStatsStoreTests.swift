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

    func testCurrentStreakWhenUserReadTodayYesterdayOrNeither() {
        let readToday = makeStore()
        readToday.recordReadingSession(seconds: 60, bookId: Book.Id(rawValue: 1), date: date(2026, 6, 3))
        readToday.recordReadingSession(seconds: 60, bookId: Book.Id(rawValue: 1), date: date(2026, 6, 4))
        XCTAssertEqual(readToday.snapshot(for: .summary, referenceDate: date(2026, 6, 4)).currentStreakDays, 2)

        let readYesterday = makeStore()
        readYesterday.recordReadingSession(seconds: 60, bookId: Book.Id(rawValue: 1), date: date(2026, 6, 3))
        XCTAssertEqual(readYesterday.snapshot(for: .summary, referenceDate: date(2026, 6, 4)).currentStreakDays, 1)

        let readNeither = makeStore()
        readNeither.recordReadingSession(seconds: 60, bookId: Book.Id(rawValue: 1), date: date(2026, 6, 2))
        XCTAssertEqual(readNeither.snapshot(for: .summary, referenceDate: date(2026, 6, 4)).currentStreakDays, 0)
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
