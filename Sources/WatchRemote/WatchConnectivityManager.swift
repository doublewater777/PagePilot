import Foundation
import WatchConnectivity

final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published var isReachable = false

    private override init() {
        super.init()
        activateSession()
    }

    private func activateSession() {
        guard WCSession.isSupported() else { return }
        isReachable = WCSession.default.activationState == .activated
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendCommand(_ command: PageCommand) {
        guard WCSession.default.isReachable else {
            return
        }

        WCSession.default.sendMessage(
            command.message,
            replyHandler: { _ in },
            errorHandler: { _ in }
        )
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isReachable = activationState == .activated
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }
}
