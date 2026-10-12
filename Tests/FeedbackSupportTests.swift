import XCTest
@testable import PagePilot

final class FeedbackSupportTests: XCTestCase {
    private let builder = FeedbackPayloadBuilder(appVersion: "1.0.22", osVersion: "iOS 26")

    func testTrimsMessageAndIncludesDiagnostics() throws {
        let payload = try builder.build(message: " \n建议\n ")
        XCTAssertEqual(payload.message, "建议")
        XCTAssertEqual(payload.appVersion, "1.0.22")
        XCTAssertEqual(payload.osVersion, "iOS 26")
    }

    func testRejectsWhitespaceOnlyMessage() {
        XCTAssertThrowsError(try builder.build(message: " \n\t ")) {
            XCTAssertEqual($0 as? FeedbackValidationError, .emptyMessage)
        }
    }

    func testCountsUnicodeScalarsLikeServer() throws {
        XCTAssertEqual(FeedbackPayloadBuilder.messageLength("👨‍👩‍👧‍👦"), 7)
        XCTAssertNoThrow(try builder.build(message: String(repeating: "😀", count: 2000)))
        XCTAssertThrowsError(try builder.build(message: String(repeating: "😀", count: 2001))) {
            XCTAssertEqual($0 as? FeedbackValidationError, .messageTooLong)
        }
        XCTAssertThrowsError(try builder.build(message: String(repeating: " ", count: 2000) + "a"))
    }

    func testEmailLinkCarriesAddressSubjectMessageAndDeviceInfo() throws {
        let url = try XCTUnwrap(FeedbackEmail.mailtoURL(message: "  翻页卡住了 & ?  "))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "mailto")
        XCTAssertEqual(components.path, FeedbackEmail.address)
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertFalse(items["subject", default: ""].isEmpty)
        let body = items["body", default: ""]
        XCTAssertTrue(body.hasPrefix("翻页卡住了 & ?"))
        XCTAssertTrue(body.contains("PagePilot"))
    }
}
