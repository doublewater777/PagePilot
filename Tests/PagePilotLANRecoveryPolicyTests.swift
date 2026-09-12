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
}
