# Experiments

- Ship in a TestFlight build and walk the first-run flow on iPhone: Watch intro page → publication picker → Reader with activation card.
- Verify iPad onboarding starts at publication picker → Reader directly.
- Measure (manual, TestFlight cohort): does the Watch intro page render in all 5 locales without truncation; does Continue advance to book selection; does choosing a book open the Reader directly; does relaunch mid-onboarding resume on the saved step.
- Pass threshold: full iPhone 17 simulator suite green, fresh-install walkthrough matches the expected sequence, iPad path unchanged.
- Loop-back trigger: testers report the intro page as friction, or the Reader activation card becomes redundant (consider merging the two surfaces).
