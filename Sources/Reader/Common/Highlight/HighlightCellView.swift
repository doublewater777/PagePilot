//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import SwiftUI
import UIKit

struct HighlightCellView: View {
    let highlight: Highlight

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(highlight.color.swiftUIColor)
                .frame(width: 4)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(highlight.locator.text.sanitized().highlight ?? "")
                    .font(.system(size: 14.5))
                    .foregroundStyle(AppColors.primaryText)
                    .lineSpacing(3)
                    .lineLimit(5)
                    .multilineTextAlignment(.leading)

                if let note = highlight.note, !note.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "note.text")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppColors.accentBlue)
                            .padding(.top, 2)
                        Text(note)
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.secondaryText)
                            .lineSpacing(2)
                            .lineLimit(3)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(highlight.color.swiftUIColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }

                HStack(spacing: 6) {
                    if let title = highlight.locator.title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(AppColors.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Text(Self.dateFormatter.string(from: highlight.created))
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.tertiaryText)
                }
            }
        }
        .padding(.vertical, 8)
    }
}
