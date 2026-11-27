//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import UIKit

protocol PublicationCollectionViewCellDelegate: AnyObject {
    var lastFlippedCell: PublicationCollectionViewCell? { get set }

    func presentMetadata(forCellAt indexPath: IndexPath)
    func removePublicationFromLibrary(forCellAt indexPath: IndexPath)
    func cellFlipped(_ cell: PublicationCollectionViewCell)
}

class PublicationCollectionViewCell: UICollectionViewCell {
    @IBOutlet var coverImageView: UIImageView!
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var authorLabel: UILabel!
    @IBOutlet var textContainerView: UIView!

    weak var delegate: PublicationCollectionViewCellDelegate?

    var publicationMenuViewController = PublicationMenuViewController()
    var isMenuDisplayed = false

    // Multi-select editing states
    var isEditingMode: Bool = false {
        didSet {
            updateSelectionAppearance()
        }
    }

    var isSelectedForEditing: Bool = false {
        didSet {
            updateSelectionAppearance()
        }
    }

    private var currentMode: LibraryViewController.ViewMode = .grid

    // Editorial hardcover containers & overlays
    private let coverShadowContainer = UIView()
    private let coverClipContainer = UIView()
    private let spineOverlayView = UIView()
    private let spineGradientLayer = CAGradientLayer()
    private let coverProgressTrack = UIView()
    private let coverProgressFill = UIView()
    private var coverProgressWidthConstraint: NSLayoutConstraint?
    private let finishedBadgeView = UIImageView()
    private let checkboxImageView = UIImageView()

    // Metadata labels
    private let metaStatusLabel = UILabel()
    private let listProgressTrack = UIView()
    private let listProgressFill = UIView()
    private var listProgressWidthConstraint: NSLayoutConstraint?

    private var listCoverWidthConstraint: NSLayoutConstraint?
    private var gridTextHeightConstraint: NSLayoutConstraint?
    private var coverWrapperLeadingConstraint: NSLayoutConstraint?
    private var coverWrapperTrailingConstraint: NSLayoutConstraint?
    private var coverWrapperTopConstraint: NSLayoutConstraint?
    private var coverWrapperBottomConstraint: NSLayoutConstraint?

    private var rootStackView: UIStackView? {
        contentView.subviews.first(where: { $0 is UIStackView && $0 != publicationMenuViewController.view }) as? UIStackView
    }

    var progress: Float = 0.0 {
        didSet {
            updateProgressAndStatusUI()
        }
    }

    override var isHighlighted: Bool {
        didSet {
            let scale: CGFloat = isHighlighted ? 0.96 : 1.0
            UIView.animate(
                withDuration: 0.22,
                delay: 0,
                usingSpringWithDamping: 0.78,
                initialSpringVelocity: 0.2,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                self.transform = CGAffineTransform(scaleX: scale, y: scale)
            }
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        // Re-pin rootStackView cleanly to contentView
        if let rootStack = rootStackView {
            let selfConstraints = constraints.filter { constraint in
                (constraint.firstItem as? UIView == rootStack) || (constraint.secondItem as? UIView == rootStack)
            }
            removeConstraints(selfConstraints)

            rootStack.translatesAutoresizingMaskIntoConstraints = false
            rootStack.spacing = 8
            NSLayoutConstraint.activate([
                rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                rootStack.topAnchor.constraint(equalTo: contentView.topAnchor),
                rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ])
        }

        if textContainerView == nil {
            textContainerView = titleLabel.superview?.superview
        }

        publicationMenuViewController.delegate = self
        publicationMenuViewController.view.isHidden = true
        contentView.addSubview(publicationMenuViewController.view)

        setupEditorialAppearance()
        setupMetadataStack()
        setupSelectionCheckbox()

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, previous: UITraitCollection) in
            if self.traitCollection.hasDifferentColorAppearance(comparedTo: previous) {
                self.applyDynamicColors()
            }
        }

        applyDynamicColors()
        updateProgressAndStatusUI()
    }

    private func setupEditorialAppearance() {
        backgroundColor = .clear
        clipsToBounds = false
        layer.masksToBounds = false
        contentView.clipsToBounds = false
        contentView.layer.masksToBounds = false

        // Wrap coverImageView inside a shadow container + continuous corner clip container
        if let rootStack = coverImageView.superview as? UIStackView,
           let index = rootStack.arrangedSubviews.firstIndex(of: coverImageView) {
            let wrapperView = UIView()
            wrapperView.translatesAutoresizingMaskIntoConstraints = false
            wrapperView.backgroundColor = .clear
            wrapperView.accessibilityLabel = "CoverWrapper"
            wrapperView.clipsToBounds = false

            rootStack.insertArrangedSubview(wrapperView, at: index)
            coverImageView.removeFromSuperview()

            coverShadowContainer.translatesAutoresizingMaskIntoConstraints = false
            coverShadowContainer.backgroundColor = .clear
            coverShadowContainer.clipsToBounds = false
            coverShadowContainer.layer.masksToBounds = false
            wrapperView.addSubview(coverShadowContainer)

            coverWrapperTopConstraint = coverShadowContainer.topAnchor.constraint(equalTo: wrapperView.topAnchor)
            coverWrapperLeadingConstraint = coverShadowContainer.leadingAnchor.constraint(equalTo: wrapperView.leadingAnchor)
            coverWrapperTrailingConstraint = coverShadowContainer.trailingAnchor.constraint(equalTo: wrapperView.trailingAnchor)
            coverWrapperBottomConstraint = coverShadowContainer.bottomAnchor.constraint(equalTo: wrapperView.bottomAnchor)
            NSLayoutConstraint.activate([
                coverWrapperTopConstraint!,
                coverWrapperLeadingConstraint!,
                coverWrapperTrailingConstraint!,
                coverWrapperBottomConstraint!,
            ])

            coverClipContainer.translatesAutoresizingMaskIntoConstraints = false
            coverClipContainer.layer.cornerRadius = 10
            coverClipContainer.layer.cornerCurve = .continuous
            coverClipContainer.layer.masksToBounds = true
            coverClipContainer.layer.borderWidth = 0.5
            coverShadowContainer.addSubview(coverClipContainer)

            NSLayoutConstraint.activate([
                coverClipContainer.topAnchor.constraint(equalTo: coverShadowContainer.topAnchor),
                coverClipContainer.leadingAnchor.constraint(equalTo: coverShadowContainer.leadingAnchor),
                coverClipContainer.trailingAnchor.constraint(equalTo: coverShadowContainer.trailingAnchor),
                coverClipContainer.bottomAnchor.constraint(equalTo: coverShadowContainer.bottomAnchor),
            ])

            coverImageView.translatesAutoresizingMaskIntoConstraints = false
            coverImageView.contentMode = .scaleAspectFill
            coverImageView.clipsToBounds = true
            coverClipContainer.addSubview(coverImageView)

            NSLayoutConstraint.activate([
                coverImageView.topAnchor.constraint(equalTo: coverClipContainer.topAnchor),
                coverImageView.leadingAnchor.constraint(equalTo: coverClipContainer.leadingAnchor),
                coverImageView.trailingAnchor.constraint(equalTo: coverClipContainer.trailingAnchor),
                coverImageView.bottomAnchor.constraint(equalTo: coverClipContainer.bottomAnchor),
            ])

            // Subtle physical hardcover spine lighting along the leading edge
            spineOverlayView.translatesAutoresizingMaskIntoConstraints = false
            spineOverlayView.isUserInteractionEnabled = false
            spineGradientLayer.colors = [
                UIColor.black.withAlphaComponent(0.18).cgColor,
                UIColor.white.withAlphaComponent(0.22).cgColor,
                UIColor.black.withAlphaComponent(0.06).cgColor,
                UIColor.clear.cgColor,
            ]
            spineGradientLayer.locations = [0.0, 0.35, 0.6, 1.0]
            spineGradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
            spineGradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
            spineOverlayView.layer.addSublayer(spineGradientLayer)
            coverClipContainer.addSubview(spineOverlayView)

            NSLayoutConstraint.activate([
                spineOverlayView.topAnchor.constraint(equalTo: coverClipContainer.topAnchor),
                spineOverlayView.leadingAnchor.constraint(equalTo: coverClipContainer.leadingAnchor),
                spineOverlayView.bottomAnchor.constraint(equalTo: coverClipContainer.bottomAnchor),
                spineOverlayView.widthAnchor.constraint(equalToConstant: 8),
            ])

            // Slim bottom progress bar embedded seamlessly along bottom edge of cover
            coverProgressTrack.translatesAutoresizingMaskIntoConstraints = false
            coverProgressTrack.backgroundColor = UIColor.black.withAlphaComponent(0.35)
            coverProgressTrack.isHidden = true
            coverClipContainer.addSubview(coverProgressTrack)

            coverProgressFill.translatesAutoresizingMaskIntoConstraints = false
            coverProgressFill.backgroundColor = AppColors.uiAccentBlue
            coverProgressTrack.addSubview(coverProgressFill)

            let fillWidth = coverProgressFill.widthAnchor.constraint(equalTo: coverProgressTrack.widthAnchor, multiplier: 0.01)
            coverProgressWidthConstraint = fillWidth

            NSLayoutConstraint.activate([
                coverProgressTrack.leadingAnchor.constraint(equalTo: coverClipContainer.leadingAnchor),
                coverProgressTrack.trailingAnchor.constraint(equalTo: coverClipContainer.trailingAnchor),
                coverProgressTrack.bottomAnchor.constraint(equalTo: coverClipContainer.bottomAnchor),
                coverProgressTrack.heightAnchor.constraint(equalToConstant: 3.5),

                coverProgressFill.leadingAnchor.constraint(equalTo: coverProgressTrack.leadingAnchor),
                coverProgressFill.topAnchor.constraint(equalTo: coverProgressTrack.topAnchor),
                coverProgressFill.bottomAnchor.constraint(equalTo: coverProgressTrack.bottomAnchor),
                fillWidth,
            ])

            // Finished subtle checkmark badge at top-right of cover
            finishedBadgeView.translatesAutoresizingMaskIntoConstraints = false
            finishedBadgeView.image = UIImage(
                systemName: "checkmark.circle.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
            )
            finishedBadgeView.tintColor = AppColors.uiAccentTeal
            finishedBadgeView.backgroundColor = .white
            finishedBadgeView.layer.cornerRadius = 9
            finishedBadgeView.clipsToBounds = true
            finishedBadgeView.isHidden = true
            coverClipContainer.addSubview(finishedBadgeView)

            NSLayoutConstraint.activate([
                finishedBadgeView.topAnchor.constraint(equalTo: coverClipContainer.topAnchor, constant: 6),
                finishedBadgeView.trailingAnchor.constraint(equalTo: coverClipContainer.trailingAnchor, constant: -6),
                finishedBadgeView.widthAnchor.constraint(equalToConstant: 18),
                finishedBadgeView.heightAnchor.constraint(equalToConstant: 18),
            ])
        }
    }

    private func setupMetadataStack() {
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentHuggingPriority(.required, for: .vertical)
        authorLabel.numberOfLines = 1
        authorLabel.lineBreakMode = .byTruncatingTail
        authorLabel.setContentHuggingPriority(.required, for: .vertical)

        metaStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        metaStatusLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
        metaStatusLabel.numberOfLines = 1
        metaStatusLabel.setContentHuggingPriority(.required, for: .vertical)

        // Compact inline progress bar used only in List mode
        listProgressTrack.translatesAutoresizingMaskIntoConstraints = false
        listProgressTrack.layer.cornerRadius = 2
        listProgressTrack.clipsToBounds = true
        listProgressTrack.isHidden = true

        listProgressFill.translatesAutoresizingMaskIntoConstraints = false
        listProgressFill.backgroundColor = AppColors.uiAccentBlue
        listProgressFill.layer.cornerRadius = 2
        listProgressTrack.addSubview(listProgressFill)

        let listFillWidth = listProgressFill.widthAnchor.constraint(equalTo: listProgressTrack.widthAnchor, multiplier: 0.01)
        listProgressWidthConstraint = listFillWidth
        NSLayoutConstraint.activate([
            listProgressTrack.heightAnchor.constraint(equalToConstant: 4),
            listProgressFill.leadingAnchor.constraint(equalTo: listProgressTrack.leadingAnchor),
            listProgressFill.topAnchor.constraint(equalTo: listProgressTrack.topAnchor),
            listProgressFill.bottomAnchor.constraint(equalTo: listProgressTrack.bottomAnchor),
            listFillWidth,
        ])

        if let stackView = titleLabel.superview as? UIStackView {
            stackView.spacing = 3
            stackView.isLayoutMarginsRelativeArrangement = true
            stackView.layoutMargins = UIEdgeInsets(top: 0, left: 2, bottom: 0, right: 2)
            // Hide legacy XIB filler view
            for sub in stackView.arrangedSubviews where sub != titleLabel && sub != authorLabel {
                sub.isHidden = true
            }
            stackView.addArrangedSubview(listProgressTrack)
            stackView.addArrangedSubview(metaStatusLabel)

            // Flexible bottom spacer keeps title, author, and status tightly stacked at the top
            let bottomSpacer = UIView()
            bottomSpacer.backgroundColor = .clear
            bottomSpacer.setContentHuggingPriority(.defaultLow - 1, for: .vertical)
            bottomSpacer.setContentCompressionResistancePriority(.defaultLow - 1, for: .vertical)
            stackView.addArrangedSubview(bottomSpacer)
        }

        if let textContainer = textContainerView {
            textContainer.backgroundColor = .clear
            for constraint in textContainer.constraints where constraint.firstAttribute == .height {
                textContainer.removeConstraint(constraint)
            }
            gridTextHeightConstraint = textContainer.heightAnchor.constraint(equalToConstant: 64)
            gridTextHeightConstraint?.isActive = true
        }
    }

    private func setupSelectionCheckbox() {
        checkboxImageView.translatesAutoresizingMaskIntoConstraints = false
        checkboxImageView.contentMode = .scaleAspectFit
        checkboxImageView.isHidden = true
        contentView.addSubview(checkboxImageView)

        NSLayoutConstraint.activate([
            checkboxImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            checkboxImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            checkboxImageView.widthAnchor.constraint(equalToConstant: 24),
            checkboxImageView.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    private func updateProgressAndStatusUI() {
        let clamped = max(0, min(1, progress))
        let isReading = clamped > 0.0 && clamped < 0.99
        let isFinished = clamped >= 0.99

        // Cover progress bar (grid mode)
        coverProgressTrack.isHidden = !(isReading && currentMode == .grid)
        if let old = coverProgressWidthConstraint {
            coverProgressTrack.removeConstraint(old)
        }
        let newCoverWidth = coverProgressFill.widthAnchor.constraint(
            equalTo: coverProgressTrack.widthAnchor,
            multiplier: CGFloat(max(0.04, clamped))
        )
        newCoverWidth.isActive = true
        coverProgressWidthConstraint = newCoverWidth

        // List progress bar (list mode)
        listProgressTrack.isHidden = !(currentMode == .list && clamped > 0)
        if let oldList = listProgressWidthConstraint {
            listProgressTrack.removeConstraint(oldList)
        }
        let newListWidth = listProgressFill.widthAnchor.constraint(
            equalTo: listProgressTrack.widthAnchor,
            multiplier: CGFloat(max(0.03, clamped))
        )
        newListWidth.isActive = true
        listProgressWidthConstraint = newListWidth
        listProgressFill.backgroundColor = isFinished ? AppColors.uiAccentTeal : AppColors.uiAccentBlue

        // Finished checkmark badge (hidden during edit mode so checkbox is unobstructed)
        finishedBadgeView.isHidden = !isFinished || isEditingMode || currentMode == .list

        if isFinished {
            metaStatusLabel.text = NSLocalizedString("bookshelf_status_completed", comment: "")
            metaStatusLabel.textColor = AppColors.uiAccentTeal
        } else if isReading {
            let pct = Int((clamped * 100).rounded())
            metaStatusLabel.text = "\(pct)%"
            metaStatusLabel.textColor = AppColors.uiAccentBlue
        } else {
            metaStatusLabel.text = NSLocalizedString("bookshelf_status_not_started", comment: "")
            metaStatusLabel.textColor = .tertiaryLabel
        }
    }

    private func updateSelectionAppearance() {
        if isEditingMode {
            checkboxImageView.isHidden = false
            finishedBadgeView.isHidden = true
            if isSelectedForEditing {
                checkboxImageView.image = UIImage(systemName: "checkmark.circle.fill")
                checkboxImageView.tintColor = AppColors.uiAccentBlue
                checkboxImageView.layer.shadowOpacity = 0

                if currentMode == .grid {
                    coverClipContainer.layer.borderWidth = 2.5
                    coverClipContainer.layer.borderColor = AppColors.uiAccentBlue.cgColor
                } else {
                    contentView.layer.borderWidth = 2.0
                    contentView.layer.borderColor = AppColors.uiAccentBlue.cgColor
                }
            } else {
                checkboxImageView.image = UIImage(systemName: "circle")
                checkboxImageView.tintColor = currentMode == .list ? .systemGray3 : .white
                checkboxImageView.layer.shadowColor = UIColor.black.cgColor
                checkboxImageView.layer.shadowOpacity = currentMode == .list ? 0 : 0.45
                checkboxImageView.layer.shadowOffset = CGSize(width: 0, height: 1)
                checkboxImageView.layer.shadowRadius = 2.5
                checkboxImageView.layer.masksToBounds = false

                applyBorderColors()
            }
        } else {
            checkboxImageView.isHidden = true
            applyBorderColors()
            updateProgressAndStatusUI()
        }
    }

    private func applyBorderColors() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        coverClipContainer.layer.borderWidth = 0.6
        coverClipContainer.layer.borderColor = (isDark ? UIColor.white.withAlphaComponent(0.12) : UIColor.black.withAlphaComponent(0.09)).cgColor

        if currentMode == .list {
            contentView.layer.borderWidth = 1.0
            contentView.layer.borderColor = (isDark ? UIColor.white.withAlphaComponent(0.06) : UIColor.black.withAlphaComponent(0.04)).cgColor
        } else {
            contentView.layer.borderWidth = 0
            contentView.layer.borderColor = nil
        }
    }

    private func applyDynamicColors() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        titleLabel.textColor = .label
        authorLabel.textColor = .secondaryLabel
        listProgressTrack.backgroundColor = isDark ? UIColor.white.withAlphaComponent(0.08) : UIColor.black.withAlphaComponent(0.06)

        if currentMode == .list {
            contentView.backgroundColor = AppColors.uiCardBackground
            contentView.layer.cornerRadius = 16
            contentView.layer.cornerCurve = .continuous
            contentView.clipsToBounds = true
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = isDark ? 0 : 0.04
            layer.shadowOffset = CGSize(width: 0, height: 4)
            layer.shadowRadius = 10

            coverShadowContainer.layer.shadowOpacity = isDark ? 0.3 : 0.14
            coverShadowContainer.layer.shadowOffset = CGSize(width: 0, height: 2)
            coverShadowContainer.layer.shadowRadius = 5
        } else {
            contentView.backgroundColor = .clear
            contentView.layer.cornerRadius = 0
            contentView.clipsToBounds = false
            layer.shadowOpacity = 0

            coverShadowContainer.layer.shadowColor = UIColor.black.cgColor
            coverShadowContainer.layer.shadowOpacity = isDark ? 0.42 : 0.16
            coverShadowContainer.layer.shadowOffset = CGSize(width: 0, height: 6)
            coverShadowContainer.layer.shadowRadius = 10
        }

        textContainerView?.backgroundColor = .clear
        applyBorderColors()
        updateSelectionAppearance()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        publicationMenuViewController.view.frame = contentView.bounds
        contentView.layoutIfNeeded()
        spineGradientLayer.frame = spineOverlayView.bounds
        coverShadowContainer.layer.shadowPath = UIBezierPath(
            roundedRect: coverShadowContainer.bounds,
            cornerRadius: coverClipContainer.layer.cornerRadius
        ).cgPath
        if currentMode == .list {
            layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 16).cgPath
        } else {
            layer.shadowPath = nil
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        coverImageView.image = nil
        coverImageView.contentMode = .scaleAspectFill
        transform = .identity
    }
}

extension PublicationCollectionViewCell {
    /// Legacy flip menu retained for protocol compatibility.
    func flipMenu() {
        guard !isEditingMode else { return }
        isMenuDisplayed = false
        publicationMenuViewController.view.isHidden = true
        rootStackView?.isHidden = false
    }
}

extension PublicationCollectionViewCell: PublicationMenuViewControllerDelegate {
    func metadataButtonTapped() {
        guard let indexPath = (superview as? UICollectionView)?.indexPath(for: self) else { return }
        delegate?.presentMetadata(forCellAt: indexPath)
    }

    func removeButtonTapped() {
        guard let indexPath = (superview as? UICollectionView)?.indexPath(for: self) else { return }
        delegate?.removePublicationFromLibrary(forCellAt: indexPath)
    }

    func cancelButtonTapped() {
        flipMenu()
    }

    func configureMode(_ mode: LibraryViewController.ViewMode) {
        currentMode = mode
        guard let rootStack = rootStackView,
              let wrapperView = coverShadowContainer.superview else { return }

        if listCoverWidthConstraint == nil {
            listCoverWidthConstraint = wrapperView.widthAnchor.constraint(equalToConstant: 74)
        }

        if mode == .list {
            rootStack.axis = .horizontal
            rootStack.alignment = .fill
            rootStack.distribution = .fill
            rootStack.spacing = 12

            coverWrapperTopConstraint?.constant = 10
            coverWrapperBottomConstraint?.constant = -10
            coverWrapperLeadingConstraint?.constant = 12
            coverWrapperTrailingConstraint?.constant = 0

            gridTextHeightConstraint?.isActive = false
            listCoverWidthConstraint?.isActive = true

            coverClipContainer.layer.cornerRadius = 7
            titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
            authorLabel.font = .systemFont(ofSize: 12.5, weight: .regular)
            metaStatusLabel.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)

            if let stackView = titleLabel.superview as? UIStackView {
                stackView.spacing = 4
                stackView.layoutMargins = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 14)
            }
        } else {
            rootStack.axis = .vertical
            rootStack.alignment = .fill
            rootStack.distribution = .fill
            rootStack.spacing = 8

            coverWrapperTopConstraint?.constant = 0
            coverWrapperBottomConstraint?.constant = 0
            coverWrapperLeadingConstraint?.constant = 0
            coverWrapperTrailingConstraint?.constant = 0

            listCoverWidthConstraint?.isActive = false
            gridTextHeightConstraint?.isActive = true

            coverClipContainer.layer.cornerRadius = 10
            titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            authorLabel.font = .systemFont(ofSize: 11, weight: .regular)
            metaStatusLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)

            if let stackView = titleLabel.superview as? UIStackView {
                stackView.spacing = 2.5
                stackView.layoutMargins = UIEdgeInsets(top: 0, left: 2, bottom: 0, right: 2)
            }
        }

        coverImageView.contentMode = .scaleAspectFill
        applyDynamicColors()
        updateProgressAndStatusUI()

        rootStack.setNeedsLayout()
        rootStack.layoutIfNeeded()
        contentView.setNeedsLayout()
        contentView.layoutIfNeeded()
    }
}
