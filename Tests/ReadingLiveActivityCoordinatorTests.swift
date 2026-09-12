import Foundation
import XCTest
@testable import PagePilot

@MainActor
final class ReadingLiveActivityCoordinatorTests: XCTestCase {
    func testStartsOneActivityWithCurrentReadingState() async {
        let client = FakeReadingLiveActivityClient()
        let coordinator = ReadingLiveActivityCoordinator(client: client)
        let startedAt = Date(timeIntervalSince1970: 1_000)

        await coordinator.sync(
            title: "Pride and Prejudice",
            progression: 0.42,
            startedAt: startedAt
        )

        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(client.requests[0].attributes.startedAt, startedAt)
        XCTAssertEqual(client.requests[0].state.title, "Pride and Prejudice")
        XCTAssertEqual(client.requests[0].state.progression, 0.42, accuracy: 0.0001)
        XCTAssertEqual(client.activeActivityIDs.count, 1)
    }

    func testRepeatedSyncForSameSessionUpdatesWithoutDuplicate() async {
        let client = FakeReadingLiveActivityClient()
        let coordinator = ReadingLiveActivityCoordinator(client: client)
        let startedAt = Date(timeIntervalSince1970: 1_000)

        await coordinator.sync(title: "Book", progression: 0.2, startedAt: startedAt)
        await coordinator.sync(title: "Book", progression: 0.35, startedAt: startedAt)

        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(client.updates.count, 1)
        XCTAssertEqual(client.updates[0].state.progression, 0.35, accuracy: 0.0001)
        XCTAssertEqual(client.activeActivityIDs.count, 1)
    }

    func testInsignificantProgressRefreshDoesNotPublishUpdate() async {
        let client = FakeReadingLiveActivityClient()
        let coordinator = ReadingLiveActivityCoordinator(client: client)
        let startedAt = Date(timeIntervalSince1970: 1_000)

        await coordinator.sync(title: "Book", progression: 0.2, startedAt: startedAt)
        await coordinator.sync(title: "Book", progression: 0.2005, startedAt: startedAt)

        XCTAssertEqual(client.requests.count, 1)
        XCTAssertTrue(client.updates.isEmpty)
    }

    func testSwitchingSessionsEndsStaleActivityBeforeStartingNext() async throws {
        let client = FakeReadingLiveActivityClient()
        let coordinator = ReadingLiveActivityCoordinator(client: client)

        await coordinator.sync(
            title: "First",
            progression: 0.2,
            startedAt: Date(timeIntervalSince1970: 1_000)
        )
        let firstActivityID = try XCTUnwrap(client.activeActivityIDs.first)

        await coordinator.sync(
            title: "Second",
            progression: 0.6,
            startedAt: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertTrue(client.ends.contains { $0.activityID == firstActivityID })
        XCTAssertEqual(client.requests.count, 2)
        XCTAssertEqual(client.requests.last?.state.title, "Second")
        XCTAssertEqual(client.activeActivityIDs.count, 1)
    }

    func testOldSessionEndDoesNotEndNewSession() async throws {
        let client = FakeReadingLiveActivityClient()
        let coordinator = ReadingLiveActivityCoordinator(client: client)
        let firstStartedAt = Date(timeIntervalSince1970: 1_000)
        let secondStartedAt = Date(timeIntervalSince1970: 2_000)

        await coordinator.sync(title: "First", progression: 0.2, startedAt: firstStartedAt)
        await coordinator.sync(title: "Second", progression: 0.6, startedAt: secondStartedAt)
        let secondActivityID = try XCTUnwrap(client.activeActivityIDs.first)
        let endCountAfterSwitch = client.ends.count

        await coordinator.end(startedAt: firstStartedAt)

        XCTAssertEqual(client.ends.count, endCountAfterSwitch)
        XCTAssertEqual(client.activeActivityIDs, [secondActivityID])
    }

    func testReconcilesActivityLeftByPreviousProcessBeforeStarting() async {
        let client = FakeReadingLiveActivityClient()
        client.activeActivityIDs = ["stale"]
        let coordinator = ReadingLiveActivityCoordinator(client: client)

        await coordinator.sync(
            title: "Book",
            progression: 0.2,
            startedAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(client.ends.map(\.activityID), ["stale"])
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(client.activeActivityIDs.count, 1)
        XCTAssertNotEqual(client.activeActivityIDs.first, "stale")
    }

    func testDisabledAuthorizationDoesNotRequestActivity() async {
        let client = FakeReadingLiveActivityClient()
        client.areActivitiesEnabled = false
        let coordinator = ReadingLiveActivityCoordinator(client: client)

        await coordinator.sync(
            title: "Book",
            progression: 0.2,
            startedAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertTrue(client.requests.isEmpty)
        XCTAssertTrue(client.activeActivityIDs.isEmpty)
    }

    func testRequestFailureIsContainedAndRetriedOnNextSync() async {
        let client = FakeReadingLiveActivityClient()
        client.failNextRequest = true
        let coordinator = ReadingLiveActivityCoordinator(client: client)
        let startedAt = Date(timeIntervalSince1970: 1_000)

        await coordinator.sync(title: "Book", progression: 0.2, startedAt: startedAt)
        XCTAssertTrue(client.activeActivityIDs.isEmpty)

        await coordinator.sync(title: "Book", progression: 0.3, startedAt: startedAt)

        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(client.requests[0].state.progression, 0.3, accuracy: 0.0001)
        XCTAssertEqual(client.activeActivityIDs.count, 1)
    }

    func testUpdateFailureIsContainedAndSessionCanStillEnd() async throws {
        let client = FakeReadingLiveActivityClient()
        let coordinator = ReadingLiveActivityCoordinator(client: client)
        let startedAt = Date(timeIntervalSince1970: 1_000)

        await coordinator.sync(title: "Book", progression: 0.2, startedAt: startedAt)
        let activityID = try XCTUnwrap(client.activeActivityIDs.first)
        client.failUpdateIDs = [activityID]

        await coordinator.sync(title: "Book", progression: 0.4, startedAt: startedAt)
        await coordinator.end(startedAt: startedAt)

        XCTAssertTrue(client.updates.isEmpty)
        XCTAssertEqual(client.ends.last?.activityID, activityID)
        XCTAssertTrue(client.activeActivityIDs.isEmpty)
    }

    func testStaleCleanupFailureDoesNotCreateDuplicateActivity() async {
        let client = FakeReadingLiveActivityClient()
        client.activeActivityIDs = ["stale"]
        client.failEndIDs = ["stale"]
        let coordinator = ReadingLiveActivityCoordinator(client: client)

        await coordinator.sync(
            title: "Book",
            progression: 0.2,
            startedAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertTrue(client.requests.isEmpty)
        XCTAssertEqual(client.activeActivityIDs, ["stale"])
    }

    func testEndFailureIsContained() async throws {
        let client = FakeReadingLiveActivityClient()
        let coordinator = ReadingLiveActivityCoordinator(client: client)
        let startedAt = Date(timeIntervalSince1970: 1_000)

        await coordinator.sync(
            title: "Book",
            progression: 0.8,
            startedAt: startedAt
        )
        let activityID = try XCTUnwrap(client.activeActivityIDs.first)
        client.failEndIDs = [activityID]

        await coordinator.end(startedAt: startedAt)

        XCTAssertEqual(client.activeActivityIDs, [activityID])
    }

    func testEndClearsActiveReadingActivity() async {
        let client = FakeReadingLiveActivityClient()
        let coordinator = ReadingLiveActivityCoordinator(client: client)
        let startedAt = Date(timeIntervalSince1970: 1_000)

        await coordinator.sync(title: "Book", progression: 0.8, startedAt: startedAt)
        await coordinator.end(startedAt: startedAt)

        XCTAssertEqual(client.ends.count, 1)
        XCTAssertEqual(client.ends[0].state?.title, "Book")
        XCTAssertEqual(client.ends[0].state?.progression, 0.8)
        XCTAssertTrue(client.activeActivityIDs.isEmpty)
    }
}

@MainActor
private final class FakeReadingLiveActivityClient: ReadingLiveActivityClient {
    struct Request {
        let attributes: ReadingLiveActivityAttributes
        let state: ReadingLiveActivityAttributes.ContentState
    }

    struct Update {
        let activityID: String
        let state: ReadingLiveActivityAttributes.ContentState
    }

    struct End {
        let activityID: String
        let state: ReadingLiveActivityAttributes.ContentState?
    }

    enum Failure: Error {
        case requested
    }

    var areActivitiesEnabled = true
    var activeActivityIDs: [String] = []
    var requests: [Request] = []
    var updates: [Update] = []
    var ends: [End] = []
    var failNextRequest = false
    var failUpdateIDs: Set<String> = []
    var failEndIDs: Set<String> = []

    func request(
        attributes: ReadingLiveActivityAttributes,
        state: ReadingLiveActivityAttributes.ContentState
    ) throws -> String {
        if failNextRequest {
            failNextRequest = false
            throw Failure.requested
        }

        let id = "activity-\(requests.count + 1)"
        requests.append(Request(attributes: attributes, state: state))
        activeActivityIDs.append(id)
        return id
    }

    func update(
        activityID: String,
        state: ReadingLiveActivityAttributes.ContentState
    ) async throws {
        if failUpdateIDs.contains(activityID) {
            throw Failure.requested
        }
        updates.append(Update(activityID: activityID, state: state))
    }

    func end(
        activityID: String,
        state: ReadingLiveActivityAttributes.ContentState?
    ) async throws {
        if failEndIDs.contains(activityID) {
            throw Failure.requested
        }
        ends.append(End(activityID: activityID, state: state))
        activeActivityIDs.removeAll { $0 == activityID }
    }
}
