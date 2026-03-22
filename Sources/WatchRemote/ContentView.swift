import SwiftUI

struct ContentView: View {
    @State private var crownValue: Double = 0.0
    @State private var lastSentValue: Double = 0.0
    @State private var lastPageTurnTime: Date = Date()
    @EnvironmentObject var connectivityManager: WatchConnectivityManager

    // Crown rotation thresholds
    private let baseThreshold: Double = 2.0
    private let maxThreshold: Double = 10.0
    private let speedWindow: TimeInterval = 0.3

    private var connectionStatusText: Text {
        Text(connectivityManager.isReachable
             ? LocalizedStringKey("watch.connected")
             : LocalizedStringKey("watch.notConnected"))
    }

    var body: some View {
        VStack(spacing: 10) {
            // Connection status
            HStack(spacing: 4) {
                Circle()
                    .fill(connectivityManager.isReachable ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                connectionStatusText
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

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
            }

            Spacer()

            // Hint
            Text(LocalizedStringKey("watch.crownHint"))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 5)
        .focusable()
        .digitalCrownRotation($crownValue)
        .onChange(of: crownValue) { oldValue, newValue in
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
