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

`ProPurchaseManager` applies the active `pro` entitlement through the existing notification and iPad relay lifecycle. Network failures preserve the previously cached Pro status. Empty delegate updates trigger guarded re-verification instead of directly revoking access. A successfully confirmed expired entitlement revokes access. The DEBUG `-PagePilotDebugPro` / `PagePilotDebugPro` override remains available.

## Existing customers

The App Store product IDs are unchanged, so existing Apple subscriptions continue their renewal schedule and price. On the first launch with RevenueCat, `syncPurchases()` imports existing purchases without prompting for an explicit restore. The completion flag `revenuecat_synced_v1` is written only after successful synchronization. Concurrent launch/foreground refreshes share one task.

Before that sync completes, unsolicited empty CustomerInfo updates cannot revoke cached access. If RevenueCat reports no Pro while StoreKit still verifies a valid existing purchase, synchronization is treated as incomplete and retried later. The same validation protects explicit restore and subsequent foreground refreshes; a valid Apple purchase must not be mistaken for a confirmed expiration. This StoreKit check is read-only: it does not purchase, restore, observe updates, or finish transactions. The paywall's explicit Restore Purchases action remains available.

## Verification

`Tests/ProPurchaseManagerTests.swift` covers cached access on errors, legacy synchronization and retries, delegate updates, expiration, purchase confirmation, cancellation, restore, public key validation, entitlement mapping, and DEBUG access. `Tests/PaywallSubscriptionCopyTests.swift` covers trial and billing disclosures across supported locales.

Verified on 2026-10-12:

- Debug builds succeeded with zero errors and warnings.
- 38 purchase manager, paywall copy, and opt-in StoreKit integration tests passed (zero failures or skips) on iPhone 18 Pro, iOS 27.0. Result bundle: `/Users/water/Library/Developer/MobileBuildMCP/workspaces/dev-48b27da0eab4/result-bundles/test_sim_2026-10-12T04-15-12-648Z_pid67121_99361398.xcresult`.
- After adding empty-delegate-update protection, all 31 manager / paywall copy tests passed, including the new regression test (zero failures or skips). Result bundle: `/Users/water/Library/Developer/MobileBuildMCP/workspaces/dev-48b27da0eab4/result-bundles/test_sim_2026-10-12T04-21-18-192Z_pid67121_23450b0d.xcresult`. Across the two runs, all 39 distinct tests passed.
- Localization validation passed for all five app and App Store locales.
- App Store Connect app `6760964443` has both subscriptions and the lifetime non-consumable in `APPROVED` state, with the unchanged product IDs above.
- The public SDK endpoint returns all three packages from the current `default` offering. The iOS app launches with RevenueCat configured for StoreKit 2 and receives successful CustomerInfo responses.
- A bare simulator launch did not resolve App Store products. It does not activate the scheme's StoreKit configuration file; use Xcode's Run configuration for local StoreKit UI testing, or a real sandbox account on a device for end-to-end validation.
- The repaired `PagePilot.storekit` resolves all three product IDs, the monthly/yearly billing periods, and the local annual three-day trial. Local transactions verify monthly/yearly/lifetime legacy recognition, refunds, expiration without renewal, and preservation of valid Apple purchases when RevenueCat reports no Pro.
- An isolated local StoreKit smoke test used the real SDK and PagePilot backend to load the offering, purchase lifetime Pro, confirm an active sandbox `pro` entitlement, and restore access into a new purchase manager with empty cached defaults. RevenueCat's customer API independently confirms customer `pagepilot-local-smoke-6AA7D2B6-3E46-4E5D-931A-3BB67B2C4D0C`, purchase `otpAap1b38ed4b593f30331b7a06b47db6e401`, product `prodaecb834f43`, and entitlement `entl41349e3562`. Its store purchase identifier starts with `StoreKitTest_Transaction_`, proving this is an Xcode synthetic transaction, **not** an Apple sandbox receipt.
- After testing, the app was rebuilt and launched with the normal iOS public SDK key; no test-only build override is persisted.

## Repeating local integration tests

`ProStoreKitIntegrationTests` is opt-in and skips by default. On iOS 27, StoreKitTest must initialize before the app/SDK makes its first StoreKit connection. For a MobileBuildMCP `test_sim` run, supply:

- Build arguments: `CODE_SIGNING_ALLOWED=NO`, `ONLY_ACTIVE_ARCH=YES`, `REVENUECAT_API_KEY=` (empty for this test build only), and `-only-testing:PagePilotTests/ProStoreKitIntegrationTests`.
- Test-runner environment: `PAGEPILOT_RC_LOCAL_STOREKIT=1`.
- For the optional network purchase/restore test, also supply `PAGEPILOT_RC_LOCAL_SMOKE=1` and `PAGEPILOT_RC_SMOKE_API_KEY` containing the iOS public SDK key from `Integrations/SPM/RevenueCat.xcconfig`. The test configures RevenueCat after creating its local StoreKit session and uses a unique `pagepilot-local-smoke-…` customer.

The StoreKit file is bundled only in the test target. These transactions use synthetic local prices, do not charge money, and do not verify Apple servers. After testing, rebuild normally without the empty-key override. Do not change the checked-in Debug/Release key to run these tests.

## Remaining release acceptance

Use a dedicated test installation, not an installation containing a real user's books, for reinstall/restore scenarios:

1. On a device signed into an Apple sandbox account, purchase a current offering package and verify the correct customer, transaction, and active `pro` entitlement in RevenueCat's Sandbox view.
2. Cancel the Apple purchase sheet and verify no error alert, loading state is cleared, and another attempt is possible.
3. Reinstall the dedicated test app, sign into the same sandbox account, and restore from the paywall. Verify Pro and its gated features return.
4. Upgrade an existing subscriber's installation in place (do not uninstall). Verify no new purchase is required, Pro remains available, and the original purchase is recognized by RevenueCat after synchronization.

Before releasing, verify a sandbox purchase and restore against the PagePilot project and an existing subscriber's entitlement after synchronization. Local code tests alone cannot prove a real customer's receipt migration.
