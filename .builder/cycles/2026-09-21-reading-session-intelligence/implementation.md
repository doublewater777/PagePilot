# Implementation

## Architecture

### Existing sources of truth

Keep the current responsibilities:

- `Book.locator` / `Book.progression`: resume position.
- `ReadingStatsStore`: current daily aggregates, goals, streaks, badges, and existing stats UI.
- `ReadingSession`: immutable historical fact describing one reading interval.

Do not make session history responsible for restoring the current Reader position.

## ReadingSession model

Initial fields:

- `id`: local database primary key.
- `sessionID`: stable UUID for future sync/deduplication.
- `bookId`: parent book.
- `startedAt`.
- `endedAt`.
- `durationSeconds`.
- `startProgression`.
- `endProgression`.
- `watchPageTurns`.

Derived values should not be persisted unless needed for query performance:

- progress delta.
- progress per minute.
- estimated remaining time.

## Persistence

- Store sessions in GRDB.
- Index by `startedAt`.
- Add a compound index for `bookId + startedAt`.
- Cascade-delete local session records when a Book is deleted.
- Persist all non-zero-duration sessions even if they are too small to show in the UI.

## Reader integration

Reuse the existing `ReaderViewController` lifecycle rather than adding another session manager:

- capture start timestamp, start progression, and Watch-turn counter at session start;
- capture end timestamp, end progression, and Watch-turn delta at session end;
- continue recording the same interval into `ReadingStatsStore`;
- persist `ReadingSession` independently.

A failure to persist detailed history must not prevent the Reader from closing or daily stats from being recorded.

## Session Summary

A later UI ticket should present, for a meaningful session:

- duration;
- start → end progression;
- positive progress made;
- Watch page turns when non-zero;
- optional daily-goal state.

Example:

> 28 min  
> 32% → 39% · +7%  
> 29 Watch page turns

The summary should be dismissible and should not automatically present a paywall.

## Reading History

Provide chronological session history with:

- date/time;
- book;
- duration;
- progress range;
- Watch-turn context.

Per-book history should be queryable separately from global history.

## Pace and finish estimate

For qualifying positive-progress sessions:

1. Calculate each session's forward progress per active minute.
2. Use a recent-window or recency-weighted average rather than lifetime average.
3. Estimate remaining active reading minutes:
   `(1 - currentProgression) / weightedProgressPerMinute`.
4. Convert to a finish date only when there is enough recent daily-reading behavior to support it.
5. Display estimates as approximate, not guaranteed dates.

Do not include sessions with negative/zero progress in the velocity denominator.

## Pro behavior

- Keep immediate session feedback free.
- Gate longitudinal insight at the destination/action level.
- Avoid a blocking upgrade sheet automatically appearing after Reader exit.
- Existing entitlement infrastructure should be reused.

## Cloud sync follow-up

When session synchronization is added:

- add a distinct CloudKit record type;
- use `sessionID` as stable identity;
- treat completed sessions as immutable records;
- deduplicate by `sessionID`;
- only sync when existing Cloud Sync preference and Pro entitlement permit it;
- define deletion/tombstone behavior consistently with Book deletion.

## Migration strategy

No backfill of historical sessions is required. Existing daily aggregates cannot be losslessly expanded into per-session history. Session history starts accumulating after the migration is installed.
