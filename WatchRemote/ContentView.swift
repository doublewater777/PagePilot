import SwiftUI

struct ContentView: View {
    @State private var crownValue: Double = 0.0
    @State private var lastSentValue: Double = 0.0
    @State private var lastPageTurnTime: Date = Date()
    @EnvironmentObject var connectivityManager: WatchConnectivityManager

    // Crown rotation thresholds
    private var baseThreshold: Double {
        connectivityManager.crownSensitivity
    }
    private let maxThreshold: Double = 10.0
    private let speedWindow: TimeInterval = 0.3

    private var isConnected: Bool {
        switch connectivityManager.controlTarget {
        case .iPad:
            return connectivityManager.isRelayConnected
        case .iPhone:
            return connectivityManager.isReachable
        }
    }

    private var guidanceKey: String? {
        if !connectivityManager.lastError.isEmpty {
            return nil
        }
        if !isConnected {
            switch connectivityManager.controlTarget {
            case .iPad:
                return connectivityManager.isReachable ? "watch.hint.openIPad" : "watch.hint.openIPhone"
            case .iPhone:
                return "watch.hint.openIPhone"
            }
        }
        if connectivityManager.hasReceivedStatus && !connectivityManager.readerReady {
            switch connectivityManager.controlTarget {
            case .iPad:
                return "watch.hint.openBookIPad"
            case .iPhone:
                return "watch.hint.openBookIPhone"
            }
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 8) {
            if !connectivityManager.lastError.isEmpty {
                Text(connectivityManager.lastError)
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
            } else if let guidanceKey {
                Text(LocalizedStringKey(guidanceKey))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)
            }

            if !connectivityManager.bookTitle.isEmpty {
                VStack(spacing: 2) {
                    Text(connectivityManager.bookTitle)
                        .font(.headline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .multilineTextAlignment(.center)

                    Text(String(format: "%.1f%%", connectivityManager.bookProgress * 100))
                        .font(.footnote)
                        .foregroundColor(.accentColor)
                }
                .padding(.horizontal, 4)
            } else {
                Spacer()
            }

            // Page turn buttons
            HStack(spacing: 25) {
                Button {
                    connectivityManager.sendCommand(.prev)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .frame(width: 45, height: 35)
                }
                .buttonStyle(.bordered)

                Button {
                    connectivityManager.sendCommand(.next)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title2)
                        .frame(width: 45, height: 35)
                }
                .buttonStyle(.bordered)
                .handGestureShortcutIfEnabled(connectivityManager.doubleTapPageTurn)
            }

            Spacer()

            // Hint
            Text(LocalizedStringKey("watch.crownHint"))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 5)
        .focusable()
        #if os(watchOS)
        .digitalCrownRotation($crownValue)
        #endif
        .onAppear {
            connectivityManager.refreshConnectionStatus()
        }
        .onChange(of: crownValue) { newValue in
            handleCrownRotation(newValue)
        }
    }

    private func handleCrownRotation(_ value: Double) {
        let now = Date()
        let timeSinceLastTurn = now.timeIntervalSince(lastPageTurnTime)

        // Speed-based threshold
        let speedFactor = min(timeSinceLastTurn / speedWindow, 1.0)
        let currentThreshold = baseThreshold + (maxThreshold - baseThreshold) * (1.0 - speedFactor)

        let delta = value - lastSentValue

        if abs(delta) > currentThreshold {
            let direction: PageCommand = delta > 0 ? .next : .prev
            connectivityManager.sendCommand(direction)
            lastSentValue = value
            lastPageTurnTime = now
        }
    }
}

extension View {
    @ViewBuilder
    func handGestureShortcutIfEnabled(_ enabled: Bool) -> some View {
        if #available(watchOS 11, *) {
            self.handGestureShortcut(.primaryAction, isEnabled: enabled)
        } else {
            self
        }
    }
}
