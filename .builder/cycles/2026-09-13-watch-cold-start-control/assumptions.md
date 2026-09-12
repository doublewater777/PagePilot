# Assumptions

- The observed delay is the initial WCSession activation/reachability transition, not a persistent transport failure.
- A short connection grace period is enough for the paired iPhone to become reachable in the reported flow.
- Preserving one command is safer than replaying every tap or Crown event after connection.
- Falsifier: real-device launches regularly exceed the grace period or a buffered command executes after the user no longer expects it.
