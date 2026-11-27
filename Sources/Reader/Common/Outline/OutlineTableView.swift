//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import ReadiumShared
import SwiftUI
import UIKit

typealias OutlineTableViewAdapter = (UIHostingController<OutlineTableView>, AnyPublisher<Locator, Never>)

protocol OutlineTableViewControllerFactory {
    func make(
        publication: Publication,
        bookId: Book.Id,
        bookmarks: BookmarkRepository,
        highlights: HighlightRepository,
        currentLocator: Locator?
    ) -> OutlineTableViewAdapter
}

enum OutlineSection: Int, CaseIterable, Identifiable {
    case tableOfContents = 0
    case bookmarks
    case highlights
    case pageList
    case landmarks

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .tableOfContents: return OutlineTableViewConstants.tabContents
        case .bookmarks: return OutlineTableViewConstants.tabBookmarks
        case .highlights: return OutlineTableViewConstants.tabHighlights
        case .pageList: return OutlineTableViewConstants.tabPagelist
        case .landmarks: return OutlineTableViewConstants.tabLandmarks
        }
    }
}

struct OutlineTableView: View {
    private let publication: Publication
    private let currentLocator: Locator?
    @ObservedObject private var bookmarksModel: BookmarksViewModel
    @ObservedObject private var highlightsModel: HighlightsViewModel
    @State private var selectedSection: OutlineSection = .tableOfContents
    @State private var outlines: [OutlineSection: [(level: Int, link: ReadiumShared.Link)]] = [:]
    @State private var coverImage: UIImage?
    @State private var didAutoScrollToCurrent = false
    @Environment(\.colorScheme) private var colorScheme

    init(
        publication: Publication,
        bookId: Book.Id,
        bookmarkRepository: BookmarkRepository,
        highlightRepository: HighlightRepository,
        currentLocator: Locator? = nil
    ) {
        self.publication = publication
        self.currentLocator = currentLocator
        bookmarksModel = BookmarksViewModel(bookId: bookId, repository: bookmarkRepository)
        highlightsModel = HighlightsViewModel(bookId: bookId, repository: highlightRepository)

        outlines = [
            .tableOfContents: [],
            .landmarks: flatten(publication.landmarks),
            .pageList: flatten(publication.pageList),
        ]
    }

    private var visibleSections: [OutlineSection] {
        var sections: [OutlineSection] = [.tableOfContents, .bookmarks, .highlights]
        if !(outlines[.pageList]?.isEmpty ?? true) {
            sections.append(.pageList)
        }
        if !(outlines[.landmarks]?.isEmpty ?? true) {
            sections.append(.landmarks)
        }
        return sections
    }

    private var bookTitle: String {
        publication.metadata.title ?? NSLocalizedString("metadata_no_title", comment: "")
    }

    private var bookAuthors: String? {
        let joined = publication.metadata.authors.map(\.name).joined(separator: ", ")
        return joined.isEmpty ? nil : joined
    }

    private var currentProgression: Double? {
        currentLocator?.locations.totalProgression
    }

    private func loadTableOfContents() async {
        if let toc = try? await publication.tableOfContents().get() {
            outlines[.tableOfContents] = flatten(!toc.isEmpty ? toc : publication.readingOrder)
        }
        if coverImage == nil, let cover = try? await publication.cover().get() {
            coverImage = cover
        }
    }

    private func normalizedHref(_ raw: String) -> String {
        raw.split(separator: "#", maxSplits: 1).first.map(String.init) ?? raw
    }

    private func activeTOCIndex(in items: [(level: Int, link: ReadiumShared.Link)]) -> Int? {
        guard let currentHref = currentLocator?.href.string else { return nil }
        let normalizedCurrent = normalizedHref(currentHref)
        // Prefer exact match (with fragment), then fallback to matching resource path.
        if let exact = items.firstIndex(where: { $0.link.href == currentHref }) {
            return exact
        }
        return items.lastIndex(where: { normalizedHref($0.link.href) == normalizedCurrent })
    }

    var body: some View {
        VStack(spacing: 0) {
            bookHeader
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)

            Picker("", selection: $selectedSection) {
                ForEach(visibleSections) { section in
                    Text(tabLabel(for: section)).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            contentSection
        }
        .background(AppColors.background.ignoresSafeArea())
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            bookmarksModel.loadIfNeeded()
            highlightsModel.loadIfNeeded()
            Task {
                await loadTableOfContents()
            }
        }
    }

    private func tabLabel(for section: OutlineSection) -> String {
        switch section {
        case .bookmarks where !bookmarksModel.bookmarks.isEmpty:
            return "\(section.title) (\(bookmarksModel.bookmarks.count))"
        case .highlights where !highlightsModel.highlights.isEmpty:
            return "\(section.title) (\(highlightsModel.highlights.count))"
        default:
            return section.title
        }
    }

    private var bookHeader: some View {
        HStack(spacing: 14) {
            Group {
                if let coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    GeneratedBookCoverView(title: bookTitle, author: bookAuthors)
                }
            }
            .frame(width: 46, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.12), radius: 5, y: 2)

            VStack(alignment: .leading, spacing: 5) {
                Text(bookTitle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppColors.primaryText)
                    .lineLimit(2)

                if let bookAuthors {
                    Text(bookAuthors)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(1)
                }

                if let currentProgression {
                    let clamped = min(max(currentProgression, 0), 1)
                    HStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(AppColors.progressTrack)
                                Capsule()
                                    .fill(AppColors.horizontalGradient)
                                    .frame(width: max(4, geo.size.width * clamped))
                            }
                        }
                        .frame(height: 4)

                        Text("\(Int((clamped * 100).rounded()))%")
                            .font(.system(size: 11.5, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(AppColors.accentBlue)
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var contentSection: some View {
        switch selectedSection {
        case .tableOfContents, .pageList, .landmarks:
            let items = outlines[selectedSection] ?? []
            if items.isEmpty {
                emptyState(
                    icon: "list.bullet.rectangle",
                    title: NSLocalizedString("reader_outline_empty_toc", comment: ""),
                    hint: nil
                )
            } else {
                let activeIndex = selectedSection == .tableOfContents ? activeTOCIndex(in: items) : nil
                ScrollViewReader { proxy in
                    List {
                        ForEach(items.indices, id: \.self) { index in
                            let item = items[index]
                            let isCurrent = activeIndex == index
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                Task {
                                    if let locator = await publication.locate(item.link) {
                                        locatorSubject.send(locator)
                                    }
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    if isCurrent {
                                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                                            .fill(AppColors.accentBlue)
                                            .frame(width: 3, height: 18)
                                    }

                                    Text(item.link.title ?? item.link.href)
                                        .font(.system(
                                            size: item.level == 0 ? 15 : 14,
                                            weight: isCurrent ? .semibold : (item.level == 0 ? .medium : .regular)
                                        ))
                                        .foregroundStyle(
                                            isCurrent
                                                ? AppColors.accentBlue
                                                : (item.level == 0 ? AppColors.primaryText : AppColors.secondaryText)
                                        )
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    if isCurrent {
                                        Circle()
                                            .fill(AppColors.accentBlue)
                                            .frame(width: 6, height: 6)
                                    }
                                }
                                .padding(.leading, CGFloat(min(item.level, 4)) * 16)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(
                                isCurrent
                                    ? AppColors.accentBlue.opacity(colorScheme == .dark ? 0.14 : 0.08)
                                    : AppColors.cardBackground
                            )
                            .id(index)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .onAppear {
                        if !didAutoScrollToCurrent, let activeIndex {
                            didAutoScrollToCurrent = true
                            DispatchQueue.main.async {
                                proxy.scrollTo(activeIndex, anchor: .center)
                            }
                        }
                    }
                    .onChange(of: items.count) { _, _ in
                        if !didAutoScrollToCurrent, let activeIndex = activeTOCIndex(in: items) {
                            didAutoScrollToCurrent = true
                            DispatchQueue.main.async {
                                proxy.scrollTo(activeIndex, anchor: .center)
                            }
                        }
                    }
                }
            }

        case .bookmarks:
            if bookmarksModel.bookmarks.isEmpty {
                emptyState(
                    icon: "bookmark",
                    title: NSLocalizedString("reader_outline_empty_bookmarks", comment: ""),
                    hint: NSLocalizedString("reader_outline_empty_bookmarks_hint", comment: "")
                )
            } else {
                List {
                    ForEach(bookmarksModel.bookmarks, id: \.self) { bookmark in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            locatorSubject.send(bookmark.locator)
                        } label: {
                            BookmarkCellView(bookmark: bookmark)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(AppColors.cardBackground)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                bookmarksModel.delete(bookmark)
                            } label: {
                                Label(NSLocalizedString("delete_button", comment: ""), systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }

        case .highlights:
            if highlightsModel.highlights.isEmpty {
                emptyState(
                    icon: "highlighter",
                    title: NSLocalizedString("reader_outline_empty_highlights", comment: ""),
                    hint: NSLocalizedString("reader_outline_empty_highlights_hint", comment: "")
                )
            } else {
                List {
                    ForEach(highlightsModel.highlights, id: \.self) { highlight in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            locatorSubject.send(highlight.locator)
                        } label: {
                            HighlightCellView(highlight: highlight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(AppColors.cardBackground)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                highlightsModel.delete(highlight)
                            } label: {
                                Label(NSLocalizedString("delete_button", comment: ""), systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func emptyState(icon: String, title: String, hint: String?) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppColors.accentBlue.opacity(colorScheme == .dark ? 0.16 : 0.08))
                    .frame(width: 58, height: 58)
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(AppColors.accentBlue)
            }

            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.primaryText)

            if let hint {
                Text(hint)
                    .font(.system(size: 13.5))
                    .foregroundStyle(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private let locatorSubject = PassthroughSubject<Locator, Never>()
    var goToLocatorPublisher: AnyPublisher<Locator, Never> {
        locatorSubject.eraseToAnyPublisher()
    }
}

enum OutlineTableViewConstants {
    static let tabContents = NSLocalizedString("reader_outline_tab_contents", comment: "Outline contents tab name")
    static let tabBookmarks = NSLocalizedString("reader_outline_tab_bookmarks", comment: "Outline bookmarks tab name")
    static let tabPagelist = NSLocalizedString("reader_outline_tab_pagelist", comment: "Outline pagelist tab name")
    static let tabLandmarks = NSLocalizedString("reader_outline_tab_landmarks", comment: "Outline landmarks tab name")
    static let tabHighlights = NSLocalizedString("reader_outline_tab_highlights", comment: "Outline highlights tab name")
}

private func flatten(_ links: [ReadiumShared.Link], level: Int = 0) -> [(level: Int, link: ReadiumShared.Link)] {
    links.flatMap { [(level, $0)] + flatten($0.children, level: level + 1) }
}
