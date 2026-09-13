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

        // Only actionable states surface the guide.
        let actionableCheck = try Self.requiredLine(
            "availability == .appNotInstalled || availability == .unpaired",
            in: source,
            startingAfter: availabilityRead
        )
        XCTAssertGreaterThan(actionableCheck, availabilityRead)
    }

    func testVisualReaderReconcilesGuideWhenWatchStateChanges() throws {
        let source = try Self.visualReaderSource()

        let guideEntry = try Self.requiredLine("showOnboardingWatchGuideIfNeeded()", in: source)
        let subscription = try Self.requiredLine(
            "WatchPageTurnService.shared.objectWillChange",
            in: source,
            startingAfter: guideEntry
        )
        let reconcileCall = try Self.requiredLine(
            "reconcileOnboardingWatchGuide()",
            in: source,
            startingAfter: subscription
        )

        XCTAssertGreaterThan(reconcileCall, guideEntry)

        // Removal path exists for non-actionable states.
        let removePath = try Self.requiredLine(
            "removeOnboardingWatchGuide()",
            in: source,
            startingAfter: reconcileCall
        )
        XCTAssertGreaterThan(removePath, reconcileCall)
    }

    func testWatchSettingsSurfaceInstallGuidanceWhenAppIsMissing() throws {
        let source = try Self.watchSettingsSource()

        let availabilityCheck = try Self.requiredLine("watchAvailability == .appNotInstalled", in: source)
        let installCopy = try Self.requiredLine(
            "onboarding_watch_install_detail",
            in: source,
            startingAfter: availabilityCheck
        )

        XCTAssertGreaterThan(installCopy, availabilityCheck)

        // No fake open action: the bridge:// scheme is private and silently fails.
        XCTAssertNil(
            Self.range(of: "watchAppURL", in: source),
            "Watch Settings must not offer a dead open-Watch-app action."
        )
    }

    func testInstallGuidanceCopyIsLocalizedForSupportedLanguages() throws {
        let expected: [String: String] = [
            "en": "Open the Watch app on your iPhone, find PagePilot under Available Apps, and install it.",
            "zh-Hans": "打开 iPhone 上的 Watch App，在「可用 App」中找到 PagePilot 并安装。",
            "de": "Öffnen Sie die Watch-App auf Ihrem iPhone und installieren Sie PagePilot unter „Verfügbare Apps“.",
            "es": "Abre la app Watch en tu iPhone e instala PagePilot desde «Apps disponibles».",
            "fr": "Ouvrez l’app Watch sur votre iPhone et installez PagePilot depuis « Apps disponibles ».",
        ]

        for (language, detail) in expected {
            let bundleURL = try XCTUnwrap(
                Bundle.main.url(forResource: language, withExtension: "lproj"),
                "Missing localization bundle for \(language)"
            )
            let bundle = try XCTUnwrap(Bundle(url: bundleURL))

            XCTAssertEqual(
                bundle.localizedString(forKey: "onboarding_watch_install_detail", value: nil, table: nil),
                detail,
                "\(language) install detail"
            )
        }
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
