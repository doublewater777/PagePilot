# Implementation

- Keep `ReaderViewController` responsible for ending the session when its view disappears.
- Remove the `willEnterForeground` observer and Reader-session restart path.
- Let the background handler update foreground-facing state without clearing the stored session.
- Reuse the existing Watch context and Reading Live Activity coordinator; no new ActivityKit lifecycle is introduced.
