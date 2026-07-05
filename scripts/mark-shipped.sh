#!/usr/bin/env bash
# Record the version currently live on the App Store.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/version.sh
source "${REPO_ROOT}/scripts/lib/version.sh"

NEW_SHIPPED="${1:-}"

if [[ -z "$NEW_SHIPPED" ]]; then
  echo "usage: mark-shipped.sh <major.minor.patch>" >&2
  echo "current shipped: $(shipped_version)" >&2
  exit 1
fi

if ! is_valid_semver "$NEW_SHIPPED"; then
  echo "mark-shipped: version must use major.minor.patch" >&2
  exit 1
fi

OLD_SHIPPED="$(shipped_version)"
printf '%s\n' "$NEW_SHIPPED" > "${REPO_ROOT}/SHIPPED_VERSION"

cat <<EOF
Marked App Store live version ${OLD_SHIPPED} -> ${NEW_SHIPPED}

Next 提审 default target: $(next_patch_version "$NEW_SHIPPED")

Suggested commit:
  ${NEW_SHIPPED}: chore: mark ${NEW_SHIPPED} as shipped
EOF