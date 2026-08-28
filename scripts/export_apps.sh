#!/usr/bin/env bash
# Export the configured APEX application as an APEXlang mirror.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
# shellcheck source=load_env.sh
source "$REPO_ROOT/scripts/load_env.sh" "${PROJECT_ENV_FILE:-$REPO_ROOT/.env}"
PROJECT_ENV_FILE="${PROJECT_ENV_FILE:-$REPO_ROOT/.env}" "$REPO_ROOT/scripts/check_db_target.sh" read apex
DB_ROLE_ARG="$APEX_REQUIRED_ROLE"

mkdir -p "$REPO_ROOT/scratch"
STAGING_DIR="$(mktemp -d "$REPO_ROOT/scratch/apex-export.XXXXXX")"
cleanup() { rm -rf -- "$STAGING_DIR"; }
trap cleanup EXIT
mkdir -p "$STAGING_DIR/apps/$APEX_PARSING_SCHEMA"

(
  cd "$STAGING_DIR"
  sql -S -noupdates -name "$APEX_SQLCL_CONNECTION" \
    "@$REPO_ROOT/scripts/export_apps.sql" \
    "$APEX_PARSING_SCHEMA" "$APEX_APP_ID" "$DB_ENVIRONMENT" \
    "$APEX_EXPECTED_USER" "$DB_ROLE_ARG"
)

APP_STAGE="$STAGING_DIR/apps/$APEX_PARSING_SCHEMA/$APEX_APP_SLUG"
test -f "$APP_STAGE/application.apx" || {
  echo "APEX export did not create $APP_STAGE/application.apx" >&2
  exit 1
}
test -f "$APP_STAGE/.apex/apexlang.json" || {
  echo "APEX export did not create $APP_STAGE/.apex/apexlang.json" >&2
  exit 1
}
"$REPO_ROOT/scripts/normalize_apx.sh" "$APP_STAGE"
"$REPO_ROOT/scripts/replace_mirror.sh" "$APP_STAGE" "apps/$APEX_PARSING_SCHEMA/$APEX_APP_SLUG"
