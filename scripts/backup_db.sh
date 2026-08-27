#!/usr/bin/env bash
# Refresh the configured schema's read-only DBMS_METADATA mirror.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
# shellcheck source=load_env.sh
source "$REPO_ROOT/scripts/load_env.sh" "${PROJECT_ENV_FILE:-$REPO_ROOT/.env}"
PROJECT_ENV_FILE="${PROJECT_ENV_FILE:-$REPO_ROOT/.env}" "$REPO_ROOT/scripts/check_db_target.sh" read
DB_ROLE_ARG="${DB_REQUIRED_ROLE:-NONE}"

mkdir -p "$REPO_ROOT/scratch"
STAGING_DIR="$(mktemp -d "$REPO_ROOT/scratch/db-backup.XXXXXX")"
cleanup() { rm -rf -- "$STAGING_DIR"; }
trap cleanup EXIT
DB_STAGE="$STAGING_DIR/database/$DB_TARGET_SCHEMA"
mkdir -p "$DB_STAGE/tables" "$DB_STAGE/views" "$DB_STAGE/packages" \
  "$DB_STAGE/procedures" "$DB_STAGE/functions" "$DB_STAGE/triggers" \
  "$STAGING_DIR/scripts"

(
  cd "$STAGING_DIR"
  sql -S -noupdates -name "$SQLCL_CONNECTION" \
    "@$REPO_ROOT/scripts/backup_db.sql" \
    "$DB_TARGET_SCHEMA" "$DB_ENVIRONMENT" "$DB_EXPECTED_USER" "$DB_ROLE_ARG"
)

test -f "$DB_STAGE/manifest.txt" || {
  echo "database backup did not create $DB_STAGE/manifest.txt" >&2
  exit 1
}
"$REPO_ROOT/scripts/replace_mirror.sh" "$DB_STAGE" "database/$DB_TARGET_SCHEMA"
