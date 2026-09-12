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
    enum ClientError: Error {
        case activityNotFound
    }

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
        guard let activity = activity(withID: activityID) else {
            throw ClientError.activityNotFound
        }
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

    private static let progressionUpdateThreshold = 0.001

    private struct Session: Equatable {
        let id: String
        let startedAt: Date
        var title: String
        var progression: Double
        var lastPublishedState: ReadingLiveActivityAttributes.ContentState?

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

    /// Best-effort reconciliation for a fresh app process. ActivityKit can keep
    /// Live Activities alive after the app process is terminated, while the
    /// Reader session itself is intentionally process-scoped. End any activities
    /// that existed before this process has established a new reading session.
    func reconcileOnLaunch() async {
        guard session == nil, activityID == nil else { return }

        let staleActivityIDs = client.activeActivityIDs
        for id in staleActivityIDs {
            do {
                try await client.end(activityID: id, state: nil)
            } catch {
                print("ReadingLiveActivityCoordinator: launch cleanup failed: \(error)")
            }
        }
    }

    func sync(title: String, progression: Double, startedAt: Date) async {
        let progression = min(max(progression, 0.0), 1.0)

        if var current = session, current.startedAt == startedAt {
            current.title = title
            current.progression = progression
            let stateToPublish = current.state
            let shouldPublishUpdate = shouldPublish(
                stateToPublish,
                after: current.lastPublishedState
            )
            session = current

            if let activityID {
                guard shouldPublishUpdate else { return }
                do {
                    try await client.update(activityID: activityID, state: stateToPublish)
                    markPublished(stateToPublish, forSessionID: current.id)
                } catch {
                    print("ReadingLiveActivityCoordinator: update failed: \(error)")
                    if !client.activeActivityIDs.contains(activityID) {
                        self.activityID = nil
                        await startActivityIfNeeded(for: current)
                    }
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
            progression: progression,
            lastPublishedState: nil
        )
        session = next
        activityID = nil
        await startActivityIfNeeded(for: next)
    }

    func end(startedAt: Date) async {
        if let session, session.startedAt != startedAt {
            return
        }

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

    private func shouldPublish(
        _ state: ReadingLiveActivityAttributes.ContentState,
        after lastPublishedState: ReadingLiveActivityAttributes.ContentState?
    ) -> Bool {
        guard let lastPublishedState else { return true }
        return lastPublishedState.title != state.title
            || abs(lastPublishedState.progression - state.progression) >= Self.progressionUpdateThreshold
    }

    private func markPublished(
        _ state: ReadingLiveActivityAttributes.ContentState,
        forSessionID sessionID: String
    ) {
        guard var current = session, current.id == sessionID else { return }
        current.lastPublishedState = state
        session = current
    }

    private func startActivityIfNeeded(for expectedSession: Session) async {
        guard client.areActivitiesEnabled else { return }

        var cleanupFailed = false
        for id in client.activeActivityIDs {
            do {
                try await client.end(activityID: id, state: nil)
            } catch {
                cleanupFailed = true
                print("ReadingLiveActivityCoordinator: stale activity cleanup failed: \(error)")
            }
        }

        guard !cleanupFailed,
              activityID == nil,
              let current = session,
              current.id == expectedSession.id
        else { return }

        do {
            let newActivityID = try client.request(
                attributes: current.attributes,
                state: current.state
            )
            activityID = newActivityID
            markPublished(current.state, forSessionID: current.id)
        } catch {
            print("ReadingLiveActivityCoordinator: request failed: \(error)")
        }
    }
}
