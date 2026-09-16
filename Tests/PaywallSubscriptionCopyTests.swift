import Foundation
import XCTest
@testable import PagePilot

final class PaywallSubscriptionCopyTests: XCTestCase {
    private let sevenDays = PaywallTrialPeriod(value: 7, unit: .day, periodCount: 1)
    private let oneWeek = PaywallTrialPeriod(value: 1, unit: .week, periodCount: 1)
    private let oneMonth = PaywallTrialPeriod(value: 1, unit: .month, periodCount: 1)

    func testYearlyTrialDisclosureIncludesDurationPriceAndAutoRenew() throws {
        let english = try localizedBundle("en")
        let chinese = try localizedBundle("zh-Hans")

        let enText = PaywallSubscriptionCopy.purchaseDisclosure(
            kind: .yearly,
            displayPrice: "$4.99",
            isTrialEligible: true,
            trialPeriod: sevenDays,
            billingPeriod: "year",
            bundle: english
        )
        XCTAssertEqual(
            enText,
            "7-day free trial, then $4.99/year. Automatically renews unless canceled in App Store subscription settings."
        )

        let zhText = PaywallSubscriptionCopy.purchaseDisclosure(
            kind: .yearly,
            displayPrice: "¥28",
            isTrialEligible: true,
            trialPeriod: sevenDays,
            billingPeriod: "年",
            bundle: chinese
        )
        XCTAssertEqual(
            zhText,
            "7 天免费试用，之后 ¥28/年，自动续订。可随时在 App Store 订阅设置中取消。"
        )
    }

    func testYearlyTrialDisclosureUsesStoreKitMonthInsteadOfSevenDays() throws {
        let english = try localizedBundle("en")
        let text = PaywallSubscriptionCopy.purchaseDisclosure(
            kind: .yearly,
            displayPrice: "$4.99",
            isTrialEligible: true,
            trialPeriod: oneMonth,
            billingPeriod: "year",
            bundle: english
        )
        XCTAssertEqual(
            text,
            "1-month free trial, then $4.99/year. Automatically renews unless canceled in App Store subscription settings."
        )
        XCTAssertFalse(text.contains("7-day"))
    }

    func testYearlyTrialDisclosureUsesOneWeekPeriod() throws {
        let english = try localizedBundle("en")
        let german = try localizedBundle("de")
        let spanish = try localizedBundle("es")
        let french = try localizedBundle("fr")

        XCTAssertEqual(
            PaywallSubscriptionCopy.purchaseDisclosure(
                kind: .yearly,
                displayPrice: "$4.99",
                isTrialEligible: true,
                trialPeriod: oneWeek,
                billingPeriod: "year",
                bundle: english
            ),
            "1-week free trial, then $4.99/year. Automatically renews unless canceled in App Store subscription settings."
        )
        XCTAssertTrue(
            PaywallSubscriptionCopy.purchaseDisclosure(
                kind: .yearly,
                displayPrice: "¥28",
                isTrialEligible: true,
                trialPeriod: oneWeek,
                billingPeriod: "Jahr",
                bundle: german
            ).contains("1 Woche kostenlos, danach ¥28/Jahr")
        )
        XCTAssertTrue(
            PaywallSubscriptionCopy.purchaseDisclosure(
                kind: .yearly,
                displayPrice: "¥28",
                isTrialEligible: true,
                trialPeriod: oneWeek,
                billingPeriod: "año",
                bundle: spanish
            ).contains("Prueba gratuita de 1 semana, luego ¥28/año")
        )
        XCTAssertTrue(
            PaywallSubscriptionCopy.purchaseDisclosure(
                kind: .yearly,
                displayPrice: "¥28",
                isTrialEligible: true,
                trialPeriod: oneWeek,
                billingPeriod: "an",
                bundle: french
            ).contains("Essai gratuit de 1 semaine, puis ¥28/an")
        )
    }

    func testTwoWeekFreeTrialUsesStoreKitValueWithSinglePeriod() throws {
        let english = try localizedBundle("en")
        let twoWeeks = PaywallTrialPeriod(value: 2, unit: .week, periodCount: 1)
        let text = PaywallSubscriptionCopy.purchaseDisclosure(
            kind: .yearly,
            displayPrice: "$4.99",
            isTrialEligible: true,
            trialPeriod: twoWeeks,
            billingPeriod: "year",
            bundle: english
        )
        XCTAssertTrue(text.contains("2-week free trial"), text)
        XCTAssertFalse(text.contains("1-week free trial"))
    }

    func testBillingDisclosurePreservesMultiUnitStoreKitPeriod() throws {
        let english = try localizedBundle("en")
        let text = PaywallSubscriptionCopy.purchaseDisclosure(
            kind: .monthly,
            displayPrice: "$9.99",
            isTrialEligible: false,
            trialPeriod: nil,
            billingPeriod: "3 months",
            bundle: english
        )
        XCTAssertEqual(
            text,
            "$9.99/3 months. Automatically renews unless canceled in App Store subscription settings."
        )
    }

    func testEligibleWithoutTrialPeriodDoesNotInventSevenDays() throws {
        let english = try localizedBundle("en")
        let text = PaywallSubscriptionCopy.purchaseDisclosure(
            kind: .yearly,
            displayPrice: "$4.99",
            isTrialEligible: true,
            trialPeriod: nil,
            billingPeriod: "year",
            bundle: english
        )
        XCTAssertEqual(
            text,
            "$4.99/year. Automatically renews unless canceled in App Store subscription settings."
        )
        XCTAssertFalse(text.contains("7-day"))
    }

    func testPaidAndLifetimeDisclosuresStayExplicit() throws {
        let english = try localizedBundle("en")

        let monthly = PaywallSubscriptionCopy.purchaseDisclosure(
            kind: .monthly,
            displayPrice: "$0.99",
            isTrialEligible: false,
            trialPeriod: sevenDays,
            billingPeriod: "month",
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
            trialPeriod: nil,
            billingPeriod: nil,
            bundle: english
        )
        XCTAssertTrue(lifetime.lowercased().contains("one-time"))
        XCTAssertFalse(lifetime.lowercased().contains("automatically renews"))
    }

    func testBuyButtonUsesStoreKitDuration() throws {
        let english = try localizedBundle("en")
        let chinese = try localizedBundle("zh-Hans")

        XCTAssertEqual(
            PaywallSubscriptionCopy.buyButtonText(
                kind: .yearly,
                isTrialEligible: true,
                trialPeriod: sevenDays,
                bundle: english
            ),
            "Start 7-Day Free Trial"
        )
        XCTAssertEqual(
            PaywallSubscriptionCopy.buyButtonText(
                kind: .yearly,
                isTrialEligible: true,
                trialPeriod: oneMonth,
                bundle: english
            ),
            "Start 1-Month Free Trial"
        )
        XCTAssertEqual(
            PaywallSubscriptionCopy.buyButtonText(
                kind: .yearly,
                isTrialEligible: true,
                trialPeriod: sevenDays,
                bundle: chinese
            ),
            "开始 7 天免费试用"
        )
        XCTAssertEqual(
            PaywallSubscriptionCopy.buyButtonText(
                kind: .yearly,
                isTrialEligible: false,
                trialPeriod: sevenDays,
                bundle: english
            ),
            "Continue"
        )
        XCTAssertEqual(
            PaywallSubscriptionCopy.buyButtonText(
                kind: .lifetime,
                isTrialEligible: false,
                trialPeriod: nil,
                bundle: english
            ),
            "Unlock Lifetime"
        )
    }

    func testMonthlyEligibleDisclosureAndCTAUseInjectedDuration() throws {
        let english = try localizedBundle("en")
        let disclosure = PaywallSubscriptionCopy.purchaseDisclosure(
            kind: .monthly,
            displayPrice: "$0.99",
            isTrialEligible: true,
            trialPeriod: oneMonth,
            billingPeriod: "month",
            bundle: english
        )
        XCTAssertEqual(
            disclosure,
            "1-month free trial, then $0.99/month. Automatically renews unless canceled in App Store subscription settings."
        )
        XCTAssertEqual(
            PaywallSubscriptionCopy.buyButtonText(
                kind: .monthly,
                isTrialEligible: true,
                trialPeriod: oneMonth,
                bundle: english
            ),
            "Start 1-Month Free Trial"
        )
    }

    func testMonthlyEligibleSubtitleUsesInjectedDuration() throws {
        let english = try localizedBundle("en")
        let subtitle = PaywallSubscriptionCopy.planSubtitle(
            kind: .monthly,
            displayPrice: "$0.99",
            isTrialEligible: true,
            trialPeriod: oneMonth,
            billingPeriod: "month",
            fallback: "$0.99/month",
            bundle: english
        )
        XCTAssertEqual(subtitle, "1-month free, then $0.99/month")
    }

    func testYearlyPlanSubtitleKeepsDiscountComparisonWhenTrialEligible() throws {
        let english = try localizedBundle("en")
        let subtitle = PaywallSubscriptionCopy.planSubtitle(
            kind: .yearly,
            displayPrice: "$4.99",
            isTrialEligible: true,
            trialPeriod: sevenDays,
            billingPeriod: "year",
            fallback: "Only $0.42/month, save 16%",
            bundle: english
        )
        XCTAssertEqual(subtitle, "Only $0.42/month, save 16%")
    }

    func testTrialDisclosureDoesNotRepeatPlanSubtitle() throws {
        let english = try localizedBundle("en")
        let chinese = try localizedBundle("zh-Hans")

        let enSubtitle = PaywallSubscriptionCopy.planSubtitle(
            kind: .yearly,
            displayPrice: "$4.99",
            isTrialEligible: true,
            trialPeriod: sevenDays,
            billingPeriod: "year",
            fallback: "Only $0.42/month, save 16%",
            bundle: english
        )
        let enDisclosure = PaywallSubscriptionCopy.purchaseDisclosure(
            kind: .yearly,
            displayPrice: "$4.99",
            isTrialEligible: true,
            trialPeriod: sevenDays,
            billingPeriod: "year",
            bundle: english
        )
        XCTAssertEqual(enSubtitle, "Only $0.42/month, save 16%")
        XCTAssertFalse(enDisclosure.hasPrefix(enSubtitle), enDisclosure)

        let zhSubtitle = PaywallSubscriptionCopy.planSubtitle(
            kind: .yearly,
            displayPrice: "¥28",
            isTrialEligible: true,
            trialPeriod: sevenDays,
            billingPeriod: "年",
            fallback: "仅 ¥2.3/月，省 16%",
            bundle: chinese
        )
        let zhDisclosure = PaywallSubscriptionCopy.purchaseDisclosure(
            kind: .yearly,
            displayPrice: "¥28",
            isTrialEligible: true,
            trialPeriod: sevenDays,
            billingPeriod: "年",
            bundle: chinese
        )
        XCTAssertEqual(zhSubtitle, "仅 ¥2.3/月，省 16%")
        XCTAssertFalse(zhDisclosure.hasPrefix(zhSubtitle), zhDisclosure)
        XCTAssertNotEqual(zhSubtitle, zhDisclosure)
    }

    func testSupportedLanguagesKeepTrialPriceAndRenewalTogether() throws {
        let expected: [String: (trial: String, renew: String, billing: String)] = [
            "en": ("7-day free trial, then ¥28/year", "Automatically renews", "year"),
            "zh-Hans": ("7 天免费试用，之后 ¥28/年", "自动续订", "年"),
            "de": ("7 Tage kostenlos, danach ¥28/Jahr", "Verlängert sich automatisch", "Jahr"),
            "es": ("Prueba gratuita de 7 días, luego ¥28/año", "Se renueva automáticamente", "año"),
            "fr": ("Essai gratuit de 7 jours, puis ¥28/an", "Renouvellement automatique", "an"),
        ]

        for (language, strings) in expected {
            let bundle = try localizedBundle(language)
            let text = PaywallSubscriptionCopy.purchaseDisclosure(
                kind: .yearly,
                displayPrice: "¥28",
                isTrialEligible: true,
                trialPeriod: sevenDays,
                billingPeriod: strings.billing,
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
