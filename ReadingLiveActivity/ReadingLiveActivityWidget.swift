//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import ActivityKit
import SwiftUI
import WidgetKit

@main
struct PagePilotReadingLiveActivityBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        if #available(iOSApplicationExtension 18.0, *) {
            ReadingLiveActivityWidget()
        } else {
            LegacyReadingLiveActivityWidget()
        }
    }
}

@available(iOSApplicationExtension 18.0, *)
private struct ReadingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        makeReadingLiveActivityConfiguration()
            .supplementalActivityFamilies([.small])
    }
}

private struct LegacyReadingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        makeReadingLiveActivityConfiguration()
    }
}

@MainActor
private func makeReadingLiveActivityConfiguration() -> ActivityConfiguration<ReadingLiveActivityAttributes> {
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

private struct ReadingLiveActivityContent: View {
    let context: ActivityViewContext<ReadingLiveActivityAttributes>

    var body: some View {
        if #available(iOSApplicationExtension 18.0, *) {
            ReadingLiveActivityAdaptiveContent(context: context)
        } else {
            mediumContent
        }
    }

    private var mediumContent: some View {
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

@available(iOSApplicationExtension 18.0, *)
private struct ReadingLiveActivityAdaptiveContent: View {
    @Environment(\.activityFamily) private var activityFamily

    let context: ActivityViewContext<ReadingLiveActivityAttributes>

    var body: some View {
        switch activityFamily {
        case .small:
            smallContent
        case .medium:
            mediumContent
        @unknown default:
            mediumContent
        }
    }

    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "book.closed")
                    .font(.caption)
                Text(context.state.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(percentText(context.state.progression))
                    .font(.title3)
                    .fontWeight(.bold)
                    .monospacedDigit()

                Spacer(minLength: 2)

                ReadingElapsedTime(startedAt: context.attributes.startedAt)
                    .font(.caption2)
            }

            ProgressView(value: clamped(context.state.progression))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var mediumContent: some View {
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
