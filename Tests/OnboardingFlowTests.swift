//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import XCTest
@testable import PagePilot

final class OnboardingFlowTests: XCTestCase {
    func testImportedPublicationShowsWatchIntroBeforeReaderOnIPhone() {
        var flow = OnboardingFlow(platform: .iPhone)

        flow.didChoosePublication(bookID: 42, source: .user)

        XCTAssertEqual(flow.step, .watchIntro)
        XCTAssertEqual(flow.publication, .init(bookID: 42, source: .user))
        XCTAssertNil(flow.controlTarget)
    }

    func testWatchIntroAdvancesToReaderOnContinue() {
        var flow = OnboardingFlow(platform: .iPhone)
        flow.didChoosePublication(bookID: 42, source: .user)

        flow.didFinishWatchIntro()

        XCTAssertEqual(flow.step, .reader)
    }

    func testWatchIntroContinueIsIgnoredOutsideWatchIntroStep() {
        var flow = OnboardingFlow(platform: .iPhone)

        flow.didFinishWatchIntro()

        XCTAssertEqual(flow.step, .choosePublication)
    }

    func testSamplePublicationUsesSameWatchIntroFlow() {
        var flow = OnboardingFlow(platform: .iPhone)

        flow.didChoosePublication(bookID: 7, source: .sample)

        XCTAssertEqual(flow.step, .watchIntro)
        XCTAssertEqual(flow.publication, .init(bookID: 7, source: .sample))
        XCTAssertNil(flow.controlTarget)
    }

    func testImportedPublicationAdvancesToReaderOnIPad() {
        var flow = OnboardingFlow(platform: .iPad)

        flow.didChoosePublication(bookID: 42, source: .user)

        XCTAssertEqual(flow.step, .reader)
    }

    func testLegacyIPhoneTargetSelectionNoLongerChangesRouting() {
        var flow = OnboardingFlow(platform: .iPhone)
        flow.didChoosePublication(bookID: 42, source: .user)

        let effect = flow.didChooseControlTarget(.iPhone, hasProAccess: false)

        XCTAssertEqual(effect, .none)
        XCTAssertEqual(flow.step, .reader)
        XCTAssertNil(flow.controlTarget)
    }

    func testLegacyIPadTargetSelectionNoLongerShowsPaywall() {
        var flow = OnboardingFlow(platform: .iPhone)
        flow.didChoosePublication(bookID: 42, source: .user)

        let effect = flow.didChooseControlTarget(.iPad, hasProAccess: false)

        XCTAssertEqual(effect, .none)
        XCTAssertEqual(flow.step, .reader)
        XCTAssertNil(flow.controlTarget)
    }

    func testSkippingLegacyControlTargetKeepsCollapsedWatchGuideEntry() {
        var flow = OnboardingFlow(platform: .iPhone)
        flow.didChoosePublication(bookID: 42, source: .user)

        flow.skipControlTarget()

        XCTAssertEqual(flow.step, .reader)
        XCTAssertNil(flow.controlTarget)
        XCTAssertTrue(flow.shouldShowWatchGuide)
    }

    func testIPadPlatformReaderDoesNotShowWatchGuide() {
        var flow = OnboardingFlow(platform: .iPad)
        flow.didChoosePublication(bookID: 42, source: .user)

        XCTAssertEqual(flow.step, .reader)
        XCTAssertFalse(flow.shouldShowWatchGuide)
    }

    func testSuccessfulWatchPageTurnCompletesActivation() {
        var flow = OnboardingFlow(platform: .iPhone)
        flow.didChoosePublication(bookID: 42, source: .user)

        flow.didCompleteWatchPageTurn()

        XCTAssertTrue(flow.isWatchSetupComplete)
        XCTAssertEqual(flow.step, .completed)
        XCTAssertTrue(
            flow.shouldShowWatchGuide,
            "Completing onboarding does not silence device-state Watch guidance."
        )
    }

    func testProgressStoreRestoresAutomaticReaderFlow() {
        let suiteName = "OnboardingFlowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = OnboardingProgressStore(defaults: defaults)
        var flow = OnboardingFlow(platform: .iPhone)
        flow.didChoosePublication(bookID: 42, source: .user)

        store.save(flow)

        XCTAssertEqual(store.load(platform: .iPhone), flow)
    }

    func testNormalizedForAutomaticRoutingPreservesWatchIntro() {
        var flow = OnboardingFlow(platform: .iPhone)
        flow.didChoosePublication(bookID: 42, source: .user)
        XCTAssertEqual(flow.step, .watchIntro)

        let normalized = flow.normalizedForAutomaticRouting()
        XCTAssertEqual(normalized.step, .watchIntro)
    }

    func testProgressStoreRestoresWatchIntroStepOnRelaunch() {
        let suiteName = "OnboardingFlowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = OnboardingProgressStore(defaults: defaults)
        var flow = OnboardingFlow(platform: .iPhone)
        flow.didChoosePublication(bookID: 42, source: .user)
        XCTAssertEqual(flow.step, .watchIntro)

        store.save(flow)

        let restored = store.load(platform: .iPhone)
        XCTAssertEqual(restored.step, .watchIntro)
        XCTAssertEqual(restored.publication, .init(bookID: 42, source: .user))
    }

    func testWatchIntroCopyIsLocalizedForSupportedLanguages() throws {
        let expectedKeys = [
            "onboarding_watch_intro_title",
            "onboarding_watch_intro_subtitle",
            "onboarding_watch_intro_point1_title",
            "onboarding_watch_intro_point1_detail",
            "onboarding_watch_intro_point2_title",
            "onboarding_watch_intro_point2_detail",
            "onboarding_watch_intro_point3_title",
            "onboarding_watch_intro_point3_detail",
            "onboarding_watch_intro_cta",
        ]
        for language in ["en", "zh-Hans", "de", "es", "fr"] {
            let bundleURL = try XCTUnwrap(Bundle.main.url(forResource: language, withExtension: "lproj"))
            let bundle = try XCTUnwrap(Bundle(url: bundleURL))
            for key in expectedKeys {
                let localized = bundle.localizedString(forKey: key, value: nil, table: nil)
                XCTAssertNotEqual(localized, key, "Missing translation for \(key) in \(language)")
                XCTAssertFalse(localized.isEmpty, "Empty translation for \(key) in \(language)")
            }
        }
    }

    func testExplicitFinishEndsTheFlowWithoutWatchActivation() {
        var flow = OnboardingFlow(platform: .iPhone)

        flow.finish()

        XCTAssertEqual(flow.step, .completed)
        XCTAssertFalse(flow.isWatchSetupComplete)
    }

    func testResetRemovesSavedProgress() {
        let suiteName = "OnboardingFlowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = OnboardingProgressStore(defaults: defaults)
        var flow = OnboardingFlow(platform: .iPhone)
        flow.didChoosePublication(bookID: 42, source: .user)
        store.save(flow)

        store.reset()

        XCTAssertEqual(store.load(platform: .iPhone).step, .choosePublication)
    }

    func testSamplePublicationCreatesMultiChapterEPUB() async throws {
        let url = try await OnboardingSamplePublication.makeURL()
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(url.pathExtension, "epub")
        XCTAssertGreaterThan(OnboardingSamplePublication.chapterCount, 1)
        XCTAssertGreaterThan(try Data(contentsOf: url).count, 0)
    }
}
