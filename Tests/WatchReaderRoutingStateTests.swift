import XCTest
@testable import PagePilot

final class WatchReaderRoutingStateTests: XCTestCase {
    func testTransportFailureInvalidatesStaleReadersAndShowsError() {
        var state = WatchReaderRoutingState(
            iPhoneReady: false,
            iPadReady: true
        )

        state.invalidateForTransportFailure(error: "Open iPhone")

        XCTAssertFalse(state.iPhoneReady)
        XCTAssertFalse(state.iPadReady)
        XCTAssertFalse(state.readerReady)
        XCTAssertEqual(state.activeReaderCount, 0)
        XCTAssertEqual(state.visibleError, "Open iPhone")
    }

    func testIPadSendFailureStaysHiddenWhileIPhoneReaderIsReady() {
        var state = WatchReaderRoutingState(
            iPhoneReady: true,
            iPadReady: true
        )

        state.invalidateForSendFailure(
            to: .iPad,
            transportReachable: true,
            error: "iPad timeout"
        )

        XCTAssertTrue(state.iPhoneReady)
        XCTAssertFalse(state.iPadReady)
        XCTAssertTrue(state.readerReady)
        XCTAssertEqual(state.visibleError, "")
    }

    func testIPadSendFailureIsVisibleWhenNoOtherReaderIsReady() {
        var state = WatchReaderRoutingState(
            iPhoneReady: false,
            iPadReady: true
        )

        state.invalidateForSendFailure(
            to: .iPad,
            transportReachable: true,
            error: "iPad timeout"
        )

        XCTAssertFalse(state.readerReady)
        XCTAssertEqual(state.visibleError, "iPad timeout")
    }

    func testUnreachableTransportDuringSendInvalidatesBothReaders() {
        var state = WatchReaderRoutingState(
            iPhoneReady: true,
            iPadReady: true
        )

        state.invalidateForSendFailure(
            to: .iPad,
            transportReachable: false,
            error: "Send failed"
        )

        XCTAssertFalse(state.iPhoneReady)
        XCTAssertFalse(state.iPadReady)
        XCTAssertEqual(state.visibleError, "Send failed")
    }
}
