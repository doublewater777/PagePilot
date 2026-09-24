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

    func testCompletedOnboardingOnlyShowsMissingWatchAppReminder() {
        let step = OnboardingFlow.Step.completed

        XCTAssertFalse(shouldShow(step: step, availability: .unpaired))
        XCTAssertTrue(shouldShow(step: step, availability: .appNotInstalled))
        XCTAssertFalse(shouldShow(step: step, availability: .unreachable))
        XCTAssertFalse(shouldShow(step: step, availability: .ready))
        XCTAssertFalse(shouldShow(step: step, availability: .unsupported))
    }

    func testDismissedMissingAppReminderStaysHidden() {
        XCTAssertFalse(
            WatchGuidePresentationPolicy.shouldShow(
                isPhone: true,
                onboardingStep: .completed,
                availability: .appNotInstalled,
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

    func testSkippingWatchGuideCompletesOnboardingAndOnlyDismissesMissingAppReminder() throws {
        let source = try Self.visualReaderSource()

        let dismissEntry = try Self.requiredLine("private func dismissOnboardingWatchGuide()", in: source)
        let finish = try Self.requiredLine("flow.finish()", in: source, startingAfter: dismissEntry)
        let save = try Self.requiredLine("progressStore.save(flow)", in: source, startingAfter: finish)
        let missingAppCheck = try Self.requiredLine(
            "if availability == .appNotInstalled",
            in: source,
            startingAfter: save
        )
        let persistDismissal = try Self.requiredLine(
            "watchInstallReminderStore.dismiss()",
            in: source,
            startingAfter: missingAppCheck
        )

        XCTAssertGreaterThan(finish, dismissEntry)
        XCTAssertGreaterThan(save, finish)
        XCTAssertGreaterThan(missingAppCheck, save)
        XCTAssertGreaterThan(persistDismissal, missingAppCheck)
        XCTAssertNil(
            Self.range(of: "availability == .appNotInstalled || availability == .unpaired", in: source),
            "An unpaired Watch must not poison a future missing-app reminder."
        )
    }

    func testLeavingMissingAppStateResetsLongTermReminderDismissal() throws {
        let source = try Self.visualReaderSource()

        let guideEntry = try Self.requiredLine("private func reconcileOnboardingWatchGuide()", in: source)
        let stateChangeCheck = try Self.requiredLine(
            "if availability != .appNotInstalled",
            in: source,
            startingAfter: guideEntry
        )
        let reset = try Self.requiredLine(
            "watchInstallReminderStore.reset()",
            in: source,
            startingAfter: stateChangeCheck
        )

        XCTAssertGreaterThan(reset, stateChangeCheck)
    }

    func testReaderUsesDifferentDismissCopyForOnboardingAndLongTermReminder() throws {
        let source = try Self.visualReaderSource()

        let presentEntry = try Self.requiredLine("private func presentOnboardingWatchGuide()", in: source)
        let dismissTitle = try Self.requiredLine(
            "let dismissTitle: LocalizedStringKey = flow.step == .reader",
            in: source,
            startingAfter: presentEntry
        )
        let onboardingCopy = try Self.requiredLine(
            "\"onboarding_watch_skip\"",
            in: source,
            startingAfter: dismissTitle
        )
        let longTermCopy = try Self.requiredLine(
            "\"close_button\"",
            in: source,
            startingAfter: onboardingCopy
        )

        XCTAssertGreaterThan(onboardingCopy, dismissTitle)
        XCTAssertGreaterThan(longTermCopy, onboardingCopy)
    }

    func testWatchSettingsIsStableRecoverySurfaceForAllWatchStates() throws {
        let source = try Self.watchSettingsSource()

        let statusSection = try Self.requiredLine("private var watchStatusSection", in: source)
        let availabilitySwitch = try Self.requiredLine(
            "switch watchService.watchAvailability",
            in: source,
            startingAfter: statusSection
        )

        XCTAssertGreaterThan(availabilitySwitch, statusSection)
        for key in [
            "onboarding_watch_unpaired_title",
            "onboarding_watch_install_title",
            "onboarding_watch_open_title",
            "onboarding_watch_ready_title",
        ] {
            XCTAssertNotNil(Self.range(of: key, in: source))
        }
        XCTAssertNotNil(Self.range(of: "watchService.activate()", in: source))

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

    func testWatchSuccessObserverIsScopedToGuideLifetime() throws {
        let source = try Self.visualReaderSource()

        let property = try Self.requiredLine(
            "private var onboardingWatchSuccessCancellable: AnyCancellable?",
            in: source
        )
        let subscription = try Self.requiredLine(
            "onboardingWatchSuccessCancellable = NotificationCenter.default.publisher(for: .watchPageTurnDidSucceed)",
            in: source,
            startingAfter: property
        )
        let removal = try Self.requiredLine(
            "private func removeOnboardingWatchGuide()",
            in: source
        )
        let cancellation = try Self.requiredLine(
            "onboardingWatchSuccessCancellable?.cancel()",
            in: source,
            startingAfter: removal
        )

        XCTAssertGreaterThan(subscription, property)
        XCTAssertGreaterThan(cancellation, removal)
    }

    func testReaderOpeningRejectsLateImportCompletions() throws {
        let source = try Self.source(named: "iPhone/OnboardingView.swift")

        XCTAssertGreaterThanOrEqual(
            Self.occurrences(of: "guard !hasFinished, !isOpeningReader else { return }", in: source),
            3,
            "Sample, file, and alternative-source imports must stop once Reader opening begins."
        )
        XCTAssertGreaterThanOrEqual(
            Self.occurrences(of: "guard !Task.isCancelled, !hasFinished, !isOpeningReader else { return }", in: source),
            2,
            "Async import completions must not overwrite the publication captured for Reader opening."
        )
    }

    func testCollapsedWatchGuideDismissTargetMeetsTouchMinimum() throws {
        let source = try Self.source(named: "Sources/Reader/Common/OnboardingWatchGuideView.swift")
        let collapsedGuide = try Self.requiredLine("private var collapsedGuide", in: source)
        let dismissTarget = try Self.requiredLine(
            ".frame(width: 44, height: 44)",
            in: source,
            startingAfter: collapsedGuide
        )

        XCTAssertGreaterThan(dismissTarget, collapsedGuide)
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

    private static func occurrences(of substring: String, in source: String) -> Int {
        var count = 0
        var searchStart = source.startIndex
        while let match = source.range(of: substring, range: searchStart..<source.endIndex) {
            count += 1
            searchStart = match.upperBound
        }
        return count
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
