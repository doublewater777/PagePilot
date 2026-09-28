import Foundation
import Network

enum PagePilotNearbyRelayError: LocalizedError {
    case invalidMessage
    case noService
    case connectionFailed(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .invalidMessage:
            return "Invalid nearby relay message."
        case .noService:
            return "No nearby PagePilot iPad was found."
        case .connectionFailed(let message):
            return message
        case .timedOut:
            return "Nearby relay timed out."
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

/// Peer-to-peer capable iPhone <-> iPad relay.
///
/// The iPad advertises a small Network.framework listener with peer-to-peer
/// links enabled. Requests are forwarded to the existing localhost HTTP relay,
/// so LAN and nearby-direct transports keep exactly the same command semantics.
final class PagePilotNearbyRelay {
    static let shared = PagePilotNearbyRelay()

    private let queue = DispatchQueue(label: "com.panyang.PagePilot.nearby-relay")
    private let serviceType = "_pagepilot-peer._tcp"
    private let serviceName = "PagePilot-iPad"
    private let endpointTimeout: TimeInterval = 2.0
    private let requestTimeout: TimeInterval = 2.5

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var discoveredEndpoint: NWEndpoint?
    private var pendingEndpointCompletions: [(NWEndpoint?) -> Void] = []
    private var endpointTimeoutWorkItem: DispatchWorkItem?
    private var browseExpiryWorkItem: DispatchWorkItem?

    private var localPortProvider: (() -> UInt)?
    private var peerActivityHandler: (() -> Void)?

    private init() {}

    // MARK: - iPad server

    func startServer(
        localPortProvider: @escaping () -> UInt,
        onPeerActivity: @escaping () -> Void
    ) {
        queue.async {
            self.localPortProvider = localPortProvider
            self.peerActivityHandler = onPeerActivity
            guard self.listener == nil else { return }

            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true

            do {
                let listener = try NWListener(using: parameters)
                listener.service = NWListener.Service(
                    name: self.serviceName,
                    type: self.serviceType
                )
                listener.newConnectionHandler = { [weak self] connection in
                    self?.accept(connection)
                }
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        print("PagePilotNearbyRelay: listener ready")
                    case .failed(let error):
                        print("PagePilotNearbyRelay: listener failed: \(error)")
                        listener?.cancel()
                        if self.listener === listener {
                            self.listener = nil
                        }
                    default:
                        break
                    }
                }
                self.listener = listener
                listener.start(queue: self.queue)
            } catch {
                print("PagePilotNearbyRelay: failed to create listener: \(error)")
            }
        }
    }

    func stopServer() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
            self.localPortProvider = nil
            self.peerActivityHandler = nil
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                self.receiveObject(on: connection) { result in
                    switch result {
                    case .success(let request):
                        self.proxyToLocalRelay(request, over: connection)
                    case .failure:
                        self.send(
                            [
                                "status": "error",
                                "ok": false,
                                "errorCode": "INVALID_COMMAND",
                                "error": "invalid nearby relay request"
                            ],
                            over: connection
                        )
                    }
                }
            case .failed(let error):
                print("PagePilotNearbyRelay: incoming connection failed: \(error)")
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func proxyToLocalRelay(_ requestObject: [String: Any], over connection: NWConnection) {
        guard let path = requestObject["path"] as? String,
              path == "status" || path == "command",
              let method = requestObject["method"] as? String,
              method == "GET" || method == "POST",
              let localPort = localPortProvider?(),
              localPort > 0,
              let url = URL(string: "http://127.0.0.1:\(localPort)/\(path)") else {
            send(
                [
                    "status": "error",
                    "ok": false,
                    "errorCode": "RELAY_TIMEOUT",
                    "error": "local relay is unavailable"
                ],
                over: connection
            )
            return
        }

        peerActivityHandler?()

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = requestTimeout
        if let body = requestObject["body"] as? [String: Any] {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        URLSession.shared.dataTask(with: request) { [weak self, weak connection] data, _, error in
            guard let self, let connection else { return }
            self.queue.async {
                if let error {
                    self.send(
                        [
                            "status": "error",
                            "ok": false,
                            "errorCode": "RELAY_TIMEOUT",
                            "error": error.localizedDescription
                        ],
                        over: connection
                    )
                    return
                }

                guard let data,
                      let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.send(
                        [
                            "status": "error",
                            "ok": false,
                            "errorCode": "RELAY_TIMEOUT",
                            "error": "invalid local relay response"
                        ],
                        over: connection
                    )
                    return
                }

                self.send(payload, over: connection)
            }
        }.resume()
    }

    // MARK: - iPhone discovery

    /// Starts a short peer-to-peer browse in parallel with the normal LAN lookup.
    /// The browse is cancelled automatically if no fallback is needed.
    func prepareFallback() {
        queue.async {
            self.startBrowserIfNeeded()
            self.scheduleBrowseExpiry()
        }
    }

    func cancelPreparedFallback(clearEndpoint: Bool = false) {
        queue.async {
            self.stopBrowser()
            if clearEndpoint {
                self.discoveredEndpoint = nil
            }
        }
    }

    func request(
        path: String,
        method: String,
        body: [String: Any]?,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        endpoint { [weak self] endpoint in
            guard let self else { return }
            guard let endpoint else {
                completion(.failure(PagePilotNearbyRelayError.noService))
                return
            }

            self.stopBrowser()
            self.sendRequest(
                to: endpoint,
                path: path,
                method: method,
                body: body,
                completion: completion
            )
        }
    }

    private func endpoint(completion: @escaping (NWEndpoint?) -> Void) {
        queue.async {
            if let endpoint = self.discoveredEndpoint {
                completion(endpoint)
                return
            }

            self.pendingEndpointCompletions.append(completion)
            self.startBrowserIfNeeded()

            guard self.endpointTimeoutWorkItem == nil else { return }

            let timeout = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.endpointTimeoutWorkItem = nil
                self.flushPendingEndpoints(with: self.discoveredEndpoint)
            }
            self.endpointTimeoutWorkItem = timeout
            self.queue.asyncAfter(deadline: .now() + self.endpointTimeout, execute: timeout)
        }
    }

    private func startBrowserIfNeeded() {
        guard browser == nil else { return }

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjour(type: serviceType, domain: nil),
            using: parameters
        )
        browser.stateUpdateHandler = { [weak self, weak browser] state in
            guard let self else { return }
            switch state {
            case .failed(let error):
                print("PagePilotNearbyRelay: browser failed: \(error)")
                if self.browser === browser {
                    self.browser = nil
                }
                self.flushPendingEndpoints(with: nil)
            default:
                break
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            guard let endpoint = results
                .map(\.endpoint)
                .first(where: { endpoint in
                    guard case let .service(name, _, _, _) = endpoint else { return false }
                    return name.hasPrefix(self.serviceName)
                }) else {
                return
            }

            self.discoveredEndpoint = endpoint
            self.flushPendingEndpoints(with: endpoint)
        }

        self.browser = browser
        browser.start(queue: queue)
    }

    private func stopBrowser() {
        browseExpiryWorkItem?.cancel()
        browseExpiryWorkItem = nil
        browser?.cancel()
        browser = nil
    }

    private func scheduleBrowseExpiry() {
        browseExpiryWorkItem?.cancel()
        let expiry = DispatchWorkItem { [weak self] in
            self?.stopBrowser()
        }
        browseExpiryWorkItem = expiry
        queue.asyncAfter(deadline: .now() + 5.0, execute: expiry)
    }

    private func flushPendingEndpoints(with endpoint: NWEndpoint?) {
        endpointTimeoutWorkItem?.cancel()
        endpointTimeoutWorkItem = nil
        guard !pendingEndpointCompletions.isEmpty else { return }

        let completions = pendingEndpointCompletions
        pendingEndpointCompletions = []
        completions.forEach { $0(endpoint) }
    }

    // MARK: - Wire transport

    private func sendRequest(
        to endpoint: NWEndpoint,
        path: String,
        method: String,
        body: [String: Any]?,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        var requestObject: [String: Any] = [
            "path": path,
            "method": method
        ]
        if let body {
            requestObject["body"] = body
        }

        let encoded: Data
        do {
            encoded = try PagePilotNearbyRelayFrame.encode(requestObject)
        } catch {
            completion(.failure(error))
            return
        }

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let connection = NWConnection(to: endpoint, using: parameters)

        var didFinish = false
        var didSend = false
        var timeoutWorkItem: DispatchWorkItem?

        let finish: (Result<[String: Any], Error>, Bool) -> Void = { [weak self, weak connection] result, invalidateEndpoint in
            guard !didFinish else { return }
            didFinish = true
            timeoutWorkItem?.cancel()
            connection?.cancel()
            if invalidateEndpoint {
                self?.discoveredEndpoint = nil
            }
            completion(result)
        }

        let timeout = DispatchWorkItem {
            finish(.failure(PagePilotNearbyRelayError.timedOut), true)
        }
        timeoutWorkItem = timeout
        queue.asyncAfter(deadline: .now() + requestTimeout, execute: timeout)

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready where !didSend:
                didSend = true
                connection.send(content: encoded, completion: .contentProcessed { error in
                    self.queue.async {
                        if let error {
                            finish(
                                .failure(PagePilotNearbyRelayError.connectionFailed(error.localizedDescription)),
                                true
                            )
                            return
                        }

                        self.receiveObject(on: connection) { result in
                            switch result {
                            case .success(let payload):
                                finish(.success(payload), false)
                            case .failure(let error):
                                finish(.failure(error), true)
                            }
                        }
                    }
                })

            case .failed(let error):
                finish(
                    .failure(PagePilotNearbyRelayError.connectionFailed(error.localizedDescription)),
                    true
                )

            case .cancelled where !didFinish:
                finish(
                    .failure(PagePilotNearbyRelayError.connectionFailed("Nearby relay connection was cancelled.")),
                    true
                )

            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func send(_ object: [String: Any], over connection: NWConnection) {
        do {
            let data = try PagePilotNearbyRelayFrame.encode(object)
            connection.send(content: data, completion: .contentProcessed { _ in
                connection.cancel()
            })
        } catch {
            connection.cancel()
        }
    }

    private func receiveObject(
        on connection: NWConnection,
        buffer: Data = Data(),
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 16 * 1024
        ) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }

            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }

            if nextBuffer.count > PagePilotNearbyRelayFrame.maximumBytes {
                completion(.failure(PagePilotNearbyRelayError.invalidMessage))
                return
            }

            if nextBuffer.contains(0x0A) {
                do {
                    completion(.success(try PagePilotNearbyRelayFrame.decode(nextBuffer)))
                } catch {
                    completion(.failure(error))
                }
                return
            }

            if let error {
                completion(.failure(PagePilotNearbyRelayError.connectionFailed(error.localizedDescription)))
                return
            }

            if isComplete {
                completion(.failure(PagePilotNearbyRelayError.invalidMessage))
                return
            }

            self.receiveObject(
                on: connection,
                buffer: nextBuffer,
                completion: completion
            )
        }
    }
}
