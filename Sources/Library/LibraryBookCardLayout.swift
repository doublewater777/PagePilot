//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import UIKit

extension LibraryViewController {
    private enum BookCardMetrics {
        // Editorial 2:3 hardcover aspect ratio.
        static let coverAspectRatio: CGFloat = 1.46

        // Compact enough for 3 elegant covers per row on iPhone and 4-7 columns
        // across iPad Split View, Stage Manager, and Mac Catalyst windows.
        static let preferredCompactCardWidth: CGFloat = 114
        static let preferredRegularCardWidth: CGFloat = 148
        static let minimumGridColumns = 2
        #if targetEnvironment(macCatalyst)
        static let maximumGridColumns = 10
        #else
        static let maximumGridColumns = 7
        #endif

        static let metadataHeight: CGFloat = 66
        static let rootStackSpacing: CGFloat = 8
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        guard let flowLayout = collectionViewLayout as? UICollectionViewFlowLayout else {
            return .zero
        }

        guard currentViewMode == .grid else {
            return flowLayout.itemSize
        }

        let contentWidth = max(
            0,
            collectionView.bounds.width
                - collectionView.adjustedContentInset.left
                - collectionView.adjustedContentInset.right
        )
        let spacing = flowLayout.minimumInteritemSpacing
        let preferredWidth = contentWidth >= 600
            ? BookCardMetrics.preferredRegularCardWidth
            : BookCardMetrics.preferredCompactCardWidth
        let proposedColumns = Int(
            ((contentWidth + spacing) / (preferredWidth + spacing)).rounded()
        )
        let minColumns = contentWidth >= 340 ? 3 : BookCardMetrics.minimumGridColumns
        let columnCount = min(
            max(proposedColumns, minColumns),
            BookCardMetrics.maximumGridColumns
        )
        let totalSpacing = CGFloat(columnCount - 1) * spacing
        let width = floor(max(0, contentWidth - totalSpacing) / CGFloat(columnCount))
        let coverHeight = width * BookCardMetrics.coverAspectRatio
        let height = ceil(
            coverHeight
                + BookCardMetrics.rootStackSpacing
                + BookCardMetrics.metadataHeight
        )

        return CGSize(width: width, height: height)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        guard let bookCell = cell as? PublicationCollectionViewCell else {
            return
        }

        bookCell.coverImageView.contentMode = .scaleAspectFill

        guard currentViewMode == .grid,
              let textContainer = bookCell.textContainerView,
              let heightConstraint = textContainer.constraints.first(where: {
                  ($0.firstItem as? UIView) === textContainer
                      && $0.firstAttribute == .height
              })
        else {
            return
        }

        heightConstraint.constant = BookCardMetrics.metadataHeight
    }
}
