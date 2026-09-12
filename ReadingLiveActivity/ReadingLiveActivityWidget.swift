//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import ActivityKit
import SwiftUI
import WidgetKit

@main
struct PagePilotReadingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReadingLiveActivityAttributes.self) { context in
            ReadingLiveActivityContent(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.state.title)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "book.closed")
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(percentText(context.state.progression))
                        .monospacedDigit()
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        ProgressView(value: clamped(context.state.progression))
                        ReadingElapsedTime(startedAt: context.attributes.startedAt)
                            .font(.caption)
                    }
                }
            } compactLeading: {
                Image(systemName: "book.closed")
            } compactTrailing: {
                Text(percentText(context.state.progression))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "book.closed")
            }
        }
    }
}

private struct ReadingLiveActivityContent: View {
    let context: ActivityViewContext<ReadingLiveActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "book.closed")
                Text(context.state.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(percentText(context.state.progression))
                    .font(.headline)
                    .monospacedDigit()
            }

            ProgressView(value: clamped(context.state.progression))

            ReadingElapsedTime(startedAt: context.attributes.startedAt)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

private struct ReadingElapsedTime: View {
    let startedAt: Date

    var body: some View {
        Text(timerInterval: startedAt ... Date.distantFuture, countsDown: false)
            .monospacedDigit()
            .lineLimit(1)
    }
}

private func clamped(_ value: Double) -> Double {
    min(max(value, 0.0), 1.0)
}

private func percentText(_ value: Double) -> String {
    String(format: "%.0f%%", clamped(value) * 100)
}
