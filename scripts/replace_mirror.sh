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
for DEST_PART in "${DEST_PARTS[@]}"; do
  if [ -z "$DEST_PART" ] || [ "$DEST_PART" = . ] || [ "$DEST_PART" = .. ] || \
     [[ ! "$DEST_PART" =~ ^[A-Za-z0-9][A-Za-z0-9._\$#-]*$ ]]; then
    echo "destination contains an unsafe path segment: $DEST_REL" >&2
    exit 1
  fi
done

FIRST_STAGED_FILE="$(find "$STAGED_DIR" -type f -print -quit)"
if [ -z "$FIRST_STAGED_FILE" ]; then
  echo "staging directory is empty: $STAGED_DIR" >&2
  exit 1
fi
FIRST_STAGED_LINK="$(find "$STAGED_DIR" -type l -print -quit)"
if [ -n "$FIRST_STAGED_LINK" ]; then
  echo "staging directory contains a symbolic link: $FIRST_STAGED_LINK" >&2
  exit 1
fi

check_clean_mirror() {
  if ! DIRTY_STATUS="$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all -- "$DEST_REL")"; then
    echo "unable to inspect Git status for mirror: $DEST_REL" >&2
    return 1
  fi
  if [ -n "$DIRTY_STATUS" ]; then
    echo "refusing to replace dirty mirror: $DEST_REL" >&2
    echo "commit, stash, or remove local changes first" >&2
    return 1
  fi
}
check_clean_mirror

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

device_id() {
  if stat -c '%d' "$1" >/dev/null 2>&1; then
    stat -c '%d' "$1"
  else
    stat -f '%d' "$1"
  fi
}
if [ "$(device_id "$STAGED_DIR")" != "$(device_id "$DEST_PARENT")" ]; then
  echo "staging and destination must be on the same filesystem" >&2
  exit 1
fi

MIRROR_NAME="$(basename -- "$DEST_DIR")"
BACKUP_DIR="$REPO_ROOT/scratch/.mirror-backup.${MIRROR_NAME}.$$"
if [ -e "$BACKUP_DIR" ] || [ -L "$BACKUP_DIR" ]; then
  echo "temporary replacement path already exists: $BACKUP_DIR" >&2
  exit 1
fi

LOCK_ROOT="$SCRATCH_ROOT/.mirror-locks"
mkdir -p "$LOCK_ROOT"
LOCK_KEY="$(printf '%s' "$CANONICAL_REL" | cksum | awk '{print $1}')"
LOCK_DIR="$LOCK_ROOT/$LOCK_KEY.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "another mirror replacement is already running for $CANONICAL_REL" >&2
  exit 1
fi

ROLLBACK_PENDING=0
cleanup_replacement() {
  cleanup_status=$?
  if [ "$ROLLBACK_PENDING" -eq 1 ] && \
     { [ -e "$BACKUP_DIR" ] || [ -L "$BACKUP_DIR" ]; } && \
     ! { [ -e "$DEST_DIR" ] || [ -L "$DEST_DIR" ]; }; then
    if ! mv -- "$BACKUP_DIR" "$DEST_DIR"; then
      echo "replacement interrupted and rollback failed; old mirror is at $BACKUP_DIR" >&2
      cleanup_status=1
    fi
  fi
  rmdir "$LOCK_DIR" 2>/dev/null || true
  trap - EXIT
  exit "$cleanup_status"
}
trap cleanup_replacement EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

# Close the check-to-replace window as much as possible after taking the lock.
check_clean_mirror

if [ -e "$DEST_DIR" ] || [ -L "$DEST_DIR" ]; then
  mv -- "$DEST_DIR" "$BACKUP_DIR"
  ROLLBACK_PENDING=1
fi

if ! mv -- "$STAGED_DIR" "$DEST_DIR"; then
  if [ -e "$BACKUP_DIR" ] || [ -L "$BACKUP_DIR" ]; then
    if ! mv -- "$BACKUP_DIR" "$DEST_DIR"; then
      echo "replacement failed and rollback failed; old mirror is at $BACKUP_DIR" >&2
      exit 1
    fi
    ROLLBACK_PENDING=0
  fi
  exit 1
fi

ROLLBACK_PENDING=0

if [ -e "$BACKUP_DIR" ] || [ -L "$BACKUP_DIR" ]; then
  if ! rm -rf -- "$BACKUP_DIR"; then
    echo "mirror installed, but rollback cleanup failed; old mirror is at $BACKUP_DIR" >&2
    exit 1
  fi
fi
