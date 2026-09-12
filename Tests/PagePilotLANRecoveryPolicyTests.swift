import Foundation
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

    func testBonjourCandidateIsRejectedAfterItsServiceIsRemoved() throws {
        let service = NSObject()
        let serviceID = ObjectIdentifier(service)
        let candidate = PagePilotLANEndpointCandidate(
            url: try XCTUnwrap(URL(string: "http://192.168.1.20:61482")),
            generation: 4,
            source: .bonjour(serviceID)
        )

        XCTAssertTrue(PagePilotLANEndpointCandidatePolicy.isCurrent(
            candidate,
            currentGeneration: 4,
            knownServiceIDs: [serviceID],
            knownServiceCount: 1,
            fallbackWasInvalidated: false
        ))
        XCTAssertFalse(PagePilotLANEndpointCandidatePolicy.isCurrent(
            candidate,
            currentGeneration: 4,
            knownServiceIDs: [],
            knownServiceCount: 0,
            fallbackWasInvalidated: false
        ))
    }

    func testEndpointCandidateIsRejectedAfterDiscoveryGenerationChanges() throws {
        let service = NSObject()
        let serviceID = ObjectIdentifier(service)
        let candidate = PagePilotLANEndpointCandidate(
            url: try XCTUnwrap(URL(string: "http://192.168.1.20:61482")),
            generation: 7,
            source: .bonjour(serviceID)
        )

        XCTAssertFalse(PagePilotLANEndpointCandidatePolicy.isCurrent(
            candidate,
            currentGeneration: 8,
            knownServiceIDs: [serviceID],
            knownServiceCount: 1,
            fallbackWasInvalidated: false
        ))
    }

    func testFallbackCandidateCannotOverrideKnownBonjourService() throws {
        let service = NSObject()
        let candidate = PagePilotLANEndpointCandidate(
            url: try XCTUnwrap(URL(string: "http://iPad.local:61482")),
            generation: 2,
            source: .fallback
        )

        XCTAssertTrue(PagePilotLANEndpointCandidatePolicy.isCurrent(
            candidate,
            currentGeneration: 2,
            knownServiceIDs: [],
            knownServiceCount: 0,
            fallbackWasInvalidated: false
        ))
        XCTAssertFalse(PagePilotLANEndpointCandidatePolicy.isCurrent(
            candidate,
            currentGeneration: 2,
            knownServiceIDs: [ObjectIdentifier(service)],
            knownServiceCount: 1,
            fallbackWasInvalidated: false
        ))
    }

    func testInvalidatedFallbackCandidateCannotBeRemembered() throws {
        let candidate = PagePilotLANEndpointCandidate(
            url: try XCTUnwrap(URL(string: "http://iPad.local:61482")),
            generation: 3,
            source: .fallback
        )

        XCTAssertFalse(PagePilotLANEndpointCandidatePolicy.isCurrent(
            candidate,
            currentGeneration: 3,
            knownServiceIDs: [],
            knownServiceCount: 0,
            fallbackWasInvalidated: true
        ))
    }
}
