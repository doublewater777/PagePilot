# Assumptions

- A visual Reader remains the active reading session while its view controller stays in the app navigation stack, even when iOS moves the app to the background.
- ActivityKit may continue to display and refresh the existing Live Activity while the app is backgrounded.
- Watch readers expect the session timer to remain meaningful across short app switches rather than resetting on each backgrounding.
- Falsifier: real-device behavior shows iOS rejects or visibly degrades the retained Live Activity often enough that users prefer immediate cleanup.
