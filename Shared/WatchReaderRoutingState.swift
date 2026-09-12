import Foundation

enum WatchReaderDestination: String, Sendable {
    case iPhone = "iphone"
    case iPad = "ipad"
}

/// Pure routing state shared by the Watch target and iOS unit tests.
///
/// A Reader being "ready" is only meaningful while the transport path that
/// produced that status is still usable. In particular, every iPad command
/// still travels Watch -> iPhone before the iPhone can relay it over LAN, so a
/// lost WCSession invalidates both cached Reader-ready states.
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

    /// Optional destination errors stay hidden while another Reader remains
    /// reachable. Once no Reader can respond, prefer the iPhone/transport error
    /// because the iPad relay also depends on that transport.
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

    mutating func invalidateForSendFailure(
        to destination: WatchReaderDestination,
        transportReachable: Bool,
        error: String
    ) {
        guard transportReachable else {
            invalidateForTransportFailure(error: error)
            return
        }

        switch destination {
        case .iPhone:
            iPhoneReady = false
            iPhoneError = error
        case .iPad:
            iPadReady = false
            iPadError = error
        }
    }
}
