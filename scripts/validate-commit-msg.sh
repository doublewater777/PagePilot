#!/usr/bin/env bash
# Validates commit messages against docs/agents/commit-convention.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/version.sh
source "${SCRIPT_DIR}/lib/version.sh"

COMMIT_MSG_FILE="${1:-}"
if [[ -z "$COMMIT_MSG_FILE" || ! -f "$COMMIT_MSG_FILE" ]]; then
  echo "usage: validate-commit-msg.sh <commit-msg-file>" >&2
  exit 1
fi

# Use the first non-empty, non-comment line as the subject.
SUBJECT=""
while IFS= read -r line || [[ -n "$line" ]]; do
  trimmed="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  if [[ -z "$trimmed" || "$trimmed" == \#* ]]; then
    continue
  fi
  SUBJECT="$trimmed"
  break
done < "$COMMIT_MSG_FILE"

if [[ -z "$SUBJECT" ]]; then
  echo "commit-msg: empty commit message" >&2
  exit 1
fi

# Git-generated merge/revert messages are exempt.
if [[ "$SUBJECT" =~ ^Merge ]]; then
  exit 0
fi
if [[ "$SUBJECT" =~ ^Revert ]]; then
  exit 0
fi
if [[ "$SUBJECT" =~ ^(fixup!|squash!) ]]; then
  exit 0
fi

if [[ ! "$SUBJECT" =~ ^([0-9]+\.[0-9]+\.[0-9]+):\ .+ ]]; then
  cat >&2 <<EOF
commit-msg: invalid format

Subject must start with the current app version:

  <version>: <description>

Examples:
  1.0.8: feat: improve WatchRemote UI
  1.0.8: fix: guard PRO state on foreground
  1.0.8: release

See docs/agents/commit-convention.md
EOF
  exit 1
fi

COMMIT_VERSION="${BASH_REMATCH[1]}"
EXPECTED_VERSION="$(expected_commit_version)"

if ! is_valid_semver "$COMMIT_VERSION"; then
  echo "commit-msg: version must use major.minor.patch (e.g. 1.0.8)" >&2
  exit 1
fi

if [[ "$COMMIT_VERSION" != "$EXPECTED_VERSION" ]]; then
  cat >&2 <<EOF
commit-msg: version mismatch

  commit message: ${COMMIT_VERSION}
  expected:       ${EXPECTED_VERSION}

Use the version from VERSION at the repo root.
To start a new release line, bump VERSION first:

  ./scripts/bump-version.sh <new-version>

See docs/agents/commit-convention.md
EOF
  exit 1
fi

exit 0