import UIKit

extension LibraryViewController {
    private enum BookCardMetrics {
        // PublicationCollectionViewCell wraps the cover with 12 pt leading/
        // trailing insets and 12/8 pt vertical insets.
        static let coverHorizontalInset: CGFloat = 24
        static let coverVerticalInset: CGFloat = 20

        // Keep the cover close to the original XIB's 150 x 220 book shape.
        static let coverAspectRatio: CGFloat = 220.0 / 150.0

        // Keep grid cards near a comfortable book-cover width while allowing
        // the column count to adapt to iPad Split View and Stage Manager.
        static let preferredGridCardWidth: CGFloat = 176
        static let minimumGridColumns = 2
        static let maximumGridColumns = 8

        // The metadata stack can contain a two-line title, author and reading
        // status. 56 pt was too short once the status row was added.
        static let metadataHeight: CGFloat = 64
        static let rootStackSpacing: CGFloat = 5
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        guard let flowLayout = collectionViewLayout as? UICollectionViewFlowLayout else {
            return .zero
        }

        // Preserve the existing compact list row exactly as configured by
        // LibraryViewController.
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
        let proposedColumns = Int(
            ((contentWidth + spacing) / (BookCardMetrics.preferredGridCardWidth + spacing)).rounded()
        )
        let columnCount = min(
            max(proposedColumns, BookCardMetrics.minimumGridColumns),
            BookCardMetrics.maximumGridColumns
        )
        let totalSpacing = CGFloat(columnCount - 1) * spacing
        let width = floor(max(0, contentWidth - totalSpacing) / CGFloat(columnCount))
        let coverWidth = max(0, width - BookCardMetrics.coverHorizontalInset)
        let coverHeight = coverWidth * BookCardMetrics.coverAspectRatio
        let height = ceil(
            coverHeight
                + BookCardMetrics.coverVerticalInset
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

        // A book cover contains important text/art near its edges. Showing the
        // whole image is preferable to cropping it to fit the card.
        bookCell.coverImageView.contentMode = .scaleAspectFit

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
