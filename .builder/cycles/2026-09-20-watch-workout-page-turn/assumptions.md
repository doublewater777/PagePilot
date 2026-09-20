# Assumptions

- Workout's Return to App behavior is user-controlled; PagePilot should explain the setting rather than trying to override it.
- Apple's `LiveActivityIntent` launches the containing app process without opening its UI, so the intent can hand work to PagePilot's existing service path.
- The shared `ReadingLiveActivityAttributes.swift` source already belongs to both the app and Live Activity extension targets and is the safest place for shared intent declarations.
- Existing Watch routing semantics remain authoritative: local iPhone Reader and Pro iPad relay may both receive the same logical page-turn request.
- Falsifier: paired-device testing shows mirrored Watch Live Activity buttons execute only in the widget extension or fail to wake the containing app process.
