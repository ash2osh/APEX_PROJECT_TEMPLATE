#!/usr/bin/env bash
# Refresh database/{{SCHEMA}}/ from live DB state via DBMS_METADATA.
# Requires a saved SQLcl connection named {{CONN_NAME}}.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p "database/{{SCHEMA}}/tables" "database/{{SCHEMA}}/views" "database/{{SCHEMA}}/packages"
sql -S -noupdates -name "{{CONN_NAME}}" @scripts/backup_db.sql
rm -f scripts/_backup_db_driver.sql
