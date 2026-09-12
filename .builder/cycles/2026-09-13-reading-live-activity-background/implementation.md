# Implementation

- Revert to a single `readingSessionStartDate` lifecycle: start on appear, finish on disappear or on backgrounding (with `celebrateGoal: false`).
- Restart the session from the `willEnterForeground` handler.
- Remove the foreground-stats pause/resume split introduced earlier today; one session timer covers stats again.
