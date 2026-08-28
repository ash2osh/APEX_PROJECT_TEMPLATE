#Requires -Version 5.1
# Pre-connect environment classification. Database identity is verified in SQL.
#
# Production safety in this template is an instruction to the client, not a
# privilege audit: read targets are allowed, write operation classes are
# refused, and the operator is told to run SELECT statements only.
param(
  [Parameter(Mandatory = $true)][ValidateSet("read", "write")][string]$Operation,
  [Parameter(Mandatory = $true)][ValidateSet("tables", "code", "apex")][string]$Target
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "load_env.ps1") -EnvFile $env:PROJECT_ENV_FILE

switch ($Target) {
  "tables" { $targetConnection = $env:TABLES_SQLCL_CONNECTION }
  "code"   { $targetConnection = $env:CODE_SQLCL_CONNECTION }
  "apex"   { $targetConnection = $env:APEX_SQLCL_CONNECTION }
}

$productionPattern = '(?i)(^|[-_.])(prod|prd|production|live)[0-9]*([-_.]|$)'
if ($targetConnection -match $productionPattern -and $env:DB_ENVIRONMENT -ne "production") {
  throw "$Target connection '$targetConnection' resembles production but DB_ENVIRONMENT=$($env:DB_ENVIRONMENT); ask the user whether this is production"
}
if ($env:DB_ENVIRONMENT -eq "production") {
  if ($Operation -ne "read") { throw "production database operations are always read-only; '$Operation' is blocked" }
  Write-Warning @"
PRODUCTION SESSION - READ ONLY
  Run SELECT statements only.
  Do NOT run INSERT, UPDATE, DELETE, MERGE, or any other DML.
  Do NOT run CREATE, ALTER, DROP, TRUNCATE, or any other DDL.
  Do NOT COMMIT. Prepare changes for an approved deployment instead.
  This is not enforced by the database. It is your contract.
"@
}
