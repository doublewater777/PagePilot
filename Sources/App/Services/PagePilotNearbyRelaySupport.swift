import Foundation
import UIKit

enum PagePilotRelayIdentity {
    static let serviceNamePrefix = "PagePilot-iPad-"
    private static let identifierKey = "pagepilot_relay_identifier"

    static func localIdentifier(defaults: UserDefaults = .standard) -> String {
        if let deviceIdentifier = UIDevice.current.identifierForVendor?.uuidString.lowercased() {
            defaults.set(deviceIdentifier, forKey: identifierKey)
            return deviceIdentifier
        }

        if let existing = defaults.string(forKey: identifierKey),
           UUID(uuidString: existing) != nil {
            return existing.lowercased()
        }

        let identifier = UUID().uuidString.lowercased()
        defaults.set(identifier, forKey: identifierKey)
        return identifier
    }

    static func serviceName(for identifier: String) -> String {
        serviceNamePrefix + identifier.lowercased()
    }

    static func identifier(fromServiceName serviceName: String) -> String? {
        guard serviceName.hasPrefix(serviceNamePrefix) else { return nil }
        let raw = String(serviceName.dropFirst(serviceNamePrefix.count)).lowercased()
        guard UUID(uuidString: raw) != nil else { return nil }
        return raw
    }
}

enum PagePilotNearbyRequestValidator {
    static func isValid(path: String, method: String) -> Bool {
        (path == "status" && method == "GET")
            || (path == "command" && method == "POST")
    }
}

enum PagePilotNearbyTargetSelectionPolicy {
    static func matches(serviceName: String, expectedIdentifier: String?) -> Bool {
        guard let expectedIdentifier else { return false }
        return PagePilotRelayIdentity.identifier(fromServiceName: serviceName)
            == expectedIdentifier.lowercased()
    }

    static func selectServiceName(
        from serviceNames: [String],
        expectedIdentifier: String?
    ) -> String? {
        serviceNames.first {
            matches(serviceName: $0, expectedIdentifier: expectedIdentifier)
        }
    }
}

enum PagePilotNearbyRelayErrorCategory: Equatable {
    case notFound
    case transport
    case authorization
}

enum PagePilotNearbyRelayError: LocalizedError, Equatable {
    case invalidMessage
    case noService
    case connectionFailed(String)
    case timedOut
    case authorizationRevoked

    var category: PagePilotNearbyRelayErrorCategory {
        switch self {
        case .noService:
            return .notFound
        case .authorizationRevoked:
            return .authorization
        case .invalidMessage, .connectionFailed, .timedOut:
            return .transport
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidMessage:
            return "Invalid nearby relay message."
        case .noService:
            return "No associated nearby PagePilot iPad was found."
        case .connectionFailed(let message):
            return message
        case .timedOut:
            return "Nearby relay timed out."
        case .authorizationRevoked:
            return "Pro access is required for nearby iPad relay."
        }
    }
}

enum PagePilotNearbyRelayFrame {
    static let maximumBytes = 64 * 1024

    static func encode(_ object: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw PagePilotNearbyRelayError.invalidMessage
        }

        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        return data
    }

    static func decode(_ data: Data) throws -> [String: Any] {
        guard data.count <= maximumBytes,
              let newline = data.firstIndex(of: 0x0A) else {
            throw PagePilotNearbyRelayError.invalidMessage
        }

        let payload = data[..<newline]
        guard let object = try JSONSerialization.jsonObject(with: Data(payload)) as? [String: Any] else {
            throw PagePilotNearbyRelayError.invalidMessage
        }
        return object
    }
}

struct PagePilotNearbyFrameBuffer {
    enum Result {
        case incomplete
        case complete([String: Any])
    }

    private(set) var data = Data()

    mutating func append(_ fragment: Data) throws -> Result {
        data.append(fragment)
        guard data.count <= PagePilotNearbyRelayFrame.maximumBytes else {
            throw PagePilotNearbyRelayError.invalidMessage
        }
        guard data.contains(0x0A) else {
            return .incomplete
        }
        return .complete(try PagePilotNearbyRelayFrame.decode(data))
    }
}

enum PagePilotNearbyLifecycleEvent {
    case browserStarted
    case targetSelected
    case browserFailed
    case connectionFailed
    case stop(clearEndpoint: Bool)
}

enum PagePilotNearbyLifecycleAction: Equatable {
    case stopBrowser
    case clearEndpoint
    case flushPending
}

struct PagePilotNearbyLifecycleState: Equatable {
    private(set) var isBrowsing = false
    private(set) var hasCachedEndpoint = false

    mutating func cacheEndpoint() {
        hasCachedEndpoint = true
    }

    mutating func handle(_ event: PagePilotNearbyLifecycleEvent) -> [PagePilotNearbyLifecycleAction] {
        switch event {
        case .browserStarted:
            isBrowsing = true
            return []

        case .targetSelected:
            isBrowsing = false
            hasCachedEndpoint = true
            return [.stopBrowser, .flushPending]

        case .browserFailed:
            isBrowsing = false
            return [.stopBrowser, .flushPending]

        case .connectionFailed:
            hasCachedEndpoint = false
            return [.clearEndpoint]

        case .stop(let clearEndpoint):
            isBrowsing = false
            if clearEndpoint {
                hasCachedEndpoint = false
                return [.stopBrowser, .clearEndpoint, .flushPending]
            }
            return [.stopBrowser, .flushPending]
        }
    }
}

enum PagePilotRelayEntitlementAction: Equatable {
    case start
    case stop
    case noOp
}

enum PagePilotRelayEntitlementLifecyclePolicy {
    static func action(isIPad: Bool, hasProAccess: Bool) -> PagePilotRelayEntitlementAction {
        guard isIPad else { return .noOp }
        return hasProAccess ? .start : .stop
    }
}


enum PagePilotNearbyWatchFailure: Equatable {
    case iPadNotFound
    case relayTimeout
    case proRequired
}

enum PagePilotNearbyWatchFailurePolicy {
    static func failure(for error: Error) -> PagePilotNearbyWatchFailure {
        guard let nearbyError = error as? PagePilotNearbyRelayError else {
            return .relayTimeout
        }

        switch nearbyError.category {
        case .notFound:
            return .iPadNotFound
        case .transport:
            return .relayTimeout
        case .authorization:
            return .proRequired
        }
    }
}

enum PagePilotRelayRoutingStep: Equatable {
    case lan
    case nearby
    case failNotFound
}

enum PagePilotRelayRoutingPolicy {
    static func initialStep(
        candidateSource: PagePilotLANEndpointSource?,
        hasNearbyTarget: Bool,
        allowNearby: Bool = true
    ) -> PagePilotRelayRoutingStep {
        guard let candidateSource else {
            return allowNearby && hasNearbyTarget ? .nearby : .failNotFound
        }
        if allowNearby,
           PagePilotRelayTransportPolicy.shouldTryNearbyBeforeLAN(candidateSource),
           hasNearbyTarget {
            return .nearby
        }
        return .lan
    }

    static func stepAfterLANFailure(hasNearbyTarget: Bool) -> PagePilotRelayRoutingStep {
        hasNearbyTarget ? .nearby : .lan
    }

    static func stepAfterNearbyFailure(hasLANFallback: Bool) -> PagePilotRelayRoutingStep {
        hasLANFallback ? .lan : .failNotFound
    }
}


enum PagePilotNearbyPendingRequestAction: Equatable {
    case proceed
    case cancel
}

enum PagePilotNearbyPendingRequestPolicy {
    static func action(hasProAccess: Bool) -> PagePilotNearbyPendingRequestAction {
        hasProAccess ? .proceed : .cancel
    }

    static func shouldProceed(hasProAccess: Bool) -> Bool {
        action(hasProAccess: hasProAccess) == .proceed
    }
}

enum PagePilotNearbyListenerFailurePolicy {
    static func shouldClearListener(callbackIsCurrent: Bool) -> Bool {
        callbackIsCurrent
    }
}
