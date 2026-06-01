//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import WatchConnectivity

/// Persisted settings for Apple Watch page turn behavior.
/// Stored in UserDefaults and synced to the Watch via WCSession.updateApplicationContext.
struct WatchPageTurnSettings {
    // MARK: Keys
    private enum Keys {
        static let hapticFeedback = "watch_haptic_feedback"
        static let controlTarget = "watch_control_target"
        static let defaultTargetMigration = "watch_default_target_iphone_migrated"
    }

    // MARK: Enums

    enum ControlTarget: String, CaseIterable, Identifiable {
        case iPhone = "iphone"
        case iPad = "ipad"

        var id: String { rawValue }

        var localizedName: String {
            switch self {
            case .iPad:
                return NSLocalizedString("watch_target_ipad", comment: "")
            case .iPhone:
                return NSLocalizedString("watch_target_iphone", comment: "")
            }
        }

    }

    init() {}

    // MARK: Storage

    var hapticFeedback: Bool {
        get { UserDefaults.standard.object(forKey: Keys.hapticFeedback) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Keys.hapticFeedback) }
    }

    var controlTarget: ControlTarget {
        get {
            if let rawVal = UserDefaults.standard.string(forKey: Keys.controlTarget),
               let val = ControlTarget(rawValue: rawVal) {
                return val
            }
            return .iPhone
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Keys.controlTarget) }
    }

    /// Fixed crown sensitivity threshold (no longer configurable).
    var crownSensitivity: Double { 2.0 }

    /// Returns a dictionary suitable for WCSession.updateApplicationContext
    var watchContext: [String: Any] {
        [
            Keys.hapticFeedback: hapticFeedback,
            Keys.controlTarget: controlTarget.rawValue
        ]
    }

    /// Syncs current settings to the paired Apple Watch.
    func syncToWatch() {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isPaired
        else { return }

        try? WCSession.default.updateApplicationContext(watchContext)
    }

    /// Performs a one-time migration of the default control target from iPad to
    /// iPhone. Call this once at app launch (e.g. from AppDelegate).
    static func migrateDefaultTargetIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Keys.defaultTargetMigration) else { return }

        let rawTarget = defaults.string(forKey: Keys.controlTarget)
        if rawTarget == nil || rawTarget == ControlTarget.iPad.rawValue {
            defaults.set(ControlTarget.iPhone.rawValue, forKey: Keys.controlTarget)
        }
        defaults.set(true, forKey: Keys.defaultTargetMigration)
    }
}
