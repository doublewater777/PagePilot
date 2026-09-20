# Experiments

## Data-layer verification

- Create a temporary database and verify session insert/read.
- Verify recent sessions sort newest-first.
- Verify per-book filtering.
- Verify progression and Watch-turn boundary handling.
- Verify zero-duration sessions are ignored.
- Verify deleting a Book cascades its ReadingSession rows.
- Run the full PagePilot iOS test suite.

## Lifecycle verification

On iPhone and iPad:

1. Open a visual book.
2. Read/turn pages.
3. Leave the Reader.
4. Confirm exactly one detailed session is persisted.
5. Confirm the existing daily reading total increases by the same elapsed interval.

Repeat with:

- app background → foreground;
- Reader dismissal;
- Watch page turns;
- iPad Watch relay if available.

Expected background behavior: backgrounding closes the current session; returning creates a new one.

## Session Summary experiment

Pass threshold:

- no summary for trivial accidental opens;
- meaningful sessions show duration and progress without requiring interpretation;
- Watch turns are shown only when relevant;
- dismissing the Reader never immediately traps the user behind a paywall.

## Prediction experiment

Use synthetic histories to verify:

- no estimate before the reliability threshold;
- zero/negative-progress sessions do not inflate pace;
- faster recent sessions appropriately move the estimate;
- displayed language remains approximate.

## Product signal

After release, evaluate whether users who see Session Summary return to the same book and open history/insight surfaces more often than users who only see existing daily statistics.
