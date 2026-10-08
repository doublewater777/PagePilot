import Foundation
import ReadiumNavigator
import ReadiumShared
import UIKit
import WatchConnectivity

enum WatchPageTurnRoute {
    static let direct = "direct"
    static let iPhoneRelay = "iPhoneRelay"
}

enum WatchPageTurnErrorCode {
    static let iPadNotFound = "IPAD_NOT_FOUND"
    static let relayTimeout = "RELAY_TIMEOUT"
    static let navigatorNotReady = "NAVIGATOR_NOT_READY"
    static let invalidCommand = "INVALID_COMMAND"
    static let proRequired = "PRO_REQUIRED"
}

enum WatchPageTurnOrigin {
    case direct
    case iPadRelay
}

enum WatchAvailability {
    case unsupported
    case unpaired
    case appNotInstalled
    case unreachable
    case ready
}

enum WatchGuideEligibility {
    /// The Reader guide reacts to live Watch state, so any iPhone Reader may
    /// show it regardless of onboarding progress.
    static func shouldShow(isPhone: Bool) -> Bool {
        isPhone
    }
}

enum WatchReaderAvailabilityPolicy {
    static func isReady(hasNavigator: Bool, applicationIsActive: Bool) -> Bool {
        hasNavigator && applicationIsActive
    }
}

/// Handles Watch session and page turn commands from Apple Watch
final class WatchPageTurnService: NSObject, ObservableObject {
    static let shared = WatchPageTurnService()

    @Published var isWatchConnected: Bool = false

    /// iPad: page-turn host state, surfaced on the iPad diagnostics page.
    @Published private(set) var peerHostState = PagePilotPeerHostState()
    /// iPhone: whether the link to the selected iPad is open right now.
    @Published private(set) var isIPadLinkConnected = false

    /// Weak reference to the currently active VisualNavigator
    weak var activeNavigator: VisualNavigator?
    private var pageTurnSuppressionToken: UUID?
    private var isPageTurnSuppressed: Bool { pageTurnSuppressionToken != nil }

    @Published var currentBookTitle: String = ""
    @Published var currentBookProgress: Double = 0.0

    var isReaderReady: Bool {
        WatchReaderAvailabilityPolicy.isReady(
            hasNavigator: activeNavigator != nil,
            applicationIsActive: UIApplication.shared.applicationState == .active
        )
    }

    private var session: WCSession?
    private let commandDedupWindow: TimeInterval = 8.0
    private var recentCommandIDs: [String: Date] = [:]
    private var lifecycleObservers: [NSObjectProtocol] = []

    var watchAvailability: WatchAvailability {
        guard WCSession.isSupported() else { return .unsupported }
        let session = WCSession.default
        guard session.isPaired else { return .unpaired }
        guard session.isWatchAppInstalled else { return .appNotInstalled }
        guard session.isReachable else { return .unreachable }
        return .ready
    }

    private override init() {
        super.init()
        PagePilotPeerHost.shared.onStateChange = { [weak self] state in
            self?.peerHostState = state
        }
        PagePilotPeerClient.shared.onConnectionChange = { [weak self] connected in
            self?.isIPadLinkConnected = connected
        }
        observeAppLifecycle()
    }

    private func observeAppLifecycle() {
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { _ in
                // A socket may not survive suspension. Watch commands that wake
                // the app reconnect on demand instead of waiting on a dead link.
                if UIDevice.current.userInterfaceIdiom == .phone {
                    PagePilotPeerClient.shared.reset()
                }
            },
            center.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                if UIDevice.current.userInterfaceIdiom == .pad {
                    self?.enableIPadRelay()
                } else {
                    self?.prepareIPadRelay()
                }
            }
        ]
    }

    func activate() {
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
        if UIDevice.current.userInterfaceIdiom == .pad {
            enableIPadRelay()
        } else {
            prepareIPadRelay()
            #if DEBUG
            PagePilotPeerSoakTest.startIfRequested()
            #endif
        }
    }

    // MARK: - iPad host

    /// Starts the iPad page-turn host when this device is an iPad with Pro.
    /// Safe to call repeatedly; no-ops on iPhone or without Pro Access.
    func enableIPadRelay() {
        switch PagePilotRelayEntitlementLifecyclePolicy.action(
            isIPad: UIDevice.current.userInterfaceIdiom == .pad,
            hasProAccess: ProPurchaseManager.shared.hasProAccess
        ) {
        case .start:
            PagePilotPeerHost.shared.start(
                advertisement: currentAdvertisement,
                hasProAccess: { ProPurchaseManager.shared.hasProAccess },
                handler: { request, reply in
                    DispatchQueue.main.async {
                        WatchPageTurnService.shared.handlePeerRequest(request, reply: reply)
                    }
                }
            )
        case .stop:
            disableIPadRelay()
        case .noOp:
            return
        }
    }

    /// Stops iPad advertising when Pro access is no longer valid.
    func disableIPadRelay() {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        recentCommandIDs.removeAll()
        PagePilotPeerHost.shared.stop()
    }

    private var currentAdvertisement: PagePilotPeerAdvertisement {
        PagePilotPeerAdvertisement(
            name: UIDevice.current.name,
            bookTitle: activeNavigator == nil ? "" : currentBookTitle
        )
    }

    /// iPad self-test: whether the host is advertising and accepting peers.
    @MainActor
    func runLocalStatusProbe() async -> Bool {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return false }
        enableIPadRelay()
        for _ in 0..<15 where !peerHostState.isListening {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return peerHostState.isListening
    }

    @MainActor
    private func handlePeerRequest(_ request: PagePilotPeerRequest, reply: @escaping ([String: Any]) -> Void) {
        switch request.kind {
        case .status:
            reply(localStatusPayload(route: WatchPageTurnRoute.direct))
        case .command:
            guard let command = request.action else {
                reply(errorPayload(
                    route: WatchPageTurnRoute.direct,
                    code: WatchPageTurnErrorCode.invalidCommand,
                    message: "invalid page command"
                ))
                return
            }
            guard shouldProcessCommand(id: request.commandID) else {
                var payload = localStatusPayload(route: WatchPageTurnRoute.direct)
                payload["pageDirection"] = command.rawValue
                payload["didTurnPage"] = false
                payload["duplicate"] = true
                reply(payload)
                return
            }
            handleCommand(command, origin: .iPadRelay, completion: reply)
        }
    }

    private func shouldProcessCommand(id: String?) -> Bool {
        guard let id, !id.isEmpty else { return true }
        let now = Date()
        recentCommandIDs = recentCommandIDs.filter {
            now.timeIntervalSince($0.value) < commandDedupWindow
        }
        if recentCommandIDs[id] != nil {
            return false
        }
        recentCommandIDs[id] = now
        return true
    }

    // MARK: - iPhone client

    /// Stops the iPhone-side link and discovery. Safe to call on entitlement revoke.
    func stopIPadRelayDiscovery() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        PagePilotPeerClient.shared.cancelDiscovery()
        PagePilotPeerClient.shared.connect(to: nil)
    }

    /// Opens the link to the selected iPad ahead of the first page turn.
    func prepareIPadRelay() {
        guard UIDevice.current.userInterfaceIdiom == .phone,
              ProPurchaseManager.shared.hasProAccess,
              let target = PagePilotNearbySelectionStore.selectedTarget() else {
            return
        }
        PagePilotPeerClient.shared.connect(to: target.id)
    }

    /// Verifies a user-chosen iPad and remembers it only if it answers.
    func connectNearbyIPad(_ target: PagePilotNearbyTarget, completion: @escaping (Bool) -> Void) {
        guard UIDevice.current.userInterfaceIdiom == .phone,
              ProPurchaseManager.shared.hasProAccess else {
            completion(false)
            return
        }
        PagePilotPeerClient.shared.send(to: target.id, kind: .status) { result in
            guard case .success(let payload) = result,
                  payload["ok"] as? Bool == true,
                  ProPurchaseManager.shared.hasProAccess else {
                completion(false)
                return
            }
            PagePilotNearbySelectionStore.remember(target)
            completion(true)
        }
    }

    /// Turns a page on the selected iPad straight from iPhone, without a Watch.
    /// Completes with whether the iPad's open Reader handled the command.
    func turnSelectedIPadPage(_ command: PageCommand, completion: @escaping (Bool) -> Void) {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            completion(false)
            return
        }
        // Reaching the end of the book is not a failure; only an undelivered
        // command or a closed Reader is.
        relayToSelectedIPad(.command, action: command) { payload in
            completion(payload["ok"] as? Bool == true)
        }
    }

    /// Sends one request to the selected iPad and replies on the main queue
    /// with the same payload shape the Watch has always received.
    fileprivate func relayToSelectedIPad(
        _ kind: PagePilotPeerRequestKind,
        action: PageCommand? = nil,
        commandID: String? = nil,
        replyHandler: (([String: Any]) -> Void)? = nil
    ) {
        guard ProPurchaseManager.shared.hasProAccess else {
            replyHandler?(errorPayload(
                route: WatchPageTurnRoute.iPhoneRelay,
                code: WatchPageTurnErrorCode.proRequired,
                message: "pro is required for iPad page turn"
            ))
            return
        }
        guard let target = PagePilotNearbySelectionStore.selectedTarget() else {
            replyHandler?(errorPayload(
                route: WatchPageTurnRoute.iPhoneRelay,
                code: WatchPageTurnErrorCode.iPadNotFound,
                message: "Select an iPad in iPhone Watch Page Turn settings first"
            ))
            return
        }

        // A Watch command may wake a suspended iPhone; finish the relay first.
        var backgroundTask = UIBackgroundTaskIdentifier.invalid
        backgroundTask = UIApplication.shared.beginBackgroundTask {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }

        PagePilotPeerClient.shared.send(
            to: target.id,
            kind: kind,
            action: action,
            commandID: kind == .command ? (commandID ?? UUID().uuidString) : nil
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(var payload):
                payload["route"] = WatchPageTurnRoute.iPhoneRelay
                replyHandler?(payload)
            case .failure(let error):
                replyHandler?(self.errorPayload(
                    route: WatchPageTurnRoute.iPhoneRelay,
                    code: error.watchErrorCode,
                    message: "iPad relay failed: \(error.rawValue)"
                ))
            }
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }
        }
    }

    // MARK: - Reader

    /// Call this from VisualReaderViewController when it appears/loads.
    func registerNavigator(_ navigator: VisualNavigator, publication: Publication) {
        self.activeNavigator = navigator
        let title = publication.metadata.title ?? ""
        let progress = navigator.currentLocation?.locations.totalProgression ?? 0.0
        self.currentBookTitle = title
        self.currentBookProgress = progress
        updateProgress(title: title, progression: progress)

        // Also (re)starts the host when Pro was granted after activate(), and
        // advertises the open book so the iPhone list can show it.
        if UIDevice.current.userInterfaceIdiom == .pad {
            enableIPadRelay()
        }
    }

    /// Call this from VisualReaderViewController when it disappears.
    func unregisterNavigator(_ navigator: VisualNavigator) {
        guard let activeNavigator, activeNavigator === navigator else { return }
        self.activeNavigator = nil
        pageTurnSuppressionToken = nil
        var context = WatchPageTurnSettings().watchContext
        context["currentBookTitle"] = ""
        context["currentBookProgress"] = 0.0
        updateApplicationContextSafely(context)
        // Keep the host running so the iPhone link survives; commands return
        // NAVIGATOR_NOT_READY until another Reader opens.
        if UIDevice.current.userInterfaceIdiom == .pad {
            PagePilotPeerHost.shared.update(advertisement: currentAdvertisement)
        }
    }

    func beginPageTurnSuppression() -> UUID {
        let token = UUID()
        pageTurnSuppressionToken = token
        return token
    }

    func endPageTurnSuppression(_ token: UUID) {
        guard pageTurnSuppressionToken == token else { return }
        pageTurnSuppressionToken = nil
    }

    /// Update reading progress on the watch
    func updateProgress(title: String, progression: Double?) {
        self.currentBookTitle = title
        self.currentBookProgress = progression ?? 0.0

        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled
        else { return }

        var context = WatchPageTurnSettings().watchContext
        context["currentBookTitle"] = title
        context["currentBookProgress"] = progression ?? 0.0

        updateApplicationContextSafely(context)
    }

    private func updateApplicationContextSafely(_ context: [String: Any]) {
        do {
            try WCSession.default.updateApplicationContext(context)
        } catch let error as WCError where error.code == .watchAppNotInstalled {
            // Expected when the Watch app is not installed; no need to log.
        } catch {
            print("WatchPageTurnService: Failed to update application context: \(error)")
        }
    }

    @MainActor
    private func recordSuccessfulWatchPageTurn(origin: WatchPageTurnOrigin) {
        ReviewPromptManager.shared.recordWatchPageTurn()
        NotificationCenter.default.post(
            name: .watchPageTurnDidSucceed,
            object: origin
        )
    }

    private func handleCommand(
        _ command: PageCommand,
        origin: WatchPageTurnOrigin = .direct,
        completion: (([String: Any]) -> Void)? = nil
    ) {
        Task { @MainActor in
            guard !self.isPageTurnSuppressed else {
                var payload = self.localStatusPayload(route: WatchPageTurnRoute.direct)
                payload["pageDirection"] = command.rawValue
                payload["didTurnPage"] = false
                completion?(payload)
                return
            }
            guard let navigator = self.activeNavigator,
                  WatchReaderAvailabilityPolicy.isReady(
                      hasNavigator: true,
                      applicationIsActive: UIApplication.shared.applicationState == .active
                  ) else {
                completion?(self.errorPayload(
                    route: WatchPageTurnRoute.direct,
                    code: WatchPageTurnErrorCode.navigatorNotReady,
                    message: "reader is not ready"
                ))
                return
            }
            let succeeded: Bool
            switch command {
            case .next:
                succeeded = await navigator.goForward(options: NavigatorGoOptions(animated: false))
            case .prev:
                succeeded = await navigator.goBackward(options: NavigatorGoOptions(animated: false))
            }

            if succeeded {
                self.recordSuccessfulWatchPageTurn(origin: origin)
            }

            var payload = self.localStatusPayload(route: WatchPageTurnRoute.direct)
            payload["pageDirection"] = command.rawValue
            payload["didTurnPage"] = succeeded
            completion?(payload)
        }
    }

    private func localStatusPayload(route: String) -> [String: Any] {
        [
            "status": "ok",
            "ok": true,
            "route": route,
            "target": UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone",
            "readerReady": isReaderReady,
            "bookTitle": currentBookTitle,
            "bookProgress": currentBookProgress,
            "crownSensitivity": WatchPageTurnSettings().crownSensitivity
        ]
    }

    private func errorPayload(route: String, code: String, message: String) -> [String: Any] {
        [
            "status": "error",
            "ok": false,
            "route": route,
            "errorCode": code,
            "error": message
        ]
    }
}

extension WatchPageTurnService: WCSessionDelegate {
    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isWatchConnected = activationState == .activated
        }
        if activationState == .activated, UIDevice.current.userInterfaceIdiom == .phone {
            WatchPageTurnSettings().syncToWatch()
            DispatchQueue.main.async {
                self.prepareIPadRelay()
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchConnected = false
        }
    }

    func sessionDidDeactivate(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchConnected = false
        }
        WCSession.default.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchConnected = session.isReachable
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleMessage(message, replyHandler: nil)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        handleMessage(message, replyHandler: replyHandler)
    }

    private func handleMessage(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)?) {
        // WCSession delivers on a background queue; hop to main for navigator / Pro state.
        DispatchQueue.main.async {
            self.handleMessageOnMain(message, replyHandler: replyHandler)
        }
    }

    private func handleMessageOnMain(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)?) {
        guard let action = message["action"] as? String else {
            replyHandler?(["status": "ignored", "reason": "invalid message"])
            return
        }

        let targetRawValue = message["target"] as? String
        let target = targetRawValue.flatMap(WatchPageTurnSettings.ControlTarget.init(rawValue:))
            ?? .iPhone

        switch action {
        case "status":
            switch target {
            case .iPad where UIDevice.current.userInterfaceIdiom == .phone:
                relayToSelectedIPad(.status, replyHandler: replyHandler)
            case .iPhone where UIDevice.current.userInterfaceIdiom == .phone:
                replyHandler?(localStatusPayload(route: WatchPageTurnRoute.direct))
            case .iPad where UIDevice.current.userInterfaceIdiom == .pad:
                // Watch is always paired to iPhone, but keep this path for completeness.
                replyHandler?(localStatusPayload(route: WatchPageTurnRoute.direct))
            default:
                replyHandler?(["status": "ignored", "reason": "unsupported target"])
            }

        case "turnPage":
            guard let directionString = message["direction"] as? String,
                  let command = PageCommand(rawValue: directionString)
            else {
                replyHandler?(["status": "ignored", "reason": "invalid page command"])
                return
            }
            let commandID = message["commandId"] as? String

            switch target {
            case .iPad where UIDevice.current.userInterfaceIdiom == .phone:
                relayToSelectedIPad(.command, action: command, commandID: commandID, replyHandler: replyHandler)
            case .iPhone where UIDevice.current.userInterfaceIdiom == .phone:
                guard isReaderReady else {
                    replyHandler?(errorPayload(
                        route: WatchPageTurnRoute.direct,
                        code: WatchPageTurnErrorCode.navigatorNotReady,
                        message: "reader is not ready"
                    ))
                    return
                }
                handleCommand(command, completion: replyHandler)
            case .iPad where UIDevice.current.userInterfaceIdiom == .pad:
                // LAN path is primary; WCSession on iPad is rare. Do not require Pro here —
                // Pro is enforced on the iPhone relay entry point.
                guard isReaderReady else {
                    replyHandler?(errorPayload(
                        route: WatchPageTurnRoute.direct,
                        code: WatchPageTurnErrorCode.navigatorNotReady,
                        message: "reader is not ready"
                    ))
                    return
                }
                handleCommand(command, completion: replyHandler)
            default:
                replyHandler?(["status": "ignored", "reason": "unsupported target"])
            }

        default:
            replyHandler?(["status": "ignored", "reason": "unknown action"])
        }
    }
}

extension Notification.Name {
    static let watchPageTurnDidSucceed = Notification.Name("watchPageTurnDidSucceed")
}

#if DEBUG
import Network

/// Device QA without hands on the iPhone: launched with `-PagePilotPeerSoak`,
/// the iPhone turns the selected iPad's page every few seconds and writes one
/// line per attempt to Documents/peer-soak.log, including whether Wi-Fi had a
/// network at that moment, so links can be checked across Wi-Fi changes.
/// `-PagePilotPeerSoakCount N` sets the number of turns (default 120).
/// Driven by scripts/peer-link-soak.sh.
private enum PagePilotPeerSoakTest {
    private static var started = false
    private static let pathMonitor = NWPathMonitor()
    private static var wifiJoined = false
    private static var turnCount = 120

    private static var logURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("peer-soak.log")
    }

    static func startIfRequested() {
        guard !started, ProcessInfo.processInfo.arguments.contains("-PagePilotPeerSoak") else { return }
        started = true
        let requestedCount = UserDefaults.standard.integer(forKey: "PagePilotPeerSoakCount")
        if requestedCount > 0 { turnCount = requestedCount }
        if let logURL { try? FileManager.default.removeItem(at: logURL) }
        pathMonitor.pathUpdateHandler = { path in
            let joined = path.status == .satisfied && path.usesInterfaceType(.wifi)
            DispatchQueue.main.async {
                if joined != wifiJoined { log("wifi network \(joined ? "joined" : "left")") }
                wifiJoined = joined
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "PagePilot.PeerSoak.path"))
        log("soak start target=\(PagePilotNearbySelectionStore.selectedTarget()?.id ?? "none")")
        run(iteration: 1)
    }

    private static func run(iteration: Int) {
        guard iteration <= turnCount else {
            log("soak done")
            return
        }
        if iteration % 5 == 1 {
            PagePilotPeerClient.shared.discoverTargets { result in
                let found = (try? result.get())?.map { "\($0.name)/\($0.id.prefix(8))" } ?? []
                log("scan found=\(found) wifiNetwork=\(wifiJoined)")
            }
        }
        let command: PageCommand = iteration % 2 == 0 ? .prev : .next
        let started = Date()
        WatchPageTurnService.shared.relayToSelectedIPad(.command, action: command) { payload in
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            let linked = WatchPageTurnService.shared.isIPadLinkConnected
            let ok = payload["ok"] as? Bool == true
            let detail = ok ? "turned=\(payload["didTurnPage"] as? Bool == true)" : "error=\(payload["error"] ?? payload["errorCode"] ?? "?")"
            log("#\(iteration) \(command.rawValue) ok=\(ok) \(ms)ms linked=\(linked) wifiNetwork=\(wifiJoined) \(detail)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                run(iteration: iteration + 1)
            }
        }
    }

    private static func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        print("PeerSoak: \(message)")
        guard let url = logURL, let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
#endif
