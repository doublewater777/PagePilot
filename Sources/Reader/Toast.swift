//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import UIKit

private final class ToastPillView: UIVisualEffectView {
    static let tagValue = 0x5050_7054

    private let iconView = UIImageView()
    private let messageLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let contentStack = UIStackView()

    init(text: String?, isActivity: Bool) {
        super.init(effect: UIBlurEffect(style: .systemThinMaterial))
        tag = Self.tagValue
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = true
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.separator.withAlphaComponent(0.35).cgColor
        isUserInteractionEnabled = false

        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = 8
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentStack)

        if isActivity {
            spinner.startAnimating()
            spinner.color = .label
            contentStack.addArrangedSubview(spinner)
        } else {
            let symbol = Self.semanticSymbol(for: text ?? "")
            iconView.image = UIImage(
                systemName: symbol,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            )
            iconView.tintColor = AppColors.uiAccentBlue
            iconView.setContentHuggingPriority(.required, for: .horizontal)
            contentStack.addArrangedSubview(iconView)
        }

        if let text, !text.isEmpty {
            messageLabel.text = text
            messageLabel.font = .systemFont(ofSize: 14, weight: .semibold)
            messageLabel.textColor = .label
            messageLabel.numberOfLines = 2
            messageLabel.textAlignment = .center
            contentStack.addArrangedSubview(messageLabel)
        }

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 11),
            contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -11),
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func semanticSymbol(for text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("bookmark") || text.contains("书签") || lower.contains("marcador") || lower.contains("signet") || lower.contains("lesezeichen") {
            return "bookmark.fill"
        }
        if lower.contains("highlight") || text.contains("高亮") {
            return "highlighter"
        }
        if lower.contains("fail") || lower.contains("error") || text.contains("失败") || text.contains("无法") {
            return "exclamationmark.circle.fill"
        }
        return "checkmark.circle.fill"
    }
}

/// Displays a sleek floating material pill near the top safe area.
func toast(_ text: String, on view: UIView, duration: TimeInterval) {
    let present = {
        view.subviews
            .filter { $0.tag == ToastPillView.tagValue }
            .forEach { $0.removeFromSuperview() }

        let pill = ToastPillView(text: text, isActivity: false)
        let container = UIView()
        container.tag = ToastPillView.tagValue
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isUserInteractionEnabled = false
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = 0.14
        container.layer.shadowRadius = 16
        container.layer.shadowOffset = CGSize(width: 0, height: 6)
        container.addSubview(pill)
        view.addSubview(container)

        NSLayoutConstraint.activate([
            pill.topAnchor.constraint(equalTo: container.topAnchor),
            pill.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            pill.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            pill.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            container.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            container.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            container.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
        ])

        container.alpha = 0
        container.transform = CGAffineTransform(translationX: 0, y: -12).scaledBy(x: 0.94, y: 0.94)

        UIView.animate(
            withDuration: 0.34,
            delay: 0,
            usingSpringWithDamping: 0.82,
            initialSpringVelocity: 0.2,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            container.alpha = 1
            container.transform = .identity
        }

        let dismissDelay = max(0.8, duration)
        DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay) { [weak container] in
            guard let container, container.superview != nil else { return }
            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseIn]) {
                container.alpha = 0
                container.transform = CGAffineTransform(translationX: 0, y: -8).scaledBy(x: 0.96, y: 0.96)
            } completion: { _ in
                container.removeFromSuperview()
            }
        }
    }

    if Thread.isMainThread {
        present()
    } else {
        DispatchQueue.main.async(execute: present)
    }
}

/// Displays a sleek centered material activity pill in the view.
///
/// - Returns: A closure to be called when the activity indicator should hide.
func toastActivity(on view: UIView) -> () -> Void {
    let pill = ToastPillView(text: nil, isActivity: true)
    let container = UIView()
    container.translatesAutoresizingMaskIntoConstraints = false
    container.layer.shadowColor = UIColor.black.cgColor
    container.layer.shadowOpacity = 0.14
    container.layer.shadowRadius = 18
    container.layer.shadowOffset = CGSize(width: 0, height: 6)
    container.addSubview(pill)

    let show = {
        view.addSubview(container)
        NSLayoutConstraint.activate([
            pill.topAnchor.constraint(equalTo: container.topAnchor),
            pill.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            pill.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            pill.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        container.alpha = 0
        container.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        UIView.animate(withDuration: 0.22) {
            container.alpha = 1
            container.transform = .identity
        }
    }

    if Thread.isMainThread {
        show()
    } else {
        DispatchQueue.main.async(execute: show)
    }

    return {
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.18, animations: {
                container.alpha = 0
            }, completion: { _ in
                container.removeFromSuperview()
            })
        }
    }
}
