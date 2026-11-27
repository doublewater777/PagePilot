//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import SwiftUI
import UIKit

/// Refined floating popover bar for picking highlight colors and editing/removing an existing highlight.
struct HighlightContextMenu: View {
    let colors: [HighlightColor]
    var selectedColor: HighlightColor? = nil
    var hasNote: Bool = false
    var showsNoteButton: Bool = false
    var showsCopyButton: Bool = false
    var showsPostcardButton: Bool = false
    var showsIntelligenceButton: Bool = false
    var showsDeleteButton: Bool = true

    private let colorSubject = PassthroughSubject<HighlightColor, Never>()
    var selectedColorPublisher: AnyPublisher<HighlightColor, Never> {
        colorSubject.eraseToAnyPublisher()
    }

    private let noteSubject = PassthroughSubject<Void, Never>()
    var selectedNotePublisher: AnyPublisher<Void, Never> {
        noteSubject.eraseToAnyPublisher()
    }

    private let copySubject = PassthroughSubject<Void, Never>()
    var selectedCopyPublisher: AnyPublisher<Void, Never> {
        copySubject.eraseToAnyPublisher()
    }

    private let postcardSubject = PassthroughSubject<Void, Never>()
    var selectedPostcardPublisher: AnyPublisher<Void, Never> {
        postcardSubject.eraseToAnyPublisher()
    }

    private let intelligenceSubject = PassthroughSubject<Void, Never>()
    var selectedIntelligencePublisher: AnyPublisher<Void, Never> {
        intelligenceSubject.eraseToAnyPublisher()
    }

    private let deleteSubject = PassthroughSubject<Void, Never>()
    var selectedDeletePublisher: AnyPublisher<Void, Never> {
        deleteSubject.eraseToAnyPublisher()
    }

    init(
        colors: [HighlightColor],
        systemFontSize: CGFloat = 20,
        selectedColor: HighlightColor? = nil,
        hasNote: Bool = false,
        showsNoteButton: Bool = false,
        showsCopyButton: Bool = false,
        showsPostcardButton: Bool = false,
        showsIntelligenceButton: Bool = false,
        showsDeleteButton: Bool = true
    ) {
        self.colors = colors
        self.selectedColor = selectedColor
        self.hasNote = hasNote
        self.showsNoteButton = showsNoteButton
        self.showsCopyButton = showsCopyButton
        self.showsPostcardButton = showsPostcardButton
        self.showsIntelligenceButton = showsIntelligenceButton
        self.showsDeleteButton = showsDeleteButton
    }

    private var actionCount: Int {
        (showsNoteButton ? 1 : 0)
            + (showsCopyButton ? 1 : 0)
            + (showsPostcardButton ? 1 : 0)
            + (showsIntelligenceButton ? 1 : 0)
            + (showsDeleteButton ? 1 : 0)
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(colors, id: \.self) { color in
                    let isSelected = selectedColor == color
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        colorSubject.send(color)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(color.swiftUIColor)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle()
                                        .stroke(Color.black.opacity(0.12), lineWidth: 0.8)
                                )
                                .shadow(color: color.swiftUIColor.opacity(0.35), radius: 3, y: 1)

                            if isSelected {
                                Circle()
                                    .stroke(Color.primary.opacity(0.85), lineWidth: 2)
                                    .frame(width: 34, height: 34)

                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(color.accessibilityName)
                }
            }

            if actionCount > 0 {
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 1, height: 22)

                HStack(spacing: 6) {
                    if showsNoteButton {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            noteSubject.send()
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: hasNote ? "note.text" : "square.and.pencil")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(hasNote ? AppColors.accentBlue : .primary)
                                    .frame(width: 34, height: 34)
                                    .background(
                                        hasNote
                                            ? AppColors.accentBlue.opacity(0.12)
                                            : Color.primary.opacity(0.05),
                                        in: Circle()
                                    )

                                if hasNote {
                                    Circle()
                                        .fill(AppColors.accentBlue)
                                        .frame(width: 7, height: 7)
                                        .offset(x: -2, y: 2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(NSLocalizedString("reader_highlight_edit_note", comment: ""))
                    }

                    if showsCopyButton {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            copySubject.send()
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.primary)
                                .frame(width: 34, height: 34)
                                .background(Color.primary.opacity(0.05), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(NSLocalizedString("reader_copy", comment: ""))
                    }

                    if showsPostcardButton {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            postcardSubject.send()
                        } label: {
                            Image(systemName: "sparkles")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppColors.accentBlue)
                                .frame(width: 34, height: 34)
                                .background(AppColors.accentBlue.opacity(0.12), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(NSLocalizedString("quote_postcard_title", comment: ""))
                    }

                    if showsIntelligenceButton {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            intelligenceSubject.send()
                        } label: {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppColors.accentTeal)
                                .frame(width: 34, height: 34)
                                .background(AppColors.accentTeal.opacity(0.13), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(NSLocalizedString("ai_explain_title", comment: ""))
                    }

                    if showsDeleteButton {
                        Button(role: .destructive) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            deleteSubject.send()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.red)
                                .frame(width: 34, height: 34)
                                .background(Color.red.opacity(0.1), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(NSLocalizedString("delete_button", comment: ""))
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .fixedSize()
    }

    var preferredSize: CGSize {
        let colorWidth = CGFloat(colors.count) * 34 + CGFloat(max(0, colors.count - 1)) * 10
        let actionsWidth = actionCount > 0
            ? 21 + CGFloat(actionCount) * 34 + CGFloat(max(0, actionCount - 1)) * 6
            : 0
        return CGSize(width: colorWidth + actionsWidth + 28, height: 54)
    }
}
