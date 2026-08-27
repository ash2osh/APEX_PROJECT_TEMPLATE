#!/usr/bin/env bash
# Export the {{APP_ID}} APEX application to apps/{{SCHEMA}}/{{APP_SLUG}}/ (APEXLANG format).
# Requires a saved SQLcl connection named {{CONN_NAME}}.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
mkdir -p "$REPO_ROOT/scratch"
STAGING_DIR="$(mktemp -d "$REPO_ROOT/scratch/apex-export.XXXXXX")"
cleanup() { rm -rf -- "$STAGING_DIR"; }
trap cleanup EXIT
mkdir -p "$STAGING_DIR/apps/{{SCHEMA}}/{{APP_SLUG}}"

(
  cd "$STAGING_DIR"
  sql -S -noupdates -name "{{CONN_NAME}}" "@$REPO_ROOT/scripts/export_apps.sql"
)

APP_STAGE="$STAGING_DIR/apps/{{SCHEMA}}/{{APP_SLUG}}"
test -d "$APP_STAGE" || { echo "APEX export did not create $APP_STAGE" >&2; exit 1; }
"$REPO_ROOT/scripts/normalize_apx.sh" "$APP_STAGE"
"$REPO_ROOT/scripts/replace_mirror.sh" "$APP_STAGE" "apps/{{SCHEMA}}/{{APP_SLUG}}"
