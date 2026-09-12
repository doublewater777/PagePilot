# Assumptions

- A Live Activity that only exists to support Watch page turning has no value once the app is backgrounded, because the Reader is no longer the visible surface.
- Ending the session on backgrounding and restarting it on foregrounding is cheap and keeps state easy to reason about.
- Falsifier: real-device use shows readers want the Lock Screen timer or progress visible even when they cannot turn pages.
