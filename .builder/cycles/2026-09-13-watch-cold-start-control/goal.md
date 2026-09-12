# Goal

- User problem: after the Watch app opens from the Live Activity, WatchConnectivity can need a few seconds before page-turn controls respond.
- Target user: readers launching PagePilot's Watch controls from an active reading Live Activity.
- Desired behavior: show a clear connection state and preserve the first page-turn gesture during the short cold-start window.
- Success: the first command entered during startup is sent once when the iPhone becomes reachable, while later startup taps do not create a burst of page turns.
- Out of scope: direct AppIntent controls inside the Live Activity, background page-turn delivery, or changing iPad relay routing.
