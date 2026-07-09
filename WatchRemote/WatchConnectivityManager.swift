import Foundation
import WatchConnectivity

final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    enum ControlTarget: String {
        case iPad = "ipad"
        case iPhone = "iphone"
    }

    @Published var isReachable = false
    @Published var relayReachable = false
    @Published var controlTarget: ControlTarget = .iPhone
    @Published var crownSensitivity: Double
    @Published var bookTitle: String = ""
    @Published var bookProgress: Double = 0.0
    @Published var readerReady = false
    @Published var hasReceivedStatus = false
    @Published var doubleTapPageTurn = true

    /// Last error message (visible on the watch UI for in-the-field debugging).
    @Published var lastError: String = ""
    /// Timestamp of last successful /status response.
    @Published var lastStatusOK: Date? = nil

    private let controlTargetKey = "watch_control_target"
    private let defaultTargetMigrationKey = "watch_default_target_iphone_migrated"
    private let relayGraceInterval: TimeInterval = 8.0
    private var statusPollTimer: Timer?
    private lazy var commandQueue = ThrottledCommandQueue(interval: 0.1, queue: .main) { [weak self] command, completion in
        self?.performSend(command, completion: completion)
    }

    var isRelayConnected: Bool {
        relayReachable || hasRecentRelaySuccess
    }

    private override init() {
        Self.migrateDefaultTargetIfNeeded(
            targetKey: controlTargetKey,
            migrationKey: defaultTargetMigrationKey
        )
        let sensitivity = UserDefaults.standard.double(forKey: "watch_crown_sensitivity")
        self.crownSensitivity = sensitivity > 0 ? sensitivity : 2.0
        if let rawTarget = UserDefaults.standard.string(forKey: "watch_control_target"),
           let target = ControlTarget(rawValue: rawTarget) {
            self.controlTarget = target
        }
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

        // Sync immediate application context if already received previously
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
        let previousTarget = controlTarget
        if let rawTarget = context[controlTargetKey] as? String,
           let target = ControlTarget(rawValue: rawTarget) {
            controlTarget = target
            UserDefaults.standard.set(rawTarget, forKey: controlTargetKey)
        }
        if let sensitivity = context["watch_crown_sensitivity"] as? Double {
            self.crownSensitivity = sensitivity
            UserDefaults.standard.set(sensitivity, forKey: "watch_crown_sensitivity")
        }
        if let doubleTap = context["watch_double_tap_page_turn"] as? Bool {
            self.doubleTapPageTurn = doubleTap
            UserDefaults.standard.set(doubleTap, forKey: "watch_double_tap_page_turn")
        }
        if controlTarget == .iPhone {
            if let title = context["currentBookTitle"] as? String {
                self.bookTitle = title
            }
            if let progress = context["currentBookProgress"] as? Double {
                self.bookProgress = progress
            }
        }
        if previousTarget != controlTarget {
            relayReachable = false
            bookTitle = ""
            bookProgress = 0.0
            readerReady = false
            hasReceivedStatus = false
            lastStatusOK = nil
            lastError = ""
            refreshStatusPolling()
        } else {
            refreshStatusPolling()
        }
    }

    func sendCommand(_ command: PageCommand) {
        guard WCSession.default.isReachable else {
            DispatchQueue.main.async {
                self.lastError = self.localized("watch.error.openIPhone")
            }
            return
        }
        commandQueue.enqueue(command)
    }

    private func performSend(_ command: PageCommand, completion: @escaping () -> Void) {
        var message = command.message
        message["target"] = controlTarget.rawValue

        WCSession.default.sendMessage(
            message,
            replyHandler: { [weak self] reply in
                self?.handleWatchConnectivityReply(reply)
                // Reply is processed for status/UI updates, but we do not gate
                // the local command queue on the remote roundtrip.
            },
            errorHandler: { [weak self] _ in
                DispatchQueue.main.async {
                    self?.lastError = self?.localized("watch.error.sendFailed") ?? ""
                }
            }
        )

        // Immediately unblock the queue. This makes successive triggers
        // (double tap, buttons, crown) feel much snappier — the throttle
        // interval now gates from dispatch time, not full reader RTT + processing.
        completion()
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
        isReachable = reachable
        guard reachable else { return }
        WCSession.default.sendMessage(
            ["action": "status", "target": controlTarget.rawValue],
            replyHandler: { [weak self] reply in
                self?.handleWatchConnectivityReply(reply)
            },
            errorHandler: { [weak self] error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if self.controlTarget == .iPad {
                        self.markRelayFailure(self.localized("watch.error.ipadTimeout"))
                    } else {
                        self.lastError = self.localized("watch.error.openIPhone")
                    }
                }
            }
        )
    }

    private func handleWatchConnectivityReply(_ reply: [String: Any]) {
        DispatchQueue.main.async {
            let route = reply["route"] as? String
            self.hasReceivedStatus = true

            if let error = reply["error"] as? String {
                let errorCode = reply["errorCode"] as? String
                if errorCode == "NAVIGATOR_NOT_READY" {
                    self.readerReady = false
                }
                if self.controlTarget == .iPad, route == "iPhoneRelay" {
                    if self.isRelayConnectivityError(errorCode) {
                        self.markRelayFailure(self.errorMessage(code: errorCode, error: error))
                    } else {
                        self.markRelaySuccess(clearError: false)
                        self.lastError = self.errorMessage(code: errorCode, error: error)
                    }
                    return
                }

                self.lastError = self.errorMessage(code: errorCode, error: error)
                return
            }

            if let route {
                if route == "iPhoneRelay" {
                    if self.controlTarget == .iPad {
                        self.markRelaySuccess()
                    }
                } else if route == "direct" {
                    if self.controlTarget == .iPhone {
                        self.lastStatusOK = Date()
                        self.lastError = ""
                    }
                }
            }

            self.applyStatusPayload(reply)
        }
    }

    private var hasRecentRelaySuccess: Bool {
        guard let lastStatusOK else { return false }
        return Date().timeIntervalSince(lastStatusOK) < relayGraceInterval
    }

    private func markRelaySuccess(clearError: Bool = true) {
        relayReachable = true
        lastStatusOK = Date()
        if clearError {
            lastError = ""
        }
    }

    private func markRelayFailure(_ message: String) {
        guard !hasRecentRelaySuccess else { return }
        relayReachable = false
        lastError = message
    }

    private func isRelayConnectivityError(_ errorCode: String?) -> Bool {
        errorCode == "IPAD_NOT_FOUND" || errorCode == "RELAY_TIMEOUT"
    }

    private func errorMessage(code: String?, error: String) -> String {
        switch code {
        case "IPAD_NOT_FOUND":
            return localized("watch.error.ipadNotFound")
        case "RELAY_TIMEOUT":
            return localized("watch.error.ipadTimeout")
        case "NAVIGATOR_NOT_READY":
            return controlTarget == .iPad
                ? localized("watch.hint.openBookIPad")
                : localized("watch.hint.openBookIPhone")
        case "PRO_REQUIRED":
            return localized("watch.error.proRequired")
        case "INVALID_COMMAND":
            return localized("watch.error.generic")
        default:
            if error.localizedCaseInsensitiveContains("reader") {
                return controlTarget == .iPad
                    ? localized("watch.hint.openBookIPad")
                    : localized("watch.hint.openBookIPhone")
            }
            return localized("watch.error.generic")
        }
    }

    private func applyStatusPayload(_ json: [String: Any]) {
        DispatchQueue.main.async {
            self.hasReceivedStatus = true
            if let title = json["bookTitle"] as? String {
                self.bookTitle = title
            }
            if let progress = json["bookProgress"] as? Double {
                self.bookProgress = progress
            }
            if let ready = json["readerReady"] as? Bool {
                self.readerReady = ready
            } else if !self.bookTitle.isEmpty {
                self.readerReady = true
            }
            if let sensitivity = json["crownSensitivity"] as? Double {
                self.crownSensitivity = sensitivity
                UserDefaults.standard.set(sensitivity, forKey: "watch_crown_sensitivity")
            }
        }
    }

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    private static func migrateDefaultTargetIfNeeded(targetKey: String, migrationKey: String) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationKey) else { return }

        let rawTarget = defaults.string(forKey: targetKey)
        if rawTarget == nil || rawTarget == ControlTarget.iPad.rawValue {
            defaults.set(ControlTarget.iPhone.rawValue, forKey: targetKey)
        }
        defaults.set(true, forKey: migrationKey)
    }
}

// MARK: - WCSessionDelegate
extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
            self.refreshConnectionStatus()
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
            self.refreshConnectionStatus()
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
