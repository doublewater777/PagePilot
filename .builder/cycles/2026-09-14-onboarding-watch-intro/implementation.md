# Implementation

- Add `OnboardingFlow.Step.watchIntro` (iPhone path only): `didChoosePublication` routes iPhone to `.watchIntro`, iPad keeps going straight to `.reader`.
- Add `OnboardingFlow.didFinishWatchIntro()` advancing `.watchIntro` → `.reader`.
- Add `watchIntroScreen` in `OnboardingView`: hero, title, subtitle, three benefit rows, single CTA that advances and opens the Reader via the existing transition.
- Localize new `onboarding_watch_intro_*` keys in all 5 locales (de/en/es/fr/zh-Hans).
- Update `OnboardingFlowTests` for the new routing; keep legacy-step migration tests intact.
- Not built: reading goal, reminders, Pro pages, any change to the Reader activation card or `WatchGuidePresentationPolicy`.
- Dependencies: none beyond existing onboarding helpers (`scrollingScreen`, `primaryButton`, `AppColors`).
