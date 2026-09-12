import XCTest
@testable import PagePilot

final class WatchResponseEpochTests: XCTestCase {
    func testCurrentReplyIsAcceptedWhileTransportIsReachable() {
        var epoch = WatchResponseEpoch()
        let token = epoch.beginRequest(to: .iPhone)

        XCTAssertTrue(epoch.accepts(token, transportReachable: true))
    }

    func testReplyFromPreviousTransportLifetimeIsRejectedAfterInvalidation() {
        var epoch = WatchResponseEpoch()
        let staleToken = epoch.beginRequest(to: .iPhone)

        epoch.invalidateTransport()
        let currentToken = epoch.beginRequest(to: .iPhone)

        XCTAssertFalse(epoch.accepts(staleToken, transportReachable: true))
        XCTAssertTrue(epoch.accepts(currentToken, transportReachable: true))
    }

    func testCurrentReplyIsRejectedWhileTransportIsUnreachable() {
        var epoch = WatchResponseEpoch()
        let token = epoch.beginRequest(to: .iPhone)

        XCTAssertFalse(epoch.accepts(token, transportReachable: false))
    }

    func testOlderReplyForSameDestinationIsRejectedAfterNewerRequestStarts() {
        var epoch = WatchResponseEpoch()
        let older = epoch.beginRequest(to: .iPad)
        let newer = epoch.beginRequest(to: .iPad)

        XCTAssertFalse(epoch.accepts(older, transportReachable: true))
        XCTAssertTrue(epoch.accepts(newer, transportReachable: true))
    }

    func testNewRequestForOtherDestinationDoesNotInvalidateCurrentReply() {
        var epoch = WatchResponseEpoch()
        let iPhone = epoch.beginRequest(to: .iPhone)
        let iPad = epoch.beginRequest(to: .iPad)

        XCTAssertTrue(epoch.accepts(iPhone, transportReachable: true))
        XCTAssertTrue(epoch.accepts(iPad, transportReachable: true))
    }
}
