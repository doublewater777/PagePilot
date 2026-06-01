//
//  Copyright 2026 Readium Foundation. All rights reserved.
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

    private var statusLabel: UILabel!
    private var checkboxImageView: UIImageView!
    private var statusStackView: UIStackView!
    private var statusDotView: UIView!
    private var progressPillContainer: UIView!
    private var progressPillLabel: UILabel!
    private var listWidthConstraint: NSLayoutConstraint?
    private var gridHeightConstraint: NSLayoutConstraint?

    private var rootStackView: UIStackView? {
        return contentView.subviews.first(where: { $0 is UIStackView && $0 != publicationMenuViewController.view }) as? UIStackView
    }

    var progress: Float = 0.0 {
        didSet {
            progressView.isHidden = true
            
            let showPill = (progress > 0.0 && progress < 0.99)
            progressPillContainer?.isHidden = !showPill
            if showPill {
                let percentage = Int(progress * 100)
                progressPillLabel?.text = "\(percentage)%"
            }
            updateStatusLabel()
        }
    }

    private lazy var progressView: UIProgressView = {
        let pView = UIProgressView(progressViewStyle: .default)
        pView.translatesAutoresizingMaskIntoConstraints = false
        pView.progressTintColor = .systemBlue
        pView.trackTintColor = .systemGray5
        
        // Add to contentView to ensure it displays above the cell background
        contentView.addSubview(pView)

        NSLayoutConstraint.activate([
            pView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 0),
            pView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: 0),
            pView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: 0),
            pView.heightAnchor.constraint(equalToConstant: 3.5)
        ])

        return pView
    }()

    override func awakeFromNib() {
        super.awakeFromNib()

        // Fix root stack view constraints to pin it to contentView instead of cell self (avoids layout break in edit mode transitions)
        if let rootStack = rootStackView {
            let selfConstraints = self.constraints.filter { constraint in
                return (constraint.firstItem as? UIView == rootStack) || (constraint.secondItem as? UIView == rootStack)
            }
            self.removeConstraints(selfConstraints)
            
            rootStack.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                rootStack.topAnchor.constraint(equalTo: contentView.topAnchor),
                rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
        }

        // Fallback for textContainerView if not connected in XIB
        if textContainerView == nil {
            textContainerView = titleLabel.superview?.superview
        }

        publicationMenuViewController.delegate = self
        publicationMenuViewController.view.isHidden = !isMenuDisplayed
        contentView.addSubview(publicationMenuViewController.view)

        // Configure premium card UI appearance (includes cover wrapping)
        setupCardAppearance()

        // Dynamically instantiate helper UI components
        setupStatusLabel()
        setupCheckboxImageView()
        setupProgressPill()

        // Set dynamic colors for dark mode
        applyDynamicColors()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyDynamicColors()
        }
    }

    private func setupStatusLabel() {
        statusDotView = UIView()
        statusDotView.translatesAutoresizingMaskIntoConstraints = false
        statusDotView.layer.cornerRadius = 3
        statusDotView.clipsToBounds = true
        
        NSLayoutConstraint.activate([
            statusDotView.widthAnchor.constraint(equalToConstant: 6),
            statusDotView.heightAnchor.constraint(equalToConstant: 6)
        ])
        
        statusLabel = UILabel()
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 9, weight: .semibold)
        statusLabel.numberOfLines = 1
        
        statusStackView = UIStackView(arrangedSubviews: [statusDotView, statusLabel])
        statusStackView.axis = .horizontal
        statusStackView.alignment = .center
        statusStackView.spacing = 4
        statusStackView.translatesAutoresizingMaskIntoConstraints = false
        
        if let stackView = titleLabel.superview as? UIStackView {
            if let fillView = stackView.arrangedSubviews.first(where: { $0.accessibilityLabel == nil && $0 != titleLabel && $0 != authorLabel }) {
                fillView.isHidden = true
            }
            stackView.addArrangedSubview(statusStackView)
        }
        updateStatusLabel()
    }

    private func setupCheckboxImageView() {
        checkboxImageView = UIImageView()
        checkboxImageView.translatesAutoresizingMaskIntoConstraints = false
        checkboxImageView.contentMode = .center
        contentView.addSubview(checkboxImageView)
        
        NSLayoutConstraint.activate([
            checkboxImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            checkboxImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            checkboxImageView.widthAnchor.constraint(equalToConstant: 24),
            checkboxImageView.heightAnchor.constraint(equalToConstant: 24)
        ])
        
        checkboxImageView.isHidden = true
    }

    private func setupProgressPill() {
        progressPillContainer = UIView()
        progressPillContainer.translatesAutoresizingMaskIntoConstraints = false
        progressPillContainer.layer.cornerRadius = 8
        progressPillContainer.clipsToBounds = true
        progressPillContainer.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        progressPillContainer.addSubview(blurView)
        
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: progressPillContainer.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: progressPillContainer.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: progressPillContainer.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: progressPillContainer.bottomAnchor)
        ])
        
        progressPillLabel = UILabel()
        progressPillLabel.translatesAutoresizingMaskIntoConstraints = false
        progressPillLabel.font = .systemFont(ofSize: 9, weight: .bold)
        progressPillLabel.textColor = .white
        progressPillLabel.textAlignment = .center
        
        progressPillContainer.addSubview(progressPillLabel)
        
        if let wrapper = coverImageView.superview {
            wrapper.addSubview(progressPillContainer)
            
            NSLayoutConstraint.activate([
                progressPillContainer.leadingAnchor.constraint(equalTo: coverImageView.leadingAnchor, constant: 8),
                progressPillContainer.bottomAnchor.constraint(equalTo: coverImageView.bottomAnchor, constant: -8),
                progressPillContainer.heightAnchor.constraint(equalToConstant: 16),
                
                progressPillLabel.leadingAnchor.constraint(equalTo: progressPillContainer.leadingAnchor, constant: 6),
                progressPillLabel.trailingAnchor.constraint(equalTo: progressPillContainer.trailingAnchor, constant: -6),
                progressPillLabel.centerYAnchor.constraint(equalTo: progressPillContainer.centerYAnchor)
            ])
        }
        
        progressPillContainer.isHidden = true
    }

    private func setupCardAppearance() {
        // Round the card container
        contentView.layer.cornerRadius = 12
        contentView.layer.masksToBounds = true
        
        // Setup shadow properties on the Cell itself
        self.backgroundColor = .clear
        self.clipsToBounds = false
        self.layer.masksToBounds = false
        
        // Wrap cover image to add custom inset margins
        if let rootStackView = coverImageView.superview as? UIStackView {
            if coverImageView.superview?.accessibilityLabel != "CoverWrapper" {
                let wrapperView = UIView()
                wrapperView.translatesAutoresizingMaskIntoConstraints = false
                wrapperView.backgroundColor = .clear
                wrapperView.accessibilityLabel = "CoverWrapper"
                
                if let index = rootStackView.arrangedSubviews.firstIndex(of: coverImageView) {
                    rootStackView.insertArrangedSubview(wrapperView, at: index)
                    coverImageView.removeFromSuperview()
                    wrapperView.addSubview(coverImageView)
                    coverImageView.translatesAutoresizingMaskIntoConstraints = false
                    
                    NSLayoutConstraint.activate([
                        coverImageView.topAnchor.constraint(equalTo: wrapperView.topAnchor, constant: 12),
                        coverImageView.leadingAnchor.constraint(equalTo: wrapperView.leadingAnchor, constant: 12),
                        coverImageView.trailingAnchor.constraint(equalTo: wrapperView.trailingAnchor, constant: -12),
                        coverImageView.bottomAnchor.constraint(equalTo: wrapperView.bottomAnchor, constant: -8)
                    ])
                }
            }
        }
        
        // Optimize cover image aspect fill, scale and round corners
        coverImageView.contentMode = .scaleAspectFill
        coverImageView.clipsToBounds = true
        coverImageView.layer.cornerRadius = 10
        coverImageView.layer.masksToBounds = true
        
        // Add inner padding to text stack view to prevent text from sticking to borders
        if let stackView = titleLabel.superview as? UIStackView {
            stackView.isLayoutMarginsRelativeArrangement = true
            stackView.layoutMargins = UIEdgeInsets(top: 4, left: 10, bottom: 6, right: 10)
        }
        
        // Set premium fonts
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        authorLabel.font = .systemFont(ofSize: 9, weight: .medium)
        
        // Force the text container view height to 56 to fully display title, author and status
        if let textContainer = textContainerView {
            for constraint in textContainer.constraints {
                if constraint.firstAttribute == .height {
                    textContainer.removeConstraint(constraint)
                }
            }
            gridHeightConstraint = textContainer.heightAnchor.constraint(equalToConstant: 56)
            gridHeightConstraint?.isActive = true
        }
    }

    private func updateStatusLabel() {
        guard statusLabel != nil, statusDotView != nil else { return }
        if progress <= 0.0 {
            statusLabel.text = NSLocalizedString("bookshelf_status_not_started", comment: "")
            statusLabel.textColor = .secondaryLabel
            statusDotView.backgroundColor = .systemGray
        } else if progress >= 0.99 {
            statusLabel.text = NSLocalizedString("bookshelf_status_completed", comment: "")
            statusLabel.textColor = .systemGreen
            statusDotView.backgroundColor = .systemGreen
        } else {
            statusLabel.text = NSLocalizedString("bookshelf_status_reading", comment: "")
            statusLabel.textColor = .systemBlue
            statusDotView.backgroundColor = .systemBlue
        }
    }

    private func updateSelectionAppearance() {
        guard checkboxImageView != nil else { return }
        if isEditingMode {
            checkboxImageView.isHidden = false
            if isSelectedForEditing {
                checkboxImageView.image = UIImage(systemName: "checkmark.circle.fill")
                checkboxImageView.tintColor = .systemBlue
                
                // Highlight the selected card with a clean blue border
                contentView.layer.borderWidth = 2.0
                contentView.layer.borderColor = UIColor.systemBlue.cgColor
            } else {
                checkboxImageView.image = UIImage(systemName: "circle")
                let isList = rootStackView?.axis == .horizontal
                checkboxImageView.tintColor = isList ? .systemGray3 : .white
                
                // Add soft shadow behind white circle icon to stand out on bright book covers
                checkboxImageView.layer.shadowColor = UIColor.black.cgColor
                checkboxImageView.layer.shadowOpacity = 0.4
                checkboxImageView.layer.shadowOffset = CGSize(width: 0, height: 1)
                checkboxImageView.layer.shadowRadius = 2.0
                checkboxImageView.layer.masksToBounds = false
                
                contentView.layer.borderWidth = 0.0
                contentView.layer.borderColor = nil
            }
        } else {
            checkboxImageView.isHidden = true
            contentView.layer.borderWidth = 0.0
            contentView.layer.borderColor = nil
        }
    }

    private func applyDynamicColors() {
        titleLabel.textColor = .label
        authorLabel.textColor = .secondaryLabel
        contentView.backgroundColor = .secondarySystemGroupedBackground
        textContainerView?.backgroundColor = .secondarySystemGroupedBackground
        
        // Adjust shadows adaptively depending on user interface style (Dark/Light)
        if traitCollection.userInterfaceStyle == .dark {
            self.layer.shadowColor = UIColor.black.cgColor
            self.layer.shadowOpacity = 0.35
            self.layer.shadowOffset = CGSize(width: 0, height: 2)
            self.layer.shadowRadius = 4.0
        } else {
            self.layer.shadowColor = UIColor.black.cgColor
            self.layer.shadowOpacity = 0.07
            self.layer.shadowOffset = CGSize(width: 0, height: 4)
            self.layer.shadowRadius = 6.0
        }
        
        updateSelectionAppearance()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        publicationMenuViewController.view.frame = contentView.bounds
        
        // Force contentView layout immediately when cell bounds change to prevent layout delay/stretching
        contentView.layoutIfNeeded()
        
        // Set dynamic shadow path for performance and accuracy
        self.layer.shadowPath = UIBezierPath(roundedRect: self.bounds, cornerRadius: 12).cgPath
    }
}

extension PublicationCollectionViewCell {
    /// Flip the PublicationCollectionViewCell and display a user menu.
    func flipMenu() {
        // Prevent flipping during multi-select editing mode
        guard !isEditingMode else { return }
        
        var transitionOptions: UIView.AnimationOptions!

        if isMenuDisplayed {
            transitionOptions = UIView.AnimationOptions.transitionFlipFromLeft
            delegate?.lastFlippedCell = nil
            isAccessibilityElement = true
        } else {
            isAccessibilityElement = false
            transitionOptions = UIView.AnimationOptions.transitionFlipFromRight
            if delegate?.lastFlippedCell != self {
                delegate?.cellFlipped(self)
            }
        }

        // Reverse the UI. Display the menu and hide the cover or vice versa
        UIView.transition(with: contentView, duration: 0.5, options: transitionOptions, animations: {
            self.rootStackView?.isHidden = !self.isMenuDisplayed
            self.publicationMenuViewController.view.isHidden = self.isMenuDisplayed
        }, completion: { _ in
            self.isMenuDisplayed = !self.isMenuDisplayed
        })
    }
}

extension PublicationCollectionViewCell: PublicationMenuViewControllerDelegate {
    func metadataButtonTapped() {
        guard let indexPath = (superview as? UICollectionView)?.indexPath(for: self) else {
            return
        }
        flipMenu()
        delegate?.presentMetadata(forCellAt: indexPath)
    }

    func removeButtonTapped() {
        guard let indexPath = (superview as? UICollectionView)?.indexPath(for: self) else {
            return
        }
        flipMenu()
        delegate?.removePublicationFromLibrary(forCellAt: indexPath)
    }

    func cancelButtonTapped() {
        flipMenu()
    }
    
    func configureMode(_ mode: LibraryViewController.ViewMode) {
        guard let rootStack = rootStackView,
              let wrapperView = coverImageView.superview else { return }
        
        if listWidthConstraint == nil {
            listWidthConstraint = wrapperView.widthAnchor.constraint(equalToConstant: 80)
        }
        
        if mode == .list {
            rootStack.axis = .horizontal
            rootStack.alignment = .fill
            rootStack.distribution = .fill
            
            gridHeightConstraint?.isActive = false
            listWidthConstraint?.isActive = true
            
            titleLabel.font = .systemFont(ofSize: 14, weight: .bold)
            authorLabel.font = .systemFont(ofSize: 11, weight: .medium)
            
            if let stackView = titleLabel.superview as? UIStackView {
                stackView.layoutMargins = UIEdgeInsets(top: 14, left: 8, bottom: 14, right: 12)
            }
        } else {
            rootStack.axis = .vertical
            rootStack.alignment = .fill
            rootStack.distribution = .fill
            
            listWidthConstraint?.isActive = false
            gridHeightConstraint?.isActive = true
            
            titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
            authorLabel.font = .systemFont(ofSize: 9, weight: .medium)
            
            if let stackView = titleLabel.superview as? UIStackView {
                stackView.layoutMargins = UIEdgeInsets(top: 4, left: 10, bottom: 6, right: 10)
            }
        }
        
        // Force Auto Layout to resolve immediately to avoid layout mismatch in reload animation
        rootStack.setNeedsLayout()
        rootStack.layoutIfNeeded()
        contentView.setNeedsLayout()
        contentView.layoutIfNeeded()
    }
}
