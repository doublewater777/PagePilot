import SwiftUI

#if os(watchOS)
import WatchKit
#endif

struct ContentView: View {
    @State private var crownValue: Double = 0.0
    @State private var lastSentValue: Double = 0.0
    @State private var lastPageTurnTime: Date = Date()
    @State private var isWorkoutHelpPresented = false
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
        if connectivityManager.isConnecting && !connectivityManager.readerReady {
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
            #if DEBUG
            if CommandLine.arguments.contains("-mockReading") {
                connectivityManager.isReachable = true
                connectivityManager.readerReady = true
                connectivityManager.bookTitle = "人类简史"
                connectivityManager.bookProgress = 0.42
                connectivityManager.readingSessionStartedAt = Date().addingTimeInterval(-1800)
                connectivityManager.readingSessionStartProgress = 0.28
                connectivityManager.lastError = ""
                return
            }
            #endif
            connectivityManager.refreshConnectionStatus()
        }
        .onChange(of: crownValue) { newValue in
            handleCrownRotation(newValue)
        }
        .alert(
            Text(LocalizedStringKey("watch.workoutHelp.title")),
            isPresented: $isWorkoutHelpPresented
        ) {
            Button(LocalizedStringKey("watch.workoutHelp.dismiss"), role: .cancel) {}
        } message: {
            Text(LocalizedStringKey("watch.workoutHelp.message"))
        }
    }

    private var content: some View {
        VStack(spacing: 4) {
            actionableErrorMessage

            if isConnected && connectivityManager.activeReaderCount > 1 {
                Image(systemName: "ipad.and.iphone")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(height: 20)
                    .accessibilityHidden(true)
            } else if isConnected && connectivityManager.readerReady && !connectivityManager.bookTitle.isEmpty {
                readingDashboard
            } else {
                Spacer(minLength: 0)
            }

            pageTurnButtons

            passiveStatusMessage

            if isConnected && connectivityManager.readerReady {
                Button {
                    isWorkoutHelpPresented = true
                } label: {
                    Label(
                        LocalizedStringKey("watch.workoutHelp.button"),
                        systemImage: "figure.run"
                    )
                    .font(.caption2)
                    .lineLimit(1)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .accessibilityIdentifier("watch.workoutHelp")
            }

            if isConnected && (!connectivityManager.readerReady || connectivityManager.bookTitle.isEmpty) {
                HStack(spacing: 4) {
                    Image(systemName: "digitalcrown.arrow.clockwise")
                        .imageScale(.small)
                    Text(LocalizedStringKey("watch.crownHint"))
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var actionableErrorMessage: some View {
        if isConnected && !connectivityManager.lastError.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .imageScale(.small)
                Text(connectivityManager.lastError)
            }
            .font(.caption2)
            .foregroundStyle(.orange)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var passiveStatusMessage: some View {
        if !isConnected && !connectivityManager.lastError.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "exclamationmark.circle")
                    .imageScale(.small)
                Text(connectivityManager.lastError)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        } else if let guidanceKey {
            HStack(alignment: .center, spacing: 4) {
                if connectivityManager.isConnecting {
                    ProgressView()
                        .scaleEffect(0.55)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: "iphone.gen3")
                        .imageScale(.small)
                }
                Text(LocalizedStringKey(guidanceKey))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var readingDashboard: some View {
        VStack(spacing: 2) {
            Text(connectivityManager.bookTitle)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.0f%%", clampedBookProgress * 100))
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Color.pagePilotBlue)
                    .monospacedDigit()

                Spacer(minLength: 2)

                if let startedAt = connectivityManager.readingSessionStartedAt {
                    sessionSummary(startedAt: startedAt)
                }
            }

            ProgressView(value: clampedBookProgress)
                .tint(Color.pagePilotBlue)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        VStack(spacing: 4) {
            Button {
                sendPageTurn(.prev)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(.headline, design: .rounded).weight(.semibold))
                    Text(LocalizedStringKey("watch.previousPage"))
                }
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 42)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("watch.pageTurn.previous")

            Button {
                sendPageTurn(.next)
            } label: {
                HStack(spacing: 7) {
                    Text(LocalizedStringKey("watch.nextPage"))
                    Image(systemName: "chevron.right")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                }
                .font(.system(.title3, design: .rounded).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.pagePilotBlue)
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

// MARK: - Color Palette (Aligned with docs/design-system.md)

extension Color {
    /// PagePilot Blue `#386EF2` (领航蓝 - 品牌主色 / Watch 翻页控制)
    static let pagePilotBlue = Color(red: 56 / 255, green: 110 / 255, blue: 242 / 255)
    /// PagePilot Teal `#299E94` (流畅绿)
    static let pagePilotTeal = Color(red: 41 / 255, green: 158 / 255, blue: 148 / 255)
}

#if DEBUG
#Preview("Disconnected") {
    ContentView()
        .environmentObject(WatchConnectivityManager.shared)
}
#endif

