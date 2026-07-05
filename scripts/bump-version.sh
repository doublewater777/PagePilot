#!/usr/bin/env bash
# Bump the canonical app version and sync project templates.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/version.sh
source "${REPO_ROOT}/scripts/lib/version.sh"

NEW_VERSION="${1:-}"
INCREMENT_BUILD=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --increment-build)
      INCREMENT_BUILD=1
      shift
      ;;
    *)
      if [[ -z "$NEW_VERSION" ]]; then
        NEW_VERSION="$1"
      fi
      shift
      ;;
  esac
done

if [[ -z "$NEW_VERSION" ]]; then
  echo "usage: bump-version.sh <major.minor.patch> [--increment-build]" >&2
  echo "current: $(current_version)" >&2
  exit 1
fi

if ! is_valid_semver "$NEW_VERSION"; then
  echo "bump-version: version must use major.minor.patch (e.g. 1.0.8)" >&2
  exit 1
fi

OLD_VERSION="$(current_version)"
if [[ "$NEW_VERSION" == "$OLD_VERSION" ]]; then
  echo "bump-version: already at ${OLD_VERSION}" >&2
  exit 1
fi

printf '%s\n' "$NEW_VERSION" > "${REPO_ROOT}/VERSION"

while IFS= read -r template; do
  sed -i '' -E "s/(MARKETING_VERSION: )${OLD_VERSION}/\1${NEW_VERSION}/g" "$template"
done < <(find "${REPO_ROOT}/Integrations" -name 'project*.yml' -type f)

if [[ -f "${REPO_ROOT}/project.yml" ]]; then
  sed -i '' -E "s/(MARKETING_VERSION: )${OLD_VERSION}/\1${NEW_VERSION}/g" "${REPO_ROOT}/project.yml"
fi

update_plist_version() {
  local plist="$1"
  [[ -f "$plist" ]] || return 0

  sed -i '' -E "/<key>CFBundleShortVersionString<\/key>/{n;s/<string>[^<]*<\/string>/<string>${NEW_VERSION}<\/string>/;}" "$plist"
}

update_plist_version "${REPO_ROOT}/iPhone/Info.plist"
update_plist_version "${REPO_ROOT}/WatchRemote/Info.plist"

NEW_BUILD=""
if [[ "$INCREMENT_BUILD" -eq 1 ]]; then
  plist="${REPO_ROOT}/iPhone/Info.plist"
  current_build="$(sed -n '/<key>CFBundleVersion<\/key>/{n;p;}' "$plist" | sed -E 's/.*<string>([^<]*)<\/string>.*/\1/' | tr -d '[:space:]')"
  if [[ -n "$current_build" && "$current_build" =~ ^[0-9]+$ ]]; then
    NEW_BUILD="$((current_build + 1))"
    for target_plist in "${REPO_ROOT}/iPhone/Info.plist" "${REPO_ROOT}/WatchRemote/Info.plist"; do
      sed -i '' -E "/<key>CFBundleVersion<\/key>/{n;s/<string>[^<]*<\/string>/<string>${NEW_BUILD}<\/string>/;}" "$target_plist"
    done
  fi
fi

cat <<EOF
Bumped ${OLD_VERSION} -> ${NEW_VERSION}

Updated:
  VERSION
  Integrations/**/project*.yml
  project.yml (if present)
  iPhone/Info.plist
  WatchRemote/Info.plist
EOF

if [[ -n "$NEW_BUILD" ]]; then
  echo "  CFBundleVersion -> ${NEW_BUILD}"
fi

cat <<EOF

Suggested commit:
  ${NEW_VERSION}: release

Suggested tag after commit:
  git tag v${NEW_VERSION}
EOF