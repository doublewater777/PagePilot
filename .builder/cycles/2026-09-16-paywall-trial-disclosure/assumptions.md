# Assumptions

- Apple is flagging Paywall copy, not the existence of subscriptions.
- Yearly Pro is the default plan and the only live free trial (ONE_WEEK).
- StoreKit `displayPrice` is the source of truth; hardcoded CNY/USD amounts would fail in other storefronts.
- Falsifier: Reviewer still cannot see the post-trial price next to the subscribe CTA.
