#!/usr/bin/env bash
# Prepare an App Store submission from the live (shipped) version baseline.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/version.sh
source "${REPO_ROOT}/scripts/lib/version.sh"

EXPLICIT_TARGET="${1:-}"
SHIPPED="$(shipped_version)"
REPO_VERSION="$(current_version)"
DEFAULT_TARGET="$(default_submission_target)"
TARGET_VERSION="${EXPLICIT_TARGET:-$DEFAULT_TARGET}"
MODE=""

if ! is_valid_semver "$TARGET_VERSION"; then
  echo "prepare-submission: version must use major.minor.patch" >&2
  exit 1
fi

if ! version_gt "$TARGET_VERSION" "$SHIPPED"; then
  cat >&2 <<EOF
prepare-submission: target ${TARGET_VERSION} must be greater than shipped ${SHIPPED}

Update SHIPPED_VERSION if App Store live version changed:
  ./scripts/mark-shipped.sh <live-version>
EOF
  exit 1
fi

if [[ -z "$EXPLICIT_TARGET" && "$TARGET_VERSION" != "$DEFAULT_TARGET" ]]; then
  echo "prepare-submission: internal error resolving default target" >&2
  exit 1
fi

TARGET_METADATA_DIR="$(metadata_dir_for_version "$TARGET_VERSION")"
METADATA_EXISTS=0
[[ -d "$TARGET_METADATA_DIR" ]] && METADATA_EXISTS=1

if [[ "$REPO_VERSION" == "$TARGET_VERSION" ]]; then
  MODE="resubmit"
elif [[ "$METADATA_EXISTS" -eq 1 ]] && [[ "$REPO_VERSION" == "$SHIPPED" ]]; then
  MODE="resubmit"
elif [[ "$REPO_VERSION" == "$SHIPPED" ]] && [[ "$TARGET_VERSION" == "$DEFAULT_TARGET" ]]; then
  MODE="new"
elif version_gt "$REPO_VERSION" "$SHIPPED" && [[ "$REPO_VERSION" == "$TARGET_VERSION" ]]; then
  MODE="resubmit"
else
  MODE="new"
fi

NEW_BUILD=""
if [[ "$MODE" == "new" ]]; then
  "${REPO_ROOT}/scripts/bump-version.sh" "$TARGET_VERSION" --increment-build

  if [[ "$METADATA_EXISTS" -eq 0 ]]; then
    SOURCE_METADATA_VERSION="$SHIPPED"
    if [[ ! -d "$(metadata_dir_for_version "$SOURCE_METADATA_VERSION")" ]]; then
      SOURCE_METADATA_VERSION="$(latest_metadata_version || true)"
    fi
    if [[ -z "$SOURCE_METADATA_VERSION" || ! -d "$(metadata_dir_for_version "$SOURCE_METADATA_VERSION")" ]]; then
      echo "prepare-submission: no metadata source found under metadata/version/" >&2
      exit 1
    fi

    mkdir -p "$TARGET_METADATA_DIR"
    cp "$(metadata_dir_for_version "$SOURCE_METADATA_VERSION")"/*.json "$TARGET_METADATA_DIR"/
    METADATA_ACTION="created metadata/version/${TARGET_VERSION}/ from ${SOURCE_METADATA_VERSION}"
  else
    METADATA_ACTION="reused existing metadata/version/${TARGET_VERSION}/"
  fi
else
  sync_version_files "$TARGET_VERSION"
  NEW_BUILD="$(increment_build_number)"
  METADATA_ACTION="reused metadata/version/${TARGET_VERSION}/ for resubmit"
fi

LAST_TAG=""
if LAST_TAG="$(git -C "$REPO_ROOT" describe --tags --abbrev=0 --match 'v*' 2>/dev/null)"; then
  LAST_TAG="${LAST_TAG#v}"
fi

cat <<EOF

Prepared submission (${MODE})
  shipped (App Store live): ${SHIPPED}
  default target:         ${DEFAULT_TARGET}
  submission target:      ${TARGET_VERSION}
  repo version:           $(current_version)

${METADATA_ACTION}

Required manual/agent step before upload:
  1. Update whatsNew in metadata/version/${TARGET_VERSION}/en-US.json
  2. Update whatsNew in metadata/version/${TARGET_VERSION}/zh-Hans.json
  3. Review description, keywords, promotionalText if needed
EOF

if [[ "$MODE" == "resubmit" ]]; then
  cat <<EOF

Resubmit note:
  Marketing version stays ${TARGET_VERSION}. Only build number was incremented.
  Do not bump to $(next_patch_version "$TARGET_VERSION") until ${TARGET_VERSION} is live on the App Store.
EOF
  if [[ -n "$NEW_BUILD" ]]; then
    echo "  CFBundleVersion -> ${NEW_BUILD}"
  fi
fi

cat <<EOF

Commits since v${SHIPPED} for release notes:
EOF

if git -C "$REPO_ROOT" rev-parse "v${SHIPPED}" >/dev/null 2>&1; then
  git -C "$REPO_ROOT" log "v${SHIPPED}..HEAD" --oneline --no-merges || true
else
  git -C "$REPO_ROOT" log --oneline --no-merges -20 || true
fi

COMMIT_SUBJECT="${TARGET_VERSION}: release"
if [[ "$MODE" == "resubmit" ]]; then
  COMMIT_SUBJECT="${TARGET_VERSION}: resubmit"
fi

cat <<EOF

After updating metadata, commit and push before building:
  ./scripts/commit-release.sh

Or manually:
  git add VERSION SHIPPED_VERSION Integrations iPhone/Info.plist WatchRemote/Info.plist metadata/version/${TARGET_VERSION}
  git commit -m "${COMMIT_SUBJECT}"
  git tag v${TARGET_VERSION}    # skip if tag already exists
  git push origin HEAD
  git push origin v${TARGET_VERSION}    # skip if tag already exists

When ${TARGET_VERSION} goes live on the App Store:
  ./scripts/mark-shipped.sh ${TARGET_VERSION}

Suggested ASC staging after build upload:
  asc release stage \\
    --app "6760964443" \\
    --version "${TARGET_VERSION}" \\
    --build "BUILD_ID" \\
    --metadata-dir "./metadata" \\
    --dry-run

See docs/agents/submission-flow.md
EOF