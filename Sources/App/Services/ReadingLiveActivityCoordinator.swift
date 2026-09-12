//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import ActivityKit
import Foundation

@MainActor
protocol ReadingLiveActivityClient: AnyObject {
    var areActivitiesEnabled: Bool { get }
    var activeActivityIDs: [String] { get }

    func request(
        attributes: ReadingLiveActivityAttributes,
        state: ReadingLiveActivityAttributes.ContentState
    ) throws -> String

    func update(
        activityID: String,
        state: ReadingLiveActivityAttributes.ContentState
    ) async throws

    func end(
        activityID: String,
        state: ReadingLiveActivityAttributes.ContentState?
    ) async throws
}

@MainActor
final class ActivityKitReadingLiveActivityClient: ReadingLiveActivityClient {
    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    var activeActivityIDs: [String] {
        Activity<ReadingLiveActivityAttributes>.activities.map(\.id)
    }

    func request(
        attributes: ReadingLiveActivityAttributes,
        state: ReadingLiveActivityAttributes.ContentState
    ) throws -> String {
        let activity = try Activity<ReadingLiveActivityAttributes>.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
        return activity.id
    }

    func update(
        activityID: String,
        state: ReadingLiveActivityAttributes.ContentState
    ) async throws {
        guard let activity = activity(withID: activityID) else { return }
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    func end(
        activityID: String,
        state: ReadingLiveActivityAttributes.ContentState?
    ) async throws {
        guard let activity = activity(withID: activityID) else { return }
        let content = state.map { ActivityContent(state: $0, staleDate: nil) }
        await activity.end(content, dismissalPolicy: .immediate)
    }

    private func activity(withID id: String) -> Activity<ReadingLiveActivityAttributes>? {
        Activity<ReadingLiveActivityAttributes>.activities.first { $0.id == id }
    }
}

@MainActor
final class ReadingLiveActivityCoordinator {
    static let shared = ReadingLiveActivityCoordinator()

    private struct Session: Equatable {
        let id: String
        let startedAt: Date
        var title: String
        var progression: Double

        var attributes: ReadingLiveActivityAttributes {
            ReadingLiveActivityAttributes(sessionID: id, startedAt: startedAt)
        }

        var state: ReadingLiveActivityAttributes.ContentState {
            ReadingLiveActivityAttributes.ContentState(
                title: title,
                progression: progression
            )
        }
    }

    private let client: ReadingLiveActivityClient
    private var session: Session?
    private var activityID: String?

    init(client: ReadingLiveActivityClient = ActivityKitReadingLiveActivityClient()) {
        self.client = client
    }

    func sync(title: String, progression: Double, startedAt: Date) async {
        let progression = min(max(progression, 0.0), 1.0)

        if var current = session, current.startedAt == startedAt {
            current.title = title
            current.progression = progression
            session = current

            if let activityID {
                do {
                    try await client.update(activityID: activityID, state: current.state)
                } catch {
                    print("ReadingLiveActivityCoordinator: update failed: \(error)")
                }
            } else {
                await startActivityIfNeeded(for: current)
            }
            return
        }

        let next = Session(
            id: UUID().uuidString,
            startedAt: startedAt,
            title: title,
            progression: progression
        )
        session = next
        activityID = nil
        await startActivityIfNeeded(for: next)
    }

    func end() async {
        let finalState = session?.state
        session = nil

        var ids = Set(client.activeActivityIDs)
        if let activityID {
            ids.insert(activityID)
        }
        self.activityID = nil

        for id in ids {
            do {
                try await client.end(activityID: id, state: finalState)
            } catch {
                print("ReadingLiveActivityCoordinator: end failed: \(error)")
            }
        }
    }

    private func startActivityIfNeeded(for expectedSession: Session) async {
        guard client.areActivitiesEnabled else { return }

        for id in client.activeActivityIDs {
            do {
                try await client.end(activityID: id, state: nil)
            } catch {
                print("ReadingLiveActivityCoordinator: stale activity cleanup failed: \(error)")
            }
        }

        guard activityID == nil,
              let current = session,
              current.id == expectedSession.id
        else { return }

        do {
            activityID = try client.request(
                attributes: current.attributes,
                state: current.state
            )
        } catch {
            print("ReadingLiveActivityCoordinator: request failed: \(error)")
        }
    }
}
