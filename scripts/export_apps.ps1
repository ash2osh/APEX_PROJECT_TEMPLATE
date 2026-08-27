# Export the {{APP_ID}} APEX application to apps/{{SCHEMA}}/ (APEXLANG format).
# Requires a saved SQLcl connection named {{CONN_NAME}}.
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
New-Item -ItemType Directory -Force -Path "apps/{{SCHEMA}}" | Out-Null
sql -S -noupdates -name "{{CONN_NAME}}" "@scripts/export_apps.sql"
& (Join-Path $PSScriptRoot "normalize_apx.ps1") "apps/{{SCHEMA}}"
