import Foundation
import ReadiumNavigator
import WatchConnectivity

/// Handles Watch session and page turn commands from Apple Watch
final class WatchPageTurnService: NSObject, ObservableObject {
    static let shared = WatchPageTurnService()

    @Published var isWatchConnected: Bool = false

    /// Weak reference to the currently active VisualNavigator
    weak var activeNavigator: VisualNavigator?

    private var session: WCSession?

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }

    /// Call this from VisualReaderViewController when it appears/loads.
    func registerNavigator(_ navigator: VisualNavigator) {
        self.activeNavigator = navigator
    }

    /// Call this from VisualReaderViewController when it disappears.
    func unregisterNavigator() {
        self.activeNavigator = nil
    }

    private func handleCommand(_ command: PageCommand) {
        guard let navigator = activeNavigator else { return }

        Task { @MainActor in
            switch command {
            case .next:
                _ = await navigator.goForward(options: NavigatorGoOptions(animated: true))
            case .prev:
                _ = await navigator.goBackward(options: NavigatorGoOptions(animated: true))
            }
        }
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
