import XCTest
@testable import PagePilot

final class ThrottledCommandQueueTests: XCTestCase {
    func testSendImmediatelyWhenIdle() {
        var sentCommands: [PageCommand] = []
        var completionCalls = 0

        let queue = ThrottledCommandQueue(interval: 0.2) { command, completion in
            sentCommands.append(command)
            completion()
            completionCalls += 1
        }

        queue.enqueue(.next)

        XCTAssertEqual(sentCommands, [.next])
        XCTAssertEqual(completionCalls, 1)
    }

    func testThrottlesConsecutiveDispatchesWithin200ms() {
        var sentCommands: [PageCommand] = []
        var completionCalls = 0

        let queue = ThrottledCommandQueue(interval: 0.2) { command, completion in
            sentCommands.append(command)
            completion()
            completionCalls += 1
        }

        queue.enqueue(.next)
        queue.enqueue(.prev)

        XCTAssertEqual(sentCommands, [.next])

        let expectation = self.expectation(description: "Wait for throttle interval")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            XCTAssertEqual(sentCommands, [.next, .prev])
            XCTAssertEqual(completionCalls, 2)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.5)
    }

    func testInFlightCommandBlocksExecutionAndQueuesLatest() {
        var sentCommands: [PageCommand] = []
        var completions: [() -> Void] = []

        let queue = ThrottledCommandQueue(interval: 0.1) { command, completion in
            sentCommands.append(command)
            completions.append(completion)
        }

        // 1. Send first command - should dispatch immediately
        queue.enqueue(.next)
        XCTAssertEqual(sentCommands, [.next])
        XCTAssertEqual(completions.count, 1)

        // 2. Queue second command (prev) and third command (next) while first is in-flight
        queue.enqueue(.prev)
        queue.enqueue(.next)

        // Only the first command should be sent so far
        XCTAssertEqual(sentCommands, [.next])

        // 3. Complete the first command
        completions[0]()

        // The queued command (.next, which overwrote .prev) should be dispatched once
        // the throttle interval (100ms) has elapsed since the first dispatch.
        // We wait 150ms to give a comfortable buffer.
        let expectation = self.expectation(description: "Wait for dispatch of queued command")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            XCTAssertEqual(sentCommands, [.next, .next])
            XCTAssertEqual(completions.count, 2)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 0.3)
    }
    func testQueuedCommandFiresImmediatelyIfCompletionIsLate() {
        // If the in-flight command takes longer than the throttle interval,
        // the queued command must fire immediately after completion — no extra wait.
        var sentCommands: [PageCommand] = []
        var completions: [() -> Void] = []

        let queue = ThrottledCommandQueue(interval: 0.05) { command, completion in
            sentCommands.append(command)
            completions.append(completion)
        }

        // 1. Dispatch first command immediately
        queue.enqueue(.next)
        XCTAssertEqual(sentCommands.count, 1)

        // 2. Enqueue a second command while first is in-flight
        queue.enqueue(.prev)
        XCTAssertEqual(sentCommands.count, 1)

        // 3. Wait longer than the throttle interval (100ms > 50ms interval)
        //    then call completion — queued command should fire right away
        let expectation = self.expectation(description: "Second command fires immediately after late completion")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Interval has already elapsed; complete first command
            completions[0]()

            // Give one run-loop tick for the async dispatch inside handleCompletion
            DispatchQueue.main.async {
                XCTAssertEqual(sentCommands, [.next, .prev],
                    "Queued command should be dispatched immediately since interval already elapsed")
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 0.5)
    }
}
