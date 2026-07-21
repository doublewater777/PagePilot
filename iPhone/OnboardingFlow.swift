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
        case chooseControlTarget
        case reader
        case iPadHandoff
        case completed
    }

    enum PublicationSource: Codable, Equatable {
        case user
        case sample
    }

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
        // iPhone path only. iPad target goes to handoff (not reader). Skip still
        // keeps a recoverable lightweight entry in the Reader.
        platform == .iPhone && step == .reader
    }

    init(platform: Platform) {
        self.platform = platform
    }

    mutating func didChoosePublication(bookID: Int64, source: PublicationSource) {
        publication = PublicationSelection(bookID: bookID, source: source)
        step = platform == .iPhone ? .chooseControlTarget : .reader
    }

    @discardableResult
    mutating func didChooseControlTarget(_ target: ControlTarget, hasProAccess: Bool) -> Effect {
        if target == .iPad, !hasProAccess {
            return .showIPadPaywall
        }
        controlTarget = target
        step = target == .iPad ? .iPadHandoff : .reader
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
        return flow
    }

    func save(_ flow: OnboardingFlow) {
        guard let data = try? JSONEncoder().encode(flow) else { return }
        defaults.set(data, forKey: key)
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }
}
