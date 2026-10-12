import Foundation
import RevenueCat
import StoreKit

protocol ProEntitlementSource: AnyObject {
    func startObserving(_ onChange: @escaping (Bool) -> Void)
    func loadProducts() async throws -> [ProStoreProduct]
    func trialEligibility(for products: [ProStoreProduct]) async -> [String: Bool]
    func purchase(_ product: ProStoreProduct) async throws -> Bool
    func restorePurchases() async throws -> Bool
    func currentEntitlement() async throws -> Bool
    func syncPurchases() async throws -> Bool
}

enum RevenueCatConfiguration {
    static func publicSDKKey(_ value: String?) -> String? {
        guard let key = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              key.hasPrefix("appl_"), key.count > 5 else { return nil }
        return key
    }

    static func configure() {
        guard !Purchases.isConfigured else { return }
        guard let key = publicSDKKey(Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String) else {
            print("RevenueCat: missing iOS public SDK key; purchases are unavailable.")
            return
        }
        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .warn
        #endif
        Purchases.configure(withAPIKey: key)
    }
}

final class RevenueCatEntitlementSource: NSObject, ProEntitlementSource, PurchasesDelegate {
    static let entitlementID = "pro"
    private var onChange: ((Bool) -> Void)?

    static func hasPro(in info: CustomerInfo) -> Bool {
        info.entitlements.active[entitlementID] != nil
    }

    func startObserving(_ onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        guard Purchases.isConfigured else { return }
        Purchases.shared.delegate = self
    }

    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        onChange?(Self.hasPro(in: customerInfo))
    }

    func loadProducts() async throws -> [ProStoreProduct] {
        try requireConfiguration()
        let offerings = try await Purchases.shared.offerings()
        return (offerings.current?.availablePackages ?? [])
            .filter { ProPurchaseManager.proProductIDs.contains($0.storeProduct.productIdentifier) }
            .map(ProStoreProduct.init)
    }

    func trialEligibility(for products: [ProStoreProduct]) async -> [String: Bool] {
        guard Purchases.isConfigured else { return [:] }
        let eligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(productIdentifiers: products.map(\.id))
        return eligibility.mapValues { $0.status == .eligible }
    }

    func purchase(_ product: ProStoreProduct) async throws -> Bool {
        try requireConfiguration()
        do {
            let result = try await Purchases.shared.purchase(package: product.package)
            guard !result.userCancelled else { throw ProPurchaseError.userCancelled }
            return Self.hasPro(in: result.customerInfo)
        } catch {
            guard (error as NSError).domain == ErrorCode.errorDomain else { throw error }
            switch (error as NSError).code {
            case ErrorCode.purchaseCancelledError.rawValue: throw ProPurchaseError.userCancelled
            case ErrorCode.paymentPendingError.rawValue: throw ProPurchaseError.pending
            default: throw error
            }
        }
    }

    func restorePurchases() async throws -> Bool {
        try requireConfiguration()
        return try await Self.validateEntitlement(Self.hasPro(in: try await Purchases.shared.restorePurchases()))
    }

    func currentEntitlement() async throws -> Bool {
        try requireConfiguration()
        return try await Self.validateEntitlement(Self.hasPro(in: try await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent)))
    }

    func syncPurchases() async throws -> Bool {
        try requireConfiguration()
        return try await Self.validateEntitlement(Self.hasPro(in: try await Purchases.shared.syncPurchases()))
    }

    static func validateEntitlement(_ hasPro: Bool) async throws -> Bool {
        // RevenueCat owns purchasing and finishing. This read-only check protects
        // existing subscribers if RC has not yet recognized a valid Apple purchase.
        if !hasPro, try await Self.hasVerifiedLegacyPurchase() {
            throw ProPurchaseError.verificationFailed
        }
        return hasPro
    }

    static func hasVerifiedLegacyPurchase() async throws -> Bool {
        for await result in StoreKit.Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                if ProPurchaseManager.proProductIDs.contains(transaction.productID) {
                    return true
                }
            case .unverified(_, let error): throw error
            }
        }
        return false
    }

    private func requireConfiguration() throws {
        guard Purchases.isConfigured else { throw ProPurchaseError.productNotFound }
    }
}
