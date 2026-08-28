param(
  [Parameter(Mandatory = $true)][ValidateSet("read", "write")][string]$Operation,
  [Parameter(Mandatory = $true)][ValidateSet("tables", "code", "apex")][string]$Target
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "load_env.ps1") -EnvFile $env:PROJECT_ENV_FILE

switch ($Target) {
  "tables" {
    $targetSchema = $env:TABLES_SCHEMA
    $targetConnection = $env:TABLES_SQLCL_CONNECTION
    $targetExpectedUser = $env:TABLES_EXPECTED_USER
    $targetRequiredRole = $env:TABLES_REQUIRED_ROLE
  }
  "code" {
    $targetSchema = $env:CODE_SCHEMA
    $targetConnection = $env:CODE_SQLCL_CONNECTION
    $targetExpectedUser = $env:CODE_EXPECTED_USER
    $targetRequiredRole = $env:CODE_REQUIRED_ROLE
  }
  "apex" {
    $targetSchema = $env:APEX_PARSING_SCHEMA
    $targetConnection = $env:APEX_SQLCL_CONNECTION
    $targetExpectedUser = $env:APEX_EXPECTED_USER
    $targetRequiredRole = $env:APEX_REQUIRED_ROLE
  }
}

$productionPattern = '(?i)(^|[-_.])(prod|prd|production|live)[0-9]*([-_.]|$)'
if ($targetConnection -match $productionPattern -and $env:DB_ENVIRONMENT -ne "production") {
  throw "$Target connection '$targetConnection' resembles production but DB_ENVIRONMENT=$($env:DB_ENVIRONMENT); ask the user whether this is production"
}
if ($env:DB_ENVIRONMENT -eq "production") {
  if ($Operation -ne "read") { throw "production database operations are always read-only; '$Operation' is blocked" }
  if ($targetRequiredRole -eq "NONE") { throw "$($Target.ToUpper())_REQUIRED_ROLE is required for production" }
  if ($targetExpectedUser -eq $targetSchema) { throw "production $Target target must use a dedicated non-owner read-only account" }
}
