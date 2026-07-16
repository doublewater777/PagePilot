import Foundation

enum QuickPositionJumpPolicy {
    static func percentage(
        totalProgression: Double?,
        targetPosition: Int,
        positionCount: Int
    ) -> Int {
        let progression: Double
        if let totalProgression, totalProgression.isFinite {
            progression = totalProgression
        } else if positionCount > 1 {
            progression = Double(targetPosition - 1) / Double(positionCount - 1)
        } else {
            progression = 1
        }
        return Int((max(0, min(1, progression)) * 100).rounded())
    }

    static func isCancellationArmed(verticalTranslation: Double) -> Bool {
        verticalTranslation <= -60
    }

    static func hapticDetent(
        position: Int,
        positionCount: Int,
        maxDetents: Int = 50
    ) -> Int {
        guard positionCount > 1, maxDetents > 1 else { return 0 }
        let clampedPosition = max(1, min(positionCount, position))
        let detentCount = min(positionCount, maxDetents)
        let progress = Double(clampedPosition - 1) / Double(positionCount - 1)
        return Int((progress * Double(detentCount - 1)).rounded())
    }

    static func targetPosition(
        currentPosition: Int,
        positionCount: Int,
        activationX: Double,
        currentX: Double,
        horizontalRange: ClosedRange<Double>
    ) -> Int {
        if currentX < activationX {
            let width = activationX - horizontalRange.lowerBound
            guard width > 0 else { return 1 }
            let progress = (currentX - horizontalRange.lowerBound) / width
            let target = 1 + Int((Double(currentPosition - 1) * progress).rounded())
            return max(1, min(positionCount, target))
        }
        if currentX > activationX {
            let width = horizontalRange.upperBound - activationX
            guard width > 0 else { return positionCount }
            let progress = (currentX - activationX) / width
            let target = currentPosition + Int((Double(positionCount - currentPosition) * progress).rounded())
            return max(1, min(positionCount, target))
        }
        return currentPosition
    }
}
