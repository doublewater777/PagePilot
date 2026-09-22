# Assumptions

## Session lifecycle

- A session starts when a visual Reader is visible and the iOS application is active.
- A session ends when the Reader leaves the screen or the app enters the background.
- Returning from the background begins a new session. This intentionally matches the current ReadingStats and Live Activity lifecycle.
- Audiobook playback is not part of this Reading Session model unless explicitly added later.

## Progress

- Readium `totalProgression` is the canonical cross-format progress signal for this feature.
- EPUB pagination is reflow-dependent, so the product should not label progress delta as an exact number of pages read.
- Negative progress delta can happen when a user navigates backward. Store the raw start/end positions, but presentation-level "progress made" should not become negative.

## Watch usage

- Watch page turns are measured from successful Watch-originated page-turn commands.
- A Watch turn count is contextual evidence of hands-free reading, not a proxy for pages read.
- The first version does not need to distinguish Digital Crown, button, Double Tap, direct iPhone control, and iPad relay paths in the persisted schema.

## Meaningful summary threshold

Proposed first-pass rule for showing a post-session summary:

- duration >= 2 minutes, OR
- forward progress delta >= 1%, OR
- successful Watch page turns >= 5.

Shorter sessions may still be persisted for data correctness but do not need to interrupt the user with a summary.

## Prediction reliability

Do not show a finish estimate until a book has at least:

- 3 qualifying sessions,
- 20 minutes of accumulated reading time,
- 5 percentage points of positive cumulative progress.

Sessions with zero or negative progress should contribute reading time/history but should not be used to calculate forward reading velocity.

## Monetization

Proposed product boundary:

- Free: current-session summary and today's reading feedback.
- Pro: longitudinal session history, per-book pace trends, finish prediction, and session history iCloud sync.

This aligns with the existing product direction where broader historical statistics and iCloud capabilities are premium.

## Falsification

The model should be revised if real usage shows that app backgrounding creates excessive session fragmentation, progression is too noisy for pace estimates, or users interpret percentage progress as exact pagination.
