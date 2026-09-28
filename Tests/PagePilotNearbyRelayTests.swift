import Foundation
import XCTest
@testable import PagePilot

final class PagePilotNearbyRelayTests: XCTestCase {
    func testNearbyRelayFrameRoundTripsJSON() throws {
        let encoded = try PagePilotNearbyRelayFrame.encode([
            "path": "command",
            "method": "POST",
            "body": [
                "action": "next",
                "requestId": "request-1"
            ]
        ])

        XCTAssertEqual(encoded.last, 0x0A)

        let decoded = try PagePilotNearbyRelayFrame.decode(encoded)
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
}
