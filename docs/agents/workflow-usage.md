# Agent Workflow Usage

Use this file as the minimum PagePilot convention for when to apply the installed engineering skills.

## TDD

Use `tdd` for behavior that can be verified through a public interface, especially Library import/removal behavior, Reader state behavior, Reading Progress persistence, Watch Page Turn handling, and Pro Access limits.

Do not write implementation-detail tests that assert private helper calls, internal collaborator call counts, or storage rows directly when the same behavior can be observed through a higher-level interface.

## Diagnose

Use `diagnose` when a bug, crash, failing test, or performance regression is reported.

Start by building a deterministic feedback loop: a failing test, a focused CLI command, a simulator reproduction, or a small harness. Do not patch from intuition when the failure has not been reproduced.

## Handoff

Use `handoff` when work spans multiple sessions, touches several modules, creates GitHub issues, changes repo workflow, or leaves follow-up tasks.

The handoff should include the goal, completed work, unfinished work, changed files, GitHub issue numbers, verification commands, and any unresolved decisions.

## Architecture Evolution

Use `improve-codebase-architecture` when PagePilot code becomes harder to change because concepts are mixed, public interfaces are too wide, tests lack a useful seam, or domain terms drift from `CONTEXT.md`.

Create an ADR only when a decision is hard to reverse, surprising without context, and the result of a real trade-off.
