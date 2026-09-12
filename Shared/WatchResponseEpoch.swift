import Foundation

enum WatchResponseKind: Equatable, Sendable {
    case status
    case command

    /// Real-time status polling is the single authority for cached Reader
    /// readiness and metadata. Command callbacks remain independently ordered so
    /// their outcome/error feedback is never swallowed by polling, but they must
    /// not promote stale Reader state after a newer status observation.
    var carriesAuthoritativeReaderState: Bool {
        self == .status
    }
}

struct WatchResponseToken: Equatable, Sendable {
    let transportEpoch: UInt64
    let requestSequence: UInt64
    let destination: WatchReaderDestination
    let kind: WatchResponseKind
}

/// Tracks both the lifetime of the Watch -> iPhone transport and the newest
/// real-time request for each Reader destination and request kind.
///
/// Transport invalidation rejects every callback from the previous WCSession
/// lifetime. Within one lifetime, only the newest request of the same kind for
/// a destination may update state. Status polling therefore cannot invalidate
/// an in-flight page-turn command (or vice versa).
struct WatchResponseEpoch: Equatable, Sendable {
    private(set) var value: UInt64 = 0
    private var iPhoneStatusSequence: UInt64 = 0
    private var iPhoneCommandSequence: UInt64 = 0
    private var iPadStatusSequence: UInt64 = 0
    private var iPadCommandSequence: UInt64 = 0

    mutating func beginRequest(
        to destination: WatchReaderDestination,
        kind: WatchResponseKind
    ) -> WatchResponseToken {
        let sequence: UInt64
        switch (destination, kind) {
        case (.iPhone, .status):
            iPhoneStatusSequence &+= 1
            sequence = iPhoneStatusSequence
        case (.iPhone, .command):
            iPhoneCommandSequence &+= 1
            sequence = iPhoneCommandSequence
        case (.iPad, .status):
            iPadStatusSequence &+= 1
            sequence = iPadStatusSequence
        case (.iPad, .command):
            iPadCommandSequence &+= 1
            sequence = iPadCommandSequence
        }

        return WatchResponseToken(
            transportEpoch: value,
            requestSequence: sequence,
            destination: destination,
            kind: kind
        )
    }

    mutating func invalidateTransport() {
        value &+= 1
        iPhoneStatusSequence = 0
        iPhoneCommandSequence = 0
        iPadStatusSequence = 0
        iPadCommandSequence = 0
    }

    func belongsToCurrentTransport(_ token: WatchResponseToken) -> Bool {
        token.transportEpoch == value
    }

    func accepts(_ token: WatchResponseToken, transportReachable: Bool) -> Bool {
        guard transportReachable, belongsToCurrentTransport(token) else {
            return false
        }

        return token.requestSequence == currentSequence(
            for: token.destination,
            kind: token.kind
        )
    }

    private func currentSequence(
        for destination: WatchReaderDestination,
        kind: WatchResponseKind
    ) -> UInt64 {
        switch (destination, kind) {
        case (.iPhone, .status):
            return iPhoneStatusSequence
        case (.iPhone, .command):
            return iPhoneCommandSequence
        case (.iPad, .status):
            return iPadStatusSequence
        case (.iPad, .command):
            return iPadCommandSequence
        }
    }
}
