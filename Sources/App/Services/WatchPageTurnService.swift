import Foundation
import Darwin
import ReadiumNavigator
import ReadiumShared
import UIKit
import WatchConnectivity
import ReadiumGCDWebServer

private enum WatchPageTurnRoute {
    static let direct = "direct"
    static let iPhoneRelay = "iPhoneRelay"
}

private enum WatchPageTurnErrorCode {
    static let iPadNotFound = "IPAD_NOT_FOUND"
    static let relayTimeout = "RELAY_TIMEOUT"
    static let navigatorNotReady = "NAVIGATOR_NOT_READY"
    static let invalidCommand = "INVALID_COMMAND"
    static let proRequired = "PRO_REQUIRED"
}

private final class PagePilotLANBrowser: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    static let shared = PagePilotLANBrowser()

    private let serviceType = "_pagepilot._tcp."
    private let serviceDomain = "local."
    private let fallbackEndpoint = URL(string: "http://iPad.local:61482")
    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    private var pendingCompletions: [(URL?) -> Void] = []
    private var isBrowsing = false
    private var fallbackWasInvalidated = false

    private(set) var lastKnownEndpoint: URL?

    private override init() {
        super.init()
        browser.delegate = self
    }

    func warmUp() {
        DispatchQueue.main.async {
            self.startBrowsingIfNeeded()
        }
    }

    func endpoint(completion: @escaping (URL?) -> Void) {
        DispatchQueue.main.async {
            if let endpoint = self.lastKnownEndpoint {
                completion(endpoint)
                return
            }

            self.startBrowsingIfNeeded()

            if let fallbackEndpoint = self.fallbackEndpoint, !self.fallbackWasInvalidated {
                print("PagePilotLANBrowser: using fast fallback \(fallbackEndpoint.absoluteString)")
                completion(fallbackEndpoint)
                return
            }

            self.pendingCompletions.append(completion)

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self else { return }
                if let endpoint = self.lastKnownEndpoint {
                    self.flushPendingIfNeeded(with: endpoint)
                } else {
                    print("PagePilotLANBrowser: Bonjour timed out")
                    self.flushPendingIfNeeded(with: nil)
                }
            }
        }
    }

    func invalidate(_ endpoint: URL) {
        DispatchQueue.main.async {
            if self.fallbackEndpoint == endpoint {
                self.fallbackWasInvalidated = true
            }
            guard self.lastKnownEndpoint == endpoint else { return }
            print("PagePilotLANBrowser: invalidating endpoint \(endpoint.absoluteString)")
            self.lastKnownEndpoint = nil
            self.startBrowsingIfNeeded()
        }
    }

    private func startBrowsingIfNeeded() {
        guard !isBrowsing else { return }
        isBrowsing = true
        print("PagePilotLANBrowser: browsing \(serviceType) in \(serviceDomain)")
        browser.searchForServices(ofType: serviceType, inDomain: serviceDomain)
    }

    private func flushPendingIfNeeded(with endpoint: URL?) {
        guard !pendingCompletions.isEmpty else { return }
        let completions = pendingCompletions
        pendingCompletions = []
        completions.forEach { $0(endpoint) }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard service.name.hasPrefix("PagePilot-iPad") else { return }
        print("PagePilotLANBrowser: found service \(service.name)")
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 2.0)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let endpoint = endpointURL(for: sender) else { return }
        print("PagePilotLANBrowser: resolved \(sender.name) -> \(endpoint.absoluteString)")
        lastKnownEndpoint = endpoint
        flushPendingIfNeeded(with: endpoint)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        print("PagePilotLANBrowser: failed to resolve \(sender.name): \(errorDict)")
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        print("PagePilotLANBrowser: failed to browse: \(errorDict)")
        flushPendingIfNeeded(with: fallbackEndpoint)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services.removeAll { $0 === service || $0.name == service.name }
        if lastKnownEndpoint?.host?.hasPrefix(service.name) == true {
            lastKnownEndpoint = nil
        }
    }

    private func endpointURL(for service: NetService) -> URL? {
        if let url = numericIPv4EndpointURL(for: service) {
            return url
        }

        guard service.port > 0 else { return nil }
        let rawHost = service.hostName ?? "\(service.name).local"
        let host = rawHost.hasSuffix(".") ? String(rawHost.dropLast()) : rawHost
        if let url = URL(string: "http://\(urlHost(host)):\(service.port)") {
            return url
        }

        return numericIPv6EndpointURL(for: service)
    }

    private func numericIPv4EndpointURL(for service: NetService) -> URL? {
        guard let addresses = service.addresses else { return nil }

        for address in addresses {
            guard let endpoint = numericEndpointURL(from: address, family: sa_family_t(AF_INET)) else {
                continue
            }
            return endpoint
        }

        return nil
    }

    private func numericIPv6EndpointURL(for service: NetService) -> URL? {
        guard let addresses = service.addresses else { return nil }

        for address in addresses {
            guard let endpoint = numericEndpointURL(from: address, family: sa_family_t(AF_INET6)) else {
                continue
            }
            return endpoint
        }

        return nil
    }

    private func numericEndpointURL(from address: Data, family: sa_family_t) -> URL? {
        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        var portBuffer = [CChar](repeating: 0, count: Int(NI_MAXSERV))

        let result = address.withUnsafeBytes { rawBuffer -> Int32 in
            guard let sockaddrPointer = rawBuffer.baseAddress?.assumingMemoryBound(to: sockaddr.self),
                  sockaddrPointer.pointee.sa_family == family else {
                return EAI_FAIL
            }

            return getnameinfo(
                sockaddrPointer,
                socklen_t(address.count),
                &hostBuffer,
                socklen_t(hostBuffer.count),
                &portBuffer,
                socklen_t(portBuffer.count),
                NI_NUMERICHOST | NI_NUMERICSERV
            )
        }

        guard result == 0,
              let port = Int(String(cString: portBuffer)) else {
            return nil
        }

        let host = String(cString: hostBuffer)
        return URL(string: "http://\(urlHost(host)):\(port)")
    }

    private func urlHost(_ host: String) -> String {
        host.contains(":") ? "[\(host)]" : host
    }
}

/// Handles Watch session and page turn commands from Apple Watch
final class WatchPageTurnService: NSObject, ObservableObject {
    static let shared = WatchPageTurnService()

    @Published var isWatchConnected: Bool = false
    @Published var isLANWatchConnected: Bool = false

    /// Weak reference to the currently active VisualNavigator
    weak var activeNavigator: VisualNavigator?

    @Published var currentBookTitle: String = ""
    @Published var currentBookProgress: Double = 0.0

    private var session: WCSession?
    private var lanServer: ReadiumGCDWebServer?
    private var lanResetTimer: Timer?
    private let preferredLANPort: UInt = 61482

    private override init() {
        super.init()
    }

    func activate() {
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
        // Start the LAN server eagerly on iPad so the Watch can discover the
        // reader even before a book is opened. The paired iPhone deliberately
        // does not advertise this service; it can act as a relay when the
        // Watch cannot reach the iPad LAN directly.
        if UIDevice.current.userInterfaceIdiom == .pad {
            startLANServer()
        }
    }

    /// Call this from VisualReaderViewController when it appears/loads.
    func registerNavigator(_ navigator: VisualNavigator, publication: Publication) {
        self.activeNavigator = navigator
        let title = publication.metadata.title ?? ""
        let progress = navigator.currentLocation?.locations.totalProgression ?? 0.0
        self.currentBookTitle = title
        self.currentBookProgress = progress
        updateProgress(title: title, progression: progress)

        // Defensive: in case activate() wasn't called for some reason.
        if UIDevice.current.userInterfaceIdiom == .pad {
            startLANServer()
        }
    }

    /// Call this from VisualReaderViewController when it disappears.
    func unregisterNavigator() {
        self.activeNavigator = nil
        var context = WatchPageTurnSettings().watchContext
        context["currentBookTitle"] = ""
        context["currentBookProgress"] = 0.0
        updateApplicationContextSafely(context)
        // Keep the LAN server running so the Watch keeps showing connected.
        // The /command handler will simply early-return when no navigator is active.
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

    private func handleCommand(_ command: PageCommand, completion: (([String: Any]) -> Void)? = nil) {
        guard let navigator = activeNavigator else {
            completion?(errorPayload(
                route: WatchPageTurnRoute.direct,
                code: WatchPageTurnErrorCode.navigatorNotReady,
                message: "reader is not ready"
            ))
            return
        }

        Task { @MainActor in
            let succeeded: Bool
            switch command {
            case .next:
                succeeded = await navigator.goForward(options: NavigatorGoOptions(animated: false))
            case .prev:
                succeeded = await navigator.goBackward(options: NavigatorGoOptions(animated: false))
            }

            if succeeded {
                ReviewPromptManager.shared.recordWatchPageTurn()
            }

            var payload = self.localStatusPayload(route: WatchPageTurnRoute.direct)
            payload["pageDirection"] = command.rawValue
            payload["didTurnPage"] = succeeded
            completion?(payload)
        }
    }

    private func relayCommandToLAN(_ command: PageCommand, replyHandler: (([String: Any]) -> Void)? = nil) {
        relayRequestToLAN(
            path: "command",
            method: "POST",
            body: [
                "action": command.rawValue,
                "source": "watch",
                "requestId": UUID().uuidString,
                "timestamp": Date().timeIntervalSince1970
            ],
            replyHandler: replyHandler
        )
    }

    private func relayStatusToLAN(replyHandler: (([String: Any]) -> Void)? = nil) {
        relayRequestToLAN(path: "status", method: "GET", body: nil, replyHandler: replyHandler)
    }

    private func relayRequestToLAN(
        path: String,
        method: String,
        body: [String: Any]?,
        replyHandler: (([String: Any]) -> Void)? = nil
    ) {
        PagePilotLANBrowser.shared.endpoint { endpoint in
            guard let endpoint else {
                replyHandler?(self.errorPayload(
                    route: WatchPageTurnRoute.iPhoneRelay,
                    code: WatchPageTurnErrorCode.iPadNotFound,
                    message: "iPhone could not find PagePilot on iPad"
                ))
                return
            }

            let url = endpoint.appendingPathComponent(path)
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = 2.5
            if let body {
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    PagePilotLANBrowser.shared.invalidate(endpoint)
                    replyHandler?(self.errorPayload(
                        route: WatchPageTurnRoute.iPhoneRelay,
                        code: WatchPageTurnErrorCode.relayTimeout,
                        message: "\(error.localizedDescription) (\(url.absoluteString))"
                    ))
                    return
                }

                var payload: [String: Any] = [
                    "status": "ok",
                    "ok": true,
                    "route": WatchPageTurnRoute.iPhoneRelay,
                    "endpoint": endpoint.absoluteString
                ]
                if let data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    payload.merge(json) { _, new in new }
                    payload["route"] = WatchPageTurnRoute.iPhoneRelay
                }

                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    if payload["error"] == nil {
                        payload = self.errorPayload(
                            route: WatchPageTurnRoute.iPhoneRelay,
                            code: WatchPageTurnErrorCode.relayTimeout,
                            message: "iPad HTTP \(http.statusCode)"
                        )
                    } else {
                        payload["status"] = "error"
                        payload["ok"] = false
                    }
                }
                replyHandler?(payload)
            }.resume()
        }
    }

    private func localStatusPayload(route: String) -> [String: Any] {
        [
            "status": "ok",
            "ok": true,
            "route": route,
            "target": route == WatchPageTurnRoute.iPhoneRelay ? "ipad" : WatchPageTurnSettings().controlTarget.rawValue,
            "readerReady": activeNavigator != nil,
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

    private func jsonResponse(_ object: [String: Any], statusCode: Int = 200) -> ReadiumGCDWebServerDataResponse? {
        guard let response = ReadiumGCDWebServerDataResponse(jsonObject: object) else { return nil }
        response.statusCode = statusCode
        return response
    }

    // MARK: - LAN Server

    func markLANWatchConnected() {
        isLANWatchConnected = true
        lanResetTimer?.invalidate()
        lanResetTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.isLANWatchConnected = false
            }
        }
    }

    private func startLANServer() {
        guard lanServer == nil else { return }
        
        let webServer = ReadiumGCDWebServer()
        
        // GET /status
        webServer.addHandler(
            forMethod: "GET",
            path: "/status",
            request: ReadiumGCDWebServerRequest.self,
            asyncProcessBlock: { _, completionBlock in
                DispatchQueue.main.async {
                    let title = WatchPageTurnService.shared.currentBookTitle
                    let progress = WatchPageTurnService.shared.currentBookProgress
                    let sensitivity = WatchPageTurnSettings().crownSensitivity
                    WatchPageTurnService.shared.markLANWatchConnected()
                    
                    let responseDict: [String: Any] = [
                        "status": "ok",
                        "ok": true,
                        "target": "ipad",
                        "readerReady": WatchPageTurnService.shared.activeNavigator != nil,
                        "bookTitle": title,
                        "bookProgress": progress,
                        "crownSensitivity": sensitivity
                    ]
                    
                    completionBlock(WatchPageTurnService.shared.jsonResponse(responseDict))
                }
            }
        )
        
        // POST /command
        webServer.addHandler(
            forMethod: "POST",
            path: "/command",
            request: ReadiumGCDWebServerDataRequest.self,
            asyncProcessBlock: { request, completionBlock in
                let json = (request as? ReadiumGCDWebServerDataRequest)?.jsonObject as? [String: Any]
                let action = json?["action"] as? String
                
                Task { @MainActor in
                    guard let navigator = WatchPageTurnService.shared.activeNavigator else {
                        completionBlock(WatchPageTurnService.shared.jsonResponse(
                            WatchPageTurnService.shared.errorPayload(
                                route: WatchPageTurnRoute.direct,
                                code: WatchPageTurnErrorCode.navigatorNotReady,
                                message: "reader is not ready"
                            ),
                            statusCode: 409
                        ))
                        return
                    }
                    
                    guard let command = action.flatMap(PageCommand.init(rawValue:)) else {
                        completionBlock(WatchPageTurnService.shared.jsonResponse(
                            WatchPageTurnService.shared.errorPayload(
                                route: WatchPageTurnRoute.direct,
                                code: WatchPageTurnErrorCode.invalidCommand,
                                message: "invalid page command"
                            ),
                            statusCode: 409
                        ))
                        return
                    }
                    
                    let settings = WatchPageTurnSettings()
                    WatchPageTurnService.shared.markLANWatchConnected()
                    
                    let succeeded: Bool
                    switch command {
                    case .next:
                        succeeded = await navigator.goForward(options: NavigatorGoOptions(animated: false))
                    case .prev:
                        succeeded = await navigator.goBackward(options: NavigatorGoOptions(animated: false))
                    }

                    if succeeded {
                        ReviewPromptManager.shared.recordWatchPageTurn()
                    }

                    completionBlock(WatchPageTurnService.shared.jsonResponse([
                        "status": "ok",
                        "ok": true,
                        "target": "ipad",
                        "route": WatchPageTurnRoute.direct,
                        "readerReady": true,
                        "bookTitle": WatchPageTurnService.shared.currentBookTitle,
                        "bookProgress": navigator.currentLocation?.locations.totalProgression ?? 0.0,
                        "crownSensitivity": settings.crownSensitivity,
                        "pageDirection": command.rawValue,
                        "didTurnPage": succeeded
                    ]))
                }
            }
        )
        
        do {
            let deviceName = UIDevice.current.name.replacingOccurrences(of: " ", with: "-")
            try webServer.start(options: [
                ReadiumGCDWebServerOption_Port: preferredLANPort,
                ReadiumGCDWebServerOption_BonjourName: "PagePilot-iPad-\(deviceName)",
                ReadiumGCDWebServerOption_BonjourType: "_pagepilot._tcp",
                ReadiumGCDWebServerOption_AutomaticallySuspendInBackground: false
            ])
            self.lanServer = webServer
            print("WatchPageTurnService: LAN Server started. port=\(webServer.port) bonjour=PagePilot-iPad-\(deviceName)")
        } catch {
            do {
                let deviceName = UIDevice.current.name.replacingOccurrences(of: " ", with: "-")
                try webServer.start(options: [
                    ReadiumGCDWebServerOption_Port: 0,
                    ReadiumGCDWebServerOption_BonjourName: "PagePilot-iPad-\(deviceName)",
                    ReadiumGCDWebServerOption_BonjourType: "_pagepilot._tcp",
                    ReadiumGCDWebServerOption_AutomaticallySuspendInBackground: false
                ])
                self.lanServer = webServer
                print("WatchPageTurnService: LAN Server started on fallback port. port=\(webServer.port) bonjour=PagePilot-iPad-\(deviceName)")
            } catch {
                print("WatchPageTurnService: Failed to start LAN Server: \(error)")
            }
        }
    }
    
    private func stopLANServer() {
        lanServer?.stop()
        lanServer = nil
        print("WatchPageTurnService: LAN Server stopped")
    }
}

extension WatchPageTurnService: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isWatchConnected = activationState == .activated
        }
        if activationState == .activated, UIDevice.current.userInterfaceIdiom == .phone {
            WatchPageTurnSettings().syncToWatch()
            PagePilotLANBrowser.shared.warmUp()
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
        guard let action = message["action"] as? String else {
            replyHandler?(["status": "ignored", "reason": "invalid message"])
            return
        }

        let targetRawValue = message["target"] as? String
        let target = targetRawValue.flatMap(WatchPageTurnSettings.ControlTarget.init(rawValue:))
            ?? WatchPageTurnSettings().controlTarget

        switch action {
        case "status":
            switch target {
            case .iPad where UIDevice.current.userInterfaceIdiom == .phone:
                guard ProPurchaseManager.shared.hasProAccess else {
                    replyHandler?(errorPayload(
                        route: WatchPageTurnRoute.iPhoneRelay,
                        code: WatchPageTurnErrorCode.proRequired,
                        message: "pro is required for iPad page turn"
                    ))
                    return
                }
                relayStatusToLAN(replyHandler: replyHandler)
            case .iPhone where UIDevice.current.userInterfaceIdiom == .phone:
                replyHandler?(localStatusPayload(route: "direct"))
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

            switch target {
            case .iPad where UIDevice.current.userInterfaceIdiom == .phone:
                guard ProPurchaseManager.shared.hasProAccess else {
                    replyHandler?(errorPayload(
                        route: WatchPageTurnRoute.iPhoneRelay,
                        code: WatchPageTurnErrorCode.proRequired,
                        message: "pro is required for iPad page turn"
                    ))
                    return
                }
                relayCommandToLAN(command, replyHandler: replyHandler)
            case .iPhone where UIDevice.current.userInterfaceIdiom == .phone:
                guard activeNavigator != nil else {
                    replyHandler?(errorPayload(
                        route: WatchPageTurnRoute.direct,
                        code: WatchPageTurnErrorCode.navigatorNotReady,
                        message: "reader is not ready"
                    ))
                    return
                }
                handleCommand(command, completion: replyHandler)
            case .iPad where UIDevice.current.userInterfaceIdiom == .pad:
                guard ProPurchaseManager.shared.hasProAccess else {
                    replyHandler?(errorPayload(
                        route: WatchPageTurnRoute.direct,
                        code: WatchPageTurnErrorCode.proRequired,
                        message: "pro is required for iPad page turn"
                    ))
                    return
                }
                guard activeNavigator != nil else {
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
