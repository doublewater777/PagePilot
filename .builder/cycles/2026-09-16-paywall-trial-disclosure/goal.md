# Goal

- User problem: App Review rejected the current subscription screen under Guideline 3.1.2(c) because the free trial was visible, but the post-trial price and auto-renewal were not clearly shown before purchase.
- Target user: first-time subscribers seeing the in-app Paywall, including App Review.
- Desired behavior: before tapping subscribe, users can see trial length, the exact price after the trial, and that the plan auto-renews unless canceled.
- Success: yearly trial copy on the selected plan and directly under the purchase button includes duration + localized StoreKit price + auto-renew/cancel; tests cover all 5 locales.
- Out of scope: changing prices, adding a monthly trial, RevenueCat, or submitting the new build.
