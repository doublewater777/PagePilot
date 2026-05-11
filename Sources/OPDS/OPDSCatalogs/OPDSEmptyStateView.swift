//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import SwiftUI

/// Shown when the user has no OPDS catalogs configured.
///
/// PagePilot does not bundle any content source itself. Instead, this view
/// helps the user search the open web for OPDS feeds they want to add, by
/// linking to common search engines with a pre-filled query.
struct OPDSEmptyStateView: View {
    var onAddCatalog: () -> Void

    @State private var query: String = NSLocalizedString(
        "opds_empty_default_query",
        comment: "Default search query prefilled in the search box"
    )

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                whatIsOPDSSection
                searchSection
                howToAddSection
                addButton
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)

            Text(NSLocalizedString("opds_empty_title", comment: ""))
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text(NSLocalizedString("opds_empty_subtitle", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var whatIsOPDSSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                NSLocalizedString("opds_empty_what_title", comment: ""),
                systemImage: "info.circle"
            )
            .font(.headline)

            Text(NSLocalizedString("opds_empty_what_body", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                NSLocalizedString("opds_empty_search_title", comment: ""),
                systemImage: "magnifyingglass"
            )
            .font(.headline)

            Text(NSLocalizedString("opds_empty_search_body", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField(
                NSLocalizedString("opds_empty_search_placeholder", comment: ""),
                text: $query
            )
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

            VStack(spacing: 8) {
                ForEach(SearchEngine.all) { engine in
                    searchEngineRow(engine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func searchEngineRow(_ engine: SearchEngine) -> some View {
        Button {
            openSearch(on: engine)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: engine.symbolName)
                    .font(.body)
                    .frame(width: 24)
                    .foregroundStyle(.tint)

                Text(engine.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "arrow.up.right.square")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var howToAddSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                NSLocalizedString("opds_empty_how_title", comment: ""),
                systemImage: "plus.circle"
            )
            .font(.headline)

            Text(NSLocalizedString("opds_empty_how_body", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var addButton: some View {
        Button(action: onAddCatalog) {
            Label(
                NSLocalizedString("opds_empty_add_button", comment: ""),
                systemImage: "plus.circle.fill"
            )
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
    }

    // MARK: - Actions

    private func openSearch(on engine: SearchEngine) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveQuery = trimmed.isEmpty
            ? NSLocalizedString("opds_empty_default_query", comment: "")
            : trimmed
        guard let url = engine.searchURL(for: effectiveQuery) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Search engines

private struct SearchEngine: Identifiable {
    let id: String
    let displayName: String
    let symbolName: String
    private let urlBuilder: (String) -> URL?

    func searchURL(for query: String) -> URL? {
        urlBuilder(query)
    }

    static let all: [SearchEngine] = [
        SearchEngine(
            id: "baidu",
            displayName: NSLocalizedString("search_engine_baidu", comment: ""),
            symbolName: "magnifyingglass.circle"
        ) { query in
            Self.url(base: "https://www.baidu.com/s", param: "wd", query: query)
        },
        SearchEngine(
            id: "bing",
            displayName: NSLocalizedString("search_engine_bing", comment: ""),
            symbolName: "globe"
        ) { query in
            Self.url(base: "https://www.bing.com/search", param: "q", query: query)
        },
        SearchEngine(
            id: "google",
            displayName: NSLocalizedString("search_engine_google", comment: ""),
            symbolName: "g.circle"
        ) { query in
            Self.url(base: "https://www.google.com/search", param: "q", query: query)
        },
        SearchEngine(
            id: "so360",
            displayName: NSLocalizedString("search_engine_360", comment: ""),
            symbolName: "scope"
        ) { query in
            Self.url(base: "https://www.so.com/s", param: "q", query: query)
        },
        SearchEngine(
            id: "sogou",
            displayName: NSLocalizedString("search_engine_sogou", comment: ""),
            symbolName: "text.magnifyingglass"
        ) { query in
            Self.url(base: "https://www.sogou.com/web", param: "query", query: query)
        },
        SearchEngine(
            id: "shenma",
            displayName: NSLocalizedString("search_engine_shenma", comment: ""),
            symbolName: "sparkle.magnifyingglass"
        ) { query in
            Self.url(base: "https://m.sm.cn/s", param: "q", query: query)
        },
    ]

    private static func url(base: String, param: String, query: String) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = [URLQueryItem(name: param, value: query)]
        return components?.url
    }
}

#Preview {
    OPDSEmptyStateView(onAddCatalog: {})
}
