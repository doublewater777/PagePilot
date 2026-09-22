import SwiftUI

#if os(watchOS)
import WatchKit
#endif

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
        connectivityManager.isReachable
    }

    private var guidanceKey: String? {
        if !connectivityManager.lastError.isEmpty {
            return nil
        }
        if connectivityManager.isConnecting {
            return "watch.status.connecting"
        }
        if !isConnected {
            return "watch.hint.openIPhone"
        }
        // Reader routing is automatic now. Avoid telling the user to choose a
        // specific device when neither Reader is active; the page-turn buttons
        // remain available and the next status poll will pick up either device.
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

            if isConnected && connectivityManager.activeReaderCount > 1 {
                Image(systemName: "ipad.and.iphone")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(height: 22)
                    .accessibilityHidden(true)
            } else if isConnected && connectivityManager.readerReady && !connectivityManager.bookTitle.isEmpty {
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
        VStack(spacing: 4) {
            Text(connectivityManager.bookTitle)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.0f%%", clampedBookProgress * 100))
                    .font(.headline)
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
        VStack(spacing: 6) {
            Button {
                sendPageTurn(.prev)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text(LocalizedStringKey("watch.previousPage"))
                }
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("watch.pageTurn.previous")

            Button {
                sendPageTurn(.next)
            } label: {
                HStack(spacing: 7) {
                    Text(LocalizedStringKey("watch.nextPage"))
                    Image(systemName: "chevron.right")
                }
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("watch.pageTurn.next")
        }
    }

    private var doubleTapShortcutButton: some View {
        Button {
            sendPageTurn(.next)
        } label: {
            Color.clear
                .frame(width: 1, height: 1)
        }
        .buttonStyle(.plain)
        .opacity(0.01)
        .accessibilityHidden(true)
        .handGestureShortcutIfEnabled(connectivityManager.doubleTapPageTurn)
    }

    private func sendPageTurn(_ command: PageCommand) {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #endif
        connectivityManager.sendCommand(command)
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
            sendPageTurn(direction)
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
