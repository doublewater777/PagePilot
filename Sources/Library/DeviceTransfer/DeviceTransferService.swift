//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import Foundation
import ReadiumGCDWebServer
import ReadiumShared
import UIKit

// MARK: - Discovered Peer

struct TransferPeer: Identifiable, Equatable {
    let id: String          // Bonjour service name
    let name: String        // Human-readable device name
    let endpoint: URL
}

// MARK: - DeviceTransferService

/// Manages LAN book transfer between PagePilot instances.
///
/// **Sender side**: discovers peers via Bonjour, then POSTs book files
/// directly to the peer's HTTP server.
///
/// **Receiver side**: runs an HTTP server that accepts incoming book files
/// and imports them into the local library.
final class DeviceTransferService: NSObject, ObservableObject {

    static let shared = DeviceTransferService()

    // MARK: - Published State

    @Published private(set) var discoveredPeers: [TransferPeer] = []
    @Published private(set) var isReceiving: Bool = false
    @Published private(set) var receivedCount: Int = 0

    /// Called on main thread when a file has been received and saved to disk.
    var onFileReceived: ((URL) -> Void)?

    // MARK: - Private

    private let serviceType = "_pagepilot-transfer._tcp."
    private let serviceDomain = "local."
    private let port: UInt = 61483

    private var server: ReadiumGCDWebServer?
    private var browser: NetServiceBrowser?
    private var services: [NetService] = []
    private var publishedService: NetService?

    private override init() {}

    // MARK: - Receiver

    /// Start the HTTP server and advertise via Bonjour so other devices can find us.
    func startReceiving() {
        guard server == nil else { return }

        let webServer = ReadiumGCDWebServer()

        // GET /ping — lets senders verify we're alive
        webServer.addHandler(
            forMethod: "GET",
            path: "/ping",
            request: ReadiumGCDWebServerRequest.self,
            processBlock: { _ in
                ReadiumGCDWebServerDataResponse(
                    data: Data("{\"ok\":true}".utf8),
                    contentType: "application/json"
                )
            }
        )

        // POST /receive — accepts a single book file
        webServer.addHandler(
            forMethod: "POST",
            path: "/receive",
            request: ReadiumGCDWebServerDataRequest.self,
            processBlock: { [weak self] request in
                self?.handleIncomingFile(request: request)
            }
        )

        do {
            let deviceName = UIDevice.current.name.replacingOccurrences(of: " ", with: "-")
            try webServer.start(options: [
                ReadiumGCDWebServerOption_Port: port,
                ReadiumGCDWebServerOption_BonjourName: "PagePilot-\(deviceName)",
                ReadiumGCDWebServerOption_BonjourType: serviceType.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
                ReadiumGCDWebServerOption_AutomaticallySuspendInBackground: false,
            ])
            self.server = webServer
            DispatchQueue.main.async { self.isReceiving = true }
            print("DeviceTransfer: receiver started on port \(webServer.port)")
        } catch {
            do {
                let deviceName = UIDevice.current.name.replacingOccurrences(of: " ", with: "-")
                try webServer.start(options: [
                    ReadiumGCDWebServerOption_Port: 0,
                    ReadiumGCDWebServerOption_BonjourName: "PagePilot-\(deviceName)",
                    ReadiumGCDWebServerOption_BonjourType: serviceType.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
                    ReadiumGCDWebServerOption_AutomaticallySuspendInBackground: false,
                ])
                self.server = webServer
                DispatchQueue.main.async { self.isReceiving = true }
                print("DeviceTransfer: receiver started on fallback port \(webServer.port)")
            } catch {
                print("DeviceTransfer: failed to start receiver: \(error)")
            }
        }
    }

    func stopReceiving() {
        server?.stop()
        server = nil
        DispatchQueue.main.async {
            self.isReceiving = false
            self.receivedCount = 0
        }
    }

    // MARK: - Sender / Discovery

    func startDiscovery() {
        guard browser == nil else { return }
        let b = NetServiceBrowser()
        b.delegate = self
        b.searchForServices(ofType: serviceType, inDomain: serviceDomain)
        browser = b
        print("DeviceTransfer: browsing for peers")
    }

    func stopDiscovery() {
        browser?.stop()
        browser = nil
        services.removeAll()
        DispatchQueue.main.async { self.discoveredPeers.removeAll() }
    }

    /// Sends a single book file to the given peer.
    /// Returns the number of bytes sent, or throws on failure.
    func sendBook(at fileURL: URL, to peer: TransferPeer, progress: @escaping (Double) -> Void) async throws {
        let filename = fileURL.lastPathComponent

        var request = URLRequest(url: peer.endpoint.appendingPathComponent("receive"))
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(filename.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filename,
                         forHTTPHeaderField: "X-Filename")
        request.timeoutInterval = 60

        let (_, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DeviceTransferError.sendFailed
        }
        progress(1.0)
    }

    // MARK: - Incoming file handler

    private func handleIncomingFile(request: ReadiumGCDWebServerRequest?) -> ReadiumGCDWebServerResponse? {
        guard let dataRequest = request as? ReadiumGCDWebServerDataRequest,
              !dataRequest.data.isEmpty
        else {
            return errorResponse(message: "No data", status: 400)
        }
        let data = dataRequest.data

        // Decode filename from header
        let rawFilename = request?.headers["X-Filename"] as? String ?? "book"
        let filename = rawFilename.removingPercentEncoding ?? rawFilename
        let sanitized = filename.sanitizedPathComponent
        let destURL = Paths.documents.appendingUniquePathComponent(sanitized).url

        do {
            try data.write(to: destURL, options: .atomic)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.receivedCount += 1
                self.onFileReceived?(destURL)
            }
            print("DeviceTransfer: received \(filename) → \(destURL.lastPathComponent)")
            return ReadiumGCDWebServerDataResponse(
                data: Data("{\"ok\":true}".utf8),
                contentType: "application/json"
            )
        } catch {
            print("DeviceTransfer: failed to save \(filename): \(error)")
            return errorResponse(message: error.localizedDescription, status: 500)
        }
    }

    private func errorResponse(message: String, status: Int) -> ReadiumGCDWebServerDataResponse {
        let payload: [String: Any] = ["ok": false, "error": message]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{\"ok\":false}".utf8)
        let r = ReadiumGCDWebServerDataResponse(data: data, contentType: "application/json")
        r.statusCode = status
        return r
    }
}

// MARK: - NetServiceBrowserDelegate

extension DeviceTransferService: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard service.name.hasPrefix("PagePilot-") else { return }
        print("DeviceTransfer: found \(service.name)")
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services.removeAll { $0 === service }
        DispatchQueue.main.async {
            self.discoveredPeers.removeAll { $0.id == service.name }
        }
    }
}

// MARK: - NetServiceDelegate

extension DeviceTransferService: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let endpoint = endpointURL(for: sender) else { return }
        let deviceName = sender.name
            .replacingOccurrences(of: "PagePilot-", with: "")
            .replacingOccurrences(of: "-", with: " ")
        let peer = TransferPeer(id: sender.name, name: deviceName, endpoint: endpoint)
        print("DeviceTransfer: resolved \(sender.name) → \(endpoint)")
        DispatchQueue.main.async {
            if !self.discoveredPeers.contains(where: { $0.id == peer.id }) {
                self.discoveredPeers.append(peer)
            }
        }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        print("DeviceTransfer: failed to resolve \(sender.name): \(errorDict)")
    }

    private func endpointURL(for service: NetService) -> URL? {
        guard let addresses = service.addresses else { return nil }
        for address in addresses {
            if let url = ipv4URL(from: address, port: service.port) { return url }
        }
        // Fallback to hostname
        guard service.port > 0 else { return nil }
        let raw = service.hostName ?? "\(service.name).local"
        let host = raw.hasSuffix(".") ? String(raw.dropLast()) : raw
        return URL(string: "http://\(host):\(service.port)")
    }

    private func ipv4URL(from address: Data, port: Int) -> URL? {
        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = address.withUnsafeBytes { rawBuf -> Int32 in
            guard let ptr = rawBuf.baseAddress?.assumingMemoryBound(to: sockaddr.self),
                  ptr.pointee.sa_family == sa_family_t(AF_INET) else { return EAI_FAIL }
            return getnameinfo(ptr, socklen_t(address.count),
                               &hostBuffer, socklen_t(hostBuffer.count),
                               nil, 0, NI_NUMERICHOST)
        }
        guard result == 0 else { return nil }
        let host = String(cString: hostBuffer)
        return URL(string: "http://\(host):\(port)")
    }
}

// MARK: - Error

enum DeviceTransferError: LocalizedError {
    case sendFailed
    case peerNotFound

    var errorDescription: String? {
        switch self {
        case .sendFailed: return NSLocalizedString("transfer_error_send_failed", comment: "")
        case .peerNotFound: return NSLocalizedString("transfer_error_peer_not_found", comment: "")
        }
    }
}
