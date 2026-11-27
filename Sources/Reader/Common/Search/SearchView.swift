//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import Foundation
import ReadiumNavigator
import ReadiumShared
import SwiftUI
import UIKit

struct SearchView: View {
    @ObservedObject var viewModel: SearchViewModel
    var onClose: (() -> Void)? = nil

    @State private var viewVisible: Bool = false
    @State private var inputText: String = ""
    @FocusState private var isSearchFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    private var isSearching: Bool {
        switch viewModel.state {
        case .starting, .loadingNext:
            return true
        default:
            return false
        }
    }

    private var hasQuery: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchInputBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                if hasQuery && !viewModel.results.isEmpty {
                    HStack {
                        Text(String(
                            format: NSLocalizedString("reader_search_results_count", comment: ""),
                            viewModel.results.count
                        ))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.secondaryText)
                        .monospacedDigit()

                        Spacer()

                        if isSearching {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }

                contentBody
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("reader_search_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton {
                        if let onClose {
                            onClose()
                        } else {
                            dismiss()
                        }
                    }
                }
            }
        }
        .onAppear {
            viewVisible = true
            if inputText.isEmpty && !viewModel.query.isEmpty {
                inputText = viewModel.query
            }
            if inputText.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isSearchFocused = true
                }
            }
        }
        .onDisappear {
            viewVisible = false
        }
    }

    private var searchInputBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColors.secondaryText)

            TextField(NSLocalizedString("search_placeholder", comment: ""), text: $inputText)
                .focused($isSearchFocused)
                .font(.system(size: 15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onChange(of: inputText) { _, newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        viewModel.cancelSearch()
                    } else {
                        viewModel.search(with: newValue)
                    }
                }

            if !inputText.isEmpty {
                Button {
                    inputText = ""
                    viewModel.cancelSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isSearchFocused
                        ? AppColors.accentBlue.opacity(0.6)
                        : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)),
                    lineWidth: isSearchFocused ? 1.5 : 1
                )
        )
    }

    @ViewBuilder
    private var contentBody: some View {
        if !hasQuery {
            emptyState(
                icon: "magnifyingglass",
                title: NSLocalizedString("reader_search_prompt", comment: "")
            )
        } else if viewModel.results.isEmpty && isSearching {
            VStack(spacing: 12) {
                ProgressView()
                    .tint(AppColors.accentBlue)
                    .scaleEffect(1.1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.results.isEmpty {
            emptyState(
                icon: "doc.text.magnifyingglass",
                title: NSLocalizedString("reader_search_no_results", comment: "")
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.results.indices, id: \.self) { index in
                            let locator = viewModel.results[index]
                            searchResultCard(locator: locator, index: index)
                                .id(index)
                                .onAppear {
                                    if index >= viewModel.results.count - 3 {
                                        viewModel.loadNextPage()
                                    }
                                }
                        }

                        if case .loadingNext = viewModel.state {
                            ProgressView()
                                .padding(.vertical, 16)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .onChange(of: viewVisible) { _, newValue in
                    if newValue, let lastSelectedIndex = viewModel.selectedIndex {
                        proxy.scrollTo(lastSelectedIndex, anchor: .top)
                    }
                }
            }
        }
    }

    private func searchResultCard(locator: Locator, index: Int) -> some View {
        let text = locator.text.sanitized()
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            viewModel.selectSearchResultCell(locator: locator, index: index)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if let title = locator.title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.accentBlue)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    if let progression = locator.locations.totalProgression {
                        Text("\(Int((min(max(progression, 0), 1) * 100).rounded()))%")
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(AppColors.tertiaryText)
                    }
                }

                highlightedExcerpt(text)
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.primaryText)
                    .lineSpacing(3)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func highlightedExcerpt(_ text: Locator.Text) -> Text {
        let before = text.before ?? ""
        let highlight = text.highlight ?? ""
        let after = text.after ?? ""

        var attributed = AttributedString(before)
        var matchAttr = AttributedString(highlight)
        matchAttr.foregroundColor = AppColors.accentBlue
        matchAttr.font = .system(size: 14, weight: .bold)
        matchAttr.backgroundColor = AppColors.accentBlue.opacity(0.14)
        attributed.append(matchAttr)
        attributed.append(AttributedString(after))

        return Text(attributed)
    }

    private func emptyState(icon: String, title: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
