#!/usr/bin/env bash
# Commit, tag, and push a prepared App Store release.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/version.sh
source "${REPO_ROOT}/scripts/lib/version.sh"

RESUBMIT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --resubmit)
      RESUBMIT=1
      shift
      ;;
    *)
      echo "usage: commit-release.sh [--resubmit]" >&2
      exit 1
      ;;
  esac
done

VERSION="$(current_version)"
METADATA_DIR="$(metadata_dir_for_version "$VERSION")"
BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"
TAG="v${VERSION}"
COMMIT_MSG="${VERSION}: release"
TAG_CREATED=0

if [[ "$RESUBMIT" -eq 1 ]]; then
  COMMIT_MSG="${VERSION}: resubmit"
fi

RELEASE_PATHS=(
  VERSION
  Integrations
  iPhone/Info.plist
  WatchRemote/Info.plist
  "metadata/version/${VERSION}"
)

if [[ ! -d "$METADATA_DIR" ]]; then
  echo "commit-release: metadata missing at ${METADATA_DIR}" >&2
  echo "Run ./scripts/prepare-submission.sh first, then update whatsNew." >&2
  exit 1
fi

if [[ -z "$(git -C "$REPO_ROOT" status --porcelain -- "${RELEASE_PATHS[@]}")" ]]; then
  echo "commit-release: no release changes to commit for ${VERSION}" >&2
  exit 1
fi

git -C "$REPO_ROOT" add "${RELEASE_PATHS[@]}"

if git -C "$REPO_ROOT" diff --cached --quiet; then
  echo "commit-release: nothing staged for ${VERSION}" >&2
  exit 1
fi

git -C "$REPO_ROOT" commit -m "$COMMIT_MSG"

if git -C "$REPO_ROOT" rev-parse "$TAG" >/dev/null 2>&1; then
  echo "commit-release: tag ${TAG} already exists; skipping tag creation"
else
  git -C "$REPO_ROOT" tag "$TAG"
  TAG_CREATED=1
fi

git -C "$REPO_ROOT" push origin "$BRANCH"
if [[ "$TAG_CREATED" -eq 1 ]]; then
  git -C "$REPO_ROOT" push origin "$TAG"
fi

cat <<EOF
Pushed ${VERSION} to origin/${BRANCH}
Commit: ${COMMIT_MSG}
EOF

if [[ "$TAG_CREATED" -eq 1 ]]; then
  echo "Tag: ${TAG}"
else
  echo "Tag: ${TAG} (unchanged)"
fi