# Implementation

- Add localized Workout compatibility guidance to iPhone Watch Settings, including the system Return to App workaround and the optional one-hour Return to Clock suggestion.
- Define `ReadingPreviousPageIntent`, `ReadingNextPageIntent`, and their request payload beside the shared Live Activity attributes.
- Add previous/next `Button(intent:)` controls to the Watch-oriented `.small` Reading Live Activity while retaining title, elapsed time, and progress.
- Observe intent requests at app launch and route them through `WatchPageTurnService`.
- Reuse local Reader turning and the existing Pro iPad LAN relay; do not add a parallel navigation stack.
