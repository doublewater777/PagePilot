//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import SwiftUI

struct BookmarkCellView: View {
    static var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }

    let bookmark: Bookmark
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(AppColors.accentBlue.opacity(colorScheme == .dark ? 0.2 : 0.1))
                    .frame(width: 34, height: 34)
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.accentBlue)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(bookmarkTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.primaryText)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(BookmarkCellView.dateFormatter.string(from: bookmark.created))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppColors.tertiaryText)
                }

                if let position = bookmark.positionText {
                    Text(position)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.accentTeal)
                }

                if let excerpt = bookmarkExcerpt {
                    Text(excerpt)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(2)
                        .lineSpacing(2)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var bookmarkTitle: String {
        if let title = bookmark.locator.title, !title.isEmpty {
            return title
        }
        return bookmark.positionText ?? NSLocalizedString("my_notes_bookmark_label", comment: "")
    }

    private var bookmarkExcerpt: String? {
        let text = bookmark.locator.text.sanitized()
        let parts = [text.before, text.highlight, text.after]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " ")
    }
}

extension Bookmark {
    var positionText: String? {
        if let position = locator.locations.position {
            return String(format: NSLocalizedString("reader_outline_position_label", comment: "Outline bookmark label when the position is available"), position)
        } else if let progression = locator.locations.progression {
            return String(format: NSLocalizedString("reader_outline_progression_label", comment: "Outline bookmark label when the progression is available"), progression * 100)
        } else {
            return nil
        }
    }
}
