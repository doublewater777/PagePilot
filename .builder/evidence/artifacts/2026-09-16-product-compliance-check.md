# Product Compliance Check

Product / feature: Paywall free-trial disclosure for App Review resubmission
Target markets: US, China, EU
Platforms: iOS
Data collected: unchanged
Payments: auto-renewing yearly (7-day free trial) and monthly subscriptions, plus lifetime IAP
AI / UGC / sensitive domains: none in this change

Overall risk: Watch, pending App Review
Blocking risks: previous binary was rejected under Guideline 3.1.2(c) for unclear free-trial conversion
High risks: none remaining in checked scope if the new disclosure stays visible beside the CTA
Watch items: monthly has no trial; copy must not imply a trial on that plan

Policy evidence:
- Source: Apple App Store Review Guidelines 3.1.2 Subscriptions
  Requirement: clearly disclose title, duration, price, auto-renewal, and free-trial conversion before purchase
  Link: https://developer.apple.com/app-store/review/guidelines/#subscriptions
  Impact: trial duration, post-trial StoreKit price, and auto-renew/cancel now appear on the plan card and under the subscribe button
- Source: Apple subscription information
  Requirement: functional Terms and Privacy links, restore purchases, and accurate localized pricing
  Link: https://developer.apple.com/app-store/subscriptions/
  Impact: existing Terms/Privacy/Restore remain; price comes from StoreKit `displayPrice`

Required changes: ship the Paywall disclosure update in a new binary
Recommended safeguards: keep using live StoreKit prices; do not hardcode ¥28 / $4.99 in UI
Recommended review owner: App Review resubmission
Incomplete checks: live Apple guideline HTML could not be fetched in this session; used official URLs plus current ASC product state (yearly ONE_WEEK free trial, monthly no intro offer)
Not legal advice: this is a launch-risk screen, not legal advice
