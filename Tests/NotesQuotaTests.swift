import XCTest
@testable import PagePilot

final class NotesQuotaTests: XCTestCase {
    func testFreeUserCanAddWhenUnderLimit() {
        let decision = NotesQuota.evaluateAdd(
            currentCount: 0,
            hasProAccess: false
        )
        XCTAssertEqual(decision, .allow)
    }

    func testFreeUserIsBlockedAtLimit() {
        let decision = NotesQuota.evaluateAdd(
            currentCount: ProPurchaseManager.freeHighlightLimit,
            hasProAccess: false
        )
        XCTAssertEqual(decision, .blocked(limit: ProPurchaseManager.freeHighlightLimit))
    }

    func testProUserCanAddPastFreeLimit() {
        let decision = NotesQuota.evaluateAdd(
            currentCount: ProPurchaseManager.freeHighlightLimit + 50,
            hasProAccess: true
        )
        XCTAssertEqual(decision, .allow)
    }

    func testFreeUserGetsWarningNearLimit() {
        // 16th add: currentCount 15 → usedAfter 16
        let decision = NotesQuota.evaluateAdd(
            currentCount: NotesQuota.warningThreshold - 1,
            hasProAccess: false
        )
        let remaining = ProPurchaseManager.freeHighlightLimit - NotesQuota.warningThreshold
        XCTAssertEqual(decision, .allowWithWarning(remaining: remaining))
    }

    func testDeletingBelowLimitAllowsAddAgain() {
        let atLimit = NotesQuota.evaluateAdd(
            currentCount: ProPurchaseManager.freeHighlightLimit,
            hasProAccess: false
        )
        XCTAssertEqual(atLimit, .blocked(limit: ProPurchaseManager.freeHighlightLimit))

        let afterDelete = NotesQuota.evaluateAdd(
            currentCount: ProPurchaseManager.freeHighlightLimit - 1,
            hasProAccess: false
        )
        // Last free slot: allowed without "0 remaining" warning.
        XCTAssertEqual(afterDelete, .allow)
    }

    func testNineteenthAddStillWarnsWithOneRemaining() {
        let decision = NotesQuota.evaluateAdd(
            currentCount: ProPurchaseManager.freeHighlightLimit - 2,
            hasProAccess: false
        )
        XCTAssertEqual(decision, .allowWithWarning(remaining: 1))
    }
}
