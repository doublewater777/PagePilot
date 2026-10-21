import UIKit
import XCTest
@testable import PagePilot

final class TrackpadPageTurnSessionTests: XCTestCase {
    func testSmallMovementDoesNotTurnUntilSwipeCrossesThreshold() {
        var session = TrackpadPageTurnSession()
        XCTAssertNil(session.update(state: .began, translation: .zero))
        XCTAssertNil(session.update(state: .changed, translation: CGPoint(x: -12, y: 3)))
        XCTAssertEqual(
            session.update(state: .changed, translation: CGPoint(x: -60, y: 4)),
            CGPoint(x: -60, y: 4)
        )
    }

    func testLongSwipeAndReversalCannotTurnAgain() {
        var session = TrackpadPageTurnSession()
        XCTAssertNotNil(session.update(state: .began, translation: CGPoint(x: 0, y: -60)))
        XCTAssertNil(session.update(state: .changed, translation: CGPoint(x: 0, y: -600)))
        XCTAssertNil(session.update(state: .changed, translation: CGPoint(x: 0, y: 200)))
        XCTAssertNil(session.update(state: .ended, translation: CGPoint(x: 0, y: -800)))
        XCTAssertNil(session.update(state: .changed, translation: CGPoint(x: 0, y: -1000)))
    }

    func testCancellationCannotCommitASwipe() {
        for terminal: UIGestureRecognizer.State in [.cancelled, .failed] {
            var session = TrackpadPageTurnSession()
            XCTAssertNil(session.update(state: .began, translation: CGPoint(x: 10, y: 0)))
            XCTAssertNil(session.update(state: terminal, translation: CGPoint(x: 100, y: 0)))
            XCTAssertNil(session.update(state: .changed, translation: CGPoint(x: 200, y: 0)))
        }
    }

    func testQuickSwipeCanCommitItsFinalDisplacementButNotTrailingEvents() {
        var session = TrackpadPageTurnSession()
        XCTAssertNil(session.update(state: .began, translation: CGPoint(x: -10, y: 0)))
        XCTAssertEqual(
            session.update(state: .ended, translation: CGPoint(x: -60, y: 0)),
            CGPoint(x: -60, y: 0)
        )
        XCTAssertNil(session.update(state: .changed, translation: CGPoint(x: -300, y: 0)))
        XCTAssertNil(session.update(state: .ended, translation: CGPoint(x: -400, y: 0)))
    }

    func testNewSwipeCanTurnInTheOppositeDirection() {
        var session = TrackpadPageTurnSession()
        XCTAssertNotNil(session.update(state: .began, translation: CGPoint(x: -60, y: 0)))
        XCTAssertNil(session.update(state: .ended, translation: CGPoint(x: -90, y: 0)))
        XCTAssertNil(session.update(state: .began, translation: .zero))
        XCTAssertEqual(
            session.update(state: .changed, translation: CGPoint(x: 60, y: 0)),
            CGPoint(x: 60, y: 0)
        )
    }

    func testEventsWithoutABeginCannotTurn() {
        var session = TrackpadPageTurnSession()
        XCTAssertNil(session.update(state: .changed, translation: CGPoint(x: 0, y: -200)))
        XCTAssertNil(session.update(state: .ended, translation: CGPoint(x: 0, y: -300)))
    }
}
