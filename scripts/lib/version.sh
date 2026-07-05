#!/usr/bin/env bash
# Shared helpers for reading the canonical app version.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION_FILE="${REPO_ROOT}/VERSION"
SHIPPED_VERSION_FILE="${REPO_ROOT}/SHIPPED_VERSION"

read_version_from_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "version file not found: $file" >&2
    return 1
  fi
  tr -d '[:space:]' < "$file"
}

current_version() {
  read_version_from_file "$VERSION_FILE"
}

shipped_version() {
  read_version_from_file "$SHIPPED_VERSION_FILE"
}

staged_version_if_bumping() {
  if ! git -C "$REPO_ROOT" diff --cached --name-only --diff-filter=ACMR | grep -qx 'VERSION'; then
    return 1
  fi

  local staged
  staged="$(git -C "$REPO_ROOT" show :VERSION 2>/dev/null || true)"
  if [[ -z "$staged" ]]; then
    return 1
  fi

  printf '%s' "$(printf '%s' "$staged" | tr -d '[:space:]')"
}

expected_commit_version() {
  if staged="$(staged_version_if_bumping 2>/dev/null)"; then
    printf '%s' "$staged"
    return 0
  fi

  current_version
}

is_valid_semver() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

version_parts() {
  local version="$1"
  local major minor patch
  IFS='.' read -r major minor patch <<< "$version"
  printf '%s %s %s' "$major" "$minor" "$patch"
}

version_gt() {
  local left="$1"
  local right="$2"
  local left_major left_minor left_patch right_major right_minor right_patch
  read -r left_major left_minor left_patch < <(version_parts "$left")
  read -r right_major right_minor right_patch < <(version_parts "$right")

  if (( left_major > right_major )); then return 0; fi
  if (( left_major < right_major )); then return 1; fi
  if (( left_minor > right_minor )); then return 0; fi
  if (( left_minor < right_minor )); then return 1; fi
  (( left_patch > right_patch ))
}

version_gte() {
  [[ "$1" == "$2" ]] || version_gt "$1" "$2"
}

next_patch_version() {
  local version="$1"
  if ! is_valid_semver "$version"; then
    echo "invalid semver: $version" >&2
    return 1
  fi

  local major minor patch
  IFS='.' read -r major minor patch <<< "$version"
  printf '%s.%s.%s' "$major" "$minor" "$((patch + 1))"
}

default_submission_target() {
  next_patch_version "$(shipped_version)"
}

metadata_dir_for_version() {
  printf '%s/metadata/version/%s' "$REPO_ROOT" "$1"
}

latest_metadata_version() {
  local dir version
  for dir in "${REPO_ROOT}"/metadata/version/*/; do
    [[ -d "$dir" ]] || continue
    version="$(basename "$dir")"
    if is_valid_semver "$version"; then
      printf '%s\n' "$version"
    fi
  done | sort -t. -k1,1n -k2,2n -k3,3n | tail -1
}

sync_version_files() {
  local target="$1"
  local current
  current="$(current_version)"

  printf '%s\n' "$target" > "$VERSION_FILE"

  while IFS= read -r template; do
    sed -i '' -E "s/(MARKETING_VERSION: )[0-9]+\.[0-9]+\.[0-9]+/\1${target}/g" "$template"
  done < <(find "${REPO_ROOT}/Integrations" -name 'project*.yml' -type f)

  if [[ -f "${REPO_ROOT}/project.yml" ]]; then
    sed -i '' -E "s/(MARKETING_VERSION: )[0-9]+\.[0-9]+\.[0-9]+/\1${target}/g" "${REPO_ROOT}/project.yml"
  fi

  for plist in "${REPO_ROOT}/iPhone/Info.plist" "${REPO_ROOT}/WatchRemote/Info.plist"; do
    [[ -f "$plist" ]] || continue
    sed -i '' -E "/<key>CFBundleShortVersionString<\/key>/{n;s/<string>[^<]*<\/string>/<string>${target}<\/string>/;}" "$plist"
  done

  if [[ "$current" != "$target" ]]; then
    echo "Synced version ${current} -> ${target}"
  else
    echo "Synced version ${target}"
  fi
}

increment_build_number() {
  local plist current_build new_build
  plist="${REPO_ROOT}/iPhone/Info.plist"
  current_build="$(sed -n '/<key>CFBundleVersion<\/key>/{n;p;}' "$plist" | sed -E 's/.*<string>([^<]*)<\/string>.*/\1/' | tr -d '[:space:]')"

  if [[ -z "$current_build" || ! "$current_build" =~ ^[0-9]+$ ]]; then
    echo "increment-build: could not read CFBundleVersion from ${plist}" >&2
    return 1
  fi

  new_build="$((current_build + 1))"
  for target_plist in "${REPO_ROOT}/iPhone/Info.plist" "${REPO_ROOT}/WatchRemote/Info.plist"; do
    sed -i '' -E "/<key>CFBundleVersion<\/key>/{n;s/<string>[^<]*<\/string>/<string>${new_build}<\/string>/;}" "$target_plist"
  done

  printf '%s' "$new_build"
}