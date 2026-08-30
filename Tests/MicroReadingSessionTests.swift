import XCTest
@testable import PagePilot

final class MicroReadingSessionTests: XCTestCase {
    func testSupportedDurations() {
        XCTAssertEqual(MicroReadingPolicy.supportedMinutes, [3, 5, 10])
        XCTAssertEqual(MicroReadingPolicy.duration(forMinutes: 3), 180)
        XCTAssertEqual(MicroReadingPolicy.duration(forMinutes: 5), 300)
        XCTAssertEqual(MicroReadingPolicy.duration(forMinutes: 10), 600)
    }

    func testUnsupportedDurationIsRejected() {
        XCTAssertNil(MicroReadingPolicy.duration(forMinutes: 0))
        XCTAssertNil(MicroReadingPolicy.duration(forMinutes: 7))
        XCTAssertNil(MicroReadingPolicy.duration(forMinutes: 60))
    }

    func testLaunchStoreConsumesOnlyMatchingBook() async {
        let firstBook = Book.Id(rawValue: 1)
        let secondBook = Book.Id(rawValue: 2)
        let now = Date(timeIntervalSince1970: 1_000)

        await MainActor.run {
            MicroReadingLaunchStore.clear()
            MicroReadingLaunchStore.prepare(bookId: firstBook, minutes: 5, now: now)

            XCTAssertNil(
                MicroReadingLaunchStore.consume(for: secondBook, now: now)
            )

            let session = MicroReadingLaunchStore.consume(for: firstBook, now: now)
            XCTAssertEqual(session?.bookId, firstBook)
            XCTAssertEqual(session?.duration, 300)
            XCTAssertNil(MicroReadingLaunchStore.consume(for: firstBook, now: now))
        }
    }

    func testLaunchStoreExpiresStaleSession() async {
        let book = Book.Id(rawValue: 1)
        let createdAt = Date(timeIntervalSince1970: 1_000)

        await MainActor.run {
            MicroReadingLaunchStore.clear()
            MicroReadingLaunchStore.prepare(bookId: book, minutes: 3, now: createdAt)

            XCTAssertNil(
                MicroReadingLaunchStore.consume(
                    for: book,
                    now: createdAt.addingTimeInterval(61)
                )
            )
        }
    }

    func testCountdownExcludesTimeWhilePaused() {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        var countdown = MicroReadingCountdown(duration: 180)

        countdown.resume(at: startedAt)
        countdown.pause(at: startedAt.addingTimeInterval(45))

        XCTAssertEqual(countdown.remaining(at: startedAt.addingTimeInterval(145)), 135)

        countdown.resume(at: startedAt.addingTimeInterval(145))
        XCTAssertEqual(countdown.remaining(at: startedAt.addingTimeInterval(160)), 120)
    }

    func testCountdownClampsAtZero() {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        var countdown = MicroReadingCountdown(duration: 3)

        countdown.resume(at: startedAt)

        XCTAssertTrue(countdown.isComplete(at: startedAt.addingTimeInterval(4)))
    }

    func testCountdownTextRoundsUpToAvoidShowingZeroEarly() {
        XCTAssertEqual(MicroReadingPolicy.countdownText(remaining: 59.1), "1:00")
        XCTAssertEqual(MicroReadingPolicy.countdownText(remaining: 0), "0:00")
    }
}
