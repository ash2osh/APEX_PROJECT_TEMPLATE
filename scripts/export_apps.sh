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
STAGE_PARENT="$STAGING_DIR/apps/$APEX_PARSING_SCHEMA"
mkdir -p "$STAGE_PARENT"

# SQLcl builds a JLine console over its standard input at startup. Handed a
# descriptor it cannot probe -- a pipe, or the Windows NUL device that
# /dev/null becomes under Git Bash -- it aborts with
# "java.io.IOException: Incorrect function" before running the script, and
# still exits 0. An empty regular file is a standard input every platform can
# probe, and it also stops SQLcl from consuming the caller's own input.
SQLCL_STDIN="$STAGING_DIR/.sqlcl-stdin"
: > "$SQLCL_STDIN"

(
  cd "$STAGING_DIR"
  sql -S -noupdates -name "$APEX_SQLCL_CONNECTION" \
    "@$REPO_ROOT/scripts/export_apps.sql" \
    "$APEX_PARSING_SCHEMA" "$APEX_APP_ID" "$DB_ENVIRONMENT" \
    "$APEX_EXPECTED_USER" "$DB_ROLE_ARG" < "$SQLCL_STDIN"
)

# SQLcl names the export directory after the application alias, which this
# template does not control and which can be renamed in APEX at any time.
# Detect what SQLcl actually created instead of predicting its name.
EXPORTED_DIR=""
EXPORTED_COUNT=0
while IFS= read -r -d '' candidate; do
  EXPORTED_DIR="$candidate"
  EXPORTED_COUNT=$((EXPORTED_COUNT + 1))
done < <(find "$STAGE_PARENT" -mindepth 1 -maxdepth 1 -type d -print0)

if [ "$EXPORTED_COUNT" -ne 1 ]; then
  echo "expected exactly one exported application directory under apps/$APEX_PARSING_SCHEMA, found $EXPORTED_COUNT" >&2
  exit 1
fi
test -f "$EXPORTED_DIR/application.apx" || {
  echo "APEX export did not create $EXPORTED_DIR/application.apx" >&2
  exit 1
}
test -f "$EXPORTED_DIR/.apex/apexlang.json" || {
  echo "APEX export did not create $EXPORTED_DIR/.apex/apexlang.json" >&2
  exit 1
}

# The mirror is named by the immutable application id, not the alias.
APP_STAGE="$STAGE_PARENT/$APEX_APP_ID"
if [ "$EXPORTED_DIR" != "$APP_STAGE" ]; then
  test -e "$APP_STAGE" && {
    echo "staged application id directory already exists: $APP_STAGE" >&2
    exit 1
  }
  mv -- "$EXPORTED_DIR" "$APP_STAGE"
fi

"$REPO_ROOT/scripts/normalize_apx.sh" "$APP_STAGE"
"$REPO_ROOT/scripts/replace_mirror.sh" "$APP_STAGE" "apps/$APEX_PARSING_SCHEMA/$APEX_APP_ID"
