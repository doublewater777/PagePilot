@ AGENTS.md

## Agent skills

### Issue tracker

Issues and PRDs are tracked in GitHub Issues. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the default mattpocock/skills triage label vocabulary. See `docs/agents/triage-labels.md`.

### Domain docs

This repo uses a single-context domain documentation layout. See `docs/agents/domain.md`.

### Commit convention

Every commit must start with the app version from `VERSION`. See `docs/agents/commit-convention.md`. Install hooks with `./scripts/setup-hooks.sh`.

### App Store submission

When the user says **提审** or asks to submit for review, follow `docs/agents/submission-flow.md`. Default target is `SHIPPED_VERSION + 1 patch`. Re-submissions keep the same marketing version and only increment build. Update What's New, then commit/tag/push with `./scripts/commit-release.sh` before staging to App Store Connect.
