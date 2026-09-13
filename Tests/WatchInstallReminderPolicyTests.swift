import XCTest
@testable import PagePilot

final class WatchInstallReminderPolicyTests: XCTestCase {
    func testGuideShowsRegardlessOfOnboardingProgress() {
        XCTAssertTrue(WatchGuideEligibility.shouldShow(isPhone: true))
    }

    func testGuideNeverShowsOnIPad() {
        XCTAssertFalse(WatchGuideEligibility.shouldShow(isPhone: false))
    }

    func testCompletedOnboardingStillShowsGuide() {
        var flow = OnboardingFlow(platform: .iPhone)
        flow.didChoosePublication(bookID: 42, source: .user)
        flow.finish()

        XCTAssertEqual(flow.step, .completed)
        XCTAssertTrue(
            flow.shouldShowWatchGuide,
            "Watch install guidance is a device-state concern, not a one-time onboarding step."
        )
    }

    func testVisualReaderDecidesGuideFromSessionState() throws {
        let source = try Self.visualReaderSource()

        let guideEntry = try Self.requiredLine("showOnboardingWatchGuideIfNeeded()", in: source)
        let availabilityRead = try Self.requiredLine(
            "WatchPageTurnService.shared.watchAvailability",
            in: source,
            startingAfter: guideEntry
        )
        XCTAssertGreaterThan(availabilityRead, guideEntry)

        XCTAssertNil(
            Self.range(of: "flow.shouldShowWatchGuide", in: source, startingAfter: guideEntry),
            "Reader guide visibility must follow Watch device state, not onboarding progress."
        )
    }

    func testWatchSettingsOfferInstallActionWhenAppIsMissing() throws {
        let source = try Self.watchSettingsSource()

        let availabilityCheck = try Self.requiredLine("watchAvailability == .appNotInstalled", in: source)
        let openCall = try Self.requiredLine(
            "WatchPageTurnService.watchAppURL",
            in: source,
            startingAfter: availabilityCheck
        )
        let installAction = try Self.requiredLine(
            "onboarding_watch_install_action",
            in: source,
            startingAfter: availabilityCheck
        )

        XCTAssertGreaterThan(openCall, availabilityCheck)
        XCTAssertGreaterThan(installAction, availabilityCheck)
    }

    private static func visualReaderSource() throws -> String {
        try Self.source(named: "Sources/Reader/Common/VisualReaderViewController.swift")
    }

    private static func watchSettingsSource() throws -> String {
        try Self.source(named: "Sources/Me/WatchSettingsView.swift")
    }

    private static func source(named path: String) throws -> String {
        let repositoryURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryURL.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private static func requiredLine(
        _ line: String,
        in source: String,
        startingAfter offset: Int = 0,
        file: StaticString = #filePath,
        lineNumber: UInt = #line
    ) throws -> Int {
        guard let position = self.range(of: line, in: source, startingAfter: offset) else {
            XCTFail("Required source boundary is missing: \(line)", file: file, line: lineNumber)
            return offset
        }
        return position
    }

    private static func range(of line: String, in source: String, startingAfter offset: Int = 0) -> Int? {
        guard offset <= source.utf16.count else { return nil }
        let start = String.Index(utf16Offset: offset, in: source)
        guard let match = source.range(of: line, range: start..<source.endIndex) else {
            return nil
        }
        let position = match.lowerBound.utf16Offset(in: source)
        return position > offset ? position : nil
    }
}
