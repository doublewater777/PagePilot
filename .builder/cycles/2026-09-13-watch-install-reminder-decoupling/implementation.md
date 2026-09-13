# Implementation

- Add `WatchGuideEligibility.shouldShow(isPhone:)`; `OnboardingFlow.shouldShowWatchGuide` now ignores `step`.
- `VisualReaderViewController` shows the guide whenever the Watch app could matter (any availability except `.unsupported`), dismisses only for the current Reader session, and keeps the collapsed-state persistence.
- Remove the 10-second auto-collapse from `OnboardingWatchGuideView`.
- `WatchSettingsView` gains an install section shown only for `appNotInstalled`, opening the iPhone Watch app via `WatchPageTurnService.watchAppURL`.
