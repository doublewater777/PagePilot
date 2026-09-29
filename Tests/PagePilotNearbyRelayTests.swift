import Foundation
import XCTest
@testable import PagePilot

final class PagePilotNearbyRelayTests: XCTestCase {
    private let firstID = "11111111-1111-1111-1111-111111111111"
    private let secondID = "22222222-2222-2222-2222-222222222222"

    func testNearbyRelayFrameRoundTripsJSON() throws {
        let encoded = try PagePilotNearbyRelayFrame.encode([
            "targetIdentifier": firstID,
            "path": "command",
            "method": "POST",
            "body": [
                "action": "next",
                "requestId": "request-1"
            ]
        ])

        XCTAssertEqual(encoded.last, 0x0A)

        let decoded = try PagePilotNearbyRelayFrame.decode(encoded)
        XCTAssertEqual(decoded["targetIdentifier"] as? String, firstID)
        XCTAssertEqual(decoded["path"] as? String, "command")
        XCTAssertEqual(decoded["method"] as? String, "POST")

        let body = try XCTUnwrap(decoded["body"] as? [String: Any])
        XCTAssertEqual(body["action"] as? String, "next")
        XCTAssertEqual(body["requestId"] as? String, "request-1")
    }

    func testNearbyRelayFrameRejectsUnterminatedPayload() throws {
        let data = try JSONSerialization.data(withJSONObject: ["path": "status"])
        XCTAssertThrowsError(try PagePilotNearbyRelayFrame.decode(data))
    }

    func testFragmentedFrameCompletesOnlyAfterNewlineArrives() throws {
        let encoded = try PagePilotNearbyRelayFrame.encode([
            "path": "status",
            "method": "GET"
        ])
        let split = encoded.count / 2
        var buffer = PagePilotNearbyFrameBuffer()

        switch try buffer.append(encoded.prefix(split)) {
        case .incomplete:
            break
        case .complete:
            XCTFail("first fragment must remain incomplete")
        }

        switch try buffer.append(encoded.suffix(from: split)) {
        case .incomplete:
            XCTFail("second fragment should complete the frame")
        case .complete(let decoded):
            XCTAssertEqual(decoded["path"] as? String, "status")
            XCTAssertEqual(decoded["method"] as? String, "GET")
        }
    }

    func testOversizedFrameIsRejected() {
        var buffer = PagePilotNearbyFrameBuffer()
        let oversized = Data(
            repeating: 0x61,
            count: PagePilotNearbyRelayFrame.maximumBytes + 1
        )

        XCTAssertThrowsError(try buffer.append(oversized))
    }

    func testOnlyExactNearbyMethodPathPairsAreAccepted() {
        XCTAssertTrue(PagePilotNearbyRequestValidator.isValid(path: "status", method: "GET"))
        XCTAssertTrue(PagePilotNearbyRequestValidator.isValid(path: "command", method: "POST"))
        XCTAssertFalse(PagePilotNearbyRequestValidator.isValid(path: "status", method: "POST"))
        XCTAssertFalse(PagePilotNearbyRequestValidator.isValid(path: "command", method: "GET"))
    }

    func testStableIdentityRoundTripsThroughBonjourServiceName() {
        let serviceName = PagePilotRelayIdentity.serviceName(for: firstID)

        XCTAssertEqual(
            PagePilotRelayIdentity.identifier(fromServiceName: serviceName),
            firstID.lowercased()
        )
        XCTAssertNil(PagePilotRelayIdentity.identifier(fromServiceName: "PagePilot-iPad"))
        XCTAssertNil(PagePilotRelayIdentity.identifier(fromServiceName: "PagePilot-iPad-not-a-uuid"))
    }

    func testMultipleNearbyPeersSelectOnlyAssociatedTarget() {
        let first = PagePilotRelayIdentity.serviceName(for: firstID)
        let second = PagePilotRelayIdentity.serviceName(for: secondID)

        XCTAssertEqual(
            PagePilotNearbyTargetSelectionPolicy.selectServiceName(
                from: [second, first],
                expectedIdentifier: firstID
            ),
            first
        )
        XCTAssertEqual(
            PagePilotNearbyTargetSelectionPolicy.selectServiceName(
                from: [first, second],
                expectedIdentifier: secondID
            ),
            second
        )
    }

    func testNoAssociatedTargetNeverSelectsArbitraryNearbyPeer() {
        let serviceNames = [
            PagePilotRelayIdentity.serviceName(for: firstID),
            PagePilotRelayIdentity.serviceName(for: secondID)
        ]

        XCTAssertNil(
            PagePilotNearbyTargetSelectionPolicy.selectServiceName(
                from: serviceNames,
                expectedIdentifier: nil
            )
        )
    }

    func testNearbyDirectPrecedesOnlyLegacyFixedLANFallback() {
        XCTAssertTrue(
            PagePilotRelayTransportPolicy.shouldTryNearbyBeforeLAN(.fallback)
        )

        let service = NSObject()
        XCTAssertFalse(
            PagePilotRelayTransportPolicy.shouldTryNearbyBeforeLAN(
                .bonjour(ObjectIdentifier(service))
            )
        )
    }

    func testResolvedBonjourLANRemainsInitialRoute() {
        let service = NSObject()
        XCTAssertEqual(
            PagePilotRelayRoutingPolicy.initialStep(
                candidateSource: .bonjour(ObjectIdentifier(service)),
                hasNearbyTarget: true
            ),
            .lan
        )
    }

    func testFixedFallbackUsesNearbyFirstWhenAssociatedTargetExists() {
        XCTAssertEqual(
            PagePilotRelayRoutingPolicy.initialStep(
                candidateSource: .fallback,
                hasNearbyTarget: true
            ),
            .nearby
        )
    }

    func testFixedFallbackStaysLANWhenNoAssociatedTargetExists() {
        XCTAssertEqual(
            PagePilotRelayRoutingPolicy.initialStep(
                candidateSource: .fallback,
                hasNearbyTarget: false
            ),
            .lan
        )
    }

    func testNoLANCandidateUsesNearbyOnlyForKnownTarget() {
        XCTAssertEqual(
            PagePilotRelayRoutingPolicy.initialStep(
                candidateSource: nil,
                hasNearbyTarget: true
            ),
            .nearby
        )
        XCTAssertEqual(
            PagePilotRelayRoutingPolicy.initialStep(
                candidateSource: nil,
                hasNearbyTarget: false
            ),
            .failNotFound
        )
    }

    func testFinalFreshLANRetryDoesNotLoopBackToNearby() {
        XCTAssertEqual(
            PagePilotRelayRoutingPolicy.initialStep(
                candidateSource: nil,
                hasNearbyTarget: true,
                allowNearby: false
            ),
            .failNotFound
        )

        XCTAssertEqual(
            PagePilotRelayRoutingPolicy.initialStep(
                candidateSource: .fallback,
                hasNearbyTarget: true,
                allowNearby: false
            ),
            .lan
        )
    }

    func testBonjourLANFailureTransitionsNearbyThenFreshLAN() {
        XCTAssertEqual(
            PagePilotRelayRoutingPolicy.stepAfterLANFailure(hasNearbyTarget: true),
            .nearby
        )
        XCTAssertEqual(
            PagePilotRelayRoutingPolicy.stepAfterNearbyFailure(hasLANFallback: true),
            .lan
        )
    }

    func testFixedFallbackNearbyFailureReturnsToLANFallback() {
        XCTAssertEqual(
            PagePilotRelayRoutingPolicy.initialStep(
                candidateSource: .fallback,
                hasNearbyTarget: true
            ),
            .nearby
        )
        XCTAssertEqual(
            PagePilotRelayRoutingPolicy.stepAfterNearbyFailure(hasLANFallback: true),
            .lan
        )
    }

    func testNearbyFailureWithoutLANFallbackEndsNotFound() {
        XCTAssertEqual(
            PagePilotRelayRoutingPolicy.stepAfterNearbyFailure(hasLANFallback: false),
            .failNotFound
        )
    }

    func testNearbyErrorMappingSeparatesDiscoveryTransportAndAuthorization() {
        XCTAssertEqual(
            PagePilotNearbyWatchFailurePolicy.failure(for: PagePilotNearbyRelayError.noService),
            .iPadNotFound
        )
        XCTAssertEqual(
            PagePilotNearbyWatchFailurePolicy.failure(for: PagePilotNearbyRelayError.timedOut),
            .relayTimeout
        )
        XCTAssertEqual(
            PagePilotNearbyWatchFailurePolicy.failure(
                for: PagePilotNearbyRelayError.connectionFailed("offline")
            ),
            .relayTimeout
        )
        XCTAssertEqual(
            PagePilotNearbyWatchFailurePolicy.failure(for: PagePilotNearbyRelayError.invalidMessage),
            .relayTimeout
        )
        XCTAssertEqual(
            PagePilotNearbyWatchFailurePolicy.failure(
                for: PagePilotNearbyRelayError.authorizationRevoked
            ),
            .proRequired
        )
    }

    func testTargetSelectionStopsBrowserBeforeConnectionAndKeepsCachedEndpoint() {
        var state = PagePilotNearbyLifecycleState()
        _ = state.handle(.browserStarted)

        XCTAssertTrue(state.isBrowsing)

        let actions = state.handle(.targetSelected)

        XCTAssertEqual(actions, [.stopBrowser, .flushPending])
        XCTAssertFalse(state.isBrowsing)
        XCTAssertTrue(state.hasCachedEndpoint)
    }

    func testConnectionFailureInvalidatesCachedEndpoint() {
        var state = PagePilotNearbyLifecycleState()
        state.cacheEndpoint()

        let actions = state.handle(.connectionFailed)

        XCTAssertEqual(actions, [.clearEndpoint])
        XCTAssertFalse(state.hasCachedEndpoint)
    }

    func testLANSuccessCancelsPreparedBrowseWithoutDroppingCachedEndpoint() {
        var state = PagePilotNearbyLifecycleState()
        _ = state.handle(.browserStarted)
        state.cacheEndpoint()

        let actions = state.handle(.stop(clearEndpoint: false))

        XCTAssertEqual(actions, [.stopBrowser, .flushPending])
        XCTAssertFalse(state.isBrowsing)
        XCTAssertTrue(state.hasCachedEndpoint)
    }

    func testEntitlementRevokeStopsBrowseAndDropsCachedEndpoint() {
        var state = PagePilotNearbyLifecycleState()
        _ = state.handle(.browserStarted)
        state.cacheEndpoint()

        let actions = state.handle(.stop(clearEndpoint: true))

        XCTAssertEqual(actions, [.stopBrowser, .clearEndpoint, .flushPending])
        XCTAssertFalse(state.isBrowsing)
        XCTAssertFalse(state.hasCachedEndpoint)
    }

    func testBrowserFailureStopsAndFlushesPendingLookup() {
        var state = PagePilotNearbyLifecycleState()
        _ = state.handle(.browserStarted)

        let actions = state.handle(.browserFailed)

        XCTAssertEqual(actions, [.stopBrowser, .flushPending])
        XCTAssertFalse(state.isBrowsing)
    }

    func testListenerFailureClearsOnlyCurrentListener() {
        XCTAssertTrue(
            PagePilotNearbyListenerFailurePolicy.shouldClearListener(callbackIsCurrent: true)
        )
        XCTAssertFalse(
            PagePilotNearbyListenerFailurePolicy.shouldClearListener(callbackIsCurrent: false)
        )
    }

    func testPendingNearbyRequestCancelsWhenProIsLost() {
        XCTAssertEqual(
            PagePilotNearbyPendingRequestPolicy.action(hasProAccess: true),
            .proceed
        )
        XCTAssertEqual(
            PagePilotNearbyPendingRequestPolicy.action(hasProAccess: false),
            .cancel
        )
        XCTAssertFalse(
            PagePilotNearbyPendingRequestPolicy.shouldProceed(hasProAccess: false)
        )
    }

    func testIPadRelayEntitlementStartsAndStopsServerLifecycle() {
        XCTAssertEqual(
            PagePilotRelayEntitlementLifecyclePolicy.action(
                isIPad: true,
                hasProAccess: true
            ),
            .start
        )
        XCTAssertEqual(
            PagePilotRelayEntitlementLifecyclePolicy.action(
                isIPad: true,
                hasProAccess: false
            ),
            .stop
        )
        XCTAssertEqual(
            PagePilotRelayEntitlementLifecyclePolicy.action(
                isIPad: false,
                hasProAccess: true
            ),
            .noOp
        )
    }
}
