# Implementation

- Replace the empty Watch launch-attribute declaration with the explicit `ReadingLiveActivityAttributes` type name.
- Add a hosted-app regression test that reads the plist from the Watch app embedded in the built PagePilot app.
- Reuse the existing Watch app UI and WatchConnectivity page-turn implementation.
- Do not add AppIntent buttons to the mirrored Live Activity in this cycle.
