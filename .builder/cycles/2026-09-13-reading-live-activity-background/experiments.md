# Experiments

- Keep source-boundary regression tests proving `didEnterBackground` finishes the session (without goal celebration) and `willEnterForeground` restarts it.
- Run the focused Reading Live Activity suites and the full iPhone 17 simulator suite.
- Real-device pass threshold: background the app mid-reading and confirm the Live Activity disappears; returning to the Reader starts a fresh activity.
- Loop back if readers miss the Lock Screen presence enough to revisit the policy.
