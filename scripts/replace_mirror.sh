#!/usr/bin/env bash
# Replace generated mirrors with completed staging directories atomically.
set -euo pipefail

REPO_ROOT="${MIRROR_SYNC_REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd -P)}"
if [ "$#" -lt 2 ] || [ $(( $# % 2 )) -ne 0 ]; then
  echo "usage: replace_mirror.sh <staged-dir> <destination> [<staged-dir> <destination> ...]" >&2
  exit 1
fi

STAGED_DIRS=()
DEST_DIRS=()
CANONICAL_RELS=()
BACKUP_DIRS=()

validate_pair() {
STAGED_DIR_ARG="$1"
DEST_DIR_ARG="$2"

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

# Create the destination parent before the first Git query. With apps/ present
# but apps/<schema>/ still absent -- every project's first APEX export -- a
# `git status -- apps/<schema>/<app-id>` prints a "could not open directory"
# warning that reads like an export failure.
DEST_PARENT="$(dirname -- "$DEST_DIR")"
mkdir -p "$DEST_PARENT"

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
PAIR_INDEX="${#STAGED_DIRS[@]}"
BACKUP_DIR="$REPO_ROOT/scratch/.mirror-backup.${MIRROR_NAME}.$$.$PAIR_INDEX"
if [ -e "$BACKUP_DIR" ] || [ -L "$BACKUP_DIR" ]; then
  echo "temporary replacement path already exists: $BACKUP_DIR" >&2
  exit 1
fi

STAGED_DIRS+=("$STAGED_DIR")
DEST_DIRS+=("$DEST_DIR")
CANONICAL_RELS+=("$CANONICAL_REL")
BACKUP_DIRS+=("$BACKUP_DIR")
}

# Lock protocol v1. Both implementations must agree, because on Windows a
# Git Bash run and a PowerShell run can target the same mirror.
#
#   path:     scratch/.mirror-locks/<first 16 hex of sha256(canonical-rel)>.lock
#   contents: version=1 / impl=sh|ps1 / pid=<n> / epoch=<unix seconds>, LF each
#
#   acquire:  atomic exclusive create (noclobber redirect / FileMode::CreateNew).
#             On failure, read the holder's fields:
#               - same impl and pid alive  -> real contention, refuse
#               - otherwise, epoch older than MIRROR_LOCK_STALE_SECONDS
#                                          -> break the lock and retry once
#               - otherwise                -> refuse, naming the file and the
#                                             remaining wait
#   release:  delete the file (EXIT trap / finally)
#
# PowerShell opens with FileShare::Read, not None, so the Bash side can still
# read the metadata of a live PowerShell lock. CreateNew, not OpenOrCreate:
# OpenOrCreate would let PowerShell silently steal a Bash lock, because Bash
# holds no OS handle. Cross-implementation liveness cannot be checked (the pid
# namespaces differ under MSYS), so cross-impl contention degrades to the
# staleness window. Same-impl contention is always detected exactly.
MIRROR_LOCK_STALE_SECONDS="${MIRROR_LOCK_STALE_SECONDS:-900}"

lock_digest() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | cut -c1-16
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | cut -c1-16
  else
    echo "SHA-256 is required to acquire a mirror lock (install sha256sum or shasum)" >&2
    return 1
  fi
}

lock_field() {
  sed -n "s/^$2=//p" "$1" 2>/dev/null | head -1 | tr -d '\r'
}

acquire_mirror_lock() {
  local lock_file="$1" canonical="$2"
  local attempt holder_version holder_impl holder_pid holder_epoch now age
  for attempt in 1 2; do
    if ( set -o noclobber
         printf 'version=1\nimpl=sh\npid=%s\nepoch=%s\n' "$$" "$(date +%s)" \
           > "$lock_file" ) 2>/dev/null; then
      return 0
    fi
    if [ "$attempt" -eq 2 ]; then
      break
    fi
    holder_version="$(lock_field "$lock_file" version)"
    holder_impl="$(lock_field "$lock_file" impl)"
    holder_pid="$(lock_field "$lock_file" pid)"
    holder_epoch="$(lock_field "$lock_file" epoch)"
    if [ "$holder_version" != "1" ] || \
       { [ "$holder_impl" != "sh" ] && [ "$holder_impl" != "ps1" ]; } || \
       [[ ! "$holder_pid" =~ ^[0-9]+$ ]] || \
       [[ ! "$holder_epoch" =~ ^[0-9]+$ ]]; then
      echo "another mirror replacement is already running for $canonical" >&2
      echo "lock metadata is incomplete or unreadable; refusing to remove $lock_file" >&2
      return 1
    fi
    now="$(date +%s)"
    if [ "$holder_impl" = sh ] && [ -n "$holder_pid" ] && kill -0 "$holder_pid" 2>/dev/null; then
      echo "another mirror replacement is already running for $canonical (pid $holder_pid)" >&2
      return 1
    fi
    age=$(( now - 10#$holder_epoch ))
    if [ "$age" -gt "$MIRROR_LOCK_STALE_SECONDS" ]; then
      echo "breaking stale mirror lock for $canonical (impl=${holder_impl:-unknown} pid=${holder_pid:-unknown} age=${age}s)" >&2
      rm -f -- "$lock_file"
      continue
    fi
    echo "another mirror replacement is already running for $canonical" >&2
    echo "if that process is gone, remove $lock_file or wait $(( MIRROR_LOCK_STALE_SECONDS - age )) seconds" >&2
    return 1
  done
  return 1
}

while [ "$#" -gt 0 ]; do
  validate_pair "$1" "$2"
  shift 2
done

LOCK_ROOT="$SCRATCH_ROOT/.mirror-locks"
mkdir -p "$LOCK_ROOT"

ACQUIRED_LOCKS=()
INSTALLED_INDEXES=()
MOVED_DEST_INDEXES=()

release_locks() {
  local lock_file
  for lock_file in "${ACQUIRED_LOCKS[@]:-}"; do
    [ -n "$lock_file" ] && rm -f -- "$lock_file" 2>/dev/null || true
  done
}

unwind_replacements() {
  local index
  # Reverse order: undo the staged move first, then restore the old mirror.
  for (( index=${#STAGED_DIRS[@]} - 1; index >= 0; index-- )); do
    case " ${INSTALLED_INDEXES[*]:-} " in
      *" $index "*)
        mv -- "${DEST_DIRS[$index]}" "${STAGED_DIRS[$index]}" 2>/dev/null || \
          echo "rollback could not return ${DEST_DIRS[$index]} to staging" >&2
        ;;
    esac
    case " ${MOVED_DEST_INDEXES[*]:-} " in
      *" $index "*)
        mv -- "${BACKUP_DIRS[$index]}" "${DEST_DIRS[$index]}" 2>/dev/null || \
          echo "rollback failed; the previous mirror is at ${BACKUP_DIRS[$index]}" >&2
        ;;
    esac
  done
}

cleanup_replacement() {
  cleanup_status=$?
  if [ "$cleanup_status" -ne 0 ]; then
    unwind_replacements
  fi
  release_locks
  trap - EXIT
  exit "$cleanup_status"
}
trap cleanup_replacement EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

for (( PAIR_INDEX=0; PAIR_INDEX < ${#STAGED_DIRS[@]}; PAIR_INDEX++ )); do
  LOCK_FILE="$LOCK_ROOT/$(lock_digest "${CANONICAL_RELS[$PAIR_INDEX]}").lock"
  acquire_mirror_lock "$LOCK_FILE" "${CANONICAL_RELS[$PAIR_INDEX]}" || exit 1
  ACQUIRED_LOCKS+=("$LOCK_FILE")
done

# Recheck every mirror after taking every lock, to close the check-to-replace
# window as much as possible, then move them all.
for (( PAIR_INDEX=0; PAIR_INDEX < ${#STAGED_DIRS[@]}; PAIR_INDEX++ )); do
  DEST_REL="${CANONICAL_RELS[$PAIR_INDEX]}"
  check_clean_mirror
done

for (( PAIR_INDEX=0; PAIR_INDEX < ${#STAGED_DIRS[@]}; PAIR_INDEX++ )); do
  if [ -e "${DEST_DIRS[$PAIR_INDEX]}" ] || [ -L "${DEST_DIRS[$PAIR_INDEX]}" ]; then
    mv -- "${DEST_DIRS[$PAIR_INDEX]}" "${BACKUP_DIRS[$PAIR_INDEX]}"
    MOVED_DEST_INDEXES+=("$PAIR_INDEX")
  fi
  if [ "${MIRROR_SYNC_TEST_FAIL_STAGED_MOVE_INDEX:-}" = "$PAIR_INDEX" ]; then
    echo "test-only staged mirror move failure at index $PAIR_INDEX" >&2
    exit 1
  fi
  mv -- "${STAGED_DIRS[$PAIR_INDEX]}" "${DEST_DIRS[$PAIR_INDEX]}"
  INSTALLED_INDEXES+=("$PAIR_INDEX")
done

# Every mirror is installed: this is the point of no return. Disarm the unwind
# before touching the saved copies, because discarding them is best-effort
# cleanup. `rm -rf` deletes what it can before failing, so unwinding from here
# would restore a partially destroyed backup over a good mirror -- losing
# committed files while reporting "mirrors installed". PowerShell keeps its
# cleanup outside the rollback for the same reason.
INSTALLED_INDEXES=()
MOVED_DEST_INDEXES=()

for (( PAIR_INDEX=0; PAIR_INDEX < ${#BACKUP_DIRS[@]}; PAIR_INDEX++ )); do
  if [ -e "${BACKUP_DIRS[$PAIR_INDEX]}" ] || [ -L "${BACKUP_DIRS[$PAIR_INDEX]}" ]; then
    rm -rf -- "${BACKUP_DIRS[$PAIR_INDEX]}" || {
      echo "mirrors installed, but cleanup failed; the previous mirror is at ${BACKUP_DIRS[$PAIR_INDEX]}" >&2
      exit 1
    }
  fi
done
