param([ValidateSet("read", "write")][string]$Operation)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "load_env.ps1") -EnvFile $env:PROJECT_ENV_FILE

$productionPattern = '(?i)(^|[-_.])(prod|prd|production|live)[0-9]*([-_.]|$)'
if ($env:SQLCL_CONNECTION -match $productionPattern -and $env:DB_ENVIRONMENT -ne "production") {
  throw "connection '$($env:SQLCL_CONNECTION)' resembles production but DB_ENVIRONMENT=$($env:DB_ENVIRONMENT); ask the user whether this is production"
}
if ($env:DB_ENVIRONMENT -eq "production") {
  if ($Operation -ne "read") { throw "production database operations are always read-only; '$Operation' is blocked" }
  if ([string]::IsNullOrWhiteSpace($env:DB_REQUIRED_ROLE) -or $env:DB_REQUIRED_ROLE -eq "NONE") { throw "DB_REQUIRED_ROLE is required for production" }
  if ($env:DB_EXPECTED_USER -eq $env:DB_TARGET_SCHEMA) { throw "production must use a dedicated non-owner read-only account" }
}
