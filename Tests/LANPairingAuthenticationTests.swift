//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import XCTest
@testable import PagePilot

final class LANPairingAuthenticationTests: XCTestCase {
    func testKeychainStorePersistsReadsAndDeletesData() throws {
        let store = KeychainStore(service: "com.panyang.PagePilotTests.\(UUID().uuidString)")
        let account = "roundtrip"
        let value = Data("pairing-secret".utf8)

        XCTAssertNil(try store.data(for: account))
        try store.set(value, for: account)
        XCTAssertEqual(try store.data(for: account), value)
        try store.remove(account)
        XCTAssertNil(try store.data(for: account))
    }

    func testPairingGenerates256BitSecretAndStoresSameSecretOnBothPeers() throws {
        let senderStore = InMemoryPairingStore(deviceID: "iphone")
        let receiverStore = InMemoryPairingStore(deviceID: "ipad")
        let sender = LANPairingManager(credentials: senderStore)
        let receiver = LANPairingManager(credentials: receiverStore)

        let pending = try sender.makeOffer()
        XCTAssertEqual(pending.secret.count, 32)

        let response = try receiver.acceptOffer(pending.body)
        let peerID = try sender.completeOffer(
            pending,
            responseBody: response,
            discoveryID: "PagePilot-iPad"
        )

        XCTAssertEqual(peerID, "ipad")
        XCTAssertEqual(senderStore.secrets["ipad"], pending.secret)
        XCTAssertEqual(receiverStore.secrets["iphone"], pending.secret)
        XCTAssertEqual(senderStore.discoveryMap["PagePilot-iPad"], "ipad")
    }

    func testPairingDoesNotSilentlyReplaceExistingPeerSecret() throws {
        let receiverStore = InMemoryPairingStore(deviceID: "ipad")
        receiverStore.secrets["iphone"] = Data(repeating: 1, count: 32)
        let receiver = LANPairingManager(credentials: receiverStore)

        let senderStore = InMemoryPairingStore(deviceID: "iphone")
        let sender = LANPairingManager(credentials: senderStore)
        let pending = try sender.makeOffer()

        XCTAssertThrowsError(try receiver.acceptOffer(pending.body)) { error in
            XCTAssertEqual(error as? LANPairingError, .alreadyPaired)
        }
        XCTAssertEqual(receiverStore.secrets["iphone"], Data(repeating: 1, count: 32))
    }

    func testSignedRequestVerifiesAndDetectsTampering() throws {
        let secret = Data(repeating: 0x5A, count: 32)
        let senderStore = InMemoryPairingStore(deviceID: "iphone")
        senderStore.secrets["ipad"] = secret
        let receiverStore = InMemoryPairingStore(deviceID: "ipad")
        receiverStore.secrets["iphone"] = secret

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let sender = LANRequestAuthenticator(credentials: senderStore)
        let receiver = LANRequestAuthenticator(credentials: receiverStore)
        let body = Data(#"{"action":"next"}"#.utf8)

        let headers = try sender.authorizationHeaders(
            method: "POST",
            path: "/command",
            body: body,
            peerDeviceID: "ipad",
            date: date,
            nonce: "nonce-1"
        )

        XCTAssertEqual(
            receiver.authenticate(
                method: "POST",
                path: "/command",
                body: body,
                headers: headers,
                now: date
            ),
            .success("iphone")
        )

        let freshReceiver = LANRequestAuthenticator(credentials: receiverStore)
        XCTAssertEqual(
            freshReceiver.authenticate(
                method: "POST",
                path: "/command",
                body: Data(#"{"action":"prev"}"#.utf8),
                headers: headers,
                now: date
            ),
            .failure(.invalidSignature)
        )
    }

    func testReplayNonceIsRejected() throws {
        let secret = Data(repeating: 0x11, count: 32)
        let senderStore = InMemoryPairingStore(deviceID: "iphone")
        senderStore.secrets["ipad"] = secret
        let receiverStore = InMemoryPairingStore(deviceID: "ipad")
        receiverStore.secrets["iphone"] = secret

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let sender = LANRequestAuthenticator(credentials: senderStore)
        let receiver = LANRequestAuthenticator(credentials: receiverStore)
        let headers = try sender.authorizationHeaders(
            method: "GET",
            path: "/status",
            body: nil,
            peerDeviceID: "ipad",
            date: date,
            nonce: "replay-me"
        )

        XCTAssertEqual(
            receiver.authenticate(
                method: "GET",
                path: "/status",
                body: nil,
                headers: headers,
                now: date
            ),
            .success("iphone")
        )
        XCTAssertEqual(
            receiver.authenticate(
                method: "GET",
                path: "/status",
                body: nil,
                headers: headers,
                now: date
            ),
            .failure(.replayedNonce)
        )
    }

    func testExpiredTimestampIsRejectedBeforeNonceConsumption() throws {
        let secret = Data(repeating: 0x22, count: 32)
        let senderStore = InMemoryPairingStore(deviceID: "iphone")
        senderStore.secrets["ipad"] = secret
        let receiverStore = InMemoryPairingStore(deviceID: "ipad")
        receiverStore.secrets["iphone"] = secret

        let signedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let sender = LANRequestAuthenticator(credentials: senderStore)
        let receiver = LANRequestAuthenticator(
            credentials: receiverStore,
            allowedClockSkew: 60
        )
        let headers = try sender.authorizationHeaders(
            method: "GET",
            path: "/status",
            body: nil,
            peerDeviceID: "ipad",
            date: signedAt,
            nonce: "expired"
        )

        XCTAssertEqual(
            receiver.authenticate(
                method: "GET",
                path: "/status",
                body: nil,
                headers: headers,
                now: signedAt.addingTimeInterval(61)
            ),
            .failure(.expiredTimestamp)
        )
    }

    func testDeviceTransferBootstrapsPairingBeforeUpload() throws {
        let source = try Self.source(
            named: "Sources/Library/DeviceTransfer/DeviceTransferService.swift"
        )

        XCTAssertTrue(source.contains(#"path: "/pair""#))
        XCTAssertTrue(source.contains("LANPairingManager.shared.acceptOffer"))
        XCTAssertTrue(source.contains("LANPairingManager.shared.ensurePaired("))
        XCTAssertTrue(source.contains("discoveryID: peer.id"))
    }

    private static func source(named path: String) throws -> String {
        let repositoryURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryURL.appendingPathComponent(path),
            encoding: .utf8
        )
    }
}

private final class InMemoryPairingStore: LANPairingCredentialStoring {
    let deviceID: String
    var secrets: [String: Data] = [:]
    var discoveryMap: [String: String] = [:]

    init(deviceID: String) {
        self.deviceID = deviceID
    }

    func localDeviceID() throws -> String {
        deviceID
    }

    func secret(for peerDeviceID: String) throws -> Data? {
        secrets[peerDeviceID]
    }

    func save(secret: Data, for peerDeviceID: String) throws {
        secrets[peerDeviceID] = secret
    }

    func pairedDeviceID(for discoveryID: String) throws -> String? {
        discoveryMap[discoveryID]
    }

    func save(peerDeviceID: String, for discoveryID: String) throws {
        discoveryMap[discoveryID] = peerDeviceID
    }
}
