#!/usr/bin/env bash
# Install repo-local git hooks for commit message validation.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

chmod +x \
  "${REPO_ROOT}/scripts/validate-commit-msg.sh" \
  "${REPO_ROOT}/scripts/bump-version.sh" \
  "${REPO_ROOT}/scripts/prepare-submission.sh" \
  "${REPO_ROOT}/scripts/commit-release.sh" \
  "${REPO_ROOT}/scripts/mark-shipped.sh" \
  "${REPO_ROOT}/scripts/lib/version.sh"

git -C "$REPO_ROOT" config core.hooksPath .githooks

echo "Installed git hooks via core.hooksPath=.githooks"
echo "Current app version: $(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"