import Foundation

/// What happened to one page-turn command on one device, as shown under Recent Turns.
enum WatchPageTurnOutcome: Equatable {
    case turned
    /// Delivered, but the page stayed (end of book, or a turn was suppressed).
    case notTurned
    case readerNotReady
    case iPadNotFound
    case unreachable
    case proRequired

    /// Reads the reply payload every page-turn route already returns.
    /// `nil` means there is nothing to show: a replayed duplicate command.
    init?(payload: [String: Any]) {
        if payload["ok"] as? Bool == true {
            guard payload["duplicate"] as? Bool != true else { return nil }
            self = payload["didTurnPage"] as? Bool == true ? .turned : .notTurned
            return
        }
        switch payload["errorCode"] as? String {
        case WatchPageTurnErrorCode.navigatorNotReady:
            self = .readerNotReady
        case WatchPageTurnErrorCode.iPadNotFound:
            self = .iPadNotFound
        case WatchPageTurnErrorCode.proRequired:
            self = .proRequired
        default:
            self = .unreachable
        }
    }
}

/// One tap on the Watch (or one iPhone button press) and what each device did with it.
struct WatchPageTurnActivity: Identifiable, Equatable {
    enum Source: Equatable {
        case watch
        case iPhone
    }

    /// Ordered as shown: iPhone before iPad. `thisDevice` is the iPad's own view.
    enum Destination: Int, Comparable {
        case iPhone
        case iPad
        case thisDevice

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    struct DeviceResult: Equatable {
        let destination: Destination
        let outcome: WatchPageTurnOutcome
    }

    let id = UUID()
    let commandID: String?
    let direction: PageCommand
    let source: Source
    let date: Date
    private(set) var results: [DeviceResult]

    var isSuccess: Bool { results.contains { $0.outcome == .turned } }

    init(commandID: String?, direction: PageCommand, source: Source, date: Date, results: [DeviceResult]) {
        self.commandID = commandID
        self.direction = direction
        self.source = source
        self.date = date
        self.results = results
    }

    fileprivate mutating func set(_ result: DeviceResult) {
        results.removeAll { $0.destination == result.destination }
        results.append(result)
        results.sort { $0.destination < $1.destination }
    }
}

struct WatchPageTurnActivityLog: Equatable {
    static let capacity = 5

    private(set) var entries: [WatchPageTurnActivity] = []

    /// Replies to the same tap (same command id) merge into one row.
    mutating func record(
        commandID: String?,
        direction: PageCommand,
        source: WatchPageTurnActivity.Source,
        destination: WatchPageTurnActivity.Destination,
        outcome: WatchPageTurnOutcome,
        date: Date = Date()
    ) {
        let result = WatchPageTurnActivity.DeviceResult(destination: destination, outcome: outcome)
        if let commandID, let index = entries.firstIndex(where: { $0.commandID == commandID }) {
            entries[index].set(result)
            return
        }
        entries.insert(
            WatchPageTurnActivity(commandID: commandID, direction: direction, source: source, date: date, results: [result]),
            at: 0
        )
        if entries.count > Self.capacity {
            entries.removeLast(entries.count - Self.capacity)
        }
    }

    /// Every Watch tap is also sent to the iPad route; without a chosen iPad
    /// that half has nothing to say unless Pro is required, where we record it
    /// to clearly indicate the feature requirement and guide the user to Pro.
    static func shouldRecord(
        destination: WatchPageTurnActivity.Destination,
        outcome: WatchPageTurnOutcome? = nil,
        hasSelectedIPad: Bool
    ) -> Bool {
        if outcome == .proRequired {
            return true
        }
        return destination != .iPad || hasSelectedIPad
    }
}
