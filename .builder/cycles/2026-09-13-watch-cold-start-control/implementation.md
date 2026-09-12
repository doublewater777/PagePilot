# Implementation

- Add a small shared first-command buffer with unit coverage.
- Treat the first five seconds of an unreachable cold launch as connecting.
- Show localized connecting guidance during that period.
- Drain the buffered command once WCSession becomes reachable; discard it on timeout.
- Do not alter command fan-out, iPad relay behavior, or Live Activity interaction architecture.
