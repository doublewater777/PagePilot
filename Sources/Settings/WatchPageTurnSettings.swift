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
        static let autoPageInterval = "watch_auto_page_interval"
        static let crownSensitivity = "watch_crown_sensitivity"
        static let pageTurnAnimation = "watch_page_turn_animation"
    }

    // MARK: Enums
    
    enum CrownSensitivity: String, CaseIterable, Identifiable {
        case low
        case medium
        case high
        
        var id: String { rawValue }
        
        var threshold: Double {
            switch self {
            case .low: return 3.5
            case .medium: return 2.0
            case .high: return 0.8
            }
        }
        
        var localizedName: String {
            switch self {
            case .low:
                return NSLocalizedString("watch_sensitivity_low", comment: "")
            case .medium:
                return NSLocalizedString("watch_sensitivity_medium", comment: "")
            case .high:
                return NSLocalizedString("watch_sensitivity_high", comment: "")
            }
        }
    }
    
    enum PageTurnAnimation: String, CaseIterable, Identifiable {
        case slide
        case curl
        case fade
        case none
        
        var id: String { rawValue }
        
        var localizedName: String {
            switch self {
            case .slide:
                return NSLocalizedString("watch_animation_slide", comment: "")
            case .curl:
                return NSLocalizedString("watch_animation_curl", comment: "")
            case .fade:
                return NSLocalizedString("watch_animation_fade", comment: "")
            case .none:
                return NSLocalizedString("watch_animation_none", comment: "")
            }
        }
        
        var icon: String {
            switch self {
            case .slide: return "arrow.left.and.right"
            case .curl: return "book.closed"
            case .fade: return "sparkles"
            case .none: return "slash.circle"
            }
        }
    }

    // MARK: Storage

    var hapticFeedback: Bool {
        get { UserDefaults.standard.object(forKey: Keys.hapticFeedback) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Keys.hapticFeedback) }
    }

    var autoPageInterval: Double {
        get {
            let val = UserDefaults.standard.double(forKey: Keys.autoPageInterval)
            return val > 0 ? val : 0
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.autoPageInterval) }
    }

    var crownSensitivity: CrownSensitivity {
        get {
            if let rawVal = UserDefaults.standard.string(forKey: Keys.crownSensitivity),
               let val = CrownSensitivity(rawValue: rawVal) {
                return val
            }
            return .medium
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Keys.crownSensitivity) }
    }

    var pageTurnAnimation: PageTurnAnimation {
        get {
            if let rawVal = UserDefaults.standard.string(forKey: Keys.pageTurnAnimation),
               let val = PageTurnAnimation(rawValue: rawVal) {
                return val
            }
            return .slide
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Keys.pageTurnAnimation) }
    }

    /// Returns a dictionary suitable for WCSession.updateApplicationContext
    var watchContext: [String: Any] {
        [
            Keys.hapticFeedback: hapticFeedback,
            "watch_crown_sensitivity": crownSensitivity.threshold,
            Keys.pageTurnAnimation: pageTurnAnimation.rawValue
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
}
