# PagePilot RevenueCat

## Configuration

- Project: `proj1f57f9a1` ([dashboard](https://app.revenuecat.com/projects/proj1f57f9a1)).
- App: `app334401cbe5`, App Store bundle ID `com.panyang.PagePilot`.
- SDK: `purchases-ios-spm` 5.94.0, linked only to the iOS app.
- Entitlement: `pro` (`entl41349e3562`).
- Current offering: `default` (`ofrngb81f7934e3`).

| Package | App Store product |
| --- | --- |
| `$rc_monthly` | `com.panyang.PagePilot.pro.monthly` |
| `$rc_annual` | `com.panyang.PagePilot.pro.yearly` |
| `$rc_lifetime` | `com.panyang.PagePilot.pro.lifetime` (non-consumable) |

The iOS public SDK key is in `Integrations/SPM/RevenueCat.xcconfig`. Both Debug and Release include it. This is a public client key; no Apple private key or RevenueCat secret key is in the repository. Optional machine-local overrides go in the gitignored `Integrations/SPM/RevenueCat.local.xcconfig`.

The existing Apple In-App Purchase key is configured in RevenueCat. App Store Connect metadata import credentials and App Store Server Notifications remain separate dashboard configuration. The SDK gets prices and introductory offers from StoreKit through RevenueCat.

## App behavior

`AppDelegate` configures RevenueCat before `AppModule` accesses `ProPurchaseManager`. RevenueCat owns all purchases, restoration, transaction observation, and finishing. The existing custom paywall displays packages from the current offering, retaining its price, trial, and renewal disclosures. No RevenueCatUI hosted paywall is required.

`ProPurchaseManager` applies the active `pro` entitlement through the existing notification and iPad relay lifecycle. Network failures preserve the previously cached Pro status. A successfully confirmed expired entitlement revokes access. The DEBUG `-PagePilotDebugPro` / `PagePilotDebugPro` override remains available.

## Existing customers

The App Store product IDs are unchanged, so existing Apple subscriptions continue their renewal schedule and price. On the first launch with RevenueCat, `syncPurchases()` imports existing purchases without prompting for an explicit restore. The completion flag `revenuecat_synced_v1` is written only after successful synchronization. Concurrent launch/foreground refreshes share one task.

Before that sync completes, unsolicited empty CustomerInfo updates cannot revoke cached access. If RevenueCat reports no Pro while StoreKit still verifies a valid existing purchase, synchronization is treated as incomplete and retried later. This StoreKit check is read-only: it does not purchase, restore, observe updates, or finish transactions. The paywall's explicit Restore Purchases action remains available.

## Verification

`Tests/ProPurchaseManagerTests.swift` covers cached access on errors, legacy synchronization and retries, delegate updates, expiration, purchase confirmation, cancellation, restore, public key validation, entitlement mapping, and DEBUG access. `Tests/PaywallSubscriptionCopyTests.swift` covers trial and billing disclosures across supported locales.

Verified on 2026-10-12:

- Debug builds succeeded with zero errors and warnings.
- 30 purchase manager / paywall copy tests passed on iPhone 18 Pro, iOS 27.0. Result bundle: `/Users/water/Library/Developer/MobileBuildMCP/workspaces/dev-48b27da0eab4/result-bundles/test_sim_2026-10-12T03-51-38-499Z_pid67121_6b0d81cc.xcresult`.
- Localization validation passed for all five app and App Store locales.
- App Store Connect app `6760964443` has both subscriptions and the lifetime non-consumable in `APPROVED` state, with the unchanged product IDs above.
- The public SDK endpoint returns all three packages from the current `default` offering. The iOS app launches with RevenueCat configured for StoreKit 2 and receives successful CustomerInfo responses.
- A bare simulator launch did not resolve App Store products. It does not activate the scheme's StoreKit configuration file; use Xcode's Run configuration for local StoreKit UI testing, or a real sandbox account on a device for end-to-end validation.

Before releasing, verify a sandbox purchase and restore against the PagePilot project and an existing subscriber's entitlement after synchronization. Local code tests alone cannot prove a real customer's receipt migration.
