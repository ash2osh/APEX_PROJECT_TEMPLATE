#!/usr/bin/env bash
# Normalize *.apx files under the given directory to LF line endings with
# exactly one trailing newline. This script only changes the files in the
# supplied directory and never consults or modifies Git.
set -euo pipefail

TARGET_DIR="${1:?usage: normalize_apx.sh <dir>}"
test -d "$TARGET_DIR" || { echo "directory does not exist: $TARGET_DIR" >&2; exit 1; }
command -v perl >/dev/null 2>&1 || { echo "normalize_apx.sh requires perl, which was not found on PATH" >&2; exit 1; }

find "$TARGET_DIR" -type f -name '*.apx' -print0 2>/dev/null | while IFS= read -r -d '' f; do
  perl -pi -e 's/\r\n/\n/g' "$f"
  perl -pi -e 's/\r/\n/g' "$f"
  perl -0pi -e 's/\n*\z/\n/' "$f"
done
