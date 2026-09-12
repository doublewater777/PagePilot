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

    func testStatusPathErrorStaysHiddenWhileAnyReaderIsReady() {
        let state = WatchReaderRoutingState(
            iPhoneReady: true,
            iPadReady: false,
            iPadError: "iPad timeout"
        )

        XCTAssertTrue(state.readerReady)
        XCTAssertEqual(state.visibleError, "")
    }

    func testStatusPathErrorIsVisibleWhenNoReaderIsReady() {
        let state = WatchReaderRoutingState(
            iPhoneReady: false,
            iPadReady: false,
            iPadError: "iPad timeout"
        )

        XCTAssertFalse(state.readerReady)
        XCTAssertEqual(state.visibleError, "iPad timeout")
    }
}
