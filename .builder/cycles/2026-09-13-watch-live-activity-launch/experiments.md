# Experiments

- Inspect the embedded Watch app's final `Info.plist`, not only the source plist.
- Pass threshold: `WKSupportsLiveActivityLaunchAttributeTypes` equals `["ReadingLiveActivityAttributes"]`.
- Run the focused configuration regression test and the full iPhone 17 simulator test suite.
- Build the PagePilot scheme for the existing iPad simulator destination.
- Loop back if a freshly reinstalled Watch app on watchOS 11.1+ still enters the iPhone fallback wrapper.
