#!/usr/bin/env bash
# Export the configured APEX application as an APEXlang mirror.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
# shellcheck source=load_env.sh
source "$REPO_ROOT/scripts/load_env.sh" "${PROJECT_ENV_FILE:-$REPO_ROOT/.env}"
PROJECT_ENV_FILE="${PROJECT_ENV_FILE:-$REPO_ROOT/.env}" "$REPO_ROOT/scripts/check_db_target.sh" read apex

IFS=',' read -r -a APP_IDS <<< "$APEX_APP_ID"

# Refuse any dirty destination before making the first database connection.
for app_id in "${APP_IDS[@]}"; do
  destination="apps/$APEX_PARSING_SCHEMA/$app_id"
  dirty_status="$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all -- "$destination")" || {
    echo "unable to inspect Git status for mirror: $destination" >&2
    exit 1
  }
  if [ -n "$dirty_status" ]; then
    echo "refusing to export over dirty mirror: $destination" >&2
    echo "commit, stash, or remove local changes first" >&2
    exit 1
  fi
done

mkdir -p "$REPO_ROOT/scratch"
STAGING_DIR="$(mktemp -d "$REPO_ROOT/scratch/apex-export.XXXXXX")"
cleanup() { rm -rf -- "$STAGING_DIR"; }
trap cleanup EXIT
STAGE_PARENT="$STAGING_DIR/staged/apps/$APEX_PARSING_SCHEMA"
mkdir -p "$STAGE_PARENT"

# SQLcl builds a JLine console over its standard input at startup. Handed a
# descriptor it cannot probe -- a pipe, or the Windows NUL device that
# /dev/null becomes under Git Bash -- it aborts with
# "java.io.IOException: Incorrect function" before running the script, and
# still exits 0. An empty regular file is a standard input every platform can
# probe, and it also stops SQLcl from consuming the caller's own input.
SQLCL_STDIN="$STAGING_DIR/.sqlcl-stdin"
: > "$SQLCL_STDIN"

for app_id in "${APP_IDS[@]}"; do
  RUN_DIR="$STAGING_DIR/runs/$app_id"
  RUN_STAGE_PARENT="$RUN_DIR/apps/$APEX_PARSING_SCHEMA"
  mkdir -p "$RUN_STAGE_PARENT"

  (
    cd "$RUN_DIR"
    sql -S -noupdates -name "$APEX_SQLCL_CONNECTION" \
      "@$REPO_ROOT/scripts/export_apps.sql" \
      "$APEX_PARSING_SCHEMA" "$app_id" "$DB_ENVIRONMENT" \
      "$APEX_EXPECTED_USER" < "$SQLCL_STDIN"
  )

  # SQLcl names each export directory after the application alias, which can
  # change independently of the immutable application id used by the mirror.
  EXPORTED_DIR=""
  EXPORTED_COUNT=0
  while IFS= read -r -d '' candidate; do
    EXPORTED_DIR="$candidate"
    EXPORTED_COUNT=$((EXPORTED_COUNT + 1))
  done < <(find "$RUN_STAGE_PARENT" -mindepth 1 -maxdepth 1 -type d -print0)

  if [ "$EXPORTED_COUNT" -ne 1 ]; then
    echo "expected exactly one exported directory for application $app_id, found $EXPORTED_COUNT" >&2
    exit 1
  fi
  test -f "$EXPORTED_DIR/application.apx" || {
    echo "APEX export for application $app_id did not create application.apx" >&2
    exit 1
  }
  test -f "$EXPORTED_DIR/.apex/apexlang.json" || {
    echo "APEX export for application $app_id did not create .apex/apexlang.json" >&2
    exit 1
  }

  APP_STAGE="$STAGE_PARENT/$app_id"
  mv -- "$EXPORTED_DIR" "$APP_STAGE"
  "$REPO_ROOT/scripts/normalize_apx.sh" "$APP_STAGE"
done

# Install only after every requested application has exported and verified.
for app_id in "${APP_IDS[@]}"; do
  "$REPO_ROOT/scripts/replace_mirror.sh" \
    "$STAGE_PARENT/$app_id" "apps/$APEX_PARSING_SCHEMA/$app_id"
done
