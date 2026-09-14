# Goal

- User problem: after PR #45 collapsed onboarding to a single publication-picker page, new users immediately faced book import without understanding PagePilot's core differentiator — hands-free page turning with Apple Watch.
- Target user: new iPhone users in the target wedge (readers who want hands-free page turning with Apple Watch) during first-run onboarding.
- Desired behavior: first-run iPhone users see one focused Watch value page before book import; tapping Continue advances to the publication picker; selecting or importing a book is the final onboarding step, directly opening the Reader with the Watch activation card.
- Success: iPhone onboarding begins with the Watch value intro page, moves to publication selection, and opens the Reader immediately after book selection; iPad onboarding starts directly at publication selection and advances to Reader; regression tests cover the full sequence.
- Out of scope: reading-goal/reminder pages, Pro upsell pages, notification permission prompts, iPad onboarding changes, Watch app install flow changes.
