# Implementation

- Add `WatchGuideEligibility.shouldShow(isPhone:)`; `OnboardingFlow.shouldShowWatchGuide` now ignores `step`.
- `VisualReaderViewController` shows the guide only for actionable Watch states (`appNotInstalled` or `unpaired`), dismisses only for the current Reader session, and keeps the collapsed-state persistence.
- Remove the 10-second auto-collapse from `OnboardingWatchGuideView`.
- `WatchSettingsView` gains an install section shown only for `appNotInstalled` with plain guidance copy; the private `bridge://` scheme was dropped because iOS silently refuses to open it.
