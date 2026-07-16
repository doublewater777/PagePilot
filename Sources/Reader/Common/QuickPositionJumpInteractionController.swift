import ReadiumShared
import UIKit

@MainActor
final class QuickPositionJumpInteractionController: NSObject {
    enum Outcome {
        case cancelled
        case committed(target: Locator)
        case failed
        case interrupted
    }

    var positions: [Locator] = []
    var isActive: Bool { session.state != .idle || recoveryTask != nil }

    private weak var hostView: UIView?
    private let overlay: QuickPositionJumpOverlay
    private let currentLocator: () -> Locator?
    private let onTap: () -> Void
    private let onBegin: () async -> Void
    private let onCommit: (Locator) async -> Bool
    private let onRestore: (Locator) async -> Bool
    private let onFinish: (Outcome) -> Void
    private let onDeferredCleanup: (Bool) -> Void
    private let haptics = QuickPositionJumpHaptics()
    private var session = QuickPositionJumpSession()
    private var originalLocator: Locator?
    private var currentPosition = 1
    private var targetPosition = 1
    private var activationX = 0.0
    private var activationY = 0.0
    private var horizontalRange = 0.0 ... 0.0
    private var commitTask: Task<Void, Never>?
    private var preparationTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var latestTouchPoint = CGPoint.zero
    private var preparationWasCancelled = false

    init(
        hostView: UIView,
        positionLabel: UILabel,
        currentLocator: @escaping () -> Locator?,
        onTap: @escaping () -> Void,
        onBegin: @escaping () async -> Void,
        onCommit: @escaping (Locator) async -> Bool,
        onRestore: @escaping (Locator) async -> Bool,
        onFinish: @escaping (Outcome) -> Void,
        onDeferredCleanup: @escaping (Bool) -> Void
    ) {
        self.hostView = hostView
        self.overlay = QuickPositionJumpOverlay(hostView: hostView, positionLabel: positionLabel)
        self.currentLocator = currentLocator
        self.onTap = onTap
        self.onBegin = onBegin
        self.onCommit = onCommit
        self.onRestore = onRestore
        self.onFinish = onFinish
        self.onDeferredCleanup = onDeferredCleanup
        super.init()

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        longPress.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.require(toFail: longPress)
        overlay.touchTarget.addGestureRecognizer(longPress)
        overlay.touchTarget.addGestureRecognizer(tap)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    func cancel() {
        guard session.state != .idle else { return }
        if session.state == .preparing {
            preparationWasCancelled = true
            return
        }
        guard originalLocator != nil else { return }
        if session.state == .committing {
            interruptCommit()
            return
        }
        commitTask?.cancel()
        finish(.cancelled)
    }

    @objc private func appDidEnterBackground() {
        cancel()
    }
    @objc private func handleTap() {
        guard session.state == .idle else { return }
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
        guard session.state == .idle,
              recoveryTask == nil,
              !positions.isEmpty,
              session.beginPreparing()
        else { return }

        latestTouchPoint = point
        preparationWasCancelled = false
        preparationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await onBegin()
            preparationTask = nil
            guard !preparationWasCancelled else {
                finish(.cancelled)
                return
            }
            activatePreview(at: latestTouchPoint)
        }
    }

    private func activatePreview(at point: CGPoint) {
        guard session.state == .preparing,
              let hostView,
              let locator = currentLocator()
        else {
            finish(.cancelled)
            return
        }

        let lowerBound = Double(hostView.safeAreaInsets.left + 20)
        let upperBound = Double(hostView.bounds.width - hostView.safeAreaInsets.right - 20)
        guard lowerBound < upperBound else {
            finish(.cancelled)
            return
        }

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
        guard session.beginPreview() else {
            finish(.cancelled)
            return
        }
        overlay.show(text: bubbleText())
    }

    private func update(with gesture: UILongPressGestureRecognizer) {
        if session.state == .preparing {
            latestTouchPoint = gesture.location(in: hostView)
            return
        }
        guard session.state == .previewing || session.state == .cancellationArmed,
              let hostView
        else { return }

        let verticalTranslation = Double(gesture.location(in: hostView).y) - activationY
        if QuickPositionJumpPolicy.isCancellationArmed(verticalTranslation: verticalTranslation) {
            if session.state != .cancellationArmed {
                session.setCancellationArmed(true)
                overlay.update(text: NSLocalizedString("reader_quick_position_cancel", comment: ""))
            }
            return
        }

        if session.state == .cancellationArmed {
            session.setCancellationArmed(false)
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
        if session.state == .preparing {
            preparationWasCancelled = true
            return
        }
        guard let originalLocator else { return }
        if session.state == .cancellationArmed {
            finish(.cancelled)
            return
        }
        guard session.state == .previewing else { return }

        let target = positions[targetPosition - 1]
        guard let taskGeneration = session.beginCommit() else { return }
        commitTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let succeeded = await onCommit(target)
            guard session.acceptsCompletion(for: taskGeneration) else { return }
            if succeeded {
                finish(.committed(target: target))
            } else {
                _ = await onRestore(originalLocator)
                guard session.acceptsCompletion(for: taskGeneration) else { return }
                haptics.notifyError()
                finish(.failed)
            }
        }
    }

    private func interruptCommit() {
        guard let originalLocator, let commitTask else { return }
        session.interruptCommit()
        commitTask.cancel()
        self.commitTask = nil
        self.originalLocator = nil
        haptics.reset()
        overlay.hide()
        onFinish(.interrupted)

        recoveryTask = Task { @MainActor [weak self] in
            await commitTask.value
            guard let self else { return }
            let restored = await onRestore(originalLocator)
            recoveryTask = nil
            onDeferredCleanup(restored)
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
        session.reset()
        preparationTask = nil
        commitTask = nil
        originalLocator = nil
        haptics.reset()
        overlay.hide()
        onFinish(outcome)
    }
}
