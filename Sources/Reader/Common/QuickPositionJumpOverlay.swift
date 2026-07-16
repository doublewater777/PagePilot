import UIKit

@MainActor
final class QuickPositionJumpOverlay {
    let touchTarget = UIView()

    private weak var positionLabel: UILabel?
    private let bubbleView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let bubbleLabel = UILabel()

    init(hostView: UIView, positionLabel: UILabel) {
        self.positionLabel = positionLabel

        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.clipsToBounds = true
        bubbleView.layer.cornerRadius = 14
        bubbleView.alpha = 0
        bubbleView.isHidden = true
        bubbleLabel.translatesAutoresizingMaskIntoConstraints = false
        bubbleLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        bubbleLabel.textColor = .label
        bubbleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        bubbleView.contentView.addSubview(bubbleLabel)
        hostView.addSubview(bubbleView)

        touchTarget.translatesAutoresizingMaskIntoConstraints = false
        touchTarget.backgroundColor = .clear
        touchTarget.isAccessibilityElement = false
        hostView.addSubview(touchTarget)

        NSLayoutConstraint.activate([
            bubbleView.centerXAnchor.constraint(equalTo: hostView.centerXAnchor),
            bubbleView.bottomAnchor.constraint(equalTo: positionLabel.topAnchor, constant: -12),
            bubbleLabel.leadingAnchor.constraint(equalTo: bubbleView.contentView.leadingAnchor, constant: 14),
            bubbleLabel.trailingAnchor.constraint(equalTo: bubbleView.contentView.trailingAnchor, constant: -14),
            bubbleLabel.topAnchor.constraint(equalTo: bubbleView.contentView.topAnchor, constant: 9),
            bubbleLabel.bottomAnchor.constraint(equalTo: bubbleView.contentView.bottomAnchor, constant: -9),
            touchTarget.centerXAnchor.constraint(equalTo: positionLabel.centerXAnchor),
            touchTarget.centerYAnchor.constraint(equalTo: positionLabel.centerYAnchor),
            touchTarget.widthAnchor.constraint(equalToConstant: 44),
            touchTarget.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    func show(text: String) {
        bubbleLabel.text = text
        positionLabel?.alpha = 0
        bubbleView.isHidden = false
        bubbleView.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        UIView.animate(
            withDuration: 0.35,
            delay: 0,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState]
        ) {
            self.bubbleView.alpha = 1
            self.bubbleView.transform = .identity
        }
    }

    func update(text: String) {
        bubbleLabel.text = text
    }

    func hide() {
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut]) {
            self.bubbleView.alpha = 0
            self.positionLabel?.alpha = 1
        } completion: { _ in
            self.bubbleView.isHidden = true
        }
    }
}
