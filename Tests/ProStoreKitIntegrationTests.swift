import RevenueCat
import StoreKit
import StoreKitTest
import XCTest
@testable import PagePilot

/// Local Apple StoreKit transactions, not App Store sandbox receipts.
@MainActor
final class ProStoreKitIntegrationTests: XCTestCase {
    private var session: SKTestSession!
    private var usingSmokeTestIdentity = false
    private static var didInitializeStoreKitSession = false

    override func setUp() async throws {
        try await super.setUp()
        guard ProcessInfo.processInfo.environment["PAGEPILOT_RC_LOCAL_STOREKIT"] == "1" else {
            throw XCTSkip("Local StoreKit tests require PAGEPILOT_RC_LOCAL_STOREKIT=1 and REVENUECAT_API_KEY= as a build override.")
        }
        if !Self.didInitializeStoreKitSession {
            XCTAssertFalse(Purchases.isConfigured, "Initialize StoreKitTest before RevenueCat on iOS 27.")
        }
        let configuration = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "PagePilot", withExtension: "storekit"))
        session = try SKTestSession(contentsOf: configuration)
        Self.didInitializeStoreKitSession = true
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
    }

    override func tearDown() async throws {
        session?.clearTransactions()
        session?.resetToDefaultState()
        session = nil
        if usingSmokeTestIdentity {
            _ = try await Purchases.shared.logOut()
            usingSmokeTestIdentity = false
        }
        try await super.tearDown()
    }

    func testLocalCatalogResolvesAllThreeProductTypesAndAnnualTrial() async throws {
        let products = try await Product.products(for: Array(ProPurchaseManager.proProductIDs))
        XCTAssertEqual(Set(products.map(\.id)), Set(ProPurchaseManager.proProductIDs))
        let monthly = try XCTUnwrap(products.first { $0.id.hasSuffix(".monthly") })
        let yearly = try XCTUnwrap(products.first { $0.id.hasSuffix(".yearly") })
        let lifetime = try XCTUnwrap(products.first { $0.id.hasSuffix(".lifetime") })
        XCTAssertEqual(monthly.type, .autoRenewable)
        XCTAssertEqual(monthly.subscription?.subscriptionPeriod.value, 1)
        XCTAssertEqual(monthly.subscription?.subscriptionPeriod.unit, .month)
        XCTAssertEqual(yearly.subscription?.subscriptionPeriod.value, 1)
        XCTAssertEqual(yearly.subscription?.subscriptionPeriod.unit, .year)
        XCTAssertEqual(yearly.subscription?.introductoryOffer?.paymentMode, .freeTrial)
        XCTAssertEqual(yearly.subscription?.introductoryOffer?.period.value, 7)
        XCTAssertEqual(yearly.subscription?.introductoryOffer?.period.unit, .day)
        XCTAssertEqual(lifetime.type, .nonConsumable)
    }

    func testNoPurchaseIsNotRecognizedAsLegacyPro() async throws {
        try await assertLegacyAccess(false)
        let expired = try await RevenueCatEntitlementSource.validateEntitlement(false)
        let active = try await RevenueCatEntitlementSource.validateEntitlement(true)
        XCTAssertFalse(expired)
        XCTAssertTrue(active)
    }

    func testExistingMonthlyPurchaseIsRecognized() async throws {
        _ = try await session.buyProduct(identifier: "com.panyang.PagePilot.pro.monthly")
        try await assertLegacyAccess(true)
    }

    func testExistingYearlyPurchaseIsRecognized() async throws {
        _ = try await session.buyProduct(identifier: "com.panyang.PagePilot.pro.yearly")
        try await assertLegacyAccess(true)
    }

    func testExistingLifetimePurchaseIsRecognizedUntilRefunded() async throws {
        let transaction = try await session.buyProduct(identifier: "com.panyang.PagePilot.pro.lifetime")
        try await assertLegacyAccess(true)
        try session.refundTransaction(identifier: UInt(transaction.id))
        try await assertLegacyAccess(false)
    }

    func testExpiredSubscriptionIsNotRecognizedAsLegacyPro() async throws {
        let productID = "com.panyang.PagePilot.pro.monthly"
        let transaction = try await session.buyProduct(identifier: productID)
        try session.disableAutoRenewForTransaction(identifier: UInt(transaction.id))
        try await assertLegacyAccess(true)
        try session.expireSubscription(productIdentifier: productID)
        try await assertLegacyAccess(false)
    }

    func testValidApplePurchaseRejectsEmptyRevenueCatEntitlement() async throws {
        _ = try await session.buyProduct(identifier: "com.panyang.PagePilot.pro.lifetime")
        try await assertLegacyAccess(true)
        do {
            _ = try await RevenueCatEntitlementSource.validateEntitlement(false)
            XCTFail("Do not revoke a verified Apple purchase when RevenueCat reports no Pro.")
        } catch {
            XCTAssertEqual(error as? ProPurchaseError, .verificationFailed)
        }
    }

    /// Opt-in: exercises the actual SDK and backend with an isolated synthetic customer.
    /// It does not validate Apple's sandbox servers or a fresh-install restore.
    func testRevenueCatLocalPurchaseAndRestore() async throws {
        guard ProcessInfo.processInfo.environment["PAGEPILOT_RC_LOCAL_SMOKE"] == "1" else {
            throw XCTSkip("Set PAGEPILOT_RC_LOCAL_SMOKE=1 to run the network smoke test.")
        }
        let key = try XCTUnwrap(RevenueCatConfiguration.publicSDKKey(ProcessInfo.processInfo.environment["PAGEPILOT_RC_SMOKE_API_KEY"]))
        Purchases.logLevel = .debug
        Purchases.configure(withAPIKey: key)
        let appUserID = "pagepilot-local-smoke-\(UUID().uuidString)"
        let login = try await Purchases.shared.logIn(appUserID)
        usingSmokeTestIdentity = true
        XCTAssertFalse(RevenueCatEntitlementSource.hasPro(in: login.customerInfo))
        print("RevenueCat local smoke appUserID: \(appUserID)")

        let source = RevenueCatEntitlementSource()
        let products = try await source.loadProducts()
        XCTAssertEqual(Set(products.map(\.id)), Set(ProPurchaseManager.proProductIDs))
        let lifetime = try XCTUnwrap(products.first { $0.id.hasSuffix(".lifetime") })
        let purchased = try await source.purchase(lifetime)
        XCTAssertTrue(purchased)
        let info = try await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent)
        let entitlement = try XCTUnwrap(info.entitlements.active["pro"])
        XCTAssertEqual(entitlement.productIdentifier, lifetime.id)
        XCTAssertTrue(entitlement.isSandbox)

        let suiteName = appUserID
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = ProPurchaseManager(source: source, defaults: defaults, automaticallyStart: false) { _ in }
        XCTAssertFalse(manager.hasProAccess)
        let restored = try await manager.restorePurchases()
        XCTAssertTrue(restored)
        XCTAssertTrue(manager.hasProAccess)
    }

    private func assertLegacyAccess(_ expected: Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        // StoreKit's transaction cache can lag test-session mutations.
        for _ in 0..<40 {
            if try await RevenueCatEntitlementSource.hasVerifiedLegacyPurchase() == expected { return }
            try await Task.sleep(for: .milliseconds(250))
        }
        let actual = try await RevenueCatEntitlementSource.hasVerifiedLegacyPurchase()
        XCTAssertEqual(actual, expected, file: file, line: line)
    }
}
