---
stage: 02-user-interviews
status: active
gate: pending
updated_at: 2026-06-07
loop_back_to: 01-hypothesis
---

# User Interviews

## Current Summary

Interview count: 0 / 10–20 target

A users: 0
B users: 0
C users: 0

Stage opened retroactively while PagePilot is at stage 10 (growth channel). Goal: validate whether Apple Watch page-turn pain is behavior-backed before scaling distribution messaging.

## Related Cycles

- `2026-06-06-app-store-approval-launch` — launch post on 即刻 already asks for scenario feedback; treat replies and DMs as interview leads.

## Inputs

- Hypothesis: `.builder/stages/01-hypothesis.md`
- Target wedge: bed, gym, commute/train, stand-mounted reading
- Recruiting draft: 即刻 launch post (`.builder/evidence/artifacts/2026-06-06-launch-ready-copy-pack.md`)

## Interview Script (PagePilot)

Open with context, not the product:

> I'm researching how people read ebooks when their phone or iPad is in an awkward position — not pitching anything yet.

### Core questions (past behavior only)

1. When was the last time you were reading and reaching for the screen felt annoying?
2. What were you doing — bed, commute, gym, desk stand, something else?
3. What did you do to keep reading without tapping the screen?
4. What tools, hacks, apps, or hardware did you try? (auto-scroll, Voice Control, Bluetooth remote, Apple Watch, etc.)
5. How much time or money did that cost you?
6. What happened when the workaround failed?
7. Why did you stop using that approach?
8. Have you run into this more than once in the past month?

### Follow-ups

- Walk me through the last time — what did you do right before and after?
- Who else was in the room or situation?
- What would have happened if you ignored it and kept tapping?
- Can you show me the setup? (photo, screen recording, or live demo)

### Segment probes (pick one scenario per interview)

| Segment | Opening probe |
|---------|---------------|
| Bed reader | Last time you read in bed with phone on a stand or pillow — how did you turn pages? |
| Gym reader | Last time you read on cardio equipment — what broke your rhythm? |
| Commute reader | Last time on train/plane with a small tray — how did page turns work? |
| Stand reader | Last time iPad was on a desk stand — what was awkward about tapping? |

### Forbidden → translate

| Don't ask | Ask instead |
|-----------|-------------|
| Would you use Watch page turning? | Last time you wished you didn't have to touch the screen — what did you try? |
| Would you pay for this? | What have you already spent (time/money) to fix awkward page turning? |
| Is this feature important? | How often did this happen in the last 30 days? |

### Classification rubric

- **A — strong pain**: problem in last 30 days; spent real time/money on workaround; can describe concrete workflow; open to follow-up.
- **B — weak pain**: recognizes annoyance; no active workaround attempt.
- **C — fake demand**: likes the concept; no recent specific scenario.

## Evidence

Interviews: _(none yet — log under `.builder/evidence/interviews/YYYY-MM-DD-person-or-segment.md`)_

Repeated pain patterns: _(pending)_
Current workarounds: _(pending)_
Costs observed: _(pending)_

## Decisions

- Only A users drive wedge selection (stage 03) and messaging (stage 10).
- Do not optimize launch copy from C-user enthusiasm alone.
- Founder conducts first 5 interviews manually (DM or 15-min call) before widening recruiting.

## Recruiting Plan

| Source | Who | How |
|--------|-----|-----|
| 即刻 launch post replies | CN readers, Apple users | Reply to comments; DM people who describe a scenario |
| Apple communities | r/apple, r/iPad, MacRumors forums | "How do you turn pages when..." threads — no product link in first message |
| Reading communities | 豆瓣读书, Kindle 贴吧, local ebook groups | Ask about local EPUB/PDF reading habits + page-turn friction |
| Personal network | Friends with Apple Watch | Direct outreach with scenario-specific opener |
| App Store reviews | PagePilot early users | Reply asking about their last reading setup (support email) |

Target mix: 5 bed, 3 commute, 3 stand, 2 gym (adjust as recruiting reveals density).

## Open Questions

- Which scenario produces the most A users?
- Do A users already wear Apple Watch while reading, or is Watch an untested idea?
- Is local import a gating pain or secondary to page-turn pain?
- CN vs EN segment — does pain pattern differ?

## Gate

Verdict: pending
Pass requires: ≥5 A users, recent behavior-backed pain, repeated workaround pattern.
Fail triggers: loop back to `01-hypothesis` and redefine user or problem.
Current blockers: 0 interviews logged.

## Change Log

- 2026-06-07: Stage opened; script and recruiting plan added; awaiting first interviews.