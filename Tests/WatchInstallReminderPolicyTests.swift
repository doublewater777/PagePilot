import XCTest
@testable import PagePilot

final class WatchInstallReminderPolicyTests: XCTestCase {
    func testFirstReaderOnboardingShowsAllWatchActivationStates() {
        let step = OnboardingFlow.Step.reader

        XCTAssertTrue(shouldShow(step: step, availability: .unpaired))
        XCTAssertTrue(shouldShow(step: step, availability: .appNotInstalled))
        XCTAssertTrue(shouldShow(step: step, availability: .unreachable))
        XCTAssertTrue(shouldShow(step: step, availability: .ready))
        XCTAssertFalse(shouldShow(step: step, availability: .unsupported))
    }

    func testCompletedOnboardingOnlyShowsActionableLongTermReminder() {
        let step = OnboardingFlow.Step.completed

        XCTAssertTrue(shouldShow(step: step, availability: .unpaired))
        XCTAssertTrue(shouldShow(step: step, availability: .appNotInstalled))
        XCTAssertFalse(shouldShow(step: step, availability: .unreachable))
        XCTAssertFalse(shouldShow(step: step, availability: .ready))
        XCTAssertFalse(shouldShow(step: step, availability: .unsupported))
    }

    func testDismissedLongTermReminderStaysHidden() {
        XCTAssertFalse(
            WatchGuidePresentationPolicy.shouldShow(
                isPhone: true,
                onboardingStep: .completed,
                availability: .appNotInstalled,
                installReminderDismissed: true
            )
        )
        XCTAssertFalse(
            WatchGuidePresentationPolicy.shouldShow(
                isPhone: true,
                onboardingStep: .completed,
                availability: .unpaired,
                installReminderDismissed: true
            )
        )
    }

    func testOnboardingGuideIgnoresLongTermReminderDismissal() {
        XCTAssertTrue(
            WatchGuidePresentationPolicy.shouldShow(
                isPhone: true,
                onboardingStep: .reader,
                availability: .ready,
                installReminderDismissed: true
            )
        )
    }

    func testGuideNeverShowsOnIPad() {
        XCTAssertFalse(
            WatchGuidePresentationPolicy.shouldShow(
                isPhone: false,
                onboardingStep: .reader,
                availability: .ready,
                installReminderDismissed: false
            )
        )
    }

    func testReminderDismissalPersistsUntilReset() {
        let suiteName = "WatchInstallReminderPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = WatchInstallReminderStore(defaults: defaults)
        XCTAssertFalse(store.isDismissed)

        store.dismiss()
        XCTAssertTrue(WatchInstallReminderStore(defaults: defaults).isDismissed)

        store.reset()
        XCTAssertFalse(WatchInstallReminderStore(defaults: defaults).isDismissed)
    }

    func testVisualReaderUsesOnboardingProgressAndPersistentReminderState() throws {
        let source = try Self.visualReaderSource()

        let guideEntry = try Self.requiredLine("private func reconcileOnboardingWatchGuide()", in: source)
        let progressRead = try Self.requiredLine(
            "OnboardingProgressStore().load(platform: .iPhone)",
            in: source,
            startingAfter: guideEntry
        )
        let policyCall = try Self.requiredLine(
            "WatchGuidePresentationPolicy.shouldShow(",
            in: source,
            startingAfter: progressRead
        )
        let reminderState = try Self.requiredLine(
            "installReminderDismissed: watchInstallReminderStore.isDismissed",
            in: source,
            startingAfter: policyCall
        )

        XCTAssertGreaterThan(progressRead, guideEntry)
        XCTAssertGreaterThan(policyCall, progressRead)
        XCTAssertGreaterThan(reminderState, policyCall)
    }

    func testSkippingWatchGuideCompletesOnboardingAndPersistsReminderDismissal() throws {
        let source = try Self.visualReaderSource()

        let dismissEntry = try Self.requiredLine("private func dismissOnboardingWatchGuide()", in: source)
        let finish = try Self.requiredLine("flow.finish()", in: source, startingAfter: dismissEntry)
        let save = try Self.requiredLine("progressStore.save(flow)", in: source, startingAfter: finish)
        let persistDismissal = try Self.requiredLine(
            "watchInstallReminderStore.dismiss()",
            in: source,
            startingAfter: save
        )

        XCTAssertGreaterThan(finish, dismissEntry)
        XCTAssertGreaterThan(save, finish)
        XCTAssertGreaterThan(persistDismissal, save)
    }

    func testReadyWatchResetsLongTermReminderDismissal() throws {
        let source = try Self.visualReaderSource()

        let guideEntry = try Self.requiredLine("private func reconcileOnboardingWatchGuide()", in: source)
        let readyCheck = try Self.requiredLine("if availability == .ready", in: source, startingAfter: guideEntry)
        let reset = try Self.requiredLine(
            "watchInstallReminderStore.reset()",
            in: source,
            startingAfter: readyCheck
        )

        XCTAssertGreaterThan(reset, readyCheck)
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

    private func shouldShow(
        step: OnboardingFlow.Step,
        availability: WatchAvailability
    ) -> Bool {
        WatchGuidePresentationPolicy.shouldShow(
            isPhone: true,
            onboardingStep: step,
            availability: availability,
            installReminderDismissed: false
        )
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
