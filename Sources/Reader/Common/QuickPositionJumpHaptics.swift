import UIKit

@MainActor
final class QuickPositionJumpHaptics {
    private let activation = UIImpactFeedbackGenerator(style: .light)
    private let boundary = UIImpactFeedbackGenerator(style: .medium)
    private let selection = UISelectionFeedbackGenerator()
    private let error = UINotificationFeedbackGenerator()
    private var lastDetent: Int?
    private var lastBoundaryPosition: Int?

    func begin(position: Int, positionCount: Int) {
        lastDetent = QuickPositionJumpPolicy.hapticDetent(
            position: position,
            positionCount: positionCount
        )
        lastBoundaryPosition = nil
        activation.prepare()
        selection.prepare()
        boundary.prepare()
        activation.impactOccurred()
    }

    func moved(to position: Int, positionCount: Int) {
        if position == 1 || position == positionCount {
            guard lastBoundaryPosition != position else { return }
            lastBoundaryPosition = position
            lastDetent = QuickPositionJumpPolicy.hapticDetent(
                position: position,
                positionCount: positionCount
            )
            boundary.impactOccurred()
            boundary.prepare()
            return
        }
        lastBoundaryPosition = nil
        let detent = QuickPositionJumpPolicy.hapticDetent(
            position: position,
            positionCount: positionCount
        )
        guard detent != lastDetent else { return }
        lastDetent = detent
        selection.selectionChanged()
        selection.prepare()
    }

    func notifyError() {
        error.notificationOccurred(.error)
    }

    func reset() {
        lastDetent = nil
        lastBoundaryPosition = nil
    }
}
