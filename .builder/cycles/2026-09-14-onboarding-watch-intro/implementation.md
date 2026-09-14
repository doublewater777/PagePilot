# Implementation

- `OnboardingFlow`: iPhone initial step is `.watchIntro`; iPad initial step is `.choosePublication`.
- `OnboardingFlow.didFinishWatchIntro()` advances `.watchIntro` → `.choosePublication`.
- `OnboardingFlow.didChoosePublication()` advances `.choosePublication` → `.reader` directly on both platforms.
- `OnboardingView`: `watchIntroScreen` displays hero, title, subtitle, 3 value props, and Continue CTA that advances to `publicationScreen`. Book selection in `publicationScreen` directly opens the Reader via `persistAndOpenReader()`.
- Localize `onboarding_watch_intro_*` keys in all 5 locales (de/en/es/fr/zh-Hans).
- Update `OnboardingFlowTests` for the new sequence; verify step normalization, persistence on relaunch, and localization parity.
- Not built: reading goal, reminders, Pro pages, any change to the Reader activation card or `WatchGuidePresentationPolicy`.
- Dependencies: none beyond existing onboarding helpers (`scrollingScreen`, `primaryButton`, `AppColors`).
