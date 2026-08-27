#!/usr/bin/env bash
# Refresh database/{{SCHEMA}}/ from live DB state via DBMS_METADATA.
# Requires a saved SQLcl connection named {{CONN_NAME}}.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
mkdir -p "$REPO_ROOT/scratch"
STAGING_DIR="$(mktemp -d "$REPO_ROOT/scratch/db-backup.XXXXXX")"
cleanup() { rm -rf -- "$STAGING_DIR"; }
trap cleanup EXIT
mkdir -p "$STAGING_DIR/database/{{SCHEMA}}/tables" \
  "$STAGING_DIR/database/{{SCHEMA}}/views" \
  "$STAGING_DIR/database/{{SCHEMA}}/packages" \
  "$STAGING_DIR/scripts"

(
  cd "$STAGING_DIR"
  sql -S -noupdates -name "{{CONN_NAME}}" "@$REPO_ROOT/scripts/backup_db.sql"
)

DB_STAGE="$STAGING_DIR/database/{{SCHEMA}}"
test -d "$DB_STAGE" || { echo "database backup did not create $DB_STAGE" >&2; exit 1; }
"$REPO_ROOT/scripts/replace_mirror.sh" "$DB_STAGE" "database/{{SCHEMA}}"
