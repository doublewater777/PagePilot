# Goal

- User problem: readers whose paired Watch lacks the PagePilot app never see the install guidance, because the Reader tip was gated on first-run onboarding progress.
- Target user: any iPhone reader with a paired Watch, regardless of onboarding state.
- Desired behavior: the Reader tip and Watch Settings react to live device state — the install action appears whenever the Watch app is missing, independent of onboarding completion.
- Success: guide visibility no longer depends on `OnboardingFlow.step`, Watch Settings exposes the install action when `appNotInstalled`, and the regression tests pass.
- Out of scope: bookshelf reminders, push notifications, iPad (LAN relay needs no Watch app).
