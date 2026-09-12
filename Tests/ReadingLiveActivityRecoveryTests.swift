import Foundation
import XCTest
@testable import PagePilot

@MainActor
final class ReadingLiveActivityRecoveryTests: XCTestCase {
    func testMissingActivityIsRecreatedOnNextMeaningfulSync() async throws {
        let client = RecoveryFakeReadingLiveActivityClient()
        let coordinator = ReadingLiveActivityCoordinator(client: client)
        let startedAt = Date(timeIntervalSince1970: 1_000)

        await coordinator.sync(title: "Book", progression: 0.2, startedAt: startedAt)
        let firstActivityID = try XCTUnwrap(client.activeActivityIDs.first)

        client.activeActivityIDs.removeAll { $0 == firstActivityID }

        await coordinator.sync(title: "Book", progression: 0.4, startedAt: startedAt)

        XCTAssertEqual(client.requests.count, 2)
        let restartedRequest = try XCTUnwrap(client.requests.last)
        XCTAssertEqual(restartedRequest.progression, 0.4, accuracy: 0.0001)
        XCTAssertEqual(client.activeActivityIDs.count, 1)
        XCTAssertNotEqual(client.activeActivityIDs.first, firstActivityID)
    }
}

@MainActor
private final class RecoveryFakeReadingLiveActivityClient: ReadingLiveActivityClient {
    enum Failure: Error {
        case activityNotFound
    }

    struct Request {
        let progression: Double
    }

    var areActivitiesEnabled = true
    var activeActivityIDs: [String] = []
    var requests: [Request] = []

    func request(
        attributes: ReadingLiveActivityAttributes,
        state: ReadingLiveActivityAttributes.ContentState
    ) throws -> String {
        let id = "activity-\(requests.count + 1)"
        requests.append(Request(progression: state.progression))
        activeActivityIDs.append(id)
        return id
    }

    func update(
        activityID: String,
        state: ReadingLiveActivityAttributes.ContentState
    ) async throws {
        guard activeActivityIDs.contains(activityID) else {
            throw Failure.activityNotFound
        }
    }

    func end(
        activityID: String,
        state: ReadingLiveActivityAttributes.ContentState?
    ) async throws {
        activeActivityIDs.removeAll { $0 == activityID }
    }
}
