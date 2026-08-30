import ActivityKit
import SwiftUI
import WidgetKit

struct MicroReadingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MicroReadingLiveActivityAttributes.self) { context in
            HStack(spacing: 8) {
                Image(systemName: "book.closed.fill")
                    .foregroundStyle(.tint)
                Text("Micro Reading")
                Spacer()
                remainingTime(for: context.state)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Micro Reading")
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "book.closed.fill")
                        .foregroundStyle(.tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    remainingTime(for: context.state)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Micro Reading")
                        .font(.headline)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "book.closed.fill")
                    .foregroundStyle(.tint)
            } compactTrailing: {
                remainingTime(for: context.state)
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "timer")
            }
            .widgetURL(URL(string: "pagepilot://micro-reading"))
        }
    }

    @ViewBuilder
    private func remainingTime(
        for state: MicroReadingLiveActivityAttributes.ContentState
    ) -> some View {
        if let endDate = state.endDate {
            Text(endDate, style: .timer)
        } else {
            Text(countdownText(seconds: state.pausedRemaining ?? 0))
        }
    }

    private func countdownText(seconds: TimeInterval) -> String {
        let value = max(0, Int(ceil(seconds)))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

@main
struct MicroReadingLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        MicroReadingLiveActivityWidget()
    }
}
