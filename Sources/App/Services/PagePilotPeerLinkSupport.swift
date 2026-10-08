import Foundation
import UIKit

// MARK: - Identity

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

// MARK: - Selected iPad

struct PagePilotNearbyTarget: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let bookTitle: String

    static func from(serviceName: String, name: String?, bookTitle: String?) -> Self? {
        guard let identifier = PagePilotRelayIdentity.identifier(fromServiceName: serviceName) else {
            return nil
        }
        let name = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Self(
            id: identifier,
            name: name.isEmpty ? "iPad" : name,
            bookTitle: bookTitle ?? ""
        )
    }
}

enum PagePilotNearbySelectionStore {
    private static let key = "pagepilot_nearby_selected_target"
    private static let legacyAssociatedTargetKey = "pagepilot_nearby_associated_target"

    static func selectedTarget(defaults: UserDefaults = .standard) -> PagePilotNearbyTarget? {
        migrateLegacyAssociation(defaults: defaults)
        guard let data = defaults.data(forKey: key),
              let target = try? JSONDecoder().decode(PagePilotNearbyTarget.self, from: data),
              UUID(uuidString: target.id) != nil else { return nil }
        return target
    }

    static func remember(_ target: PagePilotNearbyTarget, defaults: UserDefaults = .standard) {
        guard UUID(uuidString: target.id) != nil,
              let data = try? JSONEncoder().encode(target) else { return }
        defaults.set(data, forKey: key)
    }

    /// Before manual selection, the iPhone learned the iPad identity from LAN
    /// traffic. Carry that identity forward once so upgraded users keep working.
    private static func migrateLegacyAssociation(defaults: UserDefaults) {
        guard let legacy = defaults.string(forKey: legacyAssociatedTargetKey) else { return }
        defaults.removeObject(forKey: legacyAssociatedTargetKey)
        guard defaults.data(forKey: key) == nil,
              UUID(uuidString: legacy) != nil else { return }
        remember(PagePilotNearbyTarget(id: legacy.lowercased(), name: "iPad", bookTitle: ""), defaults: defaults)
    }
}

// MARK: - Entitlement

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

// MARK: - Wire protocol

/// Failures surfaced by the peer link. Host-side rejections travel over the
/// wire by raw value so the iPhone can tell "wrong iPad" from "no Pro".
enum PagePilotPeerError: String, Error, Equatable {
    case notFound
    case unreachable
    case timedOut
    case connectionLost
    case invalidMessage
    case wrongTarget
    case proRequired

    var watchErrorCode: String {
        switch self {
        case .notFound, .wrongTarget:
            return WatchPageTurnErrorCode.iPadNotFound
        case .proRequired:
            return WatchPageTurnErrorCode.proRequired
        case .unreachable, .timedOut, .connectionLost, .invalidMessage:
            return WatchPageTurnErrorCode.relayTimeout
        }
    }

    /// A dropped or stale connection is worth one fresh reconnect. A timeout
    /// already spent the caller's budget, and host rejections are final.
    var isRetryable: Bool {
        switch self {
        case .unreachable, .connectionLost:
            return true
        case .notFound, .timedOut, .invalidMessage, .wrongTarget, .proRequired:
            return false
        }
    }
}

enum PagePilotPeerRequestKind: String, Equatable {
    case status
    case command
}

struct PagePilotPeerRequest: Equatable {
    let id: String
    let target: String
    let kind: PagePilotPeerRequestKind
    let action: PageCommand?
    /// Stable across retries so the iPad turns the page at most once.
    let commandID: String?

    init(
        id: String = UUID().uuidString,
        target: String,
        kind: PagePilotPeerRequestKind,
        action: PageCommand? = nil,
        commandID: String? = nil
    ) {
        self.id = id
        self.target = target.lowercased()
        self.kind = kind
        self.action = action
        self.commandID = commandID
    }

    init?(frameObject object: [String: Any]) {
        guard let id = object["id"] as? String,
              let target = object["target"] as? String,
              let kind = (object["kind"] as? String).flatMap(PagePilotPeerRequestKind.init(rawValue:)) else {
            return nil
        }
        let action = (object["action"] as? String).flatMap(PageCommand.init(rawValue:))
        if kind == .command, action == nil { return nil }
        self.init(id: id, target: target, kind: kind, action: action, commandID: object["commandId"] as? String)
    }

    var frameObject: [String: Any] {
        var object: [String: Any] = ["id": id, "target": target, "kind": kind.rawValue]
        if let action { object["action"] = action.rawValue }
        if let commandID { object["commandId"] = commandID }
        return object
    }
}

enum PagePilotPeerResponse {
    static func success(id: String, payload: [String: Any]) -> [String: Any] {
        ["id": id, "payload": payload]
    }

    static func failure(id: String, error: PagePilotPeerError) -> [String: Any] {
        ["id": id, "error": error.rawValue]
    }

    static func parse(_ object: [String: Any]) -> (id: String, result: Result<[String: Any], PagePilotPeerError>)? {
        guard let id = object["id"] as? String else { return nil }
        if let raw = object["error"] as? String {
            return (id, .failure(PagePilotPeerError(rawValue: raw) ?? .invalidMessage))
        }
        guard let payload = object["payload"] as? [String: Any] else { return nil }
        return (id, .success(payload))
    }
}

enum PagePilotPeerHostValidation {
    static func rejection(
        for request: PagePilotPeerRequest,
        localIdentifier: String,
        hasProAccess: Bool
    ) -> PagePilotPeerError? {
        guard request.target == localIdentifier.lowercased() else { return .wrongTarget }
        guard hasProAccess else { return .proRequired }
        return nil
    }
}

/// Newline-delimited JSON frames. A persistent connection carries many frames,
/// and one network read may hold several of them or only part of one.
enum PagePilotPeerFrame {
    static let maximumBytes = 64 * 1024

    static func encode(_ object: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw PagePilotPeerError.invalidMessage
        }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        return data
    }
}

struct PagePilotPeerFrameDecoder {
    private(set) var buffer = Data()

    mutating func append(_ fragment: Data) throws -> [[String: Any]] {
        buffer.append(fragment)
        var frames: [[String: Any]] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer = Data(buffer[buffer.index(after: newline)...])
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                throw PagePilotPeerError.invalidMessage
            }
            frames.append(object)
        }
        guard buffer.count <= PagePilotPeerFrame.maximumBytes else {
            throw PagePilotPeerError.invalidMessage
        }
        return frames
    }
}

/// Requests waiting for a response on the current connection, keyed by id.
struct PagePilotPeerPendingRequests<Value> {
    private var values: [String: Value] = [:]
    private var order: [String] = []

    var isEmpty: Bool { values.isEmpty }
    var ids: [String] { order }

    mutating func add(_ value: Value, for id: String) {
        if values.updateValue(value, forKey: id) == nil {
            order.append(id)
        }
    }

    mutating func remove(_ id: String) -> Value? {
        guard let value = values.removeValue(forKey: id) else { return nil }
        order.removeAll { $0 == id }
        return value
    }

    mutating func removeAll() -> [Value] {
        let drained = order.compactMap { values[$0] }
        values.removeAll()
        order.removeAll()
        return drained
    }
}
