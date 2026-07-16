import ReadiumShared
import UIKit

@MainActor
final class QuickPositionJumpInteractionController: NSObject {
    enum Outcome {
        case cancelled
        case committed(target: Locator)
        case failed
    }

    private enum State {
        case idle
        case previewing
        case cancellationArmed
        case committing
    }

    var positions: [Locator] = []
    var isActive: Bool { state != .idle }

    private weak var hostView: UIView?
    private let overlay: QuickPositionJumpOverlay
    private let currentLocator: () -> Locator?
    private let onTap: () -> Void
    private let onBegin: () -> Void
    private let onCommit: (Locator) async -> Bool
    private let onRestore: (Locator) async -> Void
    private let onFinish: (Outcome) -> Void

    private let haptics = QuickPositionJumpHaptics()

    private var state: State = .idle
    private var originalLocator: Locator?
    private var currentPosition = 1
    private var targetPosition = 1
    private var activationX = 0.0
    private var activationY = 0.0
    private var horizontalRange = 0.0 ... 0.0
    private var commitTask: Task<Void, Never>?

    init(
        hostView: UIView,
        positionLabel: UILabel,
        currentLocator: @escaping () -> Locator?,
        onTap: @escaping () -> Void,
        onBegin: @escaping () -> Void,
        onCommit: @escaping (Locator) async -> Bool,
        onRestore: @escaping (Locator) async -> Void,
        onFinish: @escaping (Outcome) -> Void
    ) {
        self.hostView = hostView
        self.overlay = QuickPositionJumpOverlay(hostView: hostView, positionLabel: positionLabel)
        self.currentLocator = currentLocator
        self.onTap = onTap
        self.onBegin = onBegin
        self.onCommit = onCommit
        self.onRestore = onRestore
        self.onFinish = onFinish
        super.init()

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.require(toFail: longPress)
        overlay.touchTarget.addGestureRecognizer(longPress)
        overlay.touchTarget.addGestureRecognizer(tap)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func cancel() {
        guard state != .idle, originalLocator != nil else { return }
        if state == .committing {
            commitTask?.cancel()
            return
        }
        commitTask?.cancel()
        finish(.cancelled)
    }

    @objc private func appDidEnterBackground() {
        cancel()
    }

    @objc private func handleTap() {
        guard state == .idle else { return }
        onTap()
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            begin(at: gesture.location(in: hostView))
        case .changed:
            update(with: gesture)
        case .ended:
            end()
        case .cancelled, .failed:
            cancel()
        case .possible:
            break
        @unknown default:
            cancel()
        }
    }

    private func begin(at point: CGPoint) {
        guard state == .idle,
              !positions.isEmpty,
              let hostView,
              let locator = currentLocator()
        else { return }

        let lowerBound = Double(hostView.safeAreaInsets.left + 20)
        let upperBound = Double(hostView.bounds.width - hostView.safeAreaInsets.right - 20)
        guard lowerBound < upperBound else { return }

        originalLocator = locator
        currentPosition = resolvedPosition(for: locator)
        targetPosition = currentPosition
        activationX = max(lowerBound, min(upperBound, Double(point.x)))
        activationY = Double(point.y)
        horizontalRange = lowerBound ... upperBound
        haptics.begin(
            position: currentPosition,
            positionCount: positions.count
        )
        state = .previewing
        onBegin()
        overlay.show(text: bubbleText())
    }

    private func update(with gesture: UILongPressGestureRecognizer) {
        guard state == .previewing || state == .cancellationArmed,
              let hostView
        else { return }

        let verticalTranslation = Double(gesture.location(in: hostView).y) - activationY
        if QuickPositionJumpPolicy.isCancellationArmed(verticalTranslation: verticalTranslation) {
            if state != .cancellationArmed {
                state = .cancellationArmed
                overlay.update(text: NSLocalizedString("reader_quick_position_cancel", comment: ""))
            }
            return
        }

        if state == .cancellationArmed {
            state = .previewing
        }

        let x = Double(gesture.location(in: hostView).x)
        let newTarget = QuickPositionJumpPolicy.targetPosition(
            currentPosition: currentPosition,
            positionCount: positions.count,
            activationX: activationX,
            currentX: x,
            horizontalRange: horizontalRange
        )
        if newTarget != targetPosition {
            haptics.moved(to: newTarget, positionCount: positions.count)
            targetPosition = newTarget
        }
        overlay.update(text: bubbleText())
    }

    private func end() {
        guard let originalLocator else { return }
        if state == .cancellationArmed {
            finish(.cancelled)
            return
        }
        guard state == .previewing else { return }

        let target = positions[targetPosition - 1]
        state = .committing
        commitTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let succeeded = await onCommit(target)
            if Task.isCancelled {
                await onRestore(originalLocator)
                finish(.cancelled)
                return
            }
            if succeeded {
                finish(.committed(target: target))
            } else {
                await onRestore(originalLocator)
                haptics.notifyError()
                finish(.failed)
            }
        }
    }

    private func bubbleText() -> String {
        let locator = positions[targetPosition - 1]
        let percentage = QuickPositionJumpPolicy.percentage(
            totalProgression: locator.locations.totalProgression,
            targetPosition: targetPosition,
            positionCount: positions.count
        )
        return String(
            format: NSLocalizedString("reader_quick_position_format", comment: ""),
            targetPosition,
            positions.count,
            percentage
        )
    }

    private func resolvedPosition(for locator: Locator) -> Int {
        if let position = locator.locations.position,
           positions.indices.contains(position - 1) {
            return position
        }
        guard let progression = locator.locations.totalProgression else { return 1 }
        return positions.enumerated().min {
            abs(($0.element.locations.totalProgression ?? 0) - progression)
                < abs(($1.element.locations.totalProgression ?? 0) - progression)
        }.map { $0.offset + 1 } ?? 1
    }

    private func finish(_ outcome: Outcome) {
        state = .idle
        commitTask = nil
        originalLocator = nil
        haptics.reset()
        overlay.hide()
        onFinish(outcome)
    }

}
