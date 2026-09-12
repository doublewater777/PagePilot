import XCTest
@testable import PagePilot

final class WatchResponseEpochTests: XCTestCase {
    func testCurrentReplyIsAcceptedWhileTransportIsReachable() {
        let epoch = WatchResponseEpoch()
        let token = epoch.token

        XCTAssertTrue(epoch.accepts(token, transportReachable: true))
    }

    func testReplyFromPreviousTransportLifetimeIsRejectedAfterInvalidation() {
        var epoch = WatchResponseEpoch()
        let staleToken = epoch.token

        epoch.invalidateTransport()

        XCTAssertFalse(epoch.accepts(staleToken, transportReachable: true))
        XCTAssertTrue(epoch.accepts(epoch.token, transportReachable: true))
    }

    func testCurrentReplyIsRejectedWhileTransportIsUnreachable() {
        let epoch = WatchResponseEpoch()

        XCTAssertFalse(epoch.accepts(epoch.token, transportReachable: false))
    }
}
