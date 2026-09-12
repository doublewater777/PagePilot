import XCTest
@testable import PagePilot

final class WatchResponseEpochTests: XCTestCase {
    func testCurrentReplyIsAcceptedWhileTransportIsReachable() {
        var epoch = WatchResponseEpoch()
        let token = epoch.beginRequest(to: .iPhone, kind: .status)

        XCTAssertTrue(epoch.accepts(token, transportReachable: true))
    }

    func testReplyFromPreviousTransportLifetimeIsRejectedAfterInvalidation() {
        var epoch = WatchResponseEpoch()
        let staleToken = epoch.beginRequest(to: .iPhone, kind: .status)

        epoch.invalidateTransport()
        let currentToken = epoch.beginRequest(to: .iPhone, kind: .status)

        XCTAssertFalse(epoch.accepts(staleToken, transportReachable: true))
        XCTAssertTrue(epoch.accepts(currentToken, transportReachable: true))
    }

    func testCurrentReplyIsRejectedWhileTransportIsUnreachable() {
        var epoch = WatchResponseEpoch()
        let token = epoch.beginRequest(to: .iPhone, kind: .status)

        XCTAssertFalse(epoch.accepts(token, transportReachable: false))
    }

    func testOlderStatusReplyForSameDestinationIsRejectedAfterNewerStatusStarts() {
        var epoch = WatchResponseEpoch()
        let older = epoch.beginRequest(to: .iPad, kind: .status)
        let newer = epoch.beginRequest(to: .iPad, kind: .status)

        XCTAssertFalse(epoch.accepts(older, transportReachable: true))
        XCTAssertTrue(epoch.accepts(newer, transportReachable: true))
    }

    func testNewRequestForOtherDestinationDoesNotInvalidateCurrentReply() {
        var epoch = WatchResponseEpoch()
        let iPhone = epoch.beginRequest(to: .iPhone, kind: .status)
        let iPad = epoch.beginRequest(to: .iPad, kind: .status)

        XCTAssertTrue(epoch.accepts(iPhone, transportReachable: true))
        XCTAssertTrue(epoch.accepts(iPad, transportReachable: true))
    }

    func testStatusPollDoesNotInvalidateInFlightCommandForSameDestination() {
        var epoch = WatchResponseEpoch()
        let command = epoch.beginRequest(to: .iPad, kind: .command)
        let status = epoch.beginRequest(to: .iPad, kind: .status)

        XCTAssertTrue(epoch.accepts(command, transportReachable: true))
        XCTAssertTrue(epoch.accepts(status, transportReachable: true))
    }

    func testNewerCommandInvalidatesOlderCommandButNotStatus() {
        var epoch = WatchResponseEpoch()
        let status = epoch.beginRequest(to: .iPhone, kind: .status)
        let olderCommand = epoch.beginRequest(to: .iPhone, kind: .command)
        let newerCommand = epoch.beginRequest(to: .iPhone, kind: .command)

        XCTAssertTrue(epoch.accepts(status, transportReachable: true))
        XCTAssertFalse(epoch.accepts(olderCommand, transportReachable: true))
        XCTAssertTrue(epoch.accepts(newerCommand, transportReachable: true))
    }

    func testOnlyStatusRepliesCarryAuthoritativeReaderState() {
        XCTAssertTrue(WatchResponseKind.status.carriesAuthoritativeReaderState)
        XCTAssertFalse(WatchResponseKind.command.carriesAuthoritativeReaderState)
    }

    func testLateCommandSuccessCannotPromoteReaderAfterNewerNotReadyStatus() {
        var epoch = WatchResponseEpoch()
        let command = epoch.beginRequest(to: .iPad, kind: .command)
        let status = epoch.beginRequest(to: .iPad, kind: .status)
        var readerReady = true

        if epoch.accepts(status, transportReachable: true),
           status.kind.carriesAuthoritativeReaderState {
            readerReady = false
        }

        XCTAssertTrue(epoch.accepts(command, transportReachable: true))
        if command.kind.carriesAuthoritativeReaderState {
            readerReady = true
        }

        XCTAssertFalse(readerReady)
    }
}
