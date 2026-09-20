# Tickets

## RS-1 — Persist detailed ReadingSession history

**Status:** implementation in PR #57.

### Scope

- Add GRDB `ReadingSession` table and model.
- Persist stable `sessionID`, book, timestamps, duration, progress range, and Watch turns.
- Add recent/global and recent/per-book repository queries.
- Hook persistence into the existing Reader lifecycle.
- Keep `ReadingStatsStore` unchanged.
- Add persistence and cascade-delete tests.

### Acceptance criteria

- One completed Reader interval produces one durable session.
- Existing reading stats behavior does not regress.
- Data survives process relaunch.
- Book deletion cleans up its local session history.
- Full test suite passes.

---

## RS-2 — Harden session lifecycle and measurement

**Depends on:** RS-1.

### Scope

- Verify foreground/background and Reader navigation boundaries on iPhone and iPad.
- Prevent duplicate session finalization.
- Verify Watch page-turn deltas for direct Watch control and iPad relay.
- Add focused lifecycle tests where practical.
- Document any unsupported media types.

### Acceptance criteria

- Background → foreground produces two non-overlapping sessions.
- Reader dismissal produces exactly one finalization.
- A successful Watch turn inside a session increments that session's Watch count.
- No session is attributed to the wrong book.

---

## RS-3 — Add post-session Summary

**Depends on:** RS-1, RS-2.

### Scope

- Show a lightweight summary only after a meaningful visible Reader exit.
- Apply the proposed meaningful-session threshold.
- Show duration, progress range/delta, and Watch turns when relevant.
- Integrate daily-goal feedback without duplicating the current goal celebration.
- Support iPhone and adaptive iPad layouts.

### Acceptance criteria

- Accidental/trivial opens do not show a summary.
- A qualifying session shows understandable metrics.
- The summary can be dismissed immediately.
- No automatic blocking paywall is shown.
- VoiceOver and Dynamic Type remain usable.

---

## RS-4 — Add Reading History

**Depends on:** RS-1.

### Scope

- Add chronological recent-session history.
- Add per-book session history.
- Reuse existing book metadata/cover presentation where appropriate.
- Keep today's basic feedback available to free users.
- Apply existing Pro entitlement patterns to longitudinal history if approved.

### Acceptance criteria

- Sessions appear newest-first.
- A user can identify book, date/time, duration, and progress movement.
- Deleted books cannot leave broken local history rows.
- Empty/loading states are defined.

---

## RS-5 — Add reading pace and finish prediction

**Depends on:** RS-1, RS-4.

### Scope

- Implement a deterministic pace calculator over qualifying sessions.
- Enforce minimum reliability thresholds.
- Estimate remaining active reading time.
- Optionally estimate finish date from recent daily reading behavior.
- Expose confidence/insufficient-data states.
- Gate prediction as Pro without hiding basic session facts.

### Acceptance criteria

- No prediction is shown below the reliability threshold.
- Backward/no-progress sessions do not inflate forward velocity.
- Unit tests cover slow, fast, sparse, and mixed histories.
- UI labels the result as an estimate.

---

## RS-6 — Sync ReadingSession history with iCloud

**Depends on:** RS-1; should follow product validation of history.

### Scope

- Add CloudKit ReadingSession record type.
- Use stable `sessionID` for deduplication.
- Reuse existing Pro + Cloud Sync enablement policy.
- Define Book deletion/tombstone semantics.
- Handle records arriving before their parent Book.

### Acceptance criteria

- The same session is not duplicated across devices.
- Sync is disabled when Pro access or Cloud Sync preference is disabled.
- Deferred-parent behavior is safe.
- Existing Book/ReadingProgress/Bookmark/Highlight sync is unaffected.

---

## RS-7 — Contextual Pro conversion and product measurement

**Depends on:** RS-3, RS-4, RS-5.

### Scope

- Define the exact free/Pro boundary.
- Add a non-blocking upgrade entry from history/prediction surfaces.
- Do not automatically paywall Reader exit.
- Measure Summary → History/Prediction intent and upgrade entry taps using the project's approved analytics approach, if any.

### Acceptance criteria

- Free users always receive useful immediate session feedback.
- Premium value is visible before upgrade.
- Upgrade messaging references concrete unlocked insight.
- No new analytics SDK is introduced solely for this ticket.
