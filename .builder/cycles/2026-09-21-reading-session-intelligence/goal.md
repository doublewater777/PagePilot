# Goal

## Product problem

PagePilot already records daily reading totals and the current book position, but it does not preserve a durable record of each individual reading session. This prevents the product from answering useful questions such as:

- What happened in the reading session that just ended?
- How much progress did I make?
- How often do I read this book?
- How fast am I moving through it?
- At my current pace, when am I likely to finish?
- How much of my reading flow is being controlled from Apple Watch?

The missing primitive is a durable per-session history.

## Target user

Readers using PagePilot on iPhone or iPad, especially users who use Apple Watch page turning and read in repeated short or medium sessions.

## Desired behavior

Every active visual reading session produces a durable `ReadingSession` record. PagePilot can then use those records to provide:

1. a useful summary when a meaningful session ends;
2. recent reading history;
3. per-book pace and finish estimates;
4. Watch usage context;
5. a natural path to Pro features such as long-term insights and iCloud synchronization.

## Product principles

- Local-first. Reading history works without an account or network connection.
- Do not replace current reading progress. `Book.locator` / `Book.progression` remain the source of truth for resume position.
- Do not regress existing daily goals, streaks, badges, or statistics.
- Prefer progress percentage over invented EPUB "page counts".
- Avoid interruptive paywalls when the user exits a reading session.
- Predictions must be withheld when there is not enough reliable data.

## Success criteria

- A completed active reading session is durably queryable after relaunch.
- A session includes book, start/end timestamps, duration, start/end progression, and Watch page turns.
- Existing daily reading totals remain correct.
- A meaningful session can produce a concise post-session summary.
- Per-book history can support a pace estimate only after a defined reliability threshold is met.
- Free users retain useful session feedback; Pro adds longitudinal insight rather than blocking basic feedback.

## Out of scope for the first data-layer ticket

- Session Summary UI.
- Reading History UI.
- Finish-date prediction UI.
- New Pro paywall behavior.
- CloudKit synchronization of session records.
- Replacing `ReadingStatsStore` with derived SQL aggregates.
