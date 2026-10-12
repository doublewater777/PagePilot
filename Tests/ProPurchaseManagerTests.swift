import RevenueCat
import StoreKit
import XCTest
@testable import PagePilot

@MainActor
final class ProPurchaseManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var source: FakeProEntitlementSource!
    private var accessChanges: [Bool] = []

    override func setUp() {
        super.setUp()
        suiteName = "ProPurchaseManagerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        source = FakeProEntitlementSource()
        accessChanges = []
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeManager(automaticallyStart: Bool = false) -> ProPurchaseManager {
        ProPurchaseManager(source: source, defaults: defaults, automaticallyStart: automaticallyStart) { [weak self] in
            self?.accessChanges.append($0)
        }
    }

    func testLegacyPurchaseIsSyncedOnceAndKeepsPro() async {
        defaults.set(true, forKey: "entitlements_isPro")
        source.hasPro = true
        let manager = makeManager()
        await manager.verifyCurrentEntitlements()
        await manager.verifyCurrentEntitlements()
        XCTAssertTrue(manager.hasProAccess)
        XCTAssertTrue(defaults.bool(forKey: ProPurchaseManager.migrationKey))
        XCTAssertEqual(source.syncCount, 1)
        XCTAssertEqual(source.refreshCount, 1)
    }

    func testFailedMigrationKeepsCachedProAndRetries() async {
        defaults.set(true, forKey: "entitlements_isPro")
        source.error = ProPurchaseError.verificationFailed
        let manager = makeManager()
        await manager.verifyCurrentEntitlements()
        XCTAssertTrue(manager.hasProAccess)
        XCTAssertFalse(defaults.bool(forKey: ProPurchaseManager.migrationKey))
        XCTAssertTrue(accessChanges.isEmpty)
        source.error = nil
        source.hasPro = true
        await manager.verifyCurrentEntitlements()
        XCTAssertTrue(manager.hasProAccess)
        XCTAssertEqual(source.syncCount, 2)
    }

    func testNetworkErrorDoesNotRevokeCachedPro() async {
        defaults.set(true, forKey: "entitlements_isPro")
        defaults.set(true, forKey: ProPurchaseManager.migrationKey)
        source.error = URLError(.notConnectedToInternet)
        let manager = makeManager()
        await manager.verifyCurrentEntitlements()
        XCTAssertTrue(manager.hasProAccess)
        XCTAssertTrue(accessChanges.isEmpty)
    }

    func testConfirmedExpiredEntitlementRevokesProAndNotifies() async {
        defaults.set(true, forKey: "entitlements_isPro")
        defaults.set(true, forKey: ProPurchaseManager.migrationKey)
        let manager = makeManager()
        let notification = expectation(forNotification: .proAccessDidChange, object: nil) {
            ($0.object as? Bool) == false
        }
        await manager.verifyCurrentEntitlements()
        await fulfillment(of: [notification], timeout: 1)
        XCTAssertFalse(manager.hasProAccess)
        XCTAssertEqual(accessChanges, [false])
    }

    func testRestoreAppliesConfirmedEntitlement() async throws {
        source.hasPro = true
        let manager = makeManager()
        let restored = try await manager.restorePurchases()
        XCTAssertTrue(restored)
        XCTAssertTrue(manager.hasProAccess)
        XCTAssertEqual(source.restoreCount, 1)
        XCTAssertEqual(accessChanges, [true])
    }

    func testRestoreFailurePreservesAccess() async {
        defaults.set(true, forKey: "entitlements_isPro")
        source.error = URLError(.notConnectedToInternet)
        let manager = makeManager()
        do {
            _ = try await manager.restorePurchases()
            XCTFail("Restore should fail")
        } catch {
            XCTAssertEqual(error as? ProPurchaseError, .restoreFailed)
        }
        XCTAssertTrue(manager.hasProAccess)
        XCTAssertTrue(accessChanges.isEmpty)
    }

    func testEmptyRestoreDoesNotUnlockPro() async throws {
        let manager = makeManager()
        let restored = try await manager.restorePurchases()
        XCTAssertFalse(restored)
        XCTAssertFalse(manager.hasProAccess)
    }

    func testPurchaseUnlocksOnlyAfterConfirmedEntitlement() async throws {
        source.hasPro = true
        let manager = makeManager()
        try await manager.purchase(testProduct())
        XCTAssertTrue(manager.hasProAccess)
        XCTAssertEqual(accessChanges, [true])
    }

    func testPurchaseWithoutEntitlementIsNotReportedAsSuccess() async {
        let manager = makeManager()
        do {
            try await manager.purchase(testProduct())
            XCTFail("A payment without the Pro entitlement should fail verification")
        } catch {
            XCTAssertEqual(error as? ProPurchaseError, .verificationFailed)
        }
        XCTAssertFalse(manager.hasProAccess)
    }

    func testCancellationKeepsAccessAndAllowsRetry() async throws {
        defaults.set(true, forKey: "entitlements_isPro")
        source.error = ProPurchaseError.userCancelled
        let manager = makeManager()
        do {
            try await manager.purchase(testProduct())
            XCTFail("Cancelled purchase should throw cancellation")
        } catch {
            XCTAssertEqual(error as? ProPurchaseError, .userCancelled)
        }
        XCTAssertTrue(manager.hasProAccess)
        XCTAssertTrue(accessChanges.isEmpty)
        source.error = nil
        source.hasPro = true
        try await manager.purchase(testProduct())
        XCTAssertTrue(manager.hasProAccess)
    }

    private func testProduct() -> ProStoreProduct {
        ProStoreProduct(package: Package(
            identifier: "$rc_monthly", packageType: .monthly,
            storeProduct: StoreProduct(sk1Product: TestSKProduct()),
            offeringIdentifier: "default", webCheckoutUrl: nil
        ))
    }

    func testListenerIgnoresEmptyStateUntilMigrationCompletes() async {
        defaults.set(true, forKey: "entitlements_isPro")
        source.hasPro = true
        let manager = makeManager(automaticallyStart: true)
        source.onChange?(false)
        await Task.yield()
        XCTAssertTrue(manager.hasProAccess)
        await manager.verifyCurrentEntitlements()
        source.onChange?(false)
        // The callback applies updates on the main actor.
        for _ in 0..<5 { await Task.yield() }
        XCTAssertFalse(manager.hasProAccess)
        XCTAssertEqual(accessChanges.last, false)
    }

    func testPublicKeyValidationRejectsSecretsAndUnexpandedSetting() {
        XCTAssertEqual(RevenueCatConfiguration.publicSDKKey(" appl_public_key \n"), "appl_public_key")
        for key in [nil, "", "$(REVENUECAT_API_KEY)", "sk_secret", "goog_android", "appl_"] {
            XCTAssertNil(RevenueCatConfiguration.publicSDKKey(key))
        }
    }

    func testRevenueCatPeriodsPreserveUnits() {
        XCTAssertEqual(PaywallTrialPeriod.Unit(revenueCatUnit: .day), .day)
        XCTAssertEqual(PaywallTrialPeriod.Unit(revenueCatUnit: .week), .week)
        XCTAssertEqual(PaywallTrialPeriod.Unit(revenueCatUnit: .month), .month)
        XCTAssertEqual(PaywallTrialPeriod.Unit(revenueCatUnit: .year), .year)
    }

    func testEntitlementMappingHandlesActiveExpiredAndLifetimePurchases() throws {
        XCTAssertTrue(RevenueCatEntitlementSource.hasPro(in: try customerInfo(expires: "2099-01-01T00:00:00Z")))
        XCTAssertFalse(RevenueCatEntitlementSource.hasPro(in: try customerInfo(expires: "2020-01-01T00:00:00Z")))
        XCTAssertTrue(RevenueCatEntitlementSource.hasPro(in: try customerInfo(expires: nil)))
        XCTAssertFalse(RevenueCatEntitlementSource.hasPro(in: try customerInfo(expires: nil, entitlement: "other")))
    }

    private func customerInfo(expires: String?, entitlement: String = "pro") throws -> CustomerInfo {
        let expiration: Any = expires.map { $0 as Any } ?? NSNull()
        let productID = ProPurchaseManager.yearlyProductID
        let purchaseDate = "2019-01-01T00:00:00Z"
        let json: [String: Any] = [
            "schema_version": "4",
            "request_date": "2026-10-12T00:00:00Z",
            "subscriber": [
                "first_seen": purchaseDate,
                "original_app_user_id": "$RCAnonymousID:test",
                "original_application_version": "1.0",
                "non_subscriptions": [:],
                "subscriptions": [productID: [
                    "purchase_date": purchaseDate, "original_purchase_date": purchaseDate,
                    "expires_date": expiration, "store": "app_store",
                    "is_sandbox": true, "period_type": "normal", "ownership_type": "PURCHASED",
                ]],
                "entitlements": [entitlement: [
                    "product_identifier": productID, "purchase_date": purchaseDate,
                    "expires_date": expiration,
                ]],
            ],
        ]
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CustomerInfo.self, from: JSONSerialization.data(withJSONObject: json))
    }

    #if DEBUG
    func testDebugProStillWorksWhenRevenueCatFails() async {
        defaults.set(true, forKey: "PagePilotDebugPro")
        source.error = URLError(.notConnectedToInternet)
        let manager = makeManager()
        await manager.verifyCurrentEntitlements()
        XCTAssertTrue(manager.hasProAccess)
        XCTAssertEqual(accessChanges, [true])
    }
    #endif
}

private final class TestSKProduct: SKProduct, @unchecked Sendable {
    override var productIdentifier: String { ProPurchaseManager.monthlyProductID }
    override var localizedTitle: String { "PagePilot Pro Monthly" }
    override var localizedDescription: String { "Pro" }
    override var price: NSDecimalNumber { NSDecimalNumber(string: "0.99") }
    override var priceLocale: Locale { Locale(identifier: "en_US") }
}

private final class FakeProEntitlementSource: ProEntitlementSource {
    var hasPro = false
    var error: Error?
    var syncCount = 0
    var refreshCount = 0
    var restoreCount = 0
    var onChange: ((Bool) -> Void)?

    func startObserving(_ onChange: @escaping (Bool) -> Void) { self.onChange = onChange }
    func loadProducts() async throws -> [ProStoreProduct] { [] }
    func trialEligibility(for products: [ProStoreProduct]) async -> [String: Bool] { [:] }
    func purchase(_ product: ProStoreProduct) async throws -> Bool { try result() }
    func restorePurchases() async throws -> Bool {
        restoreCount += 1
        return try result()
    }
    func currentEntitlement() async throws -> Bool {
        refreshCount += 1
        return try result()
    }
    func syncPurchases() async throws -> Bool {
        syncCount += 1
        return try result()
    }
    private func result() throws -> Bool {
        if let error { throw error }
        return hasPro
    }
}
