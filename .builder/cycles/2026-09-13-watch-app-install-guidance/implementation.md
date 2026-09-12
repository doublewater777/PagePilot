# Implementation

- Add `WatchPageTurnService.watchAppURL` (`bridge://`, the iPhone Watch app).
- In `OnboardingWatchGuideView`, show a bordered-prominent `onboarding_watch_install_action` button only for the `appNotInstalled` state; tapping it opens the Watch app URL via the SwiftUI `openURL` environment.
- Keep the existing skip/collapse action beside the new button and leave all other availability states unchanged.
- Localize the new key in English, Simplified Chinese, German, Spanish, and French.
