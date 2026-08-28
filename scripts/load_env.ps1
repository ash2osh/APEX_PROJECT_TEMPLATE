#Requires -Version 5.1
# Dot-source this file to load a strict KEY=VALUE .env file without executing it.
#
# Dot-sourcing runs in the CALLER's scope, so every variable defined here is
# visible to the caller afterwards. Internals are prefixed with `projectEnv`
# and removed at the end to keep that surface small. The one unavoidable
# exception is the `$EnvFile` parameter itself: a caller that also uses a
# variable named `$EnvFile` (PowerShell names are case-insensitive, so
# `$envFile` too) will have it overwritten. Do not use that name in a script
# that dot-sources this one.
param([string]$EnvFile = $env:PROJECT_ENV_FILE)

$ErrorActionPreference = "Stop"
$projectEnvRepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if ([string]::IsNullOrWhiteSpace($EnvFile)) { $EnvFile = Join-Path $projectEnvRepoRoot ".env" }
if (-not (Test-Path -LiteralPath $EnvFile -PathType Leaf)) {
  throw "project environment error: configuration file not found: $EnvFile (copy .env.example to .env)"
}

$projectEnvSeen = @{}
$projectEnvAllowed = @(
  "PROJECT_NAME", "DB_ENVIRONMENT", "APEX_APP_ID",
  "TABLES_SCHEMA", "TABLES_SQLCL_CONNECTION", "TABLES_EXPECTED_USER", "TABLES_REQUIRED_ROLE",
  "CODE_SCHEMA", "CODE_SQLCL_CONNECTION", "CODE_EXPECTED_USER", "CODE_REQUIRED_ROLE",
  "APEX_PARSING_SCHEMA", "APEX_SQLCL_CONNECTION", "APEX_EXPECTED_USER", "APEX_REQUIRED_ROLE",
  "INSTALL_UC_APX", "UC_APX_SKILLS_AGENT"
)
foreach ($projectEnvLine in [System.IO.File]::ReadAllLines($EnvFile)) {
  $projectEnvLine = $projectEnvLine.TrimEnd("`r")
  if ([string]::IsNullOrWhiteSpace($projectEnvLine) -or $projectEnvLine.StartsWith("#")) { continue }
  if ($projectEnvLine -notmatch '^([A-Z][A-Z0-9_]*)=(.*)$') {
    throw "project environment error: invalid line in ${EnvFile}: $projectEnvLine"
  }
  $projectEnvKey = $Matches[1]
  $projectEnvValue = $Matches[2]
  if ($projectEnvKey -notin $projectEnvAllowed) { throw "project environment error: unsupported setting in ${EnvFile}: $projectEnvKey" }
  if ($projectEnvSeen.ContainsKey($projectEnvKey)) { throw "project environment error: duplicate setting in ${EnvFile}: $projectEnvKey" }
  if (($projectEnvValue.StartsWith('"') -and $projectEnvValue.EndsWith('"')) -or
      ($projectEnvValue.StartsWith("'") -and $projectEnvValue.EndsWith("'"))) {
    $projectEnvValue = $projectEnvValue.Substring(1, $projectEnvValue.Length - 2)
  }
  Set-Item -LiteralPath "Env:$projectEnvKey" -Value $projectEnvValue
  $projectEnvSeen[$projectEnvKey] = $true
}

$projectEnvRequired = @(
  "PROJECT_NAME", "DB_ENVIRONMENT", "APEX_APP_ID",
  "TABLES_SCHEMA", "TABLES_SQLCL_CONNECTION", "TABLES_EXPECTED_USER", "TABLES_REQUIRED_ROLE",
  "CODE_SCHEMA", "CODE_SQLCL_CONNECTION", "CODE_EXPECTED_USER", "CODE_REQUIRED_ROLE",
  "APEX_PARSING_SCHEMA", "APEX_SQLCL_CONNECTION", "APEX_EXPECTED_USER", "APEX_REQUIRED_ROLE",
  "INSTALL_UC_APX", "UC_APX_SKILLS_AGENT"
)
foreach ($projectEnvKey in $projectEnvRequired) {
  if (-not $projectEnvSeen.ContainsKey($projectEnvKey) -or [string]::IsNullOrWhiteSpace((Get-Item -LiteralPath "Env:$projectEnvKey").Value)) {
    throw "project environment error: $projectEnvKey is required in $EnvFile"
  }
}
if ($env:APEX_APP_ID -notmatch '^[1-9][0-9]*$') { throw "APEX_APP_ID must be a positive integer" }
if ($env:DB_ENVIRONMENT -notin @("development", "test", "staging", "production")) { throw "DB_ENVIRONMENT is invalid" }
if ($env:INSTALL_UC_APX -notin @("true", "false")) { throw "INSTALL_UC_APX must be true or false" }
if ($env:UC_APX_SKILLS_AGENT -notin @("universal", "claude-code")) { throw "UC_APX_SKILLS_AGENT is invalid" }
foreach ($projectEnvKey in @("TABLES_SCHEMA", "TABLES_EXPECTED_USER", "CODE_SCHEMA", "CODE_EXPECTED_USER", "APEX_PARSING_SCHEMA", "APEX_EXPECTED_USER")) {
  if ((Get-Item -LiteralPath "Env:$projectEnvKey").Value -notmatch '^[A-Z][A-Z0-9_$#]{0,127}$') {
    throw "$projectEnvKey must be an uppercase Oracle identifier"
  }
}
foreach ($projectEnvKey in @("TABLES_SQLCL_CONNECTION", "CODE_SQLCL_CONNECTION", "APEX_SQLCL_CONNECTION")) {
  if ((Get-Item -LiteralPath "Env:$projectEnvKey").Value -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
    throw "$projectEnvKey contains unsupported characters"
  }
}
foreach ($projectEnvKey in @("TABLES_REQUIRED_ROLE", "CODE_REQUIRED_ROLE", "APEX_REQUIRED_ROLE")) {
  if ((Get-Item -LiteralPath "Env:$projectEnvKey").Value -notmatch '^[A-Z][A-Z0-9_$#]{0,127}$') {
    throw "$projectEnvKey must be an uppercase Oracle role name or NONE"
  }
}

# Mirror load_env.sh, which unsets its own temporaries after a successful load.
Remove-Variable -Name projectEnvRepoRoot, projectEnvSeen, projectEnvAllowed,
  projectEnvRequired, projectEnvLine, projectEnvKey, projectEnvValue `
  -ErrorAction SilentlyContinue
