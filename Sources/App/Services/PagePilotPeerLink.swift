import Foundation
import Network

/// iPhone <-> iPad page-turn link.
///
/// One transport for every network situation: Network.framework with
/// peer-to-peer enabled uses a shared Wi-Fi network when there is one and
/// direct peer-to-peer Wi-Fi when there is not. The iPhone keeps a single
/// long-lived connection to the iPad the user selected, and every request
/// names that iPad so a different iPad never acts on it.
enum PagePilotPeerLinkConfiguration {
    static let serviceType = "_pagepilot-peer._tcp"

    static func parameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.connectionTimeout = 5
        // Notice a vanished peer within ~11s of silence.
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 5
        tcp.keepaliveInterval = 2
        tcp.keepaliveCount = 3
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }
}

struct PagePilotPeerAdvertisement: Equatable {
    var name: String
    var bookTitle: String

    var txtRecord: NWTXTRecord {
        NWTXTRecord([
            "name": String(name.prefix(40)),
            "book": String(bookTitle.prefix(40))
        ])
    }
}

struct PagePilotPeerHostState: Equatable {
    var isListening = false
    var connectedPeerCount = 0
    var lastRequestAt: Date?
}

// MARK: - iPad host

final class PagePilotPeerHost {
    static let shared = PagePilotPeerHost()

    typealias RequestHandler = (PagePilotPeerRequest, @escaping ([String: Any]) -> Void) -> Void

    /// Delivered on the main queue.
    var onStateChange: ((PagePilotPeerHostState) -> Void)?

    private final class Peer {
        let connection: NWConnection
        var decoder = PagePilotPeerFrameDecoder()
        var isReady = false

        init(_ connection: NWConnection) {
            self.connection = connection
        }
    }

    private let serviceType: String
    private let localIdentifier: () -> String
    private let queue: DispatchQueue
    private let restartDelay: TimeInterval

    private var isWanted = false
    private var listener: NWListener?
    private var isListening = false
    private var restartWorkItem: DispatchWorkItem?
    private var advertisement = PagePilotPeerAdvertisement(name: "iPad", bookTitle: "")
    private var hasProAccess: () -> Bool = { false }
    private var handler: RequestHandler?
    private var peers: [ObjectIdentifier: Peer] = [:]
    private var lastRequestAt: Date?
    private var acceptedConnectionCount = 0

    /// Total connections accepted since creation; lets tests prove reuse.
    var totalAcceptedConnections: Int {
        queue.sync { acceptedConnectionCount }
    }

    init(
        serviceType: String = PagePilotPeerLinkConfiguration.serviceType,
        localIdentifier: @escaping () -> String = { PagePilotRelayIdentity.localIdentifier() },
        queue: DispatchQueue = DispatchQueue(label: "PagePilot.PeerHost"),
        restartDelay: TimeInterval = 1.0
    ) {
        self.serviceType = serviceType
        self.localIdentifier = localIdentifier
        self.queue = queue
        self.restartDelay = restartDelay
    }

    /// Safe to call repeatedly; later calls only refresh the advertisement.
    func start(
        advertisement: PagePilotPeerAdvertisement,
        hasProAccess: @escaping () -> Bool,
        handler: @escaping RequestHandler
    ) {
        queue.async {
            self.isWanted = true
            self.hasProAccess = hasProAccess
            self.handler = handler
            self.applyAdvertisement(advertisement)
            self.startListenerIfNeeded()
        }
    }

    func update(advertisement: PagePilotPeerAdvertisement) {
        queue.async {
            self.applyAdvertisement(advertisement)
        }
    }

    func stop() {
        queue.async {
            self.isWanted = false
            self.handler = nil
            self.restartWorkItem?.cancel()
            self.restartWorkItem = nil
            let listener = self.listener
            self.listener = nil
            self.isListening = false
            listener?.cancel()
            let peers = Array(self.peers.values)
            self.peers.removeAll()
            peers.forEach { $0.connection.cancel() }
            self.publishState()
        }
    }

    private func applyAdvertisement(_ advertisement: PagePilotPeerAdvertisement) {
        guard advertisement != self.advertisement else { return }
        self.advertisement = advertisement
        if var service = listener?.service {
            service.txtRecordObject = advertisement.txtRecord
            listener?.service = service
        }
    }

    private func startListenerIfNeeded() {
        guard isWanted, listener == nil else { return }
        do {
            let listener = try NWListener(using: PagePilotPeerLinkConfiguration.parameters())
            listener.service = NWListener.Service(
                name: PagePilotRelayIdentity.serviceName(for: localIdentifier()),
                type: serviceType,
                txtRecord: advertisement.txtRecord
            )
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self, let listener, self.listener === listener else { return }
                print("PagePilotPeerHost: listener \(state)")
                switch state {
                case .ready:
                    self.isListening = true
                    self.publishState()
                case .failed(let error):
                    print("PagePilotPeerHost: listener failed: \(error)")
                    self.listener = nil
                    self.isListening = false
                    listener.cancel()
                    self.publishState()
                    self.scheduleRestart()
                default:
                    break
                }
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            print("PagePilotPeerHost: failed to create listener: \(error)")
            scheduleRestart()
        }
    }

    private func scheduleRestart() {
        guard isWanted, restartWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.restartWorkItem = nil
            self.startListenerIfNeeded()
        }
        restartWorkItem = work
        queue.asyncAfter(deadline: .now() + restartDelay, execute: work)
    }

    private func accept(_ connection: NWConnection) {
        let peer = Peer(connection)
        peers[ObjectIdentifier(connection)] = peer
        acceptedConnectionCount += 1

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection, let peer = self.peers[ObjectIdentifier(connection)] else { return }
            switch state {
            case .ready:
                peer.isReady = true
                self.publishState()
            case .waiting, .failed, .cancelled:
                self.drop(connection)
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive(on: connection)
    }

    private func drop(_ connection: NWConnection) {
        guard peers.removeValue(forKey: ObjectIdentifier(connection)) != nil else { return }
        connection.cancel()
        publishState()
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection, let peer = self.peers[ObjectIdentifier(connection)] else { return }
            if let data, !data.isEmpty {
                do {
                    for frame in try peer.decoder.append(data) {
                        self.handle(frame, on: connection)
                    }
                } catch {
                    self.drop(connection)
                    return
                }
            }
            if isComplete || error != nil {
                self.drop(connection)
                return
            }
            self.receive(on: connection)
        }
    }

    private func handle(_ frame: [String: Any], on connection: NWConnection) {
        guard let request = PagePilotPeerRequest(frameObject: frame) else {
            if let id = frame["id"] as? String {
                send(PagePilotPeerResponse.failure(id: id, error: .invalidMessage), on: connection)
            }
            return
        }
        if let rejection = PagePilotPeerHostValidation.rejection(
            for: request,
            localIdentifier: localIdentifier(),
            hasProAccess: hasProAccess()
        ) {
            send(PagePilotPeerResponse.failure(id: request.id, error: rejection), on: connection)
            return
        }
        guard let handler else {
            send(PagePilotPeerResponse.failure(id: request.id, error: .unreachable), on: connection)
            return
        }

        lastRequestAt = Date()
        publishState()
        handler(request) { [weak self, weak connection] payload in
            self?.queue.async {
                guard let self, let connection else { return }
                self.send(PagePilotPeerResponse.success(id: request.id, payload: payload), on: connection)
            }
        }
    }

    private func send(_ object: [String: Any], on connection: NWConnection) {
        guard let data = try? PagePilotPeerFrame.encode(object) else { return }
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    private func publishState() {
        let state = PagePilotPeerHostState(
            isListening: isListening,
            connectedPeerCount: peers.values.filter(\.isReady).count,
            lastRequestAt: lastRequestAt
        )
        DispatchQueue.main.async { [weak self] in
            self?.onStateChange?(state)
        }
    }
}

// MARK: - iPhone client

final class PagePilotPeerClient {
    static let shared = PagePilotPeerClient()

    typealias Completion = (Result<[String: Any], PagePilotPeerError>) -> Void

    /// Delivered on the main queue whenever the link becomes ready or drops.
    var onConnectionChange: ((Bool) -> Void)?

    private struct PendingRequest {
        let request: PagePilotPeerRequest
        let retriesLeft: Int
        let completion: Completion
        let timeout: DispatchWorkItem
    }

    private let serviceType: String
    private let queue: DispatchQueue
    private let discoveryTimeout: TimeInterval
    private let requestTimeout: TimeInterval
    private let reconnectDelay: TimeInterval = 2.0

    // Endpoints learned from any browse, keyed by iPad identifier.
    private var knownEndpoints: [String: NWEndpoint] = [:]

    // Selection-list discovery.
    private var listBrowser: NWBrowser?
    private var listTargets: [String: PagePilotNearbyTarget] = [:]
    private var listCompletion: ((Result<[PagePilotNearbyTarget], PagePilotPeerError>) -> Void)?
    private var listTimeout: DispatchWorkItem?

    // The link to one iPad.
    private var target: String?
    private var connection: NWConnection?
    private var isReady = false
    private var decoder = PagePilotPeerFrameDecoder()
    private var outbox: [Data] = []
    private var pending = PagePilotPeerPendingRequests<PendingRequest>()
    private var presenceBrowser: NWBrowser?
    private var notFoundTimer: DispatchWorkItem?
    private var reconnectWorkItem: DispatchWorkItem?

    init(
        serviceType: String = PagePilotPeerLinkConfiguration.serviceType,
        queue: DispatchQueue = DispatchQueue(label: "PagePilot.PeerClient"),
        discoveryTimeout: TimeInterval = 5.0,
        requestTimeout: TimeInterval = 5.0
    ) {
        self.serviceType = serviceType
        self.queue = queue
        self.discoveryTimeout = discoveryTimeout
        self.requestTimeout = requestTimeout
    }

    // MARK: Selection list

    /// Lists nearby iPads for the user to choose from. Never connects.
    func discoverTargets(completion: @escaping (Result<[PagePilotNearbyTarget], PagePilotPeerError>) -> Void) {
        queue.async {
            self.finishListDiscovery(.success([]))
            self.listTargets.removeAll()
            self.listCompletion = completion

            let browser = NWBrowser(
                for: .bonjourWithTXTRecord(type: self.serviceType, domain: nil),
                using: PagePilotPeerLinkConfiguration.parameters()
            )
            self.listBrowser = browser
            browser.stateUpdateHandler = { [weak self, weak browser] state in
                guard let self, self.listBrowser === browser else { return }
                if case .failed = state {
                    self.finishListDiscovery(.failure(.unreachable))
                }
            }
            browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
                guard let self, self.listBrowser === browser else { return }
                self.listTargets.removeAll()
                for result in results {
                    guard case let .service(name, _, _, _) = result.endpoint else { continue }
                    var deviceName: String?
                    var bookTitle: String?
                    if case .bonjour(let record) = result.metadata {
                        deviceName = record["name"]
                        bookTitle = record["book"]
                    }
                    guard let target = PagePilotNearbyTarget.from(
                        serviceName: name,
                        name: deviceName,
                        bookTitle: bookTitle
                    ) else { continue }
                    self.listTargets[target.id] = target
                    self.knownEndpoints[target.id] = result.endpoint
                }
            }
            let timeout = DispatchWorkItem { [weak self, weak browser] in
                guard let self, self.listBrowser === browser else { return }
                let targets = self.listTargets.values.sorted { $0.name < $1.name }
                self.finishListDiscovery(.success(targets))
            }
            self.listTimeout = timeout
            browser.start(queue: self.queue)
            self.queue.asyncAfter(deadline: .now() + self.discoveryTimeout, execute: timeout)
        }
    }

    func cancelDiscovery() {
        queue.async {
            self.finishListDiscovery(.success([]))
        }
    }

    private func finishListDiscovery(_ result: Result<[PagePilotNearbyTarget], PagePilotPeerError>) {
        listTimeout?.cancel()
        listTimeout = nil
        listBrowser?.cancel()
        listBrowser = nil
        let completion = listCompletion
        listCompletion = nil
        if let completion {
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: Link

    /// Opens (or keeps) the link to `target` ahead of the first request.
    /// `nil` closes the link.
    func connect(to target: String?) {
        queue.async {
            guard let target else {
                self.switchTarget(to: nil)
                return
            }
            self.switchTarget(to: target.lowercased())
            self.ensureConnection()
        }
    }

    /// Drops the link and stops browsing; the next request starts both again.
    /// Used when the app is suspended, because neither survives suspension.
    func reset() {
        queue.async {
            self.tearDown(failing: .connectionLost, allowRetry: false)
            // After tearDown, so its scheduled reconnect is cancelled too.
            self.stopPresenceBrowser()
        }
    }

    func send(
        to target: String,
        kind: PagePilotPeerRequestKind,
        action: PageCommand? = nil,
        commandID: String? = nil,
        completion: @escaping Completion
    ) {
        let request = PagePilotPeerRequest(target: target, kind: kind, action: action, commandID: commandID)
        queue.async {
            self.perform(request, retriesLeft: 1, completion: completion)
        }
    }

    private func perform(_ request: PagePilotPeerRequest, retriesLeft: Int, completion: @escaping Completion) {
        switchTarget(to: request.target)

        let frame: Data
        do {
            frame = try PagePilotPeerFrame.encode(request.frameObject)
        } catch {
            deliver(.failure(.invalidMessage), to: completion)
            return
        }

        let timeout = DispatchWorkItem { [weak self] in
            guard let self, let entry = self.pending.remove(request.id) else { return }
            self.deliver(.failure(.timedOut), to: entry.completion)
            // An unanswered request means the link is stale; rebuild it.
            self.tearDown(failing: .connectionLost, allowRetry: true)
        }
        pending.add(
            PendingRequest(request: request, retriesLeft: retriesLeft, completion: completion, timeout: timeout),
            for: request.id
        )
        queue.asyncAfter(deadline: .now() + requestTimeout, execute: timeout)

        if isReady, let connection {
            connection.send(content: frame, completion: .contentProcessed { _ in })
        } else {
            outbox.append(frame)
            ensureConnection()
        }
    }

    private func switchTarget(to newTarget: String?) {
        guard newTarget != target else { return }
        tearDown(failing: .wrongTarget, allowRetry: false)
        target = newTarget
        if newTarget == nil {
            stopPresenceBrowser()
        }
    }

    private func ensureConnection() {
        guard connection == nil, let target else { return }
        startPresenceBrowser()
        if let endpoint = knownEndpoints[target] {
            open(endpoint)
        } else if notFoundTimer == nil, !pending.isEmpty {
            let timer = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.notFoundTimer = nil
                guard self.connection == nil else { return }
                self.tearDown(failing: .notFound, allowRetry: false)
            }
            notFoundTimer = timer
            queue.asyncAfter(deadline: .now() + discoveryTimeout, execute: timer)
        }
    }

    /// Peer-to-peer Wi-Fi stays up on iPhone only while the app browses, so
    /// without a shared network the link needs a browse running for as long
    /// as it is in use. It also keeps the iPad's endpoint current.
    private func startPresenceBrowser() {
        guard presenceBrowser == nil else { return }
        let browser = NWBrowser(
            for: .bonjour(type: serviceType, domain: nil),
            using: PagePilotPeerLinkConfiguration.parameters()
        )
        presenceBrowser = browser
        browser.stateUpdateHandler = { [weak self, weak browser] state in
            guard let self, self.presenceBrowser === browser else { return }
            if case .failed(let error) = state {
                print("PagePilotPeerClient: presence browser failed: \(error)")
                self.presenceBrowser = nil
                browser?.cancel()
                self.scheduleReconnect()
            }
        }
        browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
            guard let self, self.presenceBrowser === browser else { return }
            var endpoints: [String: NWEndpoint] = [:]
            for result in results {
                guard case let .service(name, _, _, _) = result.endpoint,
                      let identifier = PagePilotRelayIdentity.identifier(fromServiceName: name) else { continue }
                endpoints[identifier] = result.endpoint
            }
            self.knownEndpoints.merge(endpoints) { _, latest in latest }
            if let target = self.target, endpoints[target] != nil, self.connection == nil {
                self.notFoundTimer?.cancel()
                self.notFoundTimer = nil
                self.ensureConnection()
            }
        }
        browser.start(queue: queue)
    }

    private func stopPresenceBrowser() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        presenceBrowser?.cancel()
        presenceBrowser = nil
    }

    /// After a drop, try again shortly so the link is ready before the next tap.
    private func scheduleReconnect() {
        guard target != nil, reconnectWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.reconnectWorkItem = nil
            self.ensureConnection()
        }
        reconnectWorkItem = work
        queue.asyncAfter(deadline: .now() + reconnectDelay, execute: work)
    }

    private func open(_ endpoint: NWEndpoint) {
        guard connection == nil else { return }
        let connection = NWConnection(to: endpoint, using: PagePilotPeerLinkConfiguration.parameters())
        self.connection = connection
        decoder = PagePilotPeerFrameDecoder()

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection, self.connection === connection else { return }
            print("PagePilotPeerClient: connection \(state) path=\(connection.currentPath.map { "\($0.availableInterfaces.map(\.name))" } ?? "none")")
            switch state {
            case .ready:
                self.isReady = true
                let frames = self.outbox
                self.outbox.removeAll()
                frames.forEach { connection.send(content: $0, completion: .contentProcessed { _ in }) }
                self.publishConnection(true)
            case .waiting:
                self.tearDown(failing: .unreachable, allowRetry: true)
            case .failed:
                self.tearDown(failing: .connectionLost, allowRetry: true)
            default:
                break
            }
        }
        // When Wi-Fi joins or leaves a network the old route can die without
        // an error. Rebuild at once instead of waiting for a request to time out.
        connection.viabilityUpdateHandler = { [weak self, weak connection] isViable in
            guard let self, let connection, self.connection === connection, !isViable else { return }
            self.tearDown(failing: .connectionLost, allowRetry: true)
        }
        connection.start(queue: queue)
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection, self.connection === connection else { return }
            if let data, !data.isEmpty {
                do {
                    for frame in try self.decoder.append(data) {
                        guard let (id, result) = PagePilotPeerResponse.parse(frame),
                              let entry = self.pending.remove(id) else { continue }
                        entry.timeout.cancel()
                        self.deliver(result, to: entry.completion)
                    }
                } catch {
                    self.tearDown(failing: .connectionLost, allowRetry: true)
                    return
                }
            }
            if isComplete || error != nil {
                self.tearDown(failing: .connectionLost, allowRetry: true)
                return
            }
            self.receive(on: connection)
        }
    }

    /// Closes the link and settles every waiting request: retryable failures
    /// get one fresh connection, everything else fails now.
    private func tearDown(failing error: PagePilotPeerError, allowRetry: Bool) {
        let wasReady = isReady
        let connection = self.connection
        self.connection = nil
        isReady = false
        outbox.removeAll()
        notFoundTimer?.cancel()
        notFoundTimer = nil
        connection?.cancel()
        if wasReady {
            publishConnection(false)
        }

        for entry in pending.removeAll() {
            entry.timeout.cancel()
            if allowRetry, error.isRetryable, entry.retriesLeft > 0, entry.request.target == target {
                perform(entry.request, retriesLeft: entry.retriesLeft - 1, completion: entry.completion)
            } else {
                deliver(.failure(error), to: entry.completion)
            }
        }
        if connection != nil, error == .connectionLost || error == .unreachable {
            scheduleReconnect()
        }
    }

    private func deliver(_ result: Result<[String: Any], PagePilotPeerError>, to completion: @escaping Completion) {
        DispatchQueue.main.async { completion(result) }
    }

    private func publishConnection(_ connected: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.onConnectionChange?(connected)
        }
    }
}
