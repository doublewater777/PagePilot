//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation

enum ReadingSessionAnalytics {
    enum Destination: String {
        case history
        case prediction
    }

    enum Source: String {
        case sessionSummary = "reading_session_summary"
        case readingHistoryPreview = "reading_history_preview"
        case readingPredictionPreview = "reading_prediction_preview"
    }
}

/// Lightweight analytics wrapper for tracking Pro and onboarding funnels.
/// Uses NotificationCenter so multiple observers can subscribe.
enum AnalyticsEvent {
    case paywallViewed(source: String)
    case paywallDismissed
    case purchaseStarted
    case purchaseSucceeded
    case purchaseFailed(error: String)
    case purchaseCancelled
    case purchasePending
    case purchaseRestored
    case proAccessGranted
    case trialActivated
    case trialExpired
    case readingSessionInsightIntent(
        destination: ReadingSessionAnalytics.Destination,
        source: ReadingSessionAnalytics.Source
    )
    case proUpgradeIntent(source: ReadingSessionAnalytics.Source)
    case statsScopeChanged(to: String)
    case onboardingViewed(platform: String)
    case onboardingTourSkipped(page: Int)
    case onboardingImportStarted(source: String)
    case onboardingImportSucceeded(source: String)
    case onboardingImportFailed(source: String, error: String)
    case onboardingReaderOpened(source: String)
    case onboardingDismissed(step: String)
    case onboardingWatchGuideShown(availability: String)
    case onboardingWatchGuideCollapsed
    case onboardingWatchGuideDismissed(availability: String)
    case onboardingWatchActivationCompleted

    var name: String {
        switch self {
        case .paywallViewed: return "paywall_viewed"
        case .paywallDismissed: return "paywall_dismissed"
        case .purchaseStarted: return "purchase_started"
        case .purchaseSucceeded: return "purchase_succeeded"
        case .purchaseFailed: return "purchase_failed"
        case .purchaseCancelled: return "purchase_cancelled"
        case .purchasePending: return "purchase_pending"
        case .purchaseRestored: return "purchase_restored"
        case .proAccessGranted: return "pro_access_granted"
        case .trialActivated: return "trial_activated"
        case .trialExpired: return "trial_expired"
        case .readingSessionInsightIntent: return "reading_session_insight_intent"
        case .proUpgradeIntent: return "pro_upgrade_intent"
        case .statsScopeChanged: return "stats_scope_changed"
        case .onboardingViewed: return "onboarding_viewed"
        case .onboardingTourSkipped: return "onboarding_tour_skipped"
        case .onboardingImportStarted: return "onboarding_import_started"
        case .onboardingImportSucceeded: return "onboarding_import_succeeded"
        case .onboardingImportFailed: return "onboarding_import_failed"
        case .onboardingReaderOpened: return "onboarding_reader_opened"
        case .onboardingDismissed: return "onboarding_dismissed"
        case .onboardingWatchGuideShown: return "onboarding_watch_guide_shown"
        case .onboardingWatchGuideCollapsed: return "onboarding_watch_guide_collapsed"
        case .onboardingWatchGuideDismissed: return "onboarding_watch_guide_dismissed"
        case .onboardingWatchActivationCompleted: return "onboarding_watch_activation_completed"
        }
    }

    var parameters: [String: String] {
        switch self {
        case .paywallViewed(let source):
            return ["source": source]
        case .purchaseFailed(let error):
            return ["error": error]
        case let .readingSessionInsightIntent(destination, source):
            return [
                "destination": destination.rawValue,
                "source": source.rawValue,
            ]
        case .proUpgradeIntent(let source):
            return ["source": source.rawValue]
        case .statsScopeChanged(let scope):
            return ["scope": scope]
        case .onboardingViewed(let platform):
            return ["platform": platform]
        case .onboardingTourSkipped(let page):
            return ["page": String(page)]
        case .onboardingImportStarted(let source),
             .onboardingImportSucceeded(let source):
            return ["source": source]
        case let .onboardingImportFailed(source, error):
            return ["source": source, "error": error]
        case .onboardingReaderOpened(let source):
            return ["source": source]
        case .onboardingDismissed(let step):
            return ["step": step]
        case .onboardingWatchGuideShown(let availability),
             .onboardingWatchGuideDismissed(let availability):
            return ["availability": availability]
        default:
            return [:]
        }
    }
}

final class Analytics {
    static let shared = Analytics()

    private init() {}

    /// Logs an analytics event via NotificationCenter for any subscriber to consume.
    func log(_ event: AnalyticsEvent) {
        var userInfo: [String: Any] = ["event_name": event.name]
        if !event.parameters.isEmpty {
            userInfo["parameters"] = event.parameters
        }
        NotificationCenter.default.post(name: .analyticsEventLogged, object: nil, userInfo: userInfo)

        // Also print to console for development/debugging
        #if DEBUG
        let params = event.parameters.isEmpty ? "" : " \(event.parameters)"
        print("[Analytics] \(event.name)\(params)")
        #endif
    }
}

extension Notification.Name {
    static let analyticsEventLogged = Notification.Name("analyticsEventLogged")
}
