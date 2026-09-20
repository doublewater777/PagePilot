//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import ActivityKit
import AppIntents
import Foundation

struct ReadingLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let title: String
        let progression: Double
    }

    let sessionID: String
    let startedAt: Date
}

enum ReadingLiveActivityPageTurnDirection: String, Equatable, Sendable {
    case previous = "prev"
    case next = "next"
}

struct ReadingLiveActivityPageTurnRequest: Equatable, Sendable {
    let direction: ReadingLiveActivityPageTurnDirection
    let commandID: String

    init(
        direction: ReadingLiveActivityPageTurnDirection,
        commandID: String = UUID().uuidString
    ) {
        self.direction = direction
        self.commandID = commandID
    }
}

extension Notification.Name {
    static let readingLiveActivityPageTurnRequested =
        Notification.Name("readingLiveActivityPageTurnRequested")
}

struct ReadingPreviousPageIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Previous Page"
    static let direction: ReadingLiveActivityPageTurnDirection = .previous

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(
            name: .readingLiveActivityPageTurnRequested,
            object: ReadingLiveActivityPageTurnRequest(direction: Self.direction)
        )
        return .result()
    }
}

struct ReadingNextPageIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Next Page"
    static let direction: ReadingLiveActivityPageTurnDirection = .next

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(
            name: .readingLiveActivityPageTurnRequested,
            object: ReadingLiveActivityPageTurnRequest(direction: Self.direction)
        )
        return .result()
    }
}
