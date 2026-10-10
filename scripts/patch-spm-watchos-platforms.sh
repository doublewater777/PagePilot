#!/bin/sh
# Xcode 27 deprecates SupportedPlatform.WatchOSVersion.v4. GRDB 6.29.3,
# Readium ZIPFoundation 3.0.1, and SQLite.swift 0.16.0 still declare it.
# Their tagged releases have no newer Package.swift, so raise watchOS to 9
# in the resolved checkouts. Resolution does not overwrite an existing
# checkout; a clean DerivedData clones .v4 again and the scheme pre-action
# runs this script before the next build.
set -eu

if [ -n "${1:-}" ]; then
  checkouts=$1
elif [ -n "${BUILD_DIR:-}" ]; then
  # Normal builds: DerivedData/<project>/Build/Products
  # Archives:      .../ArchiveIntermediates/<scheme>/BuildProductsPath
  # Walk up until SourcePackages exists. A clean archive pre-action runs
  # before that directory is created; missing checkouts are not a failure.
  dir=$BUILD_DIR
  checkouts=
  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    if [ -d "$dir/SourcePackages/checkouts" ]; then
      checkouts="$dir/SourcePackages/checkouts"
      break
    fi
    dir=$(dirname "$dir")
  done
  if [ -z "$checkouts" ]; then
    exit 0
  fi
else
  echo "patch-spm-watchos-platforms: no checkouts path and BUILD_DIR is unset" >&2
  exit 0
fi

if [ ! -d "$checkouts" ]; then
  exit 0
fi

patch_file() {
  file=$1
  if [ ! -f "$file" ]; then
    return 0
  fi
  if ! grep -q '\.watchOS(\.v4)' "$file"; then
    return 0
  fi
  chmod u+w "$file"
  # ZIPFoundation's manifest also lists Swift language version .v4. Touch only watchOS.
  sed -i '' 's/\.watchOS(\.v4)/.watchOS(.v9)/g' "$file"
  echo "patched watchOS platform in $file"
}

patch_file "$checkouts/GRDB.swift/Package.swift"
patch_file "$checkouts/SQLite.swift/Package.swift"
patch_file "$checkouts/SQLite.swift/Tests/SPM/Package.swift"
patch_file "$checkouts/ZIPFoundation/Package.swift"
