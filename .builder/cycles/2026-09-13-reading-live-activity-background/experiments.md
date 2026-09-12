# Experiments

- Add a source-boundary regression test proving `didEnterBackground` does not call the Reader session finish path.
- Add a regression test proving no `willEnterForeground` path restarts a finished Reader session.
- Run the focused Reading Live Activity suites and the full iPhone 17 simulator suite.
- Real-device pass threshold: enter a visual Reader, lock the device, unlock, and return to another app while the Live Activity remains visible; exiting the Reader still removes it.
- Loop back if background retention causes stale reading state after Reader dismissal.
