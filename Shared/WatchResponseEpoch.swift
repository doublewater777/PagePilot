import Foundation

struct WatchResponseToken: Equatable, Sendable {
    let transportEpoch: UInt64
    let requestSequence: UInt64
    let destination: WatchReaderDestination
}

/// Tracks both the lifetime of the Watch -> iPhone transport and the newest
/// real-time request for each Reader destination.
///
/// Transport invalidation rejects every callback from the previous WCSession
/// lifetime. Within one lifetime, only the newest request for a destination may
/// update readiness, so an older slow reply cannot overwrite a newer status.
struct WatchResponseEpoch: Equatable, Sendable {
    private(set) var value: UInt64 = 0
    private var iPhoneSequence: UInt64 = 0
    private var iPadSequence: UInt64 = 0

    mutating func beginRequest(to destination: WatchReaderDestination) -> WatchResponseToken {
        let sequence: UInt64
        switch destination {
        case .iPhone:
            iPhoneSequence &+= 1
            sequence = iPhoneSequence
        case .iPad:
            iPadSequence &+= 1
            sequence = iPadSequence
        }

        return WatchResponseToken(
            transportEpoch: value,
            requestSequence: sequence,
            destination: destination
        )
    }

    mutating func invalidateTransport() {
        value &+= 1
        iPhoneSequence = 0
        iPadSequence = 0
    }

    func belongsToCurrentTransport(_ token: WatchResponseToken) -> Bool {
        token.transportEpoch == value
    }

    func accepts(_ token: WatchResponseToken, transportReachable: Bool) -> Bool {
        guard transportReachable, belongsToCurrentTransport(token) else {
            return false
        }

        switch token.destination {
        case .iPhone:
            return token.requestSequence == iPhoneSequence
        case .iPad:
            return token.requestSequence == iPadSequence
        }
    }
}
