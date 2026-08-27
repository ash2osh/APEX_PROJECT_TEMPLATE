#!/usr/bin/env bash
# Normalize *.apx files under the given directory to LF line endings with
# exactly one trailing newline, and revert any file whose only change vs the
# last commit is whitespace/line-ending noise (prevents phantom diffs from
# SQLcl's export vs an editor's line-ending handling).
set -euo pipefail

TARGET_DIR="${1:?usage: normalize_apx.sh <dir>}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

find "$TARGET_DIR" -type f -name '*.apx' -print0 2>/dev/null | while IFS= read -r -d '' f; do
  perl -pi -e 's/\r\n/\n/g' "$f"
  perl -0pi -e 's/\n*\z/\n/' "$f"
  if git -C "$REPO_ROOT" diff --quiet -- "$f" 2>/dev/null; then
    :
  elif git -C "$REPO_ROOT" diff --ignore-space-at-eol --ignore-blank-lines --quiet -- "$f" 2>/dev/null; then
    git -C "$REPO_ROOT" checkout -- "$f"
  fi
done
