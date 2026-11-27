//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import ReadiumShared
import SwiftUI
import UIKit

struct PublicationMetadataView: View {
    let publication: Publication
    var book: Book? = nil
    var onOpen: (() -> Void)? = nil

    @State private var coverImage: UIImage?
    @State private var showFullDescription = false
    @State private var showAccessibility = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var titleText: String {
        publication.metadata.title ?? NSLocalizedString("metadata_no_title", comment: "")
    }

    private var authorsText: String? {
        let joined = publication.metadata.authors.map(\.name).joined(separator: ", ")
        return joined.isEmpty ? nil : joined
    }

    private var publishersText: String? {
        let joined = publication.metadata.publishers.map(\.name).joined(separator: ", ")
        return joined.isEmpty ? nil : joined
    }

    private var cleanDescription: String? {
        guard let raw = publication.metadata.description else { return nil }
        let stripped = raw
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped
    }

    private var formatLabel: String {
        if let book {
            let media = book.mediaType
            if media.matches(.epub) { return "EPUB" }
            if media.matches(.pdf) { return "PDF" }
            if media.matches(.cbz) { return "CBZ" }
            return media.string.uppercased()
        }
        return publication.metadata.layout == .fixed ? "Fixed Layout" : "EPUB"
    }

    private var languagesText: String? {
        let names = publication.metadata.languages.compactMap { code -> String? in
            Locale.current.localizedString(forIdentifier: code) ?? code
        }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 18) {
                heroHeader

                if let cleanDescription {
                    descriptionCard(cleanDescription)
                }

                detailsCard

                accessibilityCard
            }
            .frame(maxWidth: horizontalSizeClass == .regular ? 560 : .infinity)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle(NSLocalizedString("library_context_details", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let cover = try? await publication.cover().get() {
                coverImage = cover
            }
        }
    }

    private var heroHeader: some View {
        VStack(spacing: 16) {
            // Editorial hardcover display with ambient blur glow
            ZStack {
                if let coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 220, height: 180)
                        .blur(radius: 42)
                        .opacity(colorScheme == .dark ? 0.32 : 0.22)
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 40)
                        .fill(Color(uiColor: GeneratedBookCover.palette(for: titleText).top))
                        .frame(width: 200, height: 150)
                        .blur(radius: 46)
                        .opacity(colorScheme == .dark ? 0.35 : 0.2)
                }

                Group {
                    if let coverImage {
                        Image(uiImage: coverImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        GeneratedBookCoverView(title: titleText, author: authorsText)
                    }
                }
                .frame(width: 132, height: 194)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.18), radius: 18, y: 10)
            }
            .padding(.top, 8)

            VStack(spacing: 6) {
                Text(titleText)
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundStyle(AppColors.primaryText)
                    .multilineTextAlignment(.center)

                if let authorsText {
                    Text(authorsText)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppColors.secondaryText)
                        .multilineTextAlignment(.center)
                }
            }

            if let book {
                let progression = min(max(book.progression, 0), 1)
                if progression > 0 {
                    VStack(spacing: 6) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(AppColors.progressTrack)
                                Capsule()
                                    .fill(AppColors.horizontalGradient)
                                    .frame(width: max(6, geo.size.width * progression))
                            }
                        }
                        .frame(height: 6)
                        .frame(maxWidth: 220)

                        Text("\(Int((progression * 100).rounded()))%")
                            .font(.system(size: 12, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(AppColors.accentBlue)
                    }
                }
            }

            if let onOpen {
                let hasStarted = (book?.progression ?? 0) > 0
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onOpen()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "book.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text(NSLocalizedString(hasStarted ? "library_context_continue" : "library_context_open", comment: ""))
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: 260)
                    .padding(.vertical, 13)
                    .background(AppColors.horizontalGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: AppColors.accentBlue.opacity(0.24), radius: 12, y: 5)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private func descriptionCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("metadata_about_book", comment: ""))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppColors.secondaryText)

            Text(text)
                .font(.system(size: 14.5))
                .foregroundStyle(AppColors.primaryText)
                .lineSpacing(4)
                .lineLimit(showFullDescription ? nil : 5)
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showFullDescription.toggle()
                    }
                }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("metadata_details_section", comment: ""))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppColors.secondaryText)

            detailRow(label: NSLocalizedString("metadata_format", comment: ""), value: formatLabel)

            if let publishersText {
                Divider()
                detailRow(label: NSLocalizedString("metadata_publisher", comment: ""), value: publishersText)
            }

            if let published = publication.metadata.published {
                Divider()
                detailRow(
                    label: NSLocalizedString("metadata_publication_date", comment: ""),
                    value: published.formatted(date: .long, time: .omitted)
                )
            }

            if let languagesText {
                Divider()
                detailRow(label: NSLocalizedString("prefs_language", comment: ""), value: languagesText)
            }

            if let id = publication.metadata.identifier, !id.isEmpty {
                Divider()
                detailRow(label: NSLocalizedString("metadata_identifier", comment: ""), value: id)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(AppColors.secondaryText)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(AppColors.primaryText)
                .multilineTextAlignment(.trailing)
        }
    }

    private var accessibilityCard: some View {
        let guide = AccessibilityMetadataDisplayGuide(publication: publication)
        return DisclosureGroup(isExpanded: $showAccessibility) {
            VStack(alignment: .leading, spacing: 10) {
                Divider().padding(.top, 4)
                ForEach(guide.fields, id: \.id) { field in
                    if !field.statements.isEmpty && field.shouldDisplay {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(field.localizedTitle)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppColors.primaryText)
                            ForEach(field.statements) { statement in
                                let attributed = AttributedString(statement.localizedString(descriptive: false))
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("•")
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(AppColors.tertiaryText)
                                    Text(attributed)
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(AppColors.secondaryText)
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            Text(NSLocalizedString("metadata_accessibility_section", comment: ""))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.primaryText)
        }
        .tint(AppColors.secondaryText)
        .padding(16)
        .cardStyle()
    }
}
