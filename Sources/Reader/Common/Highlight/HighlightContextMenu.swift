//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import SwiftUI

struct HighlightContextMenu: View {
    let colors: [HighlightColor]
    let systemFontSize: CGFloat
    var showsDeleteButton: Bool = true

    private let colorSubject = PassthroughSubject<HighlightColor, Never>()
    var selectedColorPublisher: AnyPublisher<HighlightColor, Never> {
        colorSubject.eraseToAnyPublisher()
    }

    private let deleteSubject = PassthroughSubject<Void, Never>()
    var selectedDeletePublisher: AnyPublisher<Void, Never> {
        deleteSubject.eraseToAnyPublisher()
    }

    var body: some View {
        HStack {
            ForEach(colors, id: \.self) { color in
                Button {
                    colorSubject.send(color)
                } label: {
                    Text(emoji(for: color))
                        .font(.system(size: systemFontSize))
                }

                if color != colors.last || showsDeleteButton {
                    Divider()
                }
            }

            if showsDeleteButton {
                Button {
                    deleteSubject.send()
                } label: {
                    Image(systemName: "xmark.bin")
                        .font(.system(size: systemFontSize))
                }
            }
        }
        .fixedSize()
    }

    var preferredSize: CGSize {
        let itemSide = itemSideSize
        let itemsCount = colors.count + (showsDeleteButton ? 1 : 0)
        return CGSize(width: itemSide * CGFloat(itemsCount), height: itemSide)
    }

    // MARK: - Private

    private func emoji(for color: HighlightColor) -> String {
        switch color {
        case .red:
            return "🔴"
        case .green:
            return "🟢"
        case .blue:
            return "🔵"
        case .yellow:
            return "🟡"
        }
    }

    private var itemSideSize: CGFloat {
        let font = UIFont.systemFont(ofSize: systemFontSize)
        let fontAttributes = [NSAttributedString.Key.font: font]
        let size = ("🔴" as NSString).size(withAttributes: fontAttributes)
        return max(size.width, size.height) * 1.6
    }
}
