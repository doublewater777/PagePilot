# Goal

- User problem: tapping PagePilot's Live Activity in the Apple Watch Smart Stack falls back to “Open on iPhone” instead of opening the installed Watch app.
- Target user: readers controlling an active iPhone or iPad Reader from Apple Watch.
- Desired behavior: tapping the reading Live Activity launches PagePilot on Apple Watch, where the existing previous/next and Digital Crown controls are immediately available.
- Success: the embedded Watch app explicitly declares support for `ReadingLiveActivityAttributes`, and the PagePilot test suite remains green.
- Out of scope: executing page turns directly inside the Live Activity extension or changing the existing WatchConnectivity command path.
