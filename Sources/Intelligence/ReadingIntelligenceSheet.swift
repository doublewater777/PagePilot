//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import SwiftUI
import UIKit

/// Serene editorial sheet displaying streamed on-device Apple Intelligence responses
/// for selection explanation/translation, spoiler-free recaps, chapter summaries, and quote insights.
struct ReadingIntelligenceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let initialTask: ReadingIntelligenceTask
    let contextLoader: (() async -> ReadingIntelligenceTask?)?

    @State private var activeTask: ReadingIntelligenceTask
    @State private var selectionMode: SelectionMode = .explain
    @State private var streamedText: String = ""
    @State private var isPreparingContext: Bool = false
    @State private var isStreaming: Bool = false
    @State private var errorMessage: String?
    @State private var didCopy: Bool = false
    @State private var streamTask: Task<Void, Never>?

    private enum SelectionMode: String, CaseIterable, Identifiable {
        case explain
        case translate

        var id: String { rawValue }

        var title: String {
            switch self {
            case .explain:
                return NSLocalizedString("ai_mode_explain", comment: "")
            case .translate:
                return NSLocalizedString("ai_mode_translate", comment: "")
            }
        }
    }

    init(
        task: ReadingIntelligenceTask,
        contextLoader: (() async -> ReadingIntelligenceTask?)? = nil
    ) {
        self.initialTask = task
        self.contextLoader = contextLoader
        _activeTask = State(initialValue: task)
        if case .translateSelection = task {
            _selectionMode = State(initialValue: .translate)
        }
    }

    private var isSelectionTask: Bool {
        switch initialTask {
        case .explainSelection, .translateSelection:
            return true
        default:
            return false
        }
    }

    private var selectedQuoteText: String? {
        switch activeTask {
        case let .explainSelection(text, _, _), let .translateSelection(text, _, _):
            return text
        default:
            return nil
        }
    }

    private var subtitleContext: String? {
        switch activeTask {
        case let .explainSelection(_, bookTitle, chapterTitle),
             let .recap(bookTitle, chapterTitle, _),
             let .chapterSummary(bookTitle, chapterTitle, _):
            if let chapterTitle, !chapterTitle.isEmpty, chapterTitle != bookTitle {
                return "\(bookTitle) · \(chapterTitle)"
            }
            return bookTitle
        case let .translateSelection(_, _, bookTitle):
            return bookTitle
        case let .quoteInsights(quotes):
            return String(format: NSLocalizedString("ai_quote_insights_count_format", comment: ""), quotes.count)
        }
    }

    private var isSimulated: Bool {
        ReadingIntelligenceEngine.shared.effectiveAvailability.isSimulated
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    heroBadgeRow

                    if isSelectionTask {
                        Picker("", selection: $selectionMode) {
                            ForEach(SelectionMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: selectionMode) { _, newMode in
                            switchSelectionMode(to: newMode)
                        }
                    }

                    if let quote = selectedQuoteText, !quote.isEmpty {
                        quotedExcerptCard(quote)
                    }

                    responseCard

                    privacyFootnote
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle(activeTask.localizedTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton {
                        streamTask?.cancel()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            startGeneration(reloadContext: contextLoader != nil)
        }
        .onDisappear {
            streamTask?.cancel()
        }
    }

    // MARK: - Subviews

    private var heroBadgeRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: activeTask.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.accentGradient)
                Text(NSLocalizedString("ai_badge_apple_intelligence", comment: ""))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(AppColors.primaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                LinearGradient(
                    colors: [
                        AppColors.accentBlue.opacity(colorScheme == .dark ? 0.22 : 0.10),
                        AppColors.accentTeal.opacity(colorScheme == .dark ? 0.18 : 0.08),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(AppColors.accentBlue.opacity(colorScheme == .dark ? 0.35 : 0.2), lineWidth: 0.6)
            )

            if isSimulated {
                Text(NSLocalizedString("ai_badge_simulated_preview", comment: ""))
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.14), in: Capsule())
            }

            Spacer(minLength: 4)

            if let subtitleContext {
                Text(subtitleContext)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    private func quotedExcerptCard(_ quote: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(AppColors.accentGradient)
                .frame(width: 3)

            Text("“\(quote)”")
                .font(.system(size: 14, weight: .regular, design: .serif))
                .foregroundStyle(AppColors.secondaryText)
                .lineSpacing(4)
                .lineLimit(4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06), lineWidth: 0.6)
        )
    }

    private var responseCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let errorMessage {
                VStack(alignment: .leading, spacing: 10) {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        startGeneration(reloadContext: contextLoader != nil)
                    } label: {
                        Label(NSLocalizedString("ai_action_retry", comment: ""), systemImage: "arrow.clockwise")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(AppColors.horizontalGradient, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            } else if streamedText.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(AppColors.accentTeal)
                        Text(
                            NSLocalizedString(
                                isPreparingContext ? "ai_status_reading_context" : "ai_status_thinking",
                                comment: ""
                            )
                        )
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.secondaryText)
                    }

                    ForEach(0..<3, id: \.self) { row in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
                            .frame(height: 12)
                            .frame(maxWidth: row == 2 ? 210 : .infinity)
                    }
                }
                .padding(.vertical, 4)
            } else {
                Text(streamedText)
                    .font(.system(size: 15.5, weight: .regular))
                    .foregroundStyle(AppColors.primaryText)
                    .lineSpacing(6)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeOut(duration: 0.12), value: streamedText.count)

                Divider()
                    .opacity(0.45)

                HStack(spacing: 10) {
                    if isStreaming {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(AppColors.accentTeal)
                            Text(NSLocalizedString("ai_status_generating", comment: ""))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppColors.secondaryText)
                        }
                    } else {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            startGeneration(reloadContext: false)
                        } label: {
                            Label(NSLocalizedString("ai_action_regenerate", comment: ""), systemImage: "arrow.clockwise")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppColors.secondaryText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 8)

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        UIPasteboard.general.string = streamedText
                        didCopy = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            didCopy = false
                        }
                    } label: {
                        Label(
                            NSLocalizedString(didCopy ? "wifi_transfer_copied" : "reader_copy", comment: ""),
                            systemImage: didCopy ? "checkmark" : "doc.on.doc"
                        )
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(didCopy ? AppColors.accentTeal : AppColors.accentBlue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            (didCopy ? AppColors.accentTeal : AppColors.accentBlue).opacity(0.11),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(streamedText.isEmpty)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            AppColors.accentBlue.opacity(colorScheme == .dark ? 0.25 : 0.14),
                            AppColors.accentTeal.opacity(colorScheme == .dark ? 0.20 : 0.10),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.05), radius: 14, y: 6)
    }

    private var privacyFootnote: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield")
                .font(.system(size: 11.5, weight: .medium))
            Text(NSLocalizedString("ai_privacy_footnote", comment: ""))
                .font(.system(size: 11.5))
        }
        .foregroundStyle(AppColors.tertiaryText)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 2)
    }

    // MARK: - Actions

    private func switchSelectionMode(to mode: SelectionMode) {
        guard case let .explainSelection(text, bookTitle, chapterTitle) = initialTask else {
            if case let .translateSelection(text, _, bookTitle) = initialTask {
                activeTask = mode == .explain
                    ? .explainSelection(text: text, bookTitle: bookTitle, chapterTitle: nil)
                    : .translateSelection(text: text, targetLanguage: AppAppearancePreferences.language, bookTitle: bookTitle)
                startGeneration(reloadContext: false)
            }
            return
        }
        activeTask = mode == .explain
            ? .explainSelection(text: text, bookTitle: bookTitle, chapterTitle: chapterTitle)
            : .translateSelection(text: text, targetLanguage: AppAppearancePreferences.language, bookTitle: bookTitle)
        startGeneration(reloadContext: false)
    }

    private func startGeneration(reloadContext: Bool) {
        streamTask?.cancel()
        errorMessage = nil
        streamedText = ""
        didCopy = false
        isStreaming = true

        streamTask = Task {
            var taskToRun = activeTask
            if reloadContext, let loader = contextLoader {
                await MainActor.run { isPreparingContext = true }
                if let loaded = await loader() {
                    taskToRun = loaded
                    await MainActor.run { activeTask = loaded }
                } else {
                    await MainActor.run {
                        isPreparingContext = false
                        isStreaming = false
                        errorMessage = ReadingIntelligenceError.emptyContext.localizedDescription
                    }
                    return
                }
                await MainActor.run { isPreparingContext = false }
            }

            let stream = ReadingIntelligenceEngine.shared.stream(task: taskToRun)
            do {
                for try await partial in stream {
                    if Task.isCancelled { return }
                    await MainActor.run {
                        streamedText = partial
                    }
                }
                await MainActor.run {
                    isStreaming = false
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    isStreaming = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
