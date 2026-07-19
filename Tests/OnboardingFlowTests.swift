//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import XCTest
@testable import PagePilot

final class OnboardingFlowTests: XCTestCase {
    func testImportedPublicationAdvancesToTargetSelectionOnIPhone() {
        var flow = OnboardingFlow(platform: .iPhone)

        flow.didChoosePublication(bookID: 42, source: .user)

        XCTAssertEqual(flow.step, .chooseControlTarget)
        XCTAssertEqual(flow.publication, .init(bookID: 42, source: .user))
    }

    func testImportedPublicationAdvancesToReaderOnIPad() {
        var flow = OnboardingFlow(platform: .iPad)

        flow.didChoosePublication(bookID: 42, source: .user)

        XCTAssertEqual(flow.step, .reader)
    }

    func testIPhoneTargetAdvancesToReader() {
        var flow = OnboardingFlow(platform: .iPhone)
        flow.didChoosePublication(bookID: 42, source: .user)

        flow.didChooseControlTarget(.iPhone, hasProAccess: false)

        XCTAssertEqual(flow.step, .reader)
        XCTAssertEqual(flow.controlTarget, .iPhone)
    }

    func testLockedIPadTargetRequestsPaywallWithoutChangingSelection() {
        var flow = OnboardingFlow(platform: .iPhone)
        flow.didChoosePublication(bookID: 42, source: .user)

        let effect = flow.didChooseControlTarget(.iPad, hasProAccess: false)

        XCTAssertEqual(effect, .showIPadPaywall)
        XCTAssertEqual(flow.step, .chooseControlTarget)
        XCTAssertNil(flow.controlTarget)
    }

    func testUnlockedIPadTargetAdvancesToHandoff() {
        var flow = OnboardingFlow(platform: .iPhone)
        flow.didChoosePublication(bookID: 42, source: .user)

        let effect = flow.didChooseControlTarget(.iPad, hasProAccess: true)

        XCTAssertEqual(effect, .none)
        XCTAssertEqual(flow.step, .iPadHandoff)
        XCTAssertEqual(flow.controlTarget, .iPad)
    }

    func testSkippingControlTargetContinuesToReaderWithoutWatchGuide() {
        var flow = OnboardingFlow(platform: .iPhone)
        flow.didChoosePublication(bookID: 42, source: .sample)

        flow.skipControlTarget()

        XCTAssertEqual(flow.step, .reader)
        XCTAssertNil(flow.controlTarget)
        XCTAssertFalse(flow.shouldShowWatchGuide)
    }

    func testSuccessfulWatchPageTurnCompletesActivation() {
        var flow = OnboardingFlow(platform: .iPhone)
        flow.didChoosePublication(bookID: 42, source: .user)
        flow.didChooseControlTarget(.iPhone, hasProAccess: false)

        flow.didCompleteWatchPageTurn()

        XCTAssertTrue(flow.isWatchSetupComplete)
        XCTAssertEqual(flow.step, .completed)
        XCTAssertFalse(flow.shouldShowWatchGuide)
    }

    func testCollapsingWatchGuidePersistsLightweightState() {
        var flow = OnboardingFlow(platform: .iPhone)
        flow.didChoosePublication(bookID: 42, source: .user)
        flow.didChooseControlTarget(.iPhone, hasProAccess: false)

        flow.collapseWatchGuide()

        XCTAssertTrue(flow.shouldShowWatchGuide)
        XCTAssertTrue(flow.isWatchGuideCollapsed)
    }

    func testProgressStoreRestoresInterruptedFlow() {
        let suiteName = "OnboardingFlowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = OnboardingProgressStore(defaults: defaults)
        var flow = OnboardingFlow(platform: .iPhone)
        flow.didChoosePublication(bookID: 42, source: .sample)
        flow.didChooseControlTarget(.iPhone, hasProAccess: false)

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
}
