---
stage: 01-hypothesis
status: backfilled
gate: pass
updated_at: 2026-06-07
loop_back_to:
---

# Hypothesis

## Current Summary

PagePilot targets Apple ecosystem readers who lose reading flow when they must touch the screen to turn pages. The core proof action is importing a local book, opening it, and turning pages from Apple Watch.

## Evidence

- Product shipped and approved on App Store (2026-06-06).
- Website and launch copy name four scenarios: bed, gym, commute/train, device on a stand.
- See `project.yaml` for wedge definition.

## Related Cycles

- `2026-07-19-onboarding-import-sources` — tests whether supporting Files, Wi-Fi transfer, and OPDS reduces the first-book import barrier.

## Decisions

- Hypothesis backfilled retroactively before stage 02 user interviews.
- Stage 02 will validate whether the pain is behavior-backed or mostly aspirational.

## Open Questions

- Which scenario has the strongest recent, costly workaround behavior?
- Do readers already own Apple Watch and use it while reading?
- Is local EPUB/PDF import a blocker or a non-issue for the wedge?

## Gate

Verdict: pass (structural)
Reason: Hypothesis is falsifiable, segment is recruitable, proof action is observable.
Note: Pain itself is not yet validated — that is stage 02's job.

## Falsifiable Hypothesis

```text
I believe Apple ecosystem readers in bed, gym, commute, or stand-mounted reading scenarios
have pain because touching the screen breaks posture, comfort, and reading flow.
They currently use auto-scroll, voice control, Bluetooth page turners, or awkward one-handed taps,
but these fail because they are unreliable, unavailable for local books, or still interrupt flow.
If I provide local-first reading with Apple Watch page-turn control,
they will import a book, read with Watch, and return to the workflow within a week.
```

User: Apple ecosystem readers (iPhone/iPad + optional Apple Watch) who read local ebooks.
Scenario: Reading with device mounted or in a posture where reaching for the screen is awkward.
Pain: Screen taps break posture, comfort, and reading flow.
Current workaround: Auto-scroll, Voice Control, physical remotes, one-handed tap, or stopping reading.
Why workaround is bad: Unreliable, DRM-incompatible, extra hardware, or still breaks immersion.
Core solution: Local-first reader with Apple Watch page-turn control.
Proof action: Import a book, complete a reading session with Watch page turns, return within 7 days.

Assumptions to test:

1. The pain is recent and frequent enough that people have already tried workarounds.
2. Apple Watch is already on the wrist during at least one high-frequency reading scenario.
3. Local book import is acceptable for the wedge user (not blocked by Kindle-only habits).

## Change Log

- 2026-06-07: Backfilled from `project.yaml` and launch copy before stage 02 interviews.
