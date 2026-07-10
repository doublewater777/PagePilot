import XCTest
@testable import PagePilot

final class ReadingGoalPolicyTests: XCTestCase {
    func testReachedExactlyAtGoal() {
        XCTAssertTrue(ReadingGoalPolicy.goalReached(todaySeconds: 30 * 60, goalMinutes: 30))
    }

    func testReachedAboveGoal() {
        XCTAssertTrue(ReadingGoalPolicy.goalReached(todaySeconds: 45 * 60, goalMinutes: 30))
    }

    func testBelowGoalNotReached() {
        XCTAssertFalse(ReadingGoalPolicy.goalReached(todaySeconds: 29 * 60, goalMinutes: 30))
    }

    func testZeroSecondsNotReached() {
        XCTAssertFalse(ReadingGoalPolicy.goalReached(todaySeconds: 0, goalMinutes: 30))
    }

    func testZeroGoalNeverReached() {
        XCTAssertFalse(ReadingGoalPolicy.goalReached(todaySeconds: 9999, goalMinutes: 0))
    }
}
