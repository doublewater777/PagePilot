import Foundation
import Network

/// Peer-to-peer capable iPhone <-> iPad relay.
///
/// Nearby relay is intentionally identity-bound. An iPhone may only connect to
/// the stable relay identifier learned from the LAN candidate/last successful
/// association, and every request repeats that identifier so the iPad verifies
/// the target before forwarding anything to localhost.
final class PagePilotNearbyRelay {
    static let shared = PagePilotNearbyRelay()

    private let queue = DispatchQueue(label: "com.panyang.PagePilot.nearby-relay")
    private let serviceType = "_pagepilot-peer._tcp"
    private let endpointTimeout: TimeInterval = 2.0
    private let requestTimeout: TimeInterval = 2.5
    private let associatedTargetKey = "pagepilot_nearby_associated_target"

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var discoveredEndpoint: NWEndpoint?
    private var discoveredTargetIdentifier: String?
    private var expectedTargetIdentifier: String?
    private var pendingEndpointCompletions: [(NWEndpoint?) -> Void] = []
    private var endpointTimeoutWorkItem: DispatchWorkItem?
    private var browseExpiryWorkItem: DispatchWorkItem?
    private var lifecycleState = PagePilotNearbyLifecycleState()

    private var localPortProvider: (() -> UInt)?
    private var peerActivityHandler: (() -> Void)?
    private var shouldAcceptRequest: (() -> Bool)?
    private var incomingConnections: [ObjectIdentifier: NWConnection] = [:]

    private init() {}

    var associatedTargetIdentifier: String? {
        UserDefaults.standard.string(forKey: associatedTargetKey)?.lowercased()
    }

    func rememberAssociatedTarget(_ identifier: String?) {
        guard let identifier,
              UUID(uuidString: identifier) != nil else {
            return
        }
        UserDefaults.standard.set(identifier.lowercased(), forKey: associatedTargetKey)
    }

    // MARK: - iPad server

    func startServer(
        localPortProvider: @escaping () -> UInt,
        onPeerActivity: @escaping () -> Void,
        shouldAcceptRequest: @escaping () -> Bool
    ) {
        queue.async {
            self.localPortProvider = localPortProvider
            self.peerActivityHandler = onPeerActivity
            self.shouldAcceptRequest = shouldAcceptRequest
            guard self.listener == nil else { return }

            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true

            do {
                let listener = try NWListener(using: parameters)
                let localIdentifier = PagePilotRelayIdentity.localIdentifier()
                listener.service = NWListener.Service(
                    name: PagePilotRelayIdentity.serviceName(for: localIdentifier),
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
            self.shouldAcceptRequest = nil

            let connections = self.incomingConnections.values
            self.incomingConnections.removeAll()
            connections.forEach { $0.cancel() }
        }
    }

    private func accept(_ connection: NWConnection) {
        let connectionID = ObjectIdentifier(connection)
        incomingConnections[connectionID] = connection

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                guard self.shouldAcceptRequest?() == true else {
                    self.send(
                        [
                            "status": "error",
                            "ok": false,
                            "errorCode": "PRO_REQUIRED",
                            "error": "pro is required for iPad page turn"
                        ],
                        over: connection
                    )
                    return
                }

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
                self.finishIncoming(connection)

            case .cancelled:
                self.incomingConnections.removeValue(forKey: connectionID)

            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func proxyToLocalRelay(_ requestObject: [String: Any], over connection: NWConnection) {
        guard let targetIdentifier = requestObject["targetIdentifier"] as? String,
              targetIdentifier.lowercased() == PagePilotRelayIdentity.localIdentifier() else {
            send(
                [
                    "status": "error",
                    "ok": false,
                    "errorCode": "IPAD_NOT_FOUND",
                    "error": "nearby relay target mismatch"
                ],
                over: connection
            )
            return
        }

        guard let path = requestObject["path"] as? String,
              let method = requestObject["method"] as? String,
              PagePilotNearbyRequestValidator.isValid(path: path, method: method) else {
            send(
                [
                    "status": "error",
                    "ok": false,
                    "errorCode": "INVALID_COMMAND",
                    "error": "invalid nearby relay method/path"
                ],
                over: connection
            )
            return
        }

        guard shouldAcceptRequest?() == true else {
            send(
                [
                    "status": "error",
                    "ok": false,
                    "errorCode": "PRO_REQUIRED",
                    "error": "pro is required for iPad page turn"
                ],
                over: connection
            )
            return
        }

        guard let localPort = localPortProvider?(),
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

    /// Starts a short peer-to-peer browse for one explicitly known iPad.
    /// No target identifier means no nearby browse: failing closed is preferable
    /// to choosing an arbitrary iPad when several are in range.
    func prepareFallback(targetIdentifier: String?) {
        guard let targetIdentifier,
              UUID(uuidString: targetIdentifier) != nil else {
            return
        }

        queue.async {
            self.setExpectedTarget(targetIdentifier)
            self.startBrowserIfNeeded()
            self.scheduleBrowseExpiry()
        }
    }

    func cancelPreparedFallback(clearEndpoint: Bool = false) {
        queue.async {
            let actions = self.lifecycleState.handle(.stop(clearEndpoint: clearEndpoint))
            self.applyLifecycleActions(actions)
            if clearEndpoint {
                self.discoveredTargetIdentifier = nil
            }
        }
    }

    func request(
        targetIdentifier: String?,
        path: String,
        method: String,
        body: [String: Any]?,
        shouldProceed: @escaping () -> Bool,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard let targetIdentifier,
              UUID(uuidString: targetIdentifier) != nil else {
            completion(.failure(PagePilotNearbyRelayError.noService))
            return
        }

        endpoint(targetIdentifier: targetIdentifier) { [weak self] endpoint in
            guard let self else { return }
            guard shouldProceed() else {
                completion(.failure(PagePilotNearbyRelayError.authorizationRevoked))
                return
            }
            guard let endpoint else {
                completion(.failure(PagePilotNearbyRelayError.noService))
                return
            }

            // Browsing must be stopped before establishing the connection.
            let actions = self.lifecycleState.handle(.targetSelected)
            self.applyLifecycleActions(actions, preserveEndpoint: true)
            self.sendRequest(
                to: endpoint,
                targetIdentifier: targetIdentifier,
                path: path,
                method: method,
                body: body,
                shouldProceed: shouldProceed,
                completion: completion
            )
        }
    }

    private func endpoint(
        targetIdentifier: String,
        completion: @escaping (NWEndpoint?) -> Void
    ) {
        queue.async {
            self.setExpectedTarget(targetIdentifier)

            if let endpoint = self.discoveredEndpoint,
               self.discoveredTargetIdentifier == targetIdentifier.lowercased() {
                completion(endpoint)
                return
            }

            self.pendingEndpointCompletions.append(completion)
            self.startBrowserIfNeeded()

            guard self.endpointTimeoutWorkItem == nil else { return }

            let timeout = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.endpointTimeoutWorkItem = nil
                let endpoint = self.discoveredTargetIdentifier == targetIdentifier.lowercased()
                    ? self.discoveredEndpoint
                    : nil
                self.flushPendingEndpoints(with: endpoint)
            }
            self.endpointTimeoutWorkItem = timeout
            self.queue.asyncAfter(deadline: .now() + self.endpointTimeout, execute: timeout)
        }
    }

    private func setExpectedTarget(_ identifier: String) {
        let normalized = identifier.lowercased()
        if expectedTargetIdentifier != normalized {
            expectedTargetIdentifier = normalized
            discoveredEndpoint = nil
            discoveredTargetIdentifier = nil
        }
    }

    private func startBrowserIfNeeded() {
        guard browser == nil,
              expectedTargetIdentifier != nil else {
            return
        }

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
                    let actions = self.lifecycleState.handle(.browserFailed)
                    self.applyLifecycleActions(actions)
                }
            default:
                break
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self,
                  let expectedTargetIdentifier = self.expectedTargetIdentifier else {
                return
            }

            guard let endpoint = results
                .map(\.endpoint)
                .first(where: { endpoint in
                    guard case let .service(name, _, _, _) = endpoint else { return false }
                    return PagePilotNearbyTargetSelectionPolicy.matches(
                        serviceName: name,
                        expectedIdentifier: expectedTargetIdentifier
                    )
                }) else {
                return
            }

            self.discoveredEndpoint = endpoint
            self.discoveredTargetIdentifier = expectedTargetIdentifier
            let actions = self.lifecycleState.handle(.targetSelected)
            self.applyLifecycleActions(actions, preserveEndpoint: true)
        }

        self.browser = browser
        _ = lifecycleState.handle(.browserStarted)
        browser.start(queue: queue)
    }

    private func cancelBrowserObject() {
        browseExpiryWorkItem?.cancel()
        browseExpiryWorkItem = nil
        browser?.cancel()
        browser = nil
    }

    private func scheduleBrowseExpiry() {
        browseExpiryWorkItem?.cancel()
        let expiry = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let actions = self.lifecycleState.handle(.stop(clearEndpoint: false))
            self.applyLifecycleActions(actions, preserveEndpoint: true)
        }
        browseExpiryWorkItem = expiry
        queue.asyncAfter(deadline: .now() + 5.0, execute: expiry)
    }

    private func applyLifecycleActions(
        _ actions: [PagePilotNearbyLifecycleAction],
        preserveEndpoint: Bool = false
    ) {
        for action in actions {
            switch action {
            case .stopBrowser:
                cancelBrowserObject()
            case .clearEndpoint:
                if !preserveEndpoint {
                    discoveredEndpoint = nil
                    discoveredTargetIdentifier = nil
                }
            case .flushPending:
                flushPendingEndpoints(with: preserveEndpoint ? discoveredEndpoint : nil)
            }
        }
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
        targetIdentifier: String,
        path: String,
        method: String,
        body: [String: Any]?,
        shouldProceed: @escaping () -> Bool,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard shouldProceed() else {
            completion(.failure(PagePilotNearbyRelayError.authorizationRevoked))
            return
        }

        var requestObject: [String: Any] = [
            "targetIdentifier": targetIdentifier.lowercased(),
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
                let actions = self?.lifecycleState.handle(.connectionFailed) ?? []
                self?.applyLifecycleActions(actions)
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
                guard shouldProceed() else {
                    finish(.failure(PagePilotNearbyRelayError.authorizationRevoked), true)
                    return
                }

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
            connection.send(content: data, completion: .contentProcessed { [weak self, weak connection] _ in
                guard let self, let connection else { return }
                self.queue.async {
                    self.finishIncoming(connection)
                }
            })
        } catch {
            finishIncoming(connection)
        }
    }

    private func finishIncoming(_ connection: NWConnection) {
        incomingConnections.removeValue(forKey: ObjectIdentifier(connection))
        connection.cancel()
    }

    private func receiveObject(
        on connection: NWConnection,
        frameBuffer: PagePilotNearbyFrameBuffer = PagePilotNearbyFrameBuffer(),
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 16 * 1024
        ) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }

            var nextBuffer = frameBuffer
            if let data {
                do {
                    switch try nextBuffer.append(data) {
                    case .complete(let payload):
                        completion(.success(payload))
                        return
                    case .incomplete:
                        break
                    }
                } catch {
                    completion(.failure(error))
                    return
                }
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
                frameBuffer: nextBuffer,
                completion: completion
            )
        }
    }
}
