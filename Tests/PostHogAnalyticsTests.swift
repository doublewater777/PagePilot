//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import XCTest
@testable import PagePilot

final class PostHogAnalyticsTests: XCTestCase {

    final class MockURLProtocol: URLProtocol {
        static var lastRequest: URLRequest?
        static var lastRequestBody: [String: Any]?
        static var responseStatusCode: Int = 200

        override class func canInit(with request: URLRequest) -> Bool {
            return true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            return request
        }

        override func startLoading() {
            Self.lastRequest = request

            if let bodyData = request.httpBody ?? request.httpBodyStreamData() {
                if let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                    Self.lastRequestBody = json
                }
            }

            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://us.i.posthog.com")!,
                statusCode: Self.responseStatusCode,
                httpVersion: nil,
                headerFields: nil
            )!

            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{\"status\":\"ok\"}".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        static func reset() {
            lastRequest = nil
            lastRequestBody = nil
            responseStatusCode = 200
        }
    }

    private var mockSession: URLSession!
    private var testUserDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        mockSession = URLSession(configuration: config)

        testUserDefaults = UserDefaults(suiteName: "PostHogAnalyticsTests")!
        testUserDefaults.removePersistentDomain(forName: "PostHogAnalyticsTests")
    }

    override func tearDown() {
        testUserDefaults.removePersistentDomain(forName: "PostHogAnalyticsTests")
        super.tearDown()
    }

    func testDefaultConfigurationResolvesGracefully() {
        let config = PostHogConfiguration.resolveFromEnvironment()
        XCTAssertNotNil(config.host)
        XCTAssertTrue(config.isEnabled)
    }

    func testDistinctIdPersistenceAndReset() {
        let client = PostHogAnalytics(
            configuration: PostHogConfiguration(apiKey: "test_ph_key"),
            session: mockSession,
            userDefaults: testUserDefaults
        )

        let id1 = client.distinctId
        XCTAssertFalse(id1.isEmpty)

        let id2 = client.distinctId
        XCTAssertEqual(id1, id2)

        client.reset()
        let id3 = client.distinctId
        XCTAssertNotEqual(id1, id3)
    }

    func testCaptureDispatchesValidPostHogPayload() {
        let expectation = expectation(description: "Event dispatched")

        let client = PostHogAnalytics(
            configuration: PostHogConfiguration(
                apiKey: "phc_test_12345",
                host: URL(string: "https://us.i.posthog.com")!,
                isEnabled: true,
                debugLogging: false
            ),
            session: mockSession,
            userDefaults: testUserDefaults
        )

        client.capture("test_conversion_event", properties: [
            "button_name": "upgrade_now",
            "tier": "pro_yearly"
        ])

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            XCTAssertNotNil(MockURLProtocol.lastRequest)
            XCTAssertEqual(MockURLProtocol.lastRequest?.httpMethod, "POST")
            XCTAssertEqual(MockURLProtocol.lastRequest?.url?.path, "/capture")
            XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let body = MockURLProtocol.lastRequestBody
            XCTAssertNotNil(body)
            XCTAssertEqual(body?["api_key"] as? String, "phc_test_12345")
            XCTAssertEqual(body?["event"] as? String, "test_conversion_event")
            XCTAssertEqual(body?["distinct_id"] as? String, client.distinctId)

            let props = body?["properties"] as? [String: Any]
            XCTAssertNotNil(props)
            XCTAssertEqual(props?["button_name"] as? String, "upgrade_now")
            XCTAssertEqual(props?["tier"] as? String, "pro_yearly")
            XCTAssertEqual(props?["$lib"] as? String, "posthog-ios-light")
            XCTAssertNotNil(props?["$os"])
            XCTAssertNotNil(props?["is_duo"])

            expectation.fulfill()
        }

        waitForExpectations(timeout: 2.0)
    }

    func testNotificationCenterObserverForwardsToPostHog() {
        let expectation = expectation(description: "Notification caught and dispatched")

        let client = PostHogAnalytics(
            configuration: PostHogConfiguration(
                apiKey: "phc_observer_test",
                host: URL(string: "https://us.i.posthog.com")!,
                isEnabled: true,
                debugLogging: false
            ),
            session: mockSession,
            userDefaults: testUserDefaults
        )
        client.startObserving()

        // Trigger existing app event
        Analytics.shared.log(.paywallViewed(source: "unit_test_source"))

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            let body = MockURLProtocol.lastRequestBody
            XCTAssertNotNil(body)
            XCTAssertEqual(body?["event"] as? String, "paywall_viewed")

            let props = body?["properties"] as? [String: Any]
            XCTAssertEqual(props?["source"] as? String, "unit_test_source")

            client.stopObserving()
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2.0)
    }

    func testSendTestEventWorksWithoutApiKeyInSimulatedMode() {
        let client = PostHogAnalytics(
            configuration: PostHogConfiguration(
                apiKey: nil, // simulated mode
                host: URL(string: "https://us.i.posthog.com")!,
                isEnabled: true,
                debugLogging: true
            ),
            session: mockSession,
            userDefaults: testUserDefaults
        )

        let testId = client.sendTestEvent(context: "simulated_test")
        XCTAssertFalse(testId.isEmpty)
        // In simulated mode, no network request is sent
        XCTAssertNil(MockURLProtocol.lastRequest)
    }

    func testRecordPostureChangeCapturesDuoFoldAndUnfoldStates() {
        let expectation = expectation(description: "Posture dispatched")

        let client = PostHogAnalytics(
            configuration: PostHogConfiguration(
                apiKey: "phc_posture_test",
                host: URL(string: "https://us.i.posthog.com")!,
                isEnabled: true,
                debugLogging: false
            ),
            session: mockSession,
            userDefaults: testUserDefaults
        )

        // Test unfolded iPhone Duo (669 x 951)
        client.recordPostureChange(size: CGSize(width: 669, height: 951))

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            let body = MockURLProtocol.lastRequestBody
            XCTAssertNotNil(body)
            XCTAssertEqual(body?["event"] as? String, "duo_posture_changed")

            let props = body?["properties"] as? [String: Any]
            XCTAssertEqual(props?["duo_state"] as? String, "unfolded")
            XCTAssertEqual(props?["width"] as? Double, 669)
            XCTAssertEqual(props?["height"] as? Double, 951)

            expectation.fulfill()
        }

        waitForExpectations(timeout: 2.0)
    }
}

private extension URLRequest {
    func httpBodyStreamData() -> Data? {
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read > 0 {
                data.append(buffer, count: read)
            } else {
                break
            }
        }
        return data
    }
}
