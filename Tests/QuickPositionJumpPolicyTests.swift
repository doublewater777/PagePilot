import XCTest
@testable import PagePilot

final class QuickPositionJumpPolicyTests: XCTestCase {
    func testTargetPositionRemainsCurrentWhenFingerDoesNotMove() {
        // Given
        let currentPosition = 286

        // When
        let target = QuickPositionJumpPolicy.targetPosition(
            currentPosition: currentPosition,
            positionCount: 420,
            activationX: 200,
            currentX: 200,
            horizontalRange: 20 ... 380
        )

        // Then
        XCTAssertEqual(target, currentPosition)
    }

    func testTargetPositionReachesFirstPositionAtLeftBoundary() {
        // Given
        let horizontalRange = 20.0 ... 380.0

        // When
        let target = QuickPositionJumpPolicy.targetPosition(
            currentPosition: 286,
            positionCount: 420,
            activationX: 200,
            currentX: horizontalRange.lowerBound,
            horizontalRange: horizontalRange
        )

        // Then
        XCTAssertEqual(target, 1)
    }

    func testTargetPositionReachesLastPositionAtRightBoundary() {
        // Given
        let horizontalRange = 20.0 ... 380.0

        // When
        let target = QuickPositionJumpPolicy.targetPosition(
            currentPosition: 286,
            positionCount: 420,
            activationX: 200,
            currentX: horizontalRange.upperBound,
            horizontalRange: horizontalRange
        )

        // Then
        XCTAssertEqual(target, 420)
    }

    func testTargetPositionClampsBeyondLeftBoundary() {
        // Given
        let horizontalRange = 20.0 ... 380.0

        // When
        let target = QuickPositionJumpPolicy.targetPosition(
            currentPosition: 286,
            positionCount: 420,
            activationX: 200,
            currentX: -100,
            horizontalRange: horizontalRange
        )

        // Then
        XCTAssertEqual(target, 1)
    }

    func testTargetPositionClampsBeyondRightBoundary() {
        let target = QuickPositionJumpPolicy.targetPosition(
            currentPosition: 286,
            positionCount: 420,
            activationX: 200,
            currentX: 500,
            horizontalRange: 20 ... 380
        )

        XCTAssertEqual(target, 420)
    }

    func testSinglePositionPublicationAlwaysTargetsOne() {
        let target = QuickPositionJumpPolicy.targetPosition(
            currentPosition: 1,
            positionCount: 1,
            activationX: 20,
            currentX: 380,
            horizontalRange: 20 ... 380
        )

        XCTAssertEqual(target, 1)
    }

    func testActivationAtRightBoundaryStillReachesFirstPosition() {
        let target = QuickPositionJumpPolicy.targetPosition(
            currentPosition: 420,
            positionCount: 420,
            activationX: 380,
            currentX: 20,
            horizontalRange: 20 ... 380
        )

        XCTAssertEqual(target, 1)
    }

    func testHapticDetentsAreLimitedToFiftyForLongPublications() {
        // Given
        let positions = 1 ... 1_000

        // When
        let detents = positions.map {
            QuickPositionJumpPolicy.hapticDetent(
                position: $0,
                positionCount: positions.count
            )
        }

        // Then
        XCTAssertEqual(Set(detents).count, 50)
        XCTAssertEqual(detents.first, 0)
        XCTAssertEqual(detents.last, 49)
    }

    func testCancellationRemainsDisarmedBeforeSixtyPoints() {
        // Given
        let verticalTranslation = -59.0

        // When
        let isArmed = QuickPositionJumpPolicy.isCancellationArmed(
            verticalTranslation: verticalTranslation
        )

        // Then
        XCTAssertFalse(isArmed)
    }

    func testCancellationArmsAtSixtyPointsUpward() {
        // Given
        let verticalTranslation = -60.0

        // When
        let isArmed = QuickPositionJumpPolicy.isCancellationArmed(
            verticalTranslation: verticalTranslation
        )

        // Then
        XCTAssertTrue(isArmed)
    }

    func testPercentagePrefersLocatorTotalProgression() {
        // Given
        let totalProgression = 0.678

        // When
        let percentage = QuickPositionJumpPolicy.percentage(
            totalProgression: totalProgression,
            targetPosition: 1,
            positionCount: 420
        )

        // Then
        XCTAssertEqual(percentage, 68)
    }

    func testPercentageFallsBackToPositionRatio() {
        // Given
        let targetPosition = 210

        // When
        let percentage = QuickPositionJumpPolicy.percentage(
            totalProgression: nil,
            targetPosition: targetPosition,
            positionCount: 420
        )

        // Then
        XCTAssertEqual(percentage, 50)
    }

    func testPercentageClampsOutOfRangeProgression() {
        XCTAssertEqual(
            QuickPositionJumpPolicy.percentage(
                totalProgression: 1.5,
                targetPosition: 1,
                positionCount: 420
            ),
            100
        )
    }

    func testPercentageFallsBackWhenProgressionIsNotFinite() {
        XCTAssertEqual(
            QuickPositionJumpPolicy.percentage(
                totalProgression: .nan,
                targetPosition: 210,
                positionCount: 420
            ),
            50
        )
    }
}
