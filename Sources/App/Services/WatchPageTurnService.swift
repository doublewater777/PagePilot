import Foundation
import ReadiumNavigator
import ReadiumShared
import UIKit
import WatchConnectivity
import ReadiumGCDWebServer

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
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .light)
    private var lanServer: ReadiumGCDWebServer?
    private var lanResetTimer: Timer?

    private override init() {
        super.init()
        hapticGenerator.prepare()
    }

    func activate() {
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
        // Start the LAN server eagerly so the Watch can discover the iPad even
        // before the user opens a book. Page-turn commands still no-op when no
        // navigator is registered, but /status will respond and the Watch UI
        // will show "iPad (LAN)" — which makes troubleshooting much easier.
        startLANServer()
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
        startLANServer()
    }

    /// Call this from VisualReaderViewController when it disappears.
    func unregisterNavigator() {
        self.activeNavigator = nil
        try? WCSession.default.updateApplicationContext([
            "currentBookTitle": "",
            "currentBookProgress": 0.0
        ])
        // Keep the LAN server running so the Watch keeps showing connected.
        // The /command handler will simply early-return when no navigator is active.
    }

    /// Update reading progress on the watch
    func updateProgress(title: String, progression: Double?) {
        self.currentBookTitle = title
        self.currentBookProgress = progression ?? 0.0

        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        var context = session.receivedApplicationContext
        context["currentBookTitle"] = title
        context["currentBookProgress"] = progression ?? 0.0
        
        try? session.updateApplicationContext(context)
    }

    private func handleCommand(_ command: PageCommand) {
        guard let navigator = activeNavigator else { return }

        let settings = WatchPageTurnSettings()

        Task { @MainActor in
            let succeeded: Bool
            let animated = settings.pageTurnAnimation != .none
            switch command {
            case .next:
                succeeded = await navigator.goForward(options: NavigatorGoOptions(animated: animated))
            case .prev:
                succeeded = await navigator.goBackward(options: NavigatorGoOptions(animated: animated))
            }

            if succeeded, settings.hapticFeedback {
                hapticGenerator.impactOccurred()
            }
        }
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
            processBlock: { _ in
                var title = ""
                var progress = 0.0
                var sensitivity = 2.0
                
                DispatchQueue.main.sync {
                    title = WatchPageTurnService.shared.currentBookTitle
                    progress = WatchPageTurnService.shared.currentBookProgress
                    sensitivity = WatchPageTurnSettings().crownSensitivity.threshold
                    WatchPageTurnService.shared.markLANWatchConnected()
                }
                
                let responseDict: [String: Any] = [
                    "status": "ok",
                    "bookTitle": title,
                    "bookProgress": progress,
                    "crownSensitivity": sensitivity
                ]
                
                guard let jsonData = try? JSONSerialization.data(withJSONObject: responseDict) else {
                    return nil
                }
                return ReadiumGCDWebServerDataResponse(data: jsonData, contentType: "application/json")
            }
        )
        
        // GET /command
        webServer.addHandler(
            forMethod: "GET",
            path: "/command",
            request: ReadiumGCDWebServerRequest.self,
            processBlock: { request in
                let semaphore = DispatchSemaphore(value: 0)
                var title = ""
                var progress = 0.0
                var sensitivity = 2.0
                
                DispatchQueue.main.async {
                    guard let navigator = WatchPageTurnService.shared.activeNavigator else {
                        semaphore.signal()
                        return
                    }
                    
                    let action = request.query?["action"] as? String
                    let settings = WatchPageTurnSettings()
                    let animated = settings.pageTurnAnimation != .none
                    
                    WatchPageTurnService.shared.markLANWatchConnected()
                    
                    Task {
                        if action == "next" {
                            _ = await navigator.goForward(options: NavigatorGoOptions(animated: animated))
                        } else if action == "prev" {
                            _ = await navigator.goBackward(options: NavigatorGoOptions(animated: animated))
                        }
                        
                        title = WatchPageTurnService.shared.currentBookTitle
                        progress = navigator.currentLocation?.locations.totalProgression ?? 0.0
                        sensitivity = settings.crownSensitivity.threshold
                        semaphore.signal()
                    }
                }
                
                _ = semaphore.wait(timeout: .now() + 1.5)
                
                let responseDict: [String: Any] = [
                    "status": "ok",
                    "bookTitle": title,
                    "bookProgress": progress,
                    "crownSensitivity": sensitivity
                ]
                
                guard let jsonData = try? JSONSerialization.data(withJSONObject: responseDict) else {
                    return nil
                }
                return ReadiumGCDWebServerDataResponse(data: jsonData, contentType: "application/json")
            }
        )
        
        do {
            let deviceName = UIDevice.current.name.replacingOccurrences(of: " ", with: "-")
            try webServer.start(options: [
                ReadiumGCDWebServerOption_Port: 0,
                ReadiumGCDWebServerOption_BonjourName: "PagePilot-iPad-\(deviceName)",
                ReadiumGCDWebServerOption_AutomaticallySuspendInBackground: false
            ])
            self.lanServer = webServer
            print("WatchPageTurnService: LAN Server started. port=\(webServer.port) bonjour=PagePilot-iPad-\(deviceName)")
        } catch {
            print("WatchPageTurnService: Failed to start LAN Server: \(error)")
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
        handleMessage(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        handleMessage(message)
        replyHandler(["status": "ok"])
    }

    private func handleMessage(_ message: [String: Any]) {
        guard let action = message["action"] as? String,
              action == "turnPage",
              let directionString = message["direction"] as? String,
              let command = PageCommand(rawValue: directionString)
        else { return }

        handleCommand(command)
    }
}
