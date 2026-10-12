//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import Foundation
import UIKit

enum ProPurchaseError: Error, LocalizedError {
    case productNotFound
    case purchaseFailed
    case verificationFailed
    case userCancelled
    case pending
    case restoreFailed
    case noPurchasesToRestore

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
        case .restoreFailed:
            return NSLocalizedString("purchase_error_restore_failed", comment: "")
        case .noPurchasesToRestore:
            return NSLocalizedString("purchase_error_no_purchases_to_restore", comment: "")
        }
    }
}

final class ProPurchaseManager: ObservableObject {
    static let shared = ProPurchaseManager(source: RevenueCatEntitlementSource())

    static let monthlyProductID = "com.panyang.PagePilot.pro.monthly"
    static let yearlyProductID = "com.panyang.PagePilot.pro.yearly"
    static let lifetimeProductID = "com.panyang.PagePilot.pro.lifetime"

    private let defaults: UserDefaults
    private let source: ProEntitlementSource
    private let accessDidChange: @MainActor (Bool) -> Void
    private let proKey = "entitlements_isPro"
    static let migrationKey = "revenuecat_synced_v1"

    private var foregroundObserver: NSObjectProtocol?
    private(set) var products: [ProStoreProduct] = []
    @MainActor private var entitlementRefreshTask: Task<Bool, Never>?

    // MARK: - Access

    /// Whether the user has full Pro access.
    var hasProAccess: Bool {
        defaults.bool(forKey: proKey)
    }

    // MARK: - Init

    init(
        source: ProEntitlementSource,
        defaults: UserDefaults = .standard,
        automaticallyStart: Bool = true,
        accessDidChange: @escaping @MainActor (Bool) -> Void = { hasAccess in
            if hasAccess {
                WatchPageTurnService.shared.enableIPadRelay()
                WatchPageTurnService.shared.prepareIPadRelay()
            } else {
                WatchPageTurnService.shared.disableIPadRelay()
                WatchPageTurnService.shared.stopIPadRelayDiscovery()
            }
        }
    ) {
        self.source = source
        self.defaults = defaults
        self.accessDidChange = accessDidChange
        guard automaticallyStart else { return }
        source.startObserving { [weak self] hasPro in
            guard let self, self.defaults.bool(forKey: Self.migrationKey) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.updateProAccess(hasPro)
            }
        }
        setupForegroundObservation()

        // Cached access keeps Pro available while RevenueCat refreshes or offline.
        if hasProAccess {
            Task { @MainActor in
                accessDidChange(true)
            }
        }

        Task { @MainActor in await loadProducts() }
    }

    deinit {
        if let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Products Loading

    @discardableResult
    @MainActor
    func loadProducts() async -> [ProStoreProduct] {
        do {
            let fetchedProducts = try await source.loadProducts()
            let orderedIds = [Self.monthlyProductID, Self.yearlyProductID, Self.lifetimeProductID]
            self.products = fetchedProducts.sorted { p1, p2 in
                let idx1 = orderedIds.firstIndex(of: p1.id) ?? 99
                let idx2 = orderedIds.firstIndex(of: p2.id) ?? 99
                return idx1 < idx2
            }
            print("ProPurchaseManager: loaded \(products.count) product(s): \(products.map { $0.id })")
        } catch {
            print("ProPurchaseManager: Failed to load products: \(error)")
        }
        return products
    }

    // MARK: - Purchase

    func trialEligibility(for products: [ProStoreProduct]) async -> [String: Bool] {
        await source.trialEligibility(for: products)
    }

    @MainActor
    func purchase(_ product: ProStoreProduct) async throws {
        guard !isProcessingPurchase else { throw ProPurchaseError.pending }
        isProcessingPurchase = true
        defer { isProcessingPurchase = false }
        Analytics.shared.log(.purchaseStarted)
        do {
            let hasPro = try await source.purchase(product)
            guard hasPro else { throw ProPurchaseError.verificationFailed }
            defaults.set(true, forKey: Self.migrationKey)
            await updateProAccess(hasPro)
            Analytics.shared.log(.purchaseSucceeded)
        } catch ProPurchaseError.userCancelled {
            Analytics.shared.log(.purchaseCancelled)
            throw ProPurchaseError.userCancelled
        } catch ProPurchaseError.pending {
            Analytics.shared.log(.purchasePending)
            throw ProPurchaseError.pending
        }
    }

    @MainActor private var isProcessingPurchase = false

    // MARK: - Restore

    @discardableResult
    @MainActor
    func restorePurchases() async throws -> Bool {
        guard !isProcessingPurchase else { throw ProPurchaseError.pending }
        isProcessingPurchase = true
        defer { isProcessingPurchase = false }
        do {
            let hasPro = try await source.restorePurchases()
            defaults.set(true, forKey: Self.migrationKey)
            await updateProAccess(hasPro)
            if hasPro {
                Analytics.shared.log(.purchaseRestored)
            }
            return hasPro
        } catch {
            print("Restore failed: \(error)")
            throw ProPurchaseError.restoreFailed
        }
    }

    // MARK: - Verification

    @MainActor
    func verifyCurrentEntitlements() async {
        await syncCurrentEntitlements()
    }

    // MARK: - Foreground Re-verification

    private func setupForegroundObservation() {
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.verifyCurrentEntitlements()
            }
        }
    }

    // MARK: - Helpers

    @discardableResult
    @MainActor
    private func syncCurrentEntitlements() async -> Bool {
        if let entitlementRefreshTask { return await entitlementRefreshTask.value }
        let task = Task { @MainActor in
            do {
                let hasPro: Bool
                if defaults.bool(forKey: Self.migrationKey) {
                    hasPro = try await source.currentEntitlement()
                } else {
                    hasPro = try await source.syncPurchases()
                    defaults.set(true, forKey: Self.migrationKey)
                }
                await updateProAccess(hasPro)
                return hasProAccess
            } catch {
                print("Entitlement sync failed (keeping current Pro state \(hasProAccess)): \(error)")
                // DEBUG override must work even when the backend is unreachable.
                if debugProEnabled { await updateProAccess(true) }
                return hasProAccess
            }
        }
        entitlementRefreshTask = task
        let result = await task.value
        entitlementRefreshTask = nil
        return result
    }

    private var debugProEnabled: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-PagePilotDebugPro")
            || defaults.bool(forKey: "PagePilotDebugPro")
        #else
        return false
        #endif
    }

    @MainActor
    private func updateProAccess(_ hasAccess: Bool) async {
        let hasAccess = hasAccess || debugProEnabled
        let previous = defaults.bool(forKey: proKey)
        defaults.set(hasAccess, forKey: proKey)
        objectWillChange.send()
        if previous != hasAccess {
            NotificationCenter.default.post(name: .proAccessDidChange, object: hasAccess)
            if hasAccess { Analytics.shared.log(.proAccessGranted) }
        }

        // Re-assert relay readiness when RevenueCat confirms Pro.
        accessDidChange(hasAccess)
    }
}

extension ProPurchaseManager {
    static let freeBookLimit = 10
    /// Free tier may keep this many highlights globally; Pro is unlimited.
    static let freeHighlightLimit = 20

    static var proProductIDs: Set<String> {
        [monthlyProductID, yearlyProductID, lifetimeProductID]
    }
}
