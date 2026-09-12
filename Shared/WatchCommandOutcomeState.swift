import Foundation

enum WatchCommandRouteOutcome: Equatable, Sendable {
    case pending
    case succeeded
    case failed(String)

    var isFinished: Bool {
        switch self {
        case .pending:
            return false
        case .succeeded, .failed:
            return true
        }
    }

    var succeeded: Bool {
        if case .succeeded = self {
            return true
        }
        return false
    }

    var failureMessage: String {
        if case let .failed(message) = self {
            return message
        }
        return ""
    }
}

/// Tracks the two fan-out results for one logical Watch page-turn command.
///
/// Reader readiness is status-authoritative and intentionally independent from
/// command delivery. A command-level error becomes visible only after both
/// iPhone and iPad routes have finished and neither route succeeded. Status
/// polling cannot clear this error; beginning the next logical command does.
struct WatchCommandOutcomeState: Equatable, Sendable {
    private(set) var commandID: String?
    private(set) var iPhoneOutcome: WatchCommandRouteOutcome = .pending
    private(set) var iPadOutcome: WatchCommandRouteOutcome = .pending

    mutating func begin(commandID: String) {
        self.commandID = commandID
        iPhoneOutcome = .pending
        iPadOutcome = .pending
    }

    mutating func reset() {
        commandID = nil
        iPhoneOutcome = .pending
        iPadOutcome = .pending
    }

    mutating func recordSuccess(commandID: String, destination: WatchReaderDestination) {
        guard self.commandID == commandID else { return }
        set(.succeeded, for: destination)
    }

    mutating func recordFailure(
        commandID: String,
        destination: WatchReaderDestination,
        error: String
    ) {
        guard self.commandID == commandID else { return }
        set(.failed(error), for: destination)
    }

    var hasSucceeded: Bool {
        iPhoneOutcome.succeeded || iPadOutcome.succeeded
    }

    var allRoutesFinished: Bool {
        iPhoneOutcome.isFinished && iPadOutcome.isFinished
    }

    var allRoutesFailed: Bool {
        commandID != nil && allRoutesFinished && !hasSucceeded
    }

    var commandError: String {
        guard allRoutesFailed else { return "" }
        if !iPhoneOutcome.failureMessage.isEmpty {
            return iPhoneOutcome.failureMessage
        }
        return iPadOutcome.failureMessage
    }

    func visibleError(
        fallback routingError: String,
        defaultCommandError: String = ""
    ) -> String {
        guard allRoutesFailed else { return routingError }
        if !commandError.isEmpty { return commandError }
        return defaultCommandError.isEmpty ? routingError : defaultCommandError
    }

    private mutating func set(
        _ outcome: WatchCommandRouteOutcome,
        for destination: WatchReaderDestination
    ) {
        switch destination {
        case .iPhone:
            iPhoneOutcome = outcome
        case .iPad:
            iPadOutcome = outcome
        }
    }
}
