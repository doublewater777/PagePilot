import Foundation
import RevenueCat

/// Paywall data and the RevenueCat package used to purchase it.
struct ProStoreProduct: Identifiable {
    let package: Package

    var id: String { package.storeProduct.productIdentifier }
    var displayPrice: String { package.storeProduct.localizedPriceString }
    var price: Decimal { package.storeProduct.price }

    func formattedPrice(_ amount: Decimal) -> String {
        package.storeProduct.priceFormatter?.string(from: NSDecimalNumber(decimal: amount))
            ?? displayPrice
    }

    var trialPeriod: PaywallTrialPeriod? {
        guard let offer = package.storeProduct.introductoryDiscount,
              offer.paymentMode == .freeTrial else { return nil }
        return PaywallTrialPeriod(
            value: offer.subscriptionPeriod.value,
            unit: PaywallTrialPeriod.Unit(revenueCatUnit: offer.subscriptionPeriod.unit),
            periodCount: offer.numberOfPeriods
        )
    }

    var billingPeriod: PaywallBillingPeriod? {
        package.storeProduct.subscriptionPeriod.map {
            PaywallBillingPeriod(value: $0.value, unit: .init(revenueCatUnit: $0.unit))
        }
    }
}

extension PaywallTrialPeriod.Unit {
    init(revenueCatUnit: RevenueCat.SubscriptionPeriod.Unit) {
        switch revenueCatUnit {
        case .day: self = .day
        case .week: self = .week
        case .month: self = .month
        case .year: self = .year
        }
    }
}
