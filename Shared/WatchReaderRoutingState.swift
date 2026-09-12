import Foundation

enum WatchReaderDestination: String, Sendable {
    case iPhone = "iphone"
    case iPad = "ipad"
}

/// Pure routing state shared by the Watch target and iOS unit tests.
///
/// Reader readiness is owned by live status responses. A lost Watch -> iPhone
/// transport invalidates both cached Reader-ready states because the iPad relay
/// also depends on that transport. Per-command delivery failures are tracked
/// separately in `WatchCommandOutcomeState` and must not mutate this state.
struct WatchReaderRoutingState: Equatable, Sendable {
    var iPhoneReady: Bool
    var iPadReady: Bool
    var iPhoneError: String
    var iPadError: String

    init(
        iPhoneReady: Bool = false,
        iPadReady: Bool = false,
        iPhoneError: String = "",
        iPadError: String = ""
    ) {
        self.iPhoneReady = iPhoneReady
        self.iPadReady = iPadReady
        self.iPhoneError = iPhoneError
        self.iPadError = iPadError
    }

    var activeReaderCount: Int {
        (iPhoneReady ? 1 : 0) + (iPadReady ? 1 : 0)
    }

    var readerReady: Bool {
        activeReaderCount > 0
    }

    /// Optional status-path errors stay hidden while another Reader remains
    /// reachable. Command-level delivery errors are handled separately so a
    /// ready status cannot swallow a page-turn failure.
    var visibleError: String {
        guard !readerReady else { return "" }
        if !iPhoneError.isEmpty { return iPhoneError }
        return iPadError
    }

    mutating func invalidateForTransportFailure(error: String) {
        iPhoneReady = false
        iPadReady = false
        iPhoneError = error
        iPadError = ""
    }
}
