# Retro

- Belief: backgrounding should pause foreground-only Reader accounting, not end the user-visible reading session.
- Learning: the old single `readingSessionStartDate` mixed two lifecycles; splitting it from foreground stats keeps Live Activity state alive while preserving accurate foreground reading time.
- Decision: close the implementation cycle after paired-device lock-screen verification.
- Follow-up: loop back if iOS or ActivityKit shows a retained activity after an actual Reader dismissal.
