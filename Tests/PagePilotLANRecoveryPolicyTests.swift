import XCTest
@testable import PagePilot

final class PagePilotLANRecoveryPolicyTests: XCTestCase {
    func testKnownServicesAreReresolvedAfterEndpointInvalidation() {
        XCTAssertEqual(
            PagePilotLANRecoveryPolicy.action(knownServiceCount: 1, isBrowsing: true),
            .reresolveKnownServices
        )
    }

    func testBrowsingStartsWhenNoServiceIsKnownAndBrowserIsStopped() {
        XCTAssertEqual(
            PagePilotLANRecoveryPolicy.action(knownServiceCount: 0, isBrowsing: false),
            .startBrowsing
        )
    }

    func testActiveBrowseContinuesWhenNoServiceIsKnown() {
        XCTAssertEqual(
            PagePilotLANRecoveryPolicy.action(knownServiceCount: 0, isBrowsing: true),
            .continueBrowsing
        )
    }

    func testResolveFailureGetsTwoImmediateRetries() {
        XCTAssertTrue(PagePilotLANResolveRetryPolicy.shouldRetry(afterFailureCount: 1))
        XCTAssertTrue(PagePilotLANResolveRetryPolicy.shouldRetry(afterFailureCount: 2))
        XCTAssertFalse(PagePilotLANResolveRetryPolicy.shouldRetry(afterFailureCount: 3))
    }

    func testNormalResolveWaitsWhileSameServiceIsAlreadyResolving() {
        XCTAssertEqual(
            PagePilotLANResolveLifecyclePolicy.action(
                isResolving: true,
                forceRestart: false
            ),
            .wait
        )
    }

    func testStaleEndpointRecoveryStopsThenRestartsActiveResolve() {
        XCTAssertEqual(
            PagePilotLANResolveLifecyclePolicy.action(
                isResolving: true,
                forceRestart: true
            ),
            .stopThenRestart
        )
    }

    func testResolveStartsImmediatelyWhenServiceIsIdle() {
        XCTAssertEqual(
            PagePilotLANResolveLifecyclePolicy.action(
                isResolving: false,
                forceRestart: true
            ),
            .start
        )
    }

    func testFixedFallbackIsAllowedOnlyWithoutKnownBonjourServices() {
        XCTAssertTrue(
            PagePilotLANFallbackPolicy.shouldUseFallback(
                knownServiceCount: 0,
                fallbackWasInvalidated: false
            )
        )
        XCTAssertFalse(
            PagePilotLANFallbackPolicy.shouldUseFallback(
                knownServiceCount: 1,
                fallbackWasInvalidated: false
            )
        )
        XCTAssertFalse(
            PagePilotLANFallbackPolicy.shouldUseFallback(
                knownServiceCount: 0,
                fallbackWasInvalidated: true
            )
        )
    }

    func testConcurrentEndpointCallersShareOneLookupCycle() {
        var state = PagePilotLANLookupCycleState()

        let first = state.beginOrJoin()
        let second = state.beginOrJoin()

        XCTAssertTrue(first.isNew)
        XCTAssertFalse(second.isNew)
        XCTAssertEqual(first.id, second.id)
        XCTAssertTrue(state.isActive(first.id))
    }

    func testCompletedLookupTimerCannotFinishNextLookupInSameGeneration() {
        var state = PagePilotLANLookupCycleState()

        let first = state.beginOrJoin()
        XCTAssertTrue(state.finish(first.id))

        let second = state.beginOrJoin()
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertTrue(state.isActive(second.id))

        // Simulates the 3-second timeout from lookup A firing after lookup B
        // has already started. The stale timer must not finish B.
        XCTAssertFalse(state.finish(first.id))
        XCTAssertTrue(state.isActive(second.id))
    }

    func testCancelledLookupTimerCannotFinishReplacementCycle() {
        var state = PagePilotLANLookupCycleState()

        let first = state.beginOrJoin()
        state.cancel()
        let second = state.beginOrJoin()

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertFalse(state.isActive(first.id))

        // Simulates revoke/clear cancelling lookup A followed by a new lookup B.
        XCTAssertFalse(state.finish(first.id))
        XCTAssertTrue(state.isActive(second.id))
    }

    func testEndpointCandidateRejectsRemovedBonjourService() {
        let service = NSObject()
        let serviceID = ObjectIdentifier(service)
        let candidate = PagePilotLANEndpointCandidate(
            url: URL(string: "http://192.0.2.1:61482")!,
            generation: 4,
            source: .bonjour(serviceID)
        )

        XCTAssertFalse(
            PagePilotLANEndpointCandidatePolicy.isCurrent(
                candidate,
                currentGeneration: 4,
                knownServiceIDs: [],
                knownServiceCount: 0,
                fallbackWasInvalidated: false
            )
        )
    }

    func testEndpointCandidateRejectsPreviousDiscoveryGeneration() {
        let candidate = PagePilotLANEndpointCandidate(
            url: URL(string: "http://iPad.local:61482")!,
            generation: 4,
            source: .fallback
        )

        XCTAssertFalse(
            PagePilotLANEndpointCandidatePolicy.isCurrent(
                candidate,
                currentGeneration: 5,
                knownServiceIDs: [],
                knownServiceCount: 0,
                fallbackWasInvalidated: false
            )
        )
    }

    func testFallbackCandidateCannotOverrideKnownBonjourService() {
        let candidate = PagePilotLANEndpointCandidate(
            url: URL(string: "http://iPad.local:61482")!,
            generation: 5,
            source: .fallback
        )

        XCTAssertFalse(
            PagePilotLANEndpointCandidatePolicy.isCurrent(
                candidate,
                currentGeneration: 5,
                knownServiceIDs: [],
                knownServiceCount: 1,
                fallbackWasInvalidated: false
            )
        )
    }

    func testInvalidatedFallbackCandidateIsRejected() {
        let candidate = PagePilotLANEndpointCandidate(
            url: URL(string: "http://iPad.local:61482")!,
            generation: 5,
            source: .fallback
        )

        XCTAssertFalse(
            PagePilotLANEndpointCandidatePolicy.isCurrent(
                candidate,
                currentGeneration: 5,
                knownServiceIDs: [],
                knownServiceCount: 0,
                fallbackWasInvalidated: true
            )
        )
    }
}
