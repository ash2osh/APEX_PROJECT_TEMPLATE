#!/usr/bin/env bash
# Refresh table and code DBMS_METADATA mirrors through independent read targets.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
# shellcheck source=load_env.sh
source "$REPO_ROOT/scripts/load_env.sh" "${PROJECT_ENV_FILE:-$REPO_ROOT/.env}"
PROJECT_ENV_FILE="${PROJECT_ENV_FILE:-$REPO_ROOT/.env}" "$REPO_ROOT/scripts/check_db_target.sh" read tables
PROJECT_ENV_FILE="${PROJECT_ENV_FILE:-$REPO_ROOT/.env}" "$REPO_ROOT/scripts/check_db_target.sh" read code

BACKUP_SCHEMAS=()
add_backup_schema() {
  local candidate="$1"
  local existing
  for existing in "${BACKUP_SCHEMAS[@]}"; do
    [ "$existing" = "$candidate" ] && return
  done
  BACKUP_SCHEMAS+=("$candidate")
}
add_backup_schema "$TABLES_SCHEMA"
add_backup_schema "$CODE_SCHEMA"

# Refuse local mirror edits before making either database connection.
for schema in "${BACKUP_SCHEMAS[@]}"; do
  destination="database/$schema"
  dirty_status="$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all -- "$destination")" || {
    echo "unable to inspect Git status for mirror: $destination" >&2
    exit 1
  }
  if [ -n "$dirty_status" ]; then
    echo "refusing to back up over dirty mirror: $destination" >&2
    echo "commit, stash, or remove local changes first" >&2
    exit 1
  fi
done

mkdir -p "$REPO_ROOT/scratch"
STAGING_DIR="$(mktemp -d "$REPO_ROOT/scratch/db-backup.XXXXXX")"
cleanup() { rm -rf -- "$STAGING_DIR"; }
trap cleanup EXIT
mkdir -p "$STAGING_DIR/scripts"

for schema in "${BACKUP_SCHEMAS[@]}"; do
  db_stage="$STAGING_DIR/database/$schema"
  mkdir -p "$db_stage/tables" "$db_stage/views" "$db_stage/packages" \
    "$db_stage/procedures" "$db_stage/functions" "$db_stage/triggers"
done

# A failed SPOOL inside the generated driver prints an SP2- message that does
# not stop SQLcl, so an object can go missing without any non-zero exit code.
# The manifest states how many objects each scope should have produced; refuse
# to install a mirror that does not have exactly that many files.
verify_scope_complete() {
  local scope="$1"
  local schema="$2"
  local manifest="$STAGING_DIR/database/$schema/manifest-$scope.txt"
  local expected=0
  local line count
  while IFS= read -r line || [ -n "$line" ]; do
    count="${line##*=}"
    [[ "$line" == *=* ]] || continue
    [[ "$count" =~ ^[0-9]+$ ]] || continue
    expected=$((expected + count))
  done < "$manifest"

  local scope_dirs
  case "$scope" in
    tables) scope_dirs="tables" ;;
    code)   scope_dirs="views packages procedures functions triggers" ;;
  esac
  local actual=0
  local scope_dir found
  for scope_dir in $scope_dirs; do
    found="$(find "$STAGING_DIR/database/$schema/$scope_dir" -maxdepth 1 -type f \
      -name '*.sql' 2>/dev/null | wc -l)"
    actual=$((actual + found))
  done

  if [ "$expected" -ne "$actual" ]; then
    echo "database backup is incomplete for $schema ($scope): manifest expects" >&2
    echo "$expected object file(s) but $actual were written; the mirror was not replaced" >&2
    exit 1
  fi
}

run_backup_scope() {
  local scope="$1"
  local schema="$2"
  local connection="$3"
  local expected_user="$4"
  local required_role="$5"
  (
    cd "$STAGING_DIR"
    sql -S -noupdates -name "$connection" \
      "@$REPO_ROOT/scripts/backup_db.sql" \
      "$schema" "$scope" "$DB_ENVIRONMENT" "$expected_user" "$required_role"
  )
  test -f "$STAGING_DIR/database/$schema/manifest-$scope.txt" || {
    echo "database backup did not create manifest-$scope.txt under database/$schema" >&2
    exit 1
  }
  verify_scope_complete "$scope" "$schema"
}

# Both exports and manifests must complete before any generated mirror changes.
run_backup_scope tables "$TABLES_SCHEMA" "$TABLES_SQLCL_CONNECTION" \
  "$TABLES_EXPECTED_USER" "$TABLES_REQUIRED_ROLE"
run_backup_scope code "$CODE_SCHEMA" "$CODE_SQLCL_CONNECTION" \
  "$CODE_EXPECTED_USER" "$CODE_REQUIRED_ROLE"

for schema in "${BACKUP_SCHEMAS[@]}"; do
  "$REPO_ROOT/scripts/replace_mirror.sh" \
    "$STAGING_DIR/database/$schema" "database/$schema"
done
