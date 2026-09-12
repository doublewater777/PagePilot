import Foundation

/// Tracks the lifetime of the current Watch -> iPhone transport.
///
/// Every real-time status or command request captures the current token. When
/// WCSession becomes unavailable, the epoch advances so any delayed reply from
/// the old transport lifetime can no longer restore stale Reader readiness.
struct WatchResponseEpoch: Equatable, Sendable {
    private(set) var value: UInt64 = 0

    var token: UInt64 { value }

    mutating func invalidateTransport() {
        value &+= 1
    }

    func accepts(_ token: UInt64, transportReachable: Bool) -> Bool {
        transportReachable && token == value
    }
}
