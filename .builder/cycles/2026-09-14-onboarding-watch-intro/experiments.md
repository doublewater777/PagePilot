# Experiments

- Ship in a TestFlight build and walk the first-run flow on iPhone: publication picker → Watch intro page → Reader with activation card.
- Verify iPad onboarding still goes publication picker → Reader directly.
- Measure (manual, TestFlight cohort): does the Watch intro page render in all 5 locales without truncation; does the CTA reach the Reader every time; does relaunch mid-onboarding resume on the intro page.
- Pass threshold: full iPhone 17 simulator suite green, fresh-install walkthrough matches the expected sequence, iPad path unchanged.
- Loop-back trigger: testers report the extra page as friction, or the Reader activation card becomes redundant (consider merging the two surfaces).
