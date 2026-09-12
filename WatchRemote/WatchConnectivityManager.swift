import Foundation
import WatchConnectivity

final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published var isReachable = false
    @Published var relayReachable = false
    @Published var crownSensitivity: Double
    @Published var bookTitle: String = ""
    @Published var bookProgress: Double = 0.0
    @Published var readerReady = false
    @Published var activeReaderCount = 0
    @Published var hasReceivedStatus = false
    @Published var doubleTapPageTurn = true
    @Published var readingSessionStartedAt: Date?
    @Published var readingSessionStartProgress: Double = 0.0

    /// Last actionable error visible on the Watch. Reader/status errors and the
    /// outcome of the latest logical page-turn command have independent
    /// lifecycles; a ready status must never swallow a command that failed on
    /// every fan-out route.
    @Published var lastError: String = ""
    /// Timestamp of last successful iPad relay response.
    @Published var lastStatusOK: Date? = nil

    private let readingSessionActiveKey = "readingSessionActive"
    private let readingSessionStartedAtKey = "readingSessionStartedAt"
    private let readingSessionStartProgressKey = "readingSessionStartProgress"
    private let relayGraceInterval: TimeInterval = 8.0
    private var statusPollTimer: Timer?
    private var hasAuthoritativeReadingSessionState = false
    private var responseEpoch = WatchResponseEpoch()
    private var commandOutcomeState = WatchCommandOutcomeState()

    private var iPhoneReaderReady = false
    private var iPadReaderReady = false
    private var iPhoneBookTitle = ""
    private var iPhoneBookProgress = 0.0
    private var iPadBookTitle = ""
    private var iPadBookProgress = 0.0
    private var iPhoneErrorMessage = ""
    private var iPadErrorMessage = ""

    private var routingState: WatchReaderRoutingState {
        get {
            WatchReaderRoutingState(
                iPhoneReady: iPhoneReaderReady,
                iPadReady: iPadReaderReady,
                iPhoneError: iPhoneErrorMessage,
                iPadError: iPadErrorMessage
            )
        }
        set {
            iPhoneReaderReady = newValue.iPhoneReady
            iPadReaderReady = newValue.iPadReady
            iPhoneErrorMessage = newValue.iPhoneError
            iPadErrorMessage = newValue.iPadError
        }
    }

    private lazy var commandQueue = ThrottledCommandQueue(interval: 0.1, queue: .main) { [weak self] command, completion in
        self?.performSend(command, completion: completion)
    }

    var isRelayConnected: Bool {
        relayReachable || hasRecentRelaySuccess
    }

    private override init() {
        let sensitivity = UserDefaults.standard.double(forKey: "watch_crown_sensitivity")
        self.crownSensitivity = sensitivity > 0 ? sensitivity : 2.0
        if let dt = UserDefaults.standard.object(forKey: "watch_double_tap_page_turn") as? Bool {
            self.doubleTapPageTurn = dt
        }
        super.init()
        activateSession()
    }

    private func activateSession() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        isReachable = session.isReachable
        session.delegate = self
        session.activate()

        // Application context is persisted metadata, not proof that a Reader is
        // currently reachable. Real-time status polling is authoritative for
        // iPhone/iPad readiness.
        updateSettings(from: session.receivedApplicationContext)
    }

    func refreshConnectionStatus() {
        refreshStatusPolling()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.pollStatus()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.pollStatus()
        }
    }

    private func updateSettings(from context: [String: Any]) {
        if let sensitivity = context["watch_crown_sensitivity"] as? Double {
            crownSensitivity = sensitivity
            UserDefaults.standard.set(sensitivity, forKey: "watch_crown_sensitivity")
        }
        if let doubleTap = context["watch_double_tap_page_turn"] as? Bool {
            doubleTapPageTurn = doubleTap
            UserDefaults.standard.set(doubleTap, forKey: "watch_double_tap_page_turn")
        }

        // The application context can be cached across a WCSession outage. Keep
        // its metadata, but never let it promote Reader readiness; a fresh
        // status reply must establish that the Reader can respond now.
        if let title = context["currentBookTitle"] as? String {
            iPhoneBookTitle = title
        }
        if let progress = context["currentBookProgress"] as? Double {
            iPhoneBookProgress = progress
        }
        _ = applyReadingSessionContext(context)
        recomputeAggregateReaderState()
        refreshVisibleError()
        refreshStatusPolling()
    }

    func sendCommand(_ command: PageCommand) {
        guard WCSession.default.isReachable else {
            DispatchQueue.main.async {
                self.invalidateTransportState(error: self.localized("watch.error.openIPhone"))
            }
            return
        }
        commandQueue.enqueue(command)
    }

    private func performSend(_ command: PageCommand, completion: @escaping () -> Void) {
        let commandID = UUID().uuidString
        commandOutcomeState.begin(commandID: commandID)
        refreshVisibleError()

        // Always ask the paired iPhone first. The iPhone only turns when its
        // Reader is active, so an idle iPhone simply returns NAVIGATOR_NOT_READY.
        send(command, to: .iPhone, commandID: commandID)

        // Fan the same logical command out to the iPad route. The iPhone app
        // enforces Pro before it touches the LAN, so Free users incur no LAN
        // discovery or remote page turn. Relay failures never block local use.
        send(command, to: .iPad, commandID: commandID)

        // Immediately unblock the queue. Success/failure replies only refresh
        // status and must not gate the next crown/button event.
        completion()
    }

    private func send(_ command: PageCommand, to destination: WatchReaderDestination, commandID: String) {
        var message = command.message
        message["target"] = destination.rawValue
        message["commandId"] = commandID
        let token = responseEpoch.beginRequest(to: destination, kind: .command)

        WCSession.default.sendMessage(
            message,
            replyHandler: { [weak self] reply in
                self?.handleWatchConnectivityReply(
                    reply,
                    from: destination,
                    token: token,
                    commandID: commandID
                )
            },
            errorHandler: { [weak self] _ in
                DispatchQueue.main.async {
                    self?.applySendFailure(
                        to: destination,
                        token: token,
                        commandID: commandID
                    )
                }
            }
        )
    }

    private func invalidateTransportState(error: String) {
        responseEpoch.invalidateTransport()
        commandOutcomeState.reset()

        var state = routingState
        state.invalidateForTransportFailure(error: error)
        routingState = state

        isReachable = false
        relayReachable = false
        lastStatusOK = nil
        recomputeAggregateReaderState()
        refreshVisibleError()
    }

    private func applySendFailure(
        to destination: WatchReaderDestination,
        token: WatchResponseToken,
        commandID: String
    ) {
        let transportReachable = WCSession.default.isReachable
        if !transportReachable {
            guard responseEpoch.belongsToCurrentTransport(token) else { return }
            invalidateTransportState(error: localized("watch.error.sendFailed"))
            return
        }

        guard responseEpoch.accepts(token, transportReachable: true) else { return }

        commandOutcomeState.recordFailure(
            commandID: commandID,
            destination: destination,
            error: localized("watch.error.sendFailed")
        )

        if destination == .iPad {
            markRelayFailure()
        }

        // Reader readiness remains status-authoritative. Polling can update the
        // Reader snapshot, but it cannot clear this command-level outcome.
        pollStatus(for: destination)
        refreshVisibleError()
    }

    private func startPolling() {
        DispatchQueue.main.async {
            guard self.statusPollTimer == nil else { return }
            self.statusPollTimer = Timer.scheduledTimer(withTimeInterval: 12.0, repeats: true) { [weak self] _ in
                self?.pollStatus()
            }
        }
    }

    private func stopPolling() {
        DispatchQueue.main.async {
            self.statusPollTimer?.invalidate()
            self.statusPollTimer = nil
        }
    }

    private func refreshStatusPolling() {
        DispatchQueue.main.async {
            self.startPolling()
            self.pollStatus()
        }
    }

    private func pollStatus() {
        let reachable = WCSession.default.isReachable
        if !reachable {
            invalidateTransportState(error: localized("watch.error.openIPhone"))
            return
        }

        isReachable = true
        pollStatus(for: .iPhone)
        pollStatus(for: .iPad)
    }

    private func pollStatus(for destination: WatchReaderDestination) {
        let token = responseEpoch.beginRequest(to: destination, kind: .status)
        WCSession.default.sendMessage(
            ["action": "status", "target": destination.rawValue],
            replyHandler: { [weak self] reply in
                self?.handleWatchConnectivityReply(reply, from: destination, token: token)
            },
            errorHandler: { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    let transportReachable = WCSession.default.isReachable
                    if !transportReachable {
                        guard self.responseEpoch.belongsToCurrentTransport(token) else { return }
                        self.invalidateTransportState(error: self.localized("watch.error.openIPhone"))
                        return
                    }
                    guard self.responseEpoch.accepts(token, transportReachable: true) else { return }
                    switch destination {
                    case .iPhone:
                        self.iPhoneReaderReady = false
                    case .iPad:
                        self.markRelayFailure()
                        self.iPadReaderReady = false
                    }
                    self.recomputeAggregateReaderState()
                    self.refreshVisibleError()
                }
            }
        )
    }

    private func handleWatchConnectivityReply(
        _ reply: [String: Any],
        from destination: WatchReaderDestination,
        token: WatchResponseToken,
        commandID: String? = nil
    ) {
        DispatchQueue.main.async {
            guard self.responseEpoch.accepts(
                token,
                transportReachable: WCSession.default.isReachable
            ) else {
                return
            }

            if token.kind == .command {
                guard let commandID else { return }
                self.handleCommandReply(
                    reply,
                    from: destination,
                    commandID: commandID
                )
                return
            }

            self.handleStatusReply(reply, from: destination)
        }
    }

    private func handleCommandReply(
        _ reply: [String: Any],
        from destination: WatchReaderDestination,
        commandID: String
    ) {
        if let error = reply["error"] as? String {
            let errorCode = reply["errorCode"] as? String
            commandOutcomeState.recordFailure(
                commandID: commandID,
                destination: destination,
                error: commandFailureMessage(
                    destination: destination,
                    code: errorCode,
                    error: error
                )
            )

            if destination == .iPad {
                if errorCode == "NAVIGATOR_NOT_READY" {
                    // The relay answered; only the Reader was unavailable.
                    markRelaySuccess(clearError: false)
                } else if errorCode == "PRO_REQUIRED" || isRelayConnectivityError(errorCode) {
                    markRelayFailure()
                }
            }

            pollStatus(for: destination)
            refreshVisibleError()
            return
        }

        commandOutcomeState.recordSuccess(
            commandID: commandID,
            destination: destination
        )

        if destination == .iPad {
            // A successful command proves the relay answered, but status polling
            // remains the sole authority for cached Reader readiness/metadata.
            markRelaySuccess(clearError: false)
        }

        pollStatus(for: destination)
        refreshVisibleError()
    }

    private func handleStatusReply(
        _ reply: [String: Any],
        from destination: WatchReaderDestination
    ) {
        hasReceivedStatus = true

        if let error = reply["error"] as? String {
            let errorCode = reply["errorCode"] as? String

            if errorCode == "NAVIGATOR_NOT_READY" {
                switch destination {
                case .iPhone:
                    iPhoneReaderReady = false
                    iPhoneErrorMessage = ""
                case .iPad:
                    iPadReaderReady = false
                    iPadErrorMessage = localized("watch.hint.openBookIPad")
                    markRelaySuccess(clearError: false)
                }
                recomputeAggregateReaderState()
                refreshVisibleError()
                return
            }

            switch destination {
            case .iPad:
                iPadReaderReady = false
                if errorCode == "PRO_REQUIRED" {
                    // A Free user should not be told that an optional iPad path
                    // failed; local iPhone page turning remains valid.
                    iPadErrorMessage = ""
                    markRelayFailure()
                } else if isRelayConnectivityError(errorCode) {
                    iPadErrorMessage = errorMessage(code: errorCode, error: error)
                    markRelayFailure()
                } else {
                    iPadErrorMessage = errorMessage(code: errorCode, error: error)
                }

            case .iPhone:
                iPhoneReaderReady = false
                iPhoneErrorMessage = errorMessage(code: errorCode, error: error)
            }

            recomputeAggregateReaderState()
            refreshVisibleError()
            return
        }

        switch destination {
        case .iPhone:
            iPhoneErrorMessage = ""
            applyStatusPayload(reply, from: destination)
        case .iPad:
            iPadErrorMessage = ""
            markRelaySuccess()
            applyStatusPayload(reply, from: destination)
        }
        refreshVisibleError()
    }

    private var hasRecentRelaySuccess: Bool {
        guard let lastStatusOK else { return false }
        return Date().timeIntervalSince(lastStatusOK) < relayGraceInterval
    }

    private func markRelaySuccess(clearError: Bool = true) {
        relayReachable = true
        lastStatusOK = Date()
        if clearError {
            iPadErrorMessage = ""
        }
    }

    private func markRelayFailure() {
        guard !hasRecentRelaySuccess else { return }
        relayReachable = false
    }

    private func isRelayConnectivityError(_ errorCode: String?) -> Bool {
        errorCode == "IPAD_NOT_FOUND" || errorCode == "RELAY_TIMEOUT"
    }

    private func commandFailureMessage(
        destination: WatchReaderDestination,
        code: String?,
        error: String
    ) -> String {
        if code == "NAVIGATOR_NOT_READY" {
            return destination == .iPad ? localized("watch.hint.openBookIPad") : ""
        }
        return errorMessage(code: code, error: error)
    }

    private func errorMessage(code: String?, error: String) -> String {
        switch code {
        case "IPAD_NOT_FOUND":
            return localized("watch.error.ipadNotFound")
        case "RELAY_TIMEOUT":
            return localized("watch.error.ipadTimeout")
        case "INVALID_COMMAND":
            return localized("watch.error.generic")
        case "NAVIGATOR_NOT_READY":
            return ""
        case "PRO_REQUIRED":
            return ""
        default:
            if error.localizedCaseInsensitiveContains("reader") {
                return ""
            }
            return localized("watch.error.generic")
        }
    }

    private func applyStatusPayload(_ json: [String: Any], from destination: WatchReaderDestination) {
        let wasReaderReady = readerReady
        let ready = (json["readerReady"] as? Bool) ?? ((json["bookTitle"] as? String)?.isEmpty == false)

        switch destination {
        case .iPhone:
            iPhoneReaderReady = ready
            if let title = json["bookTitle"] as? String {
                iPhoneBookTitle = title
            }
            if let progress = json["bookProgress"] as? Double {
                iPhoneBookProgress = progress
            }
            _ = applyReadingSessionContext(json)

        case .iPad:
            iPadReaderReady = ready
            if let title = json["bookTitle"] as? String {
                iPadBookTitle = title
            }
            if let progress = json["bookProgress"] as? Double {
                iPadBookProgress = progress
            }
        }

        if let sensitivity = json["crownSensitivity"] as? Double {
            crownSensitivity = sensitivity
            UserDefaults.standard.set(sensitivity, forKey: "watch_crown_sensitivity")
        }

        recomputeAggregateReaderState(wasReaderReady: wasReaderReady)
    }

    private func recomputeAggregateReaderState(wasReaderReady: Bool? = nil) {
        let previousReady = wasReaderReady ?? readerReady
        activeReaderCount = (iPhoneReaderReady ? 1 : 0) + (iPadReaderReady ? 1 : 0)
        readerReady = activeReaderCount > 0

        if iPhoneReaderReady {
            bookTitle = iPhoneBookTitle
            bookProgress = iPhoneBookProgress
        } else if iPadReaderReady {
            bookTitle = iPadBookTitle
            bookProgress = iPadBookProgress
        } else {
            bookTitle = ""
            bookProgress = 0.0
        }

        updateFallbackReadingSession(wasReaderReady: previousReady)
    }

    private func refreshVisibleError() {
        lastError = commandOutcomeState.visibleError(
            fallback: routingState.visibleError,
            defaultCommandError: localized("watch.error.generic")
        )
    }

    @discardableResult
    private func applyReadingSessionContext(_ payload: [String: Any]) -> Bool {
        guard let active = payload[readingSessionActiveKey] as? Bool else {
            return false
        }

        hasAuthoritativeReadingSessionState = true
        guard active else {
            readingSessionStartedAt = nil
            readingSessionStartProgress = bookProgress
            return true
        }

        let timestamp = payload[readingSessionStartedAtKey] as? Double ?? 0.0
        readingSessionStartedAt = timestamp > 0
            ? Date(timeIntervalSince1970: timestamp)
            : Date()
        readingSessionStartProgress = clampProgress(
            payload[readingSessionStartProgressKey] as? Double ?? bookProgress
        )
        return true
    }

    private func updateFallbackReadingSession(wasReaderReady: Bool) {
        guard !hasAuthoritativeReadingSessionState else { return }

        if readerReady {
            if !wasReaderReady || readingSessionStartedAt == nil {
                readingSessionStartedAt = Date()
                readingSessionStartProgress = clampProgress(bookProgress)
            }
        } else {
            readingSessionStartedAt = nil
            readingSessionStartProgress = clampProgress(bookProgress)
        }
    }

    private func clampProgress(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}

// MARK: - WCSessionDelegate
extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let reachable = session.isReachable
        DispatchQueue.main.async {
            self.isReachable = reachable
            if reachable {
                self.refreshConnectionStatus()
            } else {
                self.invalidateTransportState(error: self.localized("watch.error.openIPhone"))
            }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        // Capture at delegate-entry time. Reading session.isReachable later on
        // the main queue can miss a transient false event after a fast reconnect.
        let reachable = session.isReachable
        DispatchQueue.main.async {
            self.isReachable = reachable
            if reachable {
                self.refreshConnectionStatus()
            } else {
                // A false event always advances the transport epoch, even if the
                // session has already reconnected by the time this block runs.
                self.invalidateTransportState(error: self.localized("watch.error.openIPhone"))
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        DispatchQueue.main.async {
            self.updateSettings(from: applicationContext)
        }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {
    }

    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
    #endif
}
