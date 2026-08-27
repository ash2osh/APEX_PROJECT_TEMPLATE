#!/usr/bin/env bash
# Export the {{APP_ID}} APEX application to apps/{{SCHEMA}}/ (APEXLANG format).
# Requires a saved SQLcl connection named {{CONN_NAME}}.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p "apps/{{SCHEMA}}"
sql -S -noupdates -name "{{CONN_NAME}}" @scripts/export_apps.sql
./scripts/normalize_apx.sh "apps/{{SCHEMA}}"
