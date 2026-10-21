# RT-1 — Reading Time Accuracy: Measurement and Durability Contract

Status: Draft PR #88; not merge approved. This specification defines RT-1 only, not RT-2/3/4/5.

## Sources of truth and attribution

- **Measured duration:** the monotonic `ProcessInfo.processInfo.systemUptime` delta while the visual Reader is active; never `endedAt - startedAt` for the duration when the system clock can be adjusted.
- **Day/hour attribution:** the `recordedAt` wall-clock sample taken at each checkpoint; allocate the *new, uncommitted* monotonic seconds backwards from this observed boundary, split at local calendar day/hour transitions.
- **Precision boundary:** if wall time/time zone changes between samples, the exact instant of that change cannot always be observed; consequently a finite amount of day/hour attribution can be inaccurate even while the monotonic **total seconds remain correct**. No promise of sub-checkpoint, absolute time-of-day attribution. A significant-time-change event requests an additional sample.
- Fall DST repeated local hours share the same `hourlySeconds[1]` bucket (24-bucket chart); spring DST skips absent local hour buckets. Date/hour loops must progress across DST and unusual UTC offsets.

## Checkpoint and crash-recovery guarantees

The Reader requests a checkpoint approximately every 15 seconds, and a final checkpoint when a session ends, is backgrounded, or loses its active scene.

The following states are **not interchangeable**:

1. **Queued:** the checkpoint is in an in-process serial dispatch queue but has **not yet** been written to disk. Queuing alone confers **no restart durability**.
2. **Recovery journal durably written:** an ending interval, with `sessionID`, monotonic elapsed cursor, `startedAt`, sampled `recordedAt`, and book identity, is atomically written to the separate recovery log. If main aggregate storage fails or the process stops before aggregation, this interval can be replayed on launch or foreground activation.
3. **Aggregate durably written:** the daily totals and the committed `sessionID` cursor are updated atomically in the main daily-stats JSON. Subsequent checkpoints/replays must not double-count these seconds.

The final write callback reports **two independent outcomes**: `aggregateSaved` and `recoveryJournalSaved`. `isRecoverable` is true when either durable path succeeded. A failed journal write must not be presented as guaranteed recovery. An in-memory fallback permits same-process retry but does not survive termination.

**Limited recovery guarantee, explicitly accepted:** The app restores successfully committed seconds, and a previously durable recovery-journal entry may restore a final unaggregated interval. If the process is terminated, suspended, or expires **before the journal is first persisted**, or if both aggregate and journal writes fail, the interval after the last successfully committed checkpoint can be lost. RT-1 does **not** claim lossless accounting for unsaved seconds; a normal 44-second session forcibly killed after checkpoints at 15s and 30s may restore only 30s.

A finite `UIApplication.beginBackgroundTask` lease protects the ending write as far as iOS allows. It must be ended exactly once on normal completion or system expiration. iOS may end this lease early and offers no absolute guarantee that either write completes before termination.

## Recovery journal integrity and retries

- Distinguish **nonexistent journal** (no pending records) from **existing unreadable/corrupt journal** (error).
- Never use an empty dictionary to overwrite a journal that exists but cannot be read or decoded; preserve the original bytes for future diagnosis/recovery.
- A newly queued ending interval may proceed to aggregate storage even if the recovery journal failed, but the result must expose which durable path succeeded.
- Replay pending entries at startup and app activation via the process-wide serial IO queue. Remove the journal entry only after aggregate persistence succeeds.
- Journal cleanup failure is safe: `sessionID` + committed elapsed cursor make repeated replay idempotent.
- A failed journal stage may retain a transient in-process record for retry; this is **not** restart durability.

## Scope and merge gates

- Freeze end progression, dates, monotonic duration, `sessionID` and successful Watch-turn count **before** the asynchronous final checkpoint; callback must not re-query a mutable Navigator.
- Keep Reader timer and disk work on separate executors; serialize all existing and new reads/updates of daily totals.
- Tests: final result combinations, corrupt journal preservation after a new final session, retry/deduplication, 44s interruption, concurrent writers, DST, wall-clock changes, and expiration/completion race ending the background lease once.
- **Physical-device gate A:** iPad with two independent Reader windows in a supported configuration. Verify unrelated scene events do not finalize or start the wrong Reader; verify Split View/Stage Manager focus, resizing, and repeated App/Scene notifications.
- **Physical-device gate B:** on a supported iPhone/iPad, background and force-terminate during an ending checkpoint; inspect on-device aggregate/journal state before and after relaunch and confirm outcomes match the three states above. Also record background task expiration and page-turn responsiveness when practical.
- A simulator CI pass does not substitute for either physical-device gate. PR #88 stays Draft until both are evidenced and an exact-HEAD review approves it.
