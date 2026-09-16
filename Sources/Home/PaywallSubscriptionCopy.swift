//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation

enum PaywallPlanKind: Equatable {
    case monthly
    case yearly
    case lifetime

    init(productID: String) {
        if productID.contains("monthly") {
            self = .monthly
        } else if productID.contains("yearly") {
            self = .yearly
        } else {
            self = .lifetime
        }
    }
}

enum PaywallSubscriptionCopy {
    static func purchaseDisclosure(
        kind: PaywallPlanKind,
        displayPrice: String,
        isTrialEligible: Bool,
        bundle: Bundle = .main
    ) -> String {
        switch kind {
        case .lifetime:
            return localized("paywall_purchase_disclosure_lifetime", bundle: bundle)
        case .monthly:
            let key = isTrialEligible
                ? "paywall_purchase_disclosure_trial_monthly"
                : "paywall_purchase_disclosure_paid_monthly"
            return String(format: localized(key, bundle: bundle), displayPrice)
        case .yearly:
            let key = isTrialEligible
                ? "paywall_purchase_disclosure_trial_yearly"
                : "paywall_purchase_disclosure_paid_yearly"
            return String(format: localized(key, bundle: bundle), displayPrice)
        }
    }

    static func planSubtitle(
        kind: PaywallPlanKind,
        displayPrice: String,
        isTrialEligible: Bool,
        fallback: String,
        bundle: Bundle = .main
    ) -> String {
        switch kind {
        case .lifetime:
            return fallback
        case .monthly where isTrialEligible:
            return String(
                format: localized("paywall_trial_duration_eligible_monthly", bundle: bundle),
                displayPrice
            )
        case .yearly where isTrialEligible:
            return String(
                format: localized("paywall_trial_duration_eligible_yearly", bundle: bundle),
                displayPrice
            )
        default:
            return fallback
        }
    }

    private static func localized(_ key: String, bundle: Bundle) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}
