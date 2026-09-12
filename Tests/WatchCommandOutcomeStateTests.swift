import XCTest
@testable import PagePilot

final class WatchCommandOutcomeStateTests: XCTestCase {
    func testSingleRouteFailureWaitsForOtherFanoutResult() {
        var state = WatchCommandOutcomeState()
        state.begin(commandID: "cmd")
        state.recordFailure(commandID: "cmd", destination: .iPad, error: "Send failed")

        XCTAssertFalse(state.allRoutesFinished)
        XCTAssertEqual(state.commandError, "")
    }

    func testAnySuccessfulRouteSuppressesOtherRouteFailure() {
        var state = WatchCommandOutcomeState()
        state.begin(commandID: "cmd")
        state.recordFailure(commandID: "cmd", destination: .iPad, error: "Send failed")
        state.recordSuccess(commandID: "cmd", destination: .iPhone)

        XCTAssertTrue(state.allRoutesFinished)
        XCTAssertTrue(state.hasSucceeded)
        XCTAssertEqual(state.commandError, "")
    }

    func testBothRouteFailuresProduceCommandErrorEvenWhenRoutingErrorIsHidden() {
        var state = WatchCommandOutcomeState()
        state.begin(commandID: "cmd")
        state.recordFailure(commandID: "cmd", destination: .iPhone, error: "Send failed")
        state.recordFailure(commandID: "cmd", destination: .iPad, error: "iPad timeout")

        let routing = WatchReaderRoutingState(
            iPhoneReady: false,
            iPadReady: true,
            iPhoneError: "",
            iPadError: ""
        )

        XCTAssertEqual(routing.visibleError, "")
        XCTAssertEqual(state.commandError, "Send failed")
        XCTAssertEqual(state.visibleError(fallback: routing.visibleError), "Send failed")
    }

    func testStatusFallbackCannotClearCompletedCommandFailure() {
        var state = WatchCommandOutcomeState()
        state.begin(commandID: "cmd")
        state.recordFailure(commandID: "cmd", destination: .iPhone, error: "Send failed")
        state.recordFailure(commandID: "cmd", destination: .iPad, error: "")

        XCTAssertEqual(state.visibleError(fallback: ""), "Send failed")
        XCTAssertEqual(state.visibleError(fallback: "status recovered"), "Send failed")
    }

    func testBeginningNextCommandClearsPreviousCommandError() {
        var state = WatchCommandOutcomeState()
        state.begin(commandID: "first")
        state.recordFailure(commandID: "first", destination: .iPhone, error: "Send failed")
        state.recordFailure(commandID: "first", destination: .iPad, error: "iPad timeout")
        XCTAssertEqual(state.commandError, "Send failed")

        state.begin(commandID: "second")

        XCTAssertEqual(state.commandError, "")
        XCTAssertFalse(state.allRoutesFinished)
    }

    func testLateOutcomeFromPreviousCommandIsIgnored() {
        var state = WatchCommandOutcomeState()
        state.begin(commandID: "first")
        state.begin(commandID: "second")

        state.recordFailure(commandID: "first", destination: .iPhone, error: "old failure")
        state.recordSuccess(commandID: "first", destination: .iPad)

        XCTAssertEqual(state.commandID, "second")
        XCTAssertEqual(state.iPhoneOutcome, .pending)
        XCTAssertEqual(state.iPadOutcome, .pending)
    }
}
