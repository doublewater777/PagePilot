import Foundation
import WatchConnectivity
import Network

final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published var isReachable = false
    @Published var crownSensitivity: Double
    @Published var bookTitle: String = ""
    @Published var bookProgress: Double = 0.0

    // LAN Support
    @Published var activeLANURL: URL? = nil
    private var browser: NWBrowser?
    private var statusPollTimer: Timer?

    // MARK: - Diagnostics (visible on the watch UI for in-the-field debugging)
    enum BrowserPhase: String {
        case idle           = "idle"
        case starting       = "starting"
        case ready          = "ready"
        case waiting        = "waiting"   // typically: no local network permission
        case failed         = "failed"
        case cancelled      = "cancelled"
    }

    enum ResolvePhase: String {
        case idle           = "idle"
        case found          = "found"     // service seen, resolving
        case resolving      = "resolving"
        case resolved       = "resolved"
        case failed         = "failed"
    }

    @Published var browserPhase: BrowserPhase = .idle
    @Published var resolvePhase: ResolvePhase = .idle
    /// Number of `_http._tcp` services currently visible (any name).
    @Published var visibleServiceCount: Int = 0
    /// All visible service names (any name, _http._tcp).
    @Published var visibleServiceNames: [String] = []
    /// Names of services we matched as a PagePilot iPad host.
    @Published var matchedServiceNames: [String] = []
    /// Last error message (browser failure, resolve failure, http error, etc.).
    @Published var lastError: String = ""
    /// Timestamp of last successful /status response.
    @Published var lastStatusOK: Date? = nil

    private override init() {
        let sensitivity = UserDefaults.standard.double(forKey: "watch_crown_sensitivity")
        self.crownSensitivity = sensitivity > 0 ? sensitivity : 2.0 // Default to medium (2.0)
        super.init()
        activateSession()
        startBonjourBrowser()
    }

    private func activateSession() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        isReachable = session.activationState == .activated
        session.delegate = self
        session.activate()

        // Sync immediate application context if already received previously
        updateSettings(from: session.receivedApplicationContext)
    }

    private func updateSettings(from context: [String: Any]) {
        if let sensitivity = context["watch_crown_sensitivity"] as? Double {
            self.crownSensitivity = sensitivity
            UserDefaults.standard.set(sensitivity, forKey: "watch_crown_sensitivity")
        }
        if let title = context["currentBookTitle"] as? String {
            self.bookTitle = title
        }
        if let progress = context["currentBookProgress"] as? Double {
            self.bookProgress = progress
        }
    }

    func sendCommand(_ command: PageCommand) {
        if let lanURL = activeLANURL {
            sendLANCommand(command, url: lanURL)
            return
        }

        guard WCSession.default.isReachable else {
            return
        }

        WCSession.default.sendMessage(
            command.message,
            replyHandler: { _ in },
            errorHandler: { _ in }
        )
    }

    /// User-triggered: tear down and re-create the browser. Useful when local
    /// network permission was just granted, or to retry after a transient
    /// network change (e.g. after switching Wi-Fi).
    func restartDiscovery() {
        DispatchQueue.main.async {
            print("WatchConnectivityManager: restartDiscovery requested by user")
            self.lastError = ""
            self.matchedServiceNames = []
            self.resolvePhase = .idle
            self.activeLANURL = nil
            self.stopPolling()
            self.browser?.cancel()
            self.browser = nil
            self.startBonjourBrowser()
        }
    }

    // MARK: - LAN Support Implementation

    private func startBonjourBrowser() {
        DispatchQueue.main.async { self.browserPhase = .starting }

        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_http._tcp", domain: "local")
        let browser = NWBrowser(for: descriptor, using: parameters)

        browser.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self.browserPhase = .ready
                    self.lastError = ""
                    print("WatchConnectivityManager: NWBrowser ready")
                case .failed(let error):
                    self.browserPhase = .failed
                    self.lastError = "browser: \(error.localizedDescription)"
                    print("WatchConnectivityManager: NWBrowser failed: \(error)")
                    // Auto-restart after a short delay so we don't stay dead.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                        self?.restartDiscovery()
                    }
                case .waiting(let error):
                    self.browserPhase = .waiting
                    self.lastError = "waiting: \(error.localizedDescription)"
                    print("WatchConnectivityManager: NWBrowser waiting: \(error)")
                case .cancelled:
                    self.browserPhase = .cancelled
                    print("WatchConnectivityManager: NWBrowser cancelled")
                default:
                    break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self = self else { return }

            // Both `.service(name:type:domain:interface:)` (older) and
            // other endpoint variants may appear. Extract a name and an
            // endpoint-description-for-matching for each result.
            var allNames: [String] = []
            var matchedName: String? = nil
            var matchedResult: NWBrowser.Result? = nil

            for result in results {
                let name = Self.serviceName(from: result.endpoint)
                let endpointDesc = "\(result.endpoint)"
                let displayName = name ?? endpointDesc
                allNames.append(displayName)

                // Match on either the parsed service name OR the raw
                // endpoint description, so that any iOS/watchOS variant of
                // NWEndpoint encoding still matches.
                let isMatch = (name?.contains("PagePilot-iPad") ?? false)
                    || endpointDesc.contains("PagePilot-iPad")
                    || endpointDesc.contains("PagePilot")

                if isMatch, matchedResult == nil {
                    matchedName = displayName
                    matchedResult = result
                }
            }

            // Log full endpoint descriptions to console for debugging.
            for result in results {
                print("WatchConnectivityManager: result endpoint=\(result.endpoint)")
            }

            DispatchQueue.main.async {
                self.visibleServiceCount = allNames.count
                self.visibleServiceNames = allNames
                self.matchedServiceNames = allNames.filter {
                    $0.contains("PagePilot")
                }
            }

            if let result = matchedResult, let name = matchedName, self.activeLANURL == nil {
                print("WatchConnectivityManager: Found iPad service \(name), resolving...")
                DispatchQueue.main.async {
                    self.resolvePhase = .found
                }
                self.resolveService(result, displayName: name)
            }

            if matchedResult == nil && self.activeLANURL != nil {
                print("WatchConnectivityManager: Active iPad service removed.")
                DispatchQueue.main.async {
                    self.activeLANURL = nil
                    self.resolvePhase = .idle
                    self.stopPolling()
                    self.isReachable = WCSession.default.isReachable
                    self.bookTitle = ""
                    self.bookProgress = 0.0
                }
            }
        }

        self.browser = browser
        browser.start(queue: .main)
        print("WatchConnectivityManager: Started NWBrowser.")
    }

    private static func serviceName(from endpoint: NWEndpoint) -> String? {
        switch endpoint {
        case .service(let name, _, _, _):
            return name
        default:
            // Some platform versions wrap it in a different case; fall back to
            // string description, which for Bonjour is the service name.
            let desc = "\(endpoint)"
            return desc.isEmpty ? nil : desc
        }
    }

    private func resolveService(_ result: NWBrowser.Result, displayName: String) {
        DispatchQueue.main.async { self.resolvePhase = .resolving }

        // Use TCP without TLS, no peer-to-peer (we want LAN/Wi-Fi only).
        let params = NWParameters.tcp
        params.includePeerToPeer = false
        let connection = NWConnection(to: result.endpoint, using: params)

        // Safety: cancel & mark failed if we never become ready in 5s.
        let timeoutItem = DispatchWorkItem { [weak self, weak connection] in
            guard let self = self else { return }
            if connection?.state != .ready, connection?.state != .cancelled {
                connection?.cancel()
                DispatchQueue.main.async {
                    self.resolvePhase = .failed
                    self.lastError = "resolve timeout for \(displayName)"
                    print("WatchConnectivityManager: resolve timeout for \(displayName)")
                }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeoutItem)

        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                timeoutItem.cancel()
                if let remoteEndpoint = connection.currentPath?.remoteEndpoint,
                   case let .hostPort(host, port) = remoteEndpoint {

                    let hostString: String
                    switch host {
                    case .ipv4(let ipv4):
                        hostString = "\(ipv4)"
                    case .ipv6(let ipv6):
                        // Strip the scope id (e.g. "%en0") and zone, GCDWebServer
                        // accepts the bracketed form.
                        let raw = "\(ipv6)"
                        let stripped = raw.split(separator: "%").first.map(String.init) ?? raw
                        hostString = "[\(stripped)]"
                    case .name(let name, _):
                        hostString = name
                    @unknown default:
                        hostString = ""
                    }

                    if !hostString.isEmpty {
                        var cleanHost = hostString
                        if cleanHost.hasSuffix(".") { cleanHost.removeLast() }
                        let urlString = "http://\(cleanHost):\(port)"
                        if let url = URL(string: urlString) {
                            print("WatchConnectivityManager: Resolved LAN URL: \(url)")
                            DispatchQueue.main.async {
                                self.activeLANURL = url
                                self.isReachable = true
                                self.resolvePhase = .resolved
                                self.lastError = ""
                                self.startPolling()
                                // Kick a status request immediately so the UI populates fast.
                                self.pollLANStatus()
                            }
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.resolvePhase = .failed
                        self.lastError = "resolve: no remoteEndpoint"
                    }
                }
                connection.cancel()
            case .failed(let error):
                timeoutItem.cancel()
                print("WatchConnectivityManager: Failed to resolve service: \(error)")
                DispatchQueue.main.async {
                    self.resolvePhase = .failed
                    self.lastError = "resolve: \(error.localizedDescription)"
                }
                connection.cancel()
            case .waiting(let error):
                // Don't fail yet, but expose to UI.
                DispatchQueue.main.async {
                    self.lastError = "resolve waiting: \(error.localizedDescription)"
                }
            default:
                break
            }
        }

        connection.start(queue: .global())
    }

    private func sendLANCommand(_ command: PageCommand, url: URL) {
        var components = URLComponents(url: url.appendingPathComponent("command"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "action", value: command.rawValue)]
        guard let requestURL = components?.url else { return }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 2.0

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }
            if let error = error {
                print("WatchConnectivityManager: Failed to send LAN command: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.lastError = "cmd: \(error.localizedDescription)"
                }
                return
            }
            guard let data = data else { return }
            self.parseLANResponse(data)
        }.resume()
    }

    private func startPolling() {
        DispatchQueue.main.async {
            self.statusPollTimer?.invalidate()
            self.statusPollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
                self?.pollLANStatus()
            }
            print("WatchConnectivityManager: Started status polling.")
        }
    }

    private func stopPolling() {
        DispatchQueue.main.async {
            self.statusPollTimer?.invalidate()
            self.statusPollTimer = nil
            print("WatchConnectivityManager: Stopped status polling.")
        }
    }

    private func pollLANStatus() {
        guard let lanURL = activeLANURL else { return }
        let requestURL = lanURL.appendingPathComponent("status")
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 2.0

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }
            if let error = error {
                print("WatchConnectivityManager: LAN status poll failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.lastError = "status: \(error.localizedDescription)"
                }
                return
            }
            guard let data = data else { return }
            DispatchQueue.main.async { self.lastStatusOK = Date() }
            self.parseLANResponse(data)
        }.resume()
    }

    private func parseLANResponse(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        DispatchQueue.main.async {
            if let title = json["bookTitle"] as? String {
                self.bookTitle = title
            }
            if let progress = json["bookProgress"] as? Double {
                self.bookProgress = progress
            }
            if let sensitivity = json["crownSensitivity"] as? Double {
                self.crownSensitivity = sensitivity
                UserDefaults.standard.set(sensitivity, forKey: "watch_crown_sensitivity")
            }
        }
    }
}

// MARK: - WCSessionDelegate
extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            if self.activeLANURL == nil {
                self.isReachable = activationState == .activated
            }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            if self.activeLANURL == nil {
                self.isReachable = session.isReachable
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        DispatchQueue.main.async {
            self.updateSettings(from: applicationContext)
        }
    }
}
