import XCTest
@testable import PagePilot

final class QuickPositionJumpSessionTests: XCTestCase {
    func testInterruptedCommitReturnsIdleImmediatelyAndRejectsLateCompletion() {
        var session = QuickPositionJumpSession()
        XCTAssertTrue(session.beginPreview())
        guard let token = session.beginCommit() else {
            return XCTFail("Expected committing token")
        }

        session.interruptCommit()

        XCTAssertEqual(session.state, .idle)
        XCTAssertFalse(session.acceptsCompletion(for: token))
    }

    func testNewSessionRejectsPreviousCommitCompletion() {
        var session = QuickPositionJumpSession()
        XCTAssertTrue(session.beginPreview())
        guard let oldToken = session.beginCommit() else {
            return XCTFail("Expected first committing token")
        }
        session.interruptCommit()
        XCTAssertTrue(session.beginPreview())
        guard let newToken = session.beginCommit() else {
            return XCTFail("Expected second committing token")
        }

        XCTAssertFalse(session.acceptsCompletion(for: oldToken))
        XCTAssertTrue(session.acceptsCompletion(for: newToken))
    }

    func testCancellationCanBeArmedAndDisarmedBeforeCommit() {
        var session = QuickPositionJumpSession()
        XCTAssertTrue(session.beginPreview())
        session.setCancellationArmed(true)
        XCTAssertEqual(session.state, .cancellationArmed)

        session.setCancellationArmed(false)

        XCTAssertEqual(session.state, .previewing)
        XCTAssertNotNil(session.beginCommit())
    }
}
