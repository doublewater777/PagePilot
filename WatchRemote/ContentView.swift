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

    private var clampedBookProgress: Double {
        min(max(connectivityManager.bookProgress, 0.0), 1.0)
    }

    private var sessionProgressDelta: Double {
        max(0.0, clampedBookProgress - connectivityManager.readingSessionStartProgress)
    }

    var body: some View {
        ZStack {
            content

            doubleTapShortcutButton
        }
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

    private var content: some View {
        VStack(spacing: 6) {
            statusMessage

            if connectivityManager.readerReady && !connectivityManager.bookTitle.isEmpty {
                readingDashboard
            } else {
                Spacer(minLength: 0)
            }

            pageTurnButtons

            Text(LocalizedStringKey("watch.crownHint"))
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 5)
    }

    @ViewBuilder
    private var statusMessage: some View {
        if !connectivityManager.lastError.isEmpty {
            Text(connectivityManager.lastError)
                .font(.caption2)
                .foregroundColor(.orange)
                .lineLimit(2)
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
    }

    private var readingDashboard: some View {
        VStack(spacing: 5) {
            Text(connectivityManager.bookTitle)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.0f%%", clampedBookProgress * 100))
                    .font(.title3)
                    .fontWeight(.bold)
                    .monospacedDigit()

                Spacer(minLength: 2)

                if let startedAt = connectivityManager.readingSessionStartedAt {
                    sessionSummary(startedAt: startedAt)
                }
            }

            ProgressView(value: clampedBookProgress)
        }
        .padding(.horizontal, 3)
    }

    private func sessionSummary(startedAt: Date) -> some View {
        TimelineView(.periodic(from: Date(), by: 1.0)) { context in
            VStack(alignment: .trailing, spacing: 0) {
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                    Text(elapsedText(at: context.date, since: startedAt))
                        .monospacedDigit()
                }

                Text(String(format: "+%.1f%%", sessionProgressDelta * 100))
                    .monospacedDigit()
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
    }

    private var pageTurnButtons: some View {
        HStack(spacing: 20) {
            Button {
                connectivityManager.sendCommand(.prev)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .frame(width: 42, height: 32)
            }
            .buttonStyle(.bordered)

            Button {
                connectivityManager.sendCommand(.next)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title2)
                    .frame(width: 42, height: 32)
            }
            .buttonStyle(.bordered)
        }
    }

    private var doubleTapShortcutButton: some View {
        Button {
            connectivityManager.sendCommand(.next)
        } label: {
            Color.clear
                .frame(width: 1, height: 1)
        }
        .buttonStyle(.plain)
        .opacity(0.01)
        .accessibilityHidden(true)
        .handGestureShortcutIfEnabled(connectivityManager.doubleTapPageTurn)
    }

    private func elapsedText(at date: Date, since startDate: Date) -> String {
        let totalSeconds = max(0, Int(date.timeIntervalSince(startDate)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
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
