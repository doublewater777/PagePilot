# Experiments

- Add red/green tests that bind the Live Activity previous/next intents to the existing `PageCommand.prev` and `.next` raw values.
- Verify every intent request gets a unique command identifier so LAN retries reuse one logical ID instead of producing a burst.
- Run localization validation and the full iPhone 17 simulator suite through CI.
- On a paired Watch, start Workout, let Workout become frontmost, open Smart Stack, tap PagePilot previous/next, and confirm the visible Reader turns exactly once.
- Repeat with iPhone Reader, Pro iPad relay, unavailable Reader, and rapid taps.
