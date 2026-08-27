#!/usr/bin/env bash
# Replace one generated mirror with a completed staging directory.
set -euo pipefail

REPO_ROOT="${MIRROR_SYNC_REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd -P)}"
STAGED_DIR_ARG="${1:?usage: replace_mirror.sh <staged-dir> <destination>}"
DEST_DIR_ARG="${2:?usage: replace_mirror.sh <staged-dir> <destination>}"

if [ ! -d "$STAGED_DIR_ARG" ]; then
  echo "staging directory does not exist: $STAGED_DIR_ARG" >&2
  exit 1
fi

STAGED_DIR="$(cd "$STAGED_DIR_ARG" && pwd -P)"
mkdir -p "$REPO_ROOT/scratch"
SCRATCH_ROOT="$(cd "$REPO_ROOT/scratch" && pwd -P)"
case "$STAGED_DIR" in
  "$SCRATCH_ROOT"/*) ;;
  *)
    echo "staging directory must be inside scratch/: $STAGED_DIR" >&2
    exit 1
    ;;
esac

if [[ "$DEST_DIR_ARG" = /* ]]; then
  echo "destination must be a repository-relative mirror path: $DEST_DIR_ARG" >&2
  exit 1
fi
DEST_DIR="$REPO_ROOT/$DEST_DIR_ARG"

case "$DEST_DIR" in
  "$REPO_ROOT"/*) ;;
  *)
    echo "destination must be inside the repository: $DEST_DIR" >&2
    exit 1
    ;;
esac

DEST_REL="${DEST_DIR#"$REPO_ROOT/"}"
IFS=/ read -r -a DEST_PARTS <<< "$DEST_REL"
if [[ "${DEST_PARTS[0]}" = apps && "${#DEST_PARTS[@]}" -eq 3 ]] || \
   [[ "${DEST_PARTS[0]}" = database && "${#DEST_PARTS[@]}" -eq 2 ]]; then
  :
else
  echo "destination is not an approved generated mirror: $DEST_REL" >&2
  exit 1
fi

FIRST_STAGED_FILE="$(find "$STAGED_DIR" -type f -print -quit)"
if [ -z "$FIRST_STAGED_FILE" ]; then
  echo "staging directory is empty: $STAGED_DIR" >&2
  exit 1
fi

if ! DIRTY_STATUS="$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all -- "$DEST_REL")"; then
  echo "unable to inspect Git status for mirror: $DEST_REL" >&2
  exit 1
fi
if [ -n "$DIRTY_STATUS" ]; then
  echo "refusing to replace dirty mirror: $DEST_REL" >&2
  echo "commit, stash, or remove local changes first" >&2
  exit 1
fi

DEST_PARENT="$(dirname -- "$DEST_DIR")"
mkdir -p "$DEST_PARENT"
DEST_PARENT="$(cd "$DEST_PARENT" && pwd -P)"
DEST_DIR="$DEST_PARENT/$(basename -- "$DEST_DIR")"
case "$DEST_DIR" in
  "$REPO_ROOT"/*) ;;
  *)
    echo "resolved destination escaped the repository: $DEST_DIR" >&2
    exit 1
    ;;
esac
CANONICAL_REL="${DEST_DIR#"$REPO_ROOT/"}"
IFS=/ read -r -a CANONICAL_PARTS <<< "$CANONICAL_REL"
if ! [[ "${CANONICAL_PARTS[0]}" = apps && "${#CANONICAL_PARTS[@]}" -eq 3 ]] && \
   ! [[ "${CANONICAL_PARTS[0]}" = database && "${#CANONICAL_PARTS[@]}" -eq 2 ]]; then
  echo "resolved destination is not an approved generated mirror: $CANONICAL_REL" >&2
  exit 1
fi

MIRROR_NAME="$(basename -- "$DEST_DIR")"
BACKUP_DIR="$REPO_ROOT/scratch/.mirror-backup.${MIRROR_NAME}.$$"
if [ -e "$BACKUP_DIR" ] || [ -L "$BACKUP_DIR" ]; then
  echo "temporary replacement path already exists: $BACKUP_DIR" >&2
  exit 1
fi

if [ -e "$DEST_DIR" ] || [ -L "$DEST_DIR" ]; then
  mv -- "$DEST_DIR" "$BACKUP_DIR"
fi

if ! mv -- "$STAGED_DIR" "$DEST_DIR"; then
  if [ -e "$BACKUP_DIR" ] || [ -L "$BACKUP_DIR" ]; then
    if ! mv -- "$BACKUP_DIR" "$DEST_DIR"; then
      echo "replacement failed and rollback failed; old mirror is at $BACKUP_DIR" >&2
      exit 1
    fi
  fi
  exit 1
fi

if [ -e "$BACKUP_DIR" ] || [ -L "$BACKUP_DIR" ]; then
  if ! rm -rf -- "$BACKUP_DIR"; then
    echo "mirror installed, but rollback cleanup failed; old mirror is at $BACKUP_DIR" >&2
    exit 1
  fi
fi
