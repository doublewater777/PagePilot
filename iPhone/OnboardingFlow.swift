//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation

struct OnboardingFlow: Codable, Equatable {
    enum Platform: Codable, Equatable {
        case iPhone
        case iPad
    }

    enum Step: Codable, Equatable {
        case choosePublication
        // Retained for decoding onboarding progress saved by older builds.
        case chooseControlTarget
        case reader
        case iPadHandoff
        case completed
    }

    enum PublicationSource: Codable, Equatable {
        case user
        case sample
    }

    // Retained for source and saved-state compatibility. New onboarding never
    // asks the user to choose a page-turn device.
    enum ControlTarget: Codable, Equatable {
        case iPhone
        case iPad
    }

    enum Effect: Equatable {
        case none
        case showIPadPaywall
    }

    struct PublicationSelection: Codable, Equatable {
        let bookID: Int64
        let source: PublicationSource
    }

    private(set) var platform: Platform
    private(set) var step: Step = .choosePublication
    private(set) var publication: PublicationSelection?
    private(set) var controlTarget: ControlTarget?
    private(set) var isWatchSetupComplete = false
    private(set) var isWatchGuideCollapsed = false

    var shouldShowWatchGuide: Bool {
        platform == .iPhone && step == .reader
    }

    init(platform: Platform) {
        self.platform = platform
    }

    mutating func didChoosePublication(bookID: Int64, source: PublicationSource) {
        publication = PublicationSelection(bookID: bookID, source: source)
        controlTarget = nil
        // Reader routing is automatic. iPhone users no longer stop at a target
        // picker before opening the selected Publication.
        step = .reader
    }

    /// Compatibility entry point for older UI/saved flows. Choosing a device is
    /// no longer meaningful, so any call simply continues to the Reader.
    @discardableResult
    mutating func didChooseControlTarget(_ target: ControlTarget, hasProAccess: Bool) -> Effect {
        controlTarget = nil
        step = .reader
        return .none
    }

    mutating func skipControlTarget() {
        controlTarget = nil
        isWatchGuideCollapsed = true
        step = .reader
    }

    mutating func didCompleteWatchPageTurn() {
        isWatchSetupComplete = true
        step = .completed
    }

    mutating func collapseWatchGuide() {
        guard shouldShowWatchGuide else { return }
        isWatchGuideCollapsed = true
    }

    mutating func finish() {
        step = .completed
    }

    /// Migrates interrupted onboarding from target-selection builds without
    /// making the user understand or re-select iPhone/iPad routing.
    func normalizedForAutomaticRouting() -> OnboardingFlow {
        var copy = self
        if copy.step == .chooseControlTarget || copy.step == .iPadHandoff {
            copy.step = .reader
            copy.controlTarget = nil
        }
        return copy
    }
}

struct OnboardingProgressStore {
    private let defaults: UserDefaults
    private let key = "onboardingProgress.v2"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(platform: OnboardingFlow.Platform) -> OnboardingFlow {
        guard let data = defaults.data(forKey: key),
              let flow = try? JSONDecoder().decode(OnboardingFlow.self, from: data)
        else {
            return OnboardingFlow(platform: platform)
        }
        return flow.normalizedForAutomaticRouting()
    }

    func save(_ flow: OnboardingFlow) {
        guard let data = try? JSONEncoder().encode(flow) else { return }
        defaults.set(data, forKey: key)
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }
}
