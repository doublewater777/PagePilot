import XCTest
@testable import PagePilot

final class WatchColdStartCommandBufferTests: XCTestCase {
    func testKeepsOnlyFirstCommandWhileConnecting() {
        var buffer = WatchColdStartCommandBuffer()

        buffer.storeIfEmpty(.next)
        buffer.storeIfEmpty(.prev)

        XCTAssertEqual(buffer.pendingCommand, .next)
    }

    func testCommandIsConsumedOnlyWhenTransportBecomesReachable() {
        var buffer = WatchColdStartCommandBuffer()
        buffer.storeIfEmpty(.prev)

        XCTAssertNil(buffer.takeIfReachable(false))
        XCTAssertEqual(buffer.pendingCommand, .prev)
        XCTAssertEqual(buffer.takeIfReachable(true), .prev)
        XCTAssertNil(buffer.pendingCommand)
    }

    func testClearDropsPendingCommandAfterConnectionTimeout() {
        var buffer = WatchColdStartCommandBuffer()
        buffer.storeIfEmpty(.next)

        buffer.clear()

        XCTAssertNil(buffer.pendingCommand)
    }
}
