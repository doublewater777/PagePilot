//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import StoreKit

enum ProPurchaseError: Error, LocalizedError {
    case productNotFound
    case purchaseFailed
    case verificationFailed
    case userCancelled
    case pending

    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return NSLocalizedString("purchase_error_product_not_found", comment: "")
        case .purchaseFailed:
            return NSLocalizedString("purchase_error_failed", comment: "")
        case .verificationFailed:
            return NSLocalizedString("purchase_error_verification", comment: "")
        case .userCancelled:
            return NSLocalizedString("purchase_error_cancelled", comment: "")
        case .pending:
            return NSLocalizedString("purchase_error_pending", comment: "")
        }
    }
}

final class ProPurchaseManager {
    static let shared = ProPurchaseManager()

    static let proAccessDidChange = Notification.Name("proAccessDidChange")
    static let monthlyProductID = "com.panyang.PagePilot.pro.monthly"
    static let yearlyProductID = "com.panyang.PagePilot.pro.yearly"
    static let lifetimeProductID = "com.panyang.PagePilot.pro.lifetime"

    private let defaults = UserDefaults.standard
    private let proKey = "entitlements_isPro"

    private var updateListenerTask: Task<Void, Never>?
    private(set) var products: [Product] = []

    // MARK: - Access

    /// Whether the user has full Pro access.
    var hasProAccess: Bool {
        defaults.bool(forKey: proKey)
    }

    // MARK: - Init

    private init() {
        updateListenerTask = listenForTransactions()
        Task { await loadProducts() }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Products Loading

    @discardableResult
    func loadProducts() async -> [Product] {
        do {
            let fetchedProducts = try await Product.products(for: [Self.monthlyProductID, Self.yearlyProductID, Self.lifetimeProductID])
            let orderedIds = [Self.monthlyProductID, Self.yearlyProductID, Self.lifetimeProductID]
            self.products = fetchedProducts.sorted { p1, p2 in
                let idx1 = orderedIds.firstIndex(of: p1.id) ?? 99
                let idx2 = orderedIds.firstIndex(of: p2.id) ?? 99
                return idx1 < idx2
            }
            if self.products.isEmpty {
                print("ProPurchaseManager: Product.products(for:) returned empty. Check StoreKit Configuration (.storekit file) or App Store Connect setup.")
            } else {
                print("ProPurchaseManager: loaded \(self.products.count) product(s): \(self.products.map { $0.id })")
            }
        } catch {
            print("ProPurchaseManager: Failed to load products: \(error)")
        }
        return products
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async throws {
        Analytics.shared.log(.purchaseStarted)
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await syncCurrentEntitlements()
            Analytics.shared.log(.purchaseSucceeded)

        case .userCancelled:
            Analytics.shared.log(.purchaseCancelled)
            throw ProPurchaseError.userCancelled

        case .pending:
            Analytics.shared.log(.purchasePending)
            throw ProPurchaseError.pending

        @unknown default:
            Analytics.shared.log(.purchaseFailed(error: "unknown"))
            throw ProPurchaseError.purchaseFailed
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            let hasPro = await syncCurrentEntitlements()
            if hasPro {
                Analytics.shared.log(.purchaseRestored)
            }
        } catch {
            print("Restore failed: \(error)")
        }
    }

    // MARK: - Verification

    func verifyCurrentEntitlements() async {
        await syncCurrentEntitlements()
    }

    // MARK: - Helpers

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard let self = self else { return }
                do {
                    let transaction = try self.checkVerified(result)
                    if Self.proProductIDs.contains(transaction.productID) {
                        await self.syncCurrentEntitlements()
                    }
                    await transaction.finish()
                } catch {
                    print("Transaction update failed: \(error)")
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }

    @discardableResult
    private func syncCurrentEntitlements() async -> Bool {
        var hasPro = false
        do {
            for await result in Transaction.currentEntitlements {
                let transaction = try checkVerified(result)
                guard Self.proProductIDs.contains(transaction.productID) else {
                    continue
                }

                hasPro = true
                break
            }
        } catch {
            print("Entitlement sync failed: \(error)")
        }

        await updateProAccess(hasPro)
        if hasPro {
            Analytics.shared.log(.proAccessGranted)
        }
        return hasPro
    }

    @MainActor
    private func updateProAccess(_ hasAccess: Bool) async {
        defaults.set(hasAccess, forKey: proKey)
        NotificationCenter.default.post(name: Self.proAccessDidChange, object: nil)
    }
}

extension ProPurchaseManager {
    static let freeBookLimit = 10

    static var proProductIDs: Set<String> {
        [monthlyProductID, yearlyProductID, lifetimeProductID]
    }
}
