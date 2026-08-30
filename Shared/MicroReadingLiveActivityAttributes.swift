import ActivityKit
import Foundation

struct MicroReadingLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let endDate: Date?
        let pausedRemaining: TimeInterval?
    }
}
