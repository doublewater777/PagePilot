import Foundation
import XCTest
@testable import PagePilot

final class PaywallSubscriptionCopyTests: XCTestCase {
    func testYearlyTrialDisclosureIncludesDurationPriceAndAutoRenew() throws {
        let english = try localizedBundle("en")
        let chinese = try localizedBundle("zh-Hans")

        let enText = PaywallSubscriptionCopy.purchaseDisclosure(
            kind: .yearly,
            displayPrice: "$4.99",
            isTrialEligible: true,
            bundle: english
        )
        XCTAssertTrue(enText.contains("7-day free trial"))
        XCTAssertTrue(enText.contains("$4.99/year"))
        XCTAssertTrue(enText.lowercased().contains("automatically renews"))
        XCTAssertTrue(enText.lowercased().contains("canceled"))

        let zhText = PaywallSubscriptionCopy.purchaseDisclosure(
            kind: .yearly,
            displayPrice: "¥28",
            isTrialEligible: true,
            bundle: chinese
        )
        XCTAssertTrue(zhText.contains("7 天免费试用"))
        XCTAssertTrue(zhText.contains("¥28/年"))
        XCTAssertTrue(zhText.contains("自动续订"))
        XCTAssertTrue(zhText.contains("取消"))
    }

    func testPaidAndLifetimeDisclosuresStayExplicit() throws {
        let english = try localizedBundle("en")

        let monthly = PaywallSubscriptionCopy.purchaseDisclosure(
            kind: .monthly,
            displayPrice: "$0.99",
            isTrialEligible: false,
            bundle: english
        )
        XCTAssertEqual(
            monthly,
            "$0.99/month. Automatically renews unless canceled in App Store subscription settings."
        )

        let lifetime = PaywallSubscriptionCopy.purchaseDisclosure(
            kind: .lifetime,
            displayPrice: "$6.99",
            isTrialEligible: false,
            bundle: english
        )
        XCTAssertTrue(lifetime.lowercased().contains("one-time"))
        XCTAssertFalse(lifetime.lowercased().contains("automatically renews"))
    }

    func testYearlyPlanSubtitleUsesTrialThenPriceWhenEligible() throws {
        let english = try localizedBundle("en")
        let subtitle = PaywallSubscriptionCopy.planSubtitle(
            kind: .yearly,
            displayPrice: "$4.99",
            isTrialEligible: true,
            fallback: "Only $0.42/month",
            bundle: english
        )
        XCTAssertEqual(subtitle, "7 days free, then $4.99/year")
    }

    func testSupportedLanguagesKeepTrialPriceAndRenewalTogether() throws {
        let expected: [String: (trial: String, renew: String)] = [
            "en": ("7-day free trial, then ¥28/year", "Automatically renews"),
            "zh-Hans": ("7 天免费试用，之后 ¥28/年", "自动续订"),
            "de": ("7 Tage kostenlos, danach ¥28/Jahr", "Verlängert sich automatisch"),
            "es": ("Prueba gratuita de 7 días, luego ¥28/año", "Se renueva automáticamente"),
            "fr": ("Essai gratuit de 7 jours, puis ¥28/an", "Renouvellement automatique"),
        ]

        for (language, strings) in expected {
            let bundle = try localizedBundle(language)
            let text = PaywallSubscriptionCopy.purchaseDisclosure(
                kind: .yearly,
                displayPrice: "¥28",
                isTrialEligible: true,
                bundle: bundle
            )
            XCTAssertTrue(text.contains(strings.trial), "\(language) missing trial+price: \(text)")
            XCTAssertTrue(text.contains(strings.renew), "\(language) missing auto-renew: \(text)")
        }
    }

    private func localizedBundle(_ language: String) throws -> Bundle {
        let bundleURL = try XCTUnwrap(
            Bundle.main.url(forResource: language, withExtension: "lproj"),
            "Missing localization bundle for \(language)"
        )
        return try XCTUnwrap(Bundle(url: bundleURL))
    }
}
