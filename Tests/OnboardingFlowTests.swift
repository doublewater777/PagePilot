//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import XCTest
@testable import PagePilot

final class OnboardingFlowTests: XCTestCase {
    func testImportedPublicationAdvancesDirectlyToReaderOnIPhone() {
        var flow = OnboardingFlow(platform: .iPhone)

        flow.didChoosePublication(bookID: 42, source: .user)

        XCTAssertEqual(flow.step, .reader)
        XCTAssertEqual(flow.publication, .init(bookID: 42, source: .user))
        XCTAssertNil(flow.controlTarget)
    }

    func testSamplePublicationUsesSameAutomaticRoutingFlow() {
        var flow = OnboardingFlow(platform: .iPhone)

        flow.didChoosePublication(bookID: 7, source: .sample)

        XCTAssertEqual(flow.step, .reader)
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
        XCTAssertTrue(flow.isWatchGuideCollapsed)
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
        XCTAssertFalse(flow.shouldShowWatchGuide)
    }

    func testCollapsingWatchGuidePersistsLightweightState() {
        var flow = OnboardingFlow(platform: .iPhone)
        flow.didChoosePublication(bookID: 42, source: .user)

        flow.collapseWatchGuide()

        XCTAssertTrue(flow.shouldShowWatchGuide)
        XCTAssertTrue(flow.isWatchGuideCollapsed)
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
