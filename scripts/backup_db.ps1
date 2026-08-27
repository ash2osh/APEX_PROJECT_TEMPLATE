# Refresh database/{{SCHEMA}}/ from live DB state via DBMS_METADATA.
# Requires a saved SQLcl connection named {{CONN_NAME}}.
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
New-Item -ItemType Directory -Force -Path "database/{{SCHEMA}}/tables","database/{{SCHEMA}}/views","database/{{SCHEMA}}/packages" | Out-Null
sql -S -noupdates -name "{{CONN_NAME}}" "@scripts/backup_db.sql"
Remove-Item -Force -ErrorAction SilentlyContinue "scripts/_backup_db_driver.sql"
