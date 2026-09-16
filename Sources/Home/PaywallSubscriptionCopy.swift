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

struct PaywallTrialPeriod: Equatable {
    enum Unit: Equatable {
        case day
        case week
        case month
        case year
    }

    let value: Int
    let unit: Unit
    let periodCount: Int

    var totalValue: Int {
        value * periodCount
    }
}

enum PaywallSubscriptionCopy {
    static func purchaseDisclosure(
        kind: PaywallPlanKind,
        displayPrice: String,
        isTrialEligible: Bool,
        trialPeriod: PaywallTrialPeriod?,
        billingPeriod: String?,
        bundle: Bundle = .main
    ) -> String {
        switch kind {
        case .lifetime:
            return localized("paywall_purchase_disclosure_lifetime", bundle: bundle)
        case .monthly, .yearly:
            if isTrialEligible, let trialPeriod, let billingPeriod {
                return String(
                    format: localized("paywall_purchase_disclosure_trial", bundle: bundle),
                    durationPhrase(trialPeriod, forCTA: false, bundle: bundle),
                    displayPrice,
                    billingPeriod
                )
            }
            if let billingPeriod {
                return String(
                    format: localized("paywall_purchase_disclosure_paid", bundle: bundle),
                    displayPrice,
                    billingPeriod
                )
            }
            return displayPrice
        }
    }

    static func buyButtonText(
        kind: PaywallPlanKind,
        isTrialEligible: Bool,
        trialPeriod: PaywallTrialPeriod?,
        bundle: Bundle = .main
    ) -> String {
        switch kind {
        case .lifetime:
            return localized("paywall_buy_button_lifetime", bundle: bundle)
        case .monthly, .yearly:
            if isTrialEligible, let trialPeriod {
                return String(
                    format: localized("paywall_buy_button_eligible", bundle: bundle),
                    durationPhrase(trialPeriod, forCTA: true, bundle: bundle)
                )
            }
            return localized("paywall_buy_button_ineligible", bundle: bundle)
        }
    }

    static func planSubtitle(
        kind: PaywallPlanKind,
        displayPrice: String,
        isTrialEligible: Bool,
        trialPeriod: PaywallTrialPeriod?,
        billingPeriod: String?,
        fallback: String,
        bundle: Bundle = .main
    ) -> String {
        // Yearly keeps the savings comparison on the card; trial terms sit under the CTA.
        switch kind {
        case .monthly where isTrialEligible:
            guard let trialPeriod, let billingPeriod else { return fallback }
            return String(
                format: localized("paywall_trial_duration_eligible_monthly", bundle: bundle),
                durationPhrase(trialPeriod, forCTA: false, bundle: bundle),
                displayPrice,
                billingPeriod
            )
        default:
            return fallback
        }
    }

    private static func durationPhrase(
        _ period: PaywallTrialPeriod,
        forCTA: Bool,
        bundle: Bundle
    ) -> String {
        let unit: String
        switch period.unit {
        case .day: unit = period.totalValue == 1 ? "day" : "days"
        case .week: unit = period.totalValue == 1 ? "week" : "weeks"
        case .month: unit = period.totalValue == 1 ? "month" : "months"
        case .year: unit = period.totalValue == 1 ? "year" : "years"
        }
        let key = forCTA
            ? "paywall_trial_duration_\(unit)_title"
            : "paywall_trial_duration_\(unit)"
        return String(format: localized(key, bundle: bundle), period.totalValue)
    }

    private static func localized(_ key: String, bundle: Bundle) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}
