import SwiftUI

struct ContentView: View {
    @State private var crownValue: Double = 0.0
    @State private var lastSentValue: Double = 0.0
    @State private var lastPageTurnTime: Date = Date()
    @State private var showingDiagnostics = false
    @EnvironmentObject var connectivityManager: WatchConnectivityManager

    // Crown rotation thresholds
    private var baseThreshold: Double {
        connectivityManager.crownSensitivity
    }
    private let maxThreshold: Double = 10.0
    private let speedWindow: TimeInterval = 0.3

    private var connectionStatusText: Text {
        if connectivityManager.activeLANURL != nil {
            return Text("iPad (LAN)")
        } else {
            return Text(connectivityManager.isReachable
                 ? LocalizedStringKey("watch.connected")
                 : LocalizedStringKey("watch.notConnected"))
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Connection status — tap to open diagnostics
            Button {
                showingDiagnostics = true
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(connectivityManager.isReachable ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    connectionStatusText
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if !connectivityManager.bookTitle.isEmpty {
                VStack(spacing: 2) {
                    Text(connectivityManager.bookTitle)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.center)

                    Text(String(format: "%.1f%%", connectivityManager.bookProgress))
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
        .onChange(of: crownValue) { newValue in
            handleCrownRotation(newValue)
        }
        .sheet(isPresented: $showingDiagnostics) {
            DiagnosticsView()
                .environmentObject(connectivityManager)
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

// MARK: - Diagnostics

private struct DiagnosticsView: View {
    @EnvironmentObject var manager: WatchConnectivityManager

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Diagnostics")
                    .font(.headline)

                row("WC reachable", manager.isReachable ? "yes" : "no")
                row("LAN URL", manager.activeLANURL?.absoluteString ?? "—")
                row("Browser", manager.browserPhase.rawValue)
                row("Resolve", manager.resolvePhase.rawValue)
                row("Services seen", "\(manager.visibleServiceCount)")
                if !manager.visibleServiceNames.isEmpty {
                    row("All", manager.visibleServiceNames.joined(separator: "\n"))
                }
                row("Matched", manager.matchedServiceNames.isEmpty
                    ? "—"
                    : manager.matchedServiceNames.joined(separator: ", "))
                row("Last /status",
                    manager.lastStatusOK.map { Self.timeFormatter.string(from: $0) } ?? "—")

                if !manager.lastError.isEmpty {
                    Text("Error")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                    Text(manager.lastError)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    manager.restartDiscovery()
                } label: {
                    Label("Re-scan", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 6)

                Text(hintText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 6)
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.caption2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var hintText: String {
        switch manager.browserPhase {
        case .waiting:
            return "Local network permission may be off. Check Watch settings."
        case .failed:
            return "Browser failed. Tap Re-scan."
        case .ready where manager.matchedServiceNames.isEmpty:
            return "Open a book on the iPad. The Watch only sees the iPad while a book is open."
        case .idle, .starting:
            return "Starting up…"
        default:
            return ""
        }
    }
}
