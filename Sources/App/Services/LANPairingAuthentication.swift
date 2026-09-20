//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import CryptoKit
import Foundation
import Security

// MARK: - Keychain

enum KeychainStoreError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case invalidData
}

struct KeychainStore {
    let service: String

    func data(for account: String) throws -> Data? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ] as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw KeychainStoreError.invalidData
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }

    func set(_ data: Data, for account: String) throws {
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let updateStatus = SecItemUpdate(
            identity as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(updateStatus)
        }

        var item = identity
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(addStatus)
        }
    }

    func remove(_ account: String) throws {
        let status = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }
}

// MARK: - Pairing credentials

protocol LANPairingCredentialStoring: AnyObject {
    func localDeviceID() throws -> String
    func secret(for peerDeviceID: String) throws -> Data?
    func save(secret: Data, for peerDeviceID: String) throws
    func pairedDeviceID(for discoveryID: String) throws -> String?
    func save(peerDeviceID: String, for discoveryID: String) throws
}

final class KeychainLANPairingCredentialStore: LANPairingCredentialStoring {
    private let keychain: KeychainStore
    private let deviceIDAccount = "identity.device-id"

    init(service: String = "com.panyang.PagePilot.lan-pairing") {
        keychain = KeychainStore(service: service)
    }

    func localDeviceID() throws -> String {
        if let data = try keychain.data(for: deviceIDAccount),
           let value = String(data: data, encoding: .utf8),
           !value.isEmpty {
            return value
        }

        let value = UUID().uuidString.lowercased()
        try keychain.set(Data(value.utf8), for: deviceIDAccount)
        return value
    }

    func secret(for peerDeviceID: String) throws -> Data? {
        try keychain.data(for: secretAccount(peerDeviceID))
    }

    func save(secret: Data, for peerDeviceID: String) throws {
        try keychain.set(secret, for: secretAccount(peerDeviceID))
    }

    func pairedDeviceID(for discoveryID: String) throws -> String? {
        guard let data = try keychain.data(for: discoveryAccount(discoveryID)) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func save(peerDeviceID: String, for discoveryID: String) throws {
        try keychain.set(Data(peerDeviceID.utf8), for: discoveryAccount(discoveryID))
    }

    private func secretAccount(_ peerDeviceID: String) -> String {
        "peer.secret.\(peerDeviceID)"
    }

    private func discoveryAccount(_ discoveryID: String) -> String {
        "peer.discovery.\(discoveryID)"
    }
}

// MARK: - Pairing bootstrap

struct LANPairingPendingOffer {
    let body: Data
    let secret: Data
}

private struct LANPairingOffer: Codable {
    let version: Int
    let deviceID: String
    let sharedSecret: String
}

private struct LANPairingResponse: Codable {
    let version: Int
    let deviceID: String
}

enum LANPairingError: Error, Equatable {
    case invalidPayload
    case invalidSecret
    case alreadyPaired
    case missingCredential
    case unexpectedHTTPStatus(Int)
}

final class LANPairingManager {
    static let shared = LANPairingManager(credentials: KeychainLANPairingCredentialStore())

    private static let protocolVersion = 1
    private static let secretByteCount = 32
    private let credentials: LANPairingCredentialStoring

    init(credentials: LANPairingCredentialStoring) {
        self.credentials = credentials
    }

    func makeOffer() throws -> LANPairingPendingOffer {
        let secret = Self.generateSecret()
        let offer = LANPairingOffer(
            version: Self.protocolVersion,
            deviceID: try credentials.localDeviceID(),
            sharedSecret: secret.base64EncodedString()
        )
        return LANPairingPendingOffer(
            body: try JSONEncoder().encode(offer),
            secret: secret
        )
    }

    func acceptOffer(_ body: Data) throws -> Data {
        guard let offer = try? JSONDecoder().decode(LANPairingOffer.self, from: body),
              offer.version == Self.protocolVersion,
              !offer.deviceID.isEmpty,
              let secret = Data(base64Encoded: offer.sharedSecret),
              secret.count == Self.secretByteCount else {
            throw LANPairingError.invalidPayload
        }

        let localDeviceID = try credentials.localDeviceID()
        if let existing = try credentials.secret(for: offer.deviceID) {
            guard existing == secret else {
                throw LANPairingError.alreadyPaired
            }
        } else {
            try credentials.save(secret: secret, for: offer.deviceID)
        }

        return try JSONEncoder().encode(
            LANPairingResponse(version: Self.protocolVersion, deviceID: localDeviceID)
        )
    }

    @discardableResult
    func completeOffer(
        _ pending: LANPairingPendingOffer,
        responseBody: Data,
        discoveryID: String
    ) throws -> String {
        guard let response = try? JSONDecoder().decode(LANPairingResponse.self, from: responseBody),
              response.version == Self.protocolVersion,
              !response.deviceID.isEmpty else {
            throw LANPairingError.invalidPayload
        }

        try credentials.save(secret: pending.secret, for: response.deviceID)
        try credentials.save(peerDeviceID: response.deviceID, for: discoveryID)
        return response.deviceID
    }

    @discardableResult
    func ensurePaired(
        with endpoint: URL,
        discoveryID: String,
        session: URLSession = .shared
    ) async throws -> String {
        if let peerDeviceID = try credentials.pairedDeviceID(for: discoveryID) {
            guard try credentials.secret(for: peerDeviceID) != nil else {
                throw LANPairingError.missingCredential
            }
            return peerDeviceID
        }

        let pending = try makeOffer()
        var request = URLRequest(url: endpoint.appendingPathComponent("pair"))
        request.httpMethod = "POST"
        request.httpBody = pending.body
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (responseBody, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw LANPairingError.unexpectedHTTPStatus(code)
        }

        return try completeOffer(
            pending,
            responseBody: responseBody,
            discoveryID: discoveryID
        )
    }

    static func generateSecret() -> Data {
        let key = SymmetricKey(size: .bits256)
        return key.withUnsafeBytes { Data($0) }
    }
}

// MARK: - Request authentication

enum LANAuthenticationHeaders {
    static let deviceID = "X-PagePilot-Device-ID"
    static let timestamp = "X-PagePilot-Timestamp"
    static let nonce = "X-PagePilot-Nonce"
    static let signature = "X-PagePilot-Signature"
}

enum LANAuthenticationFailure: Error, Equatable {
    case missingHeader(String)
    case invalidTimestamp
    case expiredTimestamp
    case unknownPeer
    case invalidSignature
    case replayedNonce

    var logCode: String {
        switch self {
        case .missingHeader: return "missing_header"
        case .invalidTimestamp: return "invalid_timestamp"
        case .expiredTimestamp: return "expired_timestamp"
        case .unknownPeer: return "unknown_peer"
        case .invalidSignature: return "invalid_signature"
        case .replayedNonce: return "replayed_nonce"
        }
    }
}

final class LANReplayProtector {
    private let retention: TimeInterval
    private let lock = NSLock()
    private var seen: [String: Date] = [:]

    init(retention: TimeInterval = 120) {
        self.retention = retention
    }

    func consume(peerDeviceID: String, nonce: String, now: Date) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        seen = seen.filter { now.timeIntervalSince($0.value) <= retention }
        let key = "\(peerDeviceID)\u{0}\(nonce)"
        guard seen[key] == nil else { return false }
        seen[key] = now
        return true
    }
}

final class LANRequestAuthenticator {
    private let credentials: LANPairingCredentialStoring
    private let allowedClockSkew: TimeInterval
    private let replayProtector: LANReplayProtector

    init(
        credentials: LANPairingCredentialStoring = KeychainLANPairingCredentialStore(),
        allowedClockSkew: TimeInterval = 120,
        replayProtector: LANReplayProtector? = nil
    ) {
        self.credentials = credentials
        self.allowedClockSkew = allowedClockSkew
        self.replayProtector = replayProtector ?? LANReplayProtector(retention: allowedClockSkew)
    }

    func authorizationHeaders(
        method: String,
        path: String,
        body: Data?,
        peerDeviceID: String,
        date: Date = Date(),
        nonce: String = UUID().uuidString.lowercased()
    ) throws -> [String: String] {
        guard let secret = try credentials.secret(for: peerDeviceID) else {
            throw LANAuthenticationFailure.unknownPeer
        }

        let deviceID = try credentials.localDeviceID()
        let timestamp = String(Int(date.timeIntervalSince1970))
        let signature = Self.signature(
            secret: secret,
            method: method,
            path: path,
            deviceID: deviceID,
            timestamp: timestamp,
            nonce: nonce,
            body: body
        )

        return [
            LANAuthenticationHeaders.deviceID: deviceID,
            LANAuthenticationHeaders.timestamp: timestamp,
            LANAuthenticationHeaders.nonce: nonce,
            LANAuthenticationHeaders.signature: signature,
        ]
    }

    func authenticate(
        method: String,
        path: String,
        body: Data?,
        headers: [String: String],
        now: Date = Date()
    ) -> Result<String, LANAuthenticationFailure> {
        guard let deviceID = Self.header(LANAuthenticationHeaders.deviceID, in: headers),
              !deviceID.isEmpty else {
            return .failure(.missingHeader(LANAuthenticationHeaders.deviceID))
        }
        guard let timestamp = Self.header(LANAuthenticationHeaders.timestamp, in: headers) else {
            return .failure(.missingHeader(LANAuthenticationHeaders.timestamp))
        }
        guard let timestampValue = TimeInterval(timestamp) else {
            return .failure(.invalidTimestamp)
        }
        guard abs(now.timeIntervalSince1970 - timestampValue) <= allowedClockSkew else {
            return .failure(.expiredTimestamp)
        }
        guard let nonce = Self.header(LANAuthenticationHeaders.nonce, in: headers),
              !nonce.isEmpty, nonce.count <= 128 else {
            return .failure(.missingHeader(LANAuthenticationHeaders.nonce))
        }
        guard let providedSignature = Self.header(LANAuthenticationHeaders.signature, in: headers),
              let providedCode = Data(base64Encoded: providedSignature) else {
            return .failure(.missingHeader(LANAuthenticationHeaders.signature))
        }

        let secret: Data
        do {
            guard let stored = try credentials.secret(for: deviceID) else {
                return .failure(.unknownPeer)
            }
            secret = stored
        } catch {
            return .failure(.unknownPeer)
        }

        let canonical = Self.canonicalMessage(
            method: method,
            path: path,
            deviceID: deviceID,
            timestamp: timestamp,
            nonce: nonce,
            body: body
        )
        let valid = HMAC<SHA256>.isValidAuthenticationCode(
            providedCode,
            authenticating: canonical,
            using: SymmetricKey(data: secret)
        )
        guard valid else {
            return .failure(.invalidSignature)
        }
        guard replayProtector.consume(peerDeviceID: deviceID, nonce: nonce, now: now) else {
            return .failure(.replayedNonce)
        }
        return .success(deviceID)
    }

    @discardableResult
    func authenticateOrLog(
        method: String,
        path: String,
        body: Data?,
        headers: [String: String],
        remoteAddress: String?,
        now: Date = Date()
    ) -> Result<String, LANAuthenticationFailure> {
        let result = authenticate(
            method: method,
            path: path,
            body: body,
            headers: headers,
            now: now
        )
        if case .failure(let failure) = result {
            LANSecurityLogger.authenticationFailure(failure, remoteAddress: remoteAddress)
        }
        return result
    }

    private static func signature(
        secret: Data,
        method: String,
        path: String,
        deviceID: String,
        timestamp: String,
        nonce: String,
        body: Data?
    ) -> String {
        let code = HMAC<SHA256>.authenticationCode(
            for: canonicalMessage(
                method: method,
                path: path,
                deviceID: deviceID,
                timestamp: timestamp,
                nonce: nonce,
                body: body
            ),
            using: SymmetricKey(data: secret)
        )
        return Data(code).base64EncodedString()
    }

    private static func canonicalMessage(
        method: String,
        path: String,
        deviceID: String,
        timestamp: String,
        nonce: String,
        body: Data?
    ) -> Data {
        let bodyDigest = Data(SHA256.hash(data: body ?? Data())).base64EncodedString()
        return Data([
            method.uppercased(),
            path,
            deviceID,
            timestamp,
            nonce,
            bodyDigest,
        ].joined(separator: "\n").utf8)
    }

    private static func header(_ name: String, in headers: [String: String]) -> String? {
        headers.first {
            $0.key.caseInsensitiveCompare(name) == .orderedSame
        }?.value
    }
}

enum LANSecurityLogger {
    static func authenticationFailure(
        _ failure: LANAuthenticationFailure,
        remoteAddress: String?
    ) {
        NSLog(
            "[Security][LAN] authentication rejected code=%@ remote=%@",
            failure.logCode,
            remoteAddress ?? "unknown"
        )
    }
}
