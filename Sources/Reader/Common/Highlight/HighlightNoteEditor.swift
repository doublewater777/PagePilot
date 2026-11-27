//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import SwiftUI
import UIKit

struct HighlightNoteEditor: View {
    let highlightID: Highlight.Id
    let quotedText: String
    let initialNote: String
    let initialColor: HighlightColor
    let onColorChange: ((HighlightColor) -> Void)?
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @State private var selectedColor: HighlightColor
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    init(
        highlightID: Highlight.Id,
        quotedText: String,
        initialNote: String = "",
        initialColor: HighlightColor = .yellow,
        onColorChange: ((HighlightColor) -> Void)? = nil,
        onSave: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.highlightID = highlightID
        self.quotedText = quotedText
        self.initialNote = initialNote
        self.initialColor = initialColor
        self.onColorChange = onColorChange
        self.onSave = onSave
        self.onCancel = onCancel
        _text = State(initialValue: initialNote)
        _selectedColor = State(initialValue: initialColor)
    }

    private var canSave: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if initialNote.isEmpty {
            return !trimmed.isEmpty
        }
        return true
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if !quotedText.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(selectedColor.swiftUIColor)
                            .frame(width: 4)

                        Text(quotedText)
                            .font(.system(size: 14, weight: .regular, design: .serif))
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                            .lineLimit(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(14)
                    .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05), lineWidth: 1)
                    )
                }

                if onColorChange != nil {
                    HStack(spacing: 14) {
                        ForEach([HighlightColor.yellow, .green, .blue, .red], id: \.self) { color in
                            let isSelected = selectedColor == color
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                selectedColor = color
                                onColorChange?(color)
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(color.swiftUIColor)
                                        .frame(width: 26, height: 26)
                                    if isSelected {
                                        Circle()
                                            .stroke(AppColors.primaryText, lineWidth: 2)
                                            .frame(width: 32, height: 32)
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                }

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppColors.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05), lineWidth: 1)
                        )

                    if text.isEmpty {
                        Text(NSLocalizedString("reader_highlight_note_placeholder", comment: ""))
                            .font(.system(size: 16))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $text)
                        .focused($isFocused)
                        .font(.system(size: 16))
                        .lineSpacing(4)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .scrollContentBackground(.hidden)
                }
                .frame(maxHeight: .infinity)
            }
            .padding(16)
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("highlight_note_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SheetCloseButton(
                        accessibilityLabel: NSLocalizedString("cancel_button", comment: ""),
                        action: onCancel
                    )
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("save_button", comment: "")) {
                        onSave(text)
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .onAppear {
                isFocused = true
            }
        }
    }
}
