param([string]$EnvFile = $env:PROJECT_ENV_FILE)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if ([string]::IsNullOrWhiteSpace($EnvFile)) { $EnvFile = Join-Path $repoRoot ".env" }
if (-not (Test-Path -LiteralPath $EnvFile -PathType Leaf)) {
  throw "project environment error: configuration file not found: $EnvFile (copy .env.example to .env)"
}

$seen = @{}
$allowed = @(
  "PROJECT_NAME", "DB_ENVIRONMENT", "APEX_APP_ID", "APEX_APP_SLUG",
  "TABLES_SCHEMA", "TABLES_SQLCL_CONNECTION", "TABLES_EXPECTED_USER", "TABLES_REQUIRED_ROLE",
  "CODE_SCHEMA", "CODE_SQLCL_CONNECTION", "CODE_EXPECTED_USER", "CODE_REQUIRED_ROLE",
  "APEX_PARSING_SCHEMA", "APEX_SQLCL_CONNECTION", "APEX_EXPECTED_USER", "APEX_REQUIRED_ROLE",
  "INSTALL_UC_APX", "UC_APX_SKILLS_AGENT"
)
foreach ($line in [System.IO.File]::ReadAllLines($EnvFile)) {
  $line = $line.TrimEnd("`r")
  if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) { continue }
  if ($line -notmatch '^([A-Z][A-Z0-9_]*)=(.*)$') {
    throw "project environment error: invalid line in ${EnvFile}: $line"
  }
  $key = $Matches[1]
  $value = $Matches[2]
  if ($key -notin $allowed) { throw "project environment error: unsupported setting in ${EnvFile}: $key" }
  if ($seen.ContainsKey($key)) { throw "project environment error: duplicate setting in ${EnvFile}: $key" }
  if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
      ($value.StartsWith("'") -and $value.EndsWith("'"))) {
    $value = $value.Substring(1, $value.Length - 2)
  }
  Set-Item -LiteralPath "Env:$key" -Value $value
  $seen[$key] = $true
}

$required = @(
  "PROJECT_NAME", "DB_ENVIRONMENT", "APEX_APP_ID", "APEX_APP_SLUG",
  "TABLES_SCHEMA", "TABLES_SQLCL_CONNECTION", "TABLES_EXPECTED_USER", "TABLES_REQUIRED_ROLE",
  "CODE_SCHEMA", "CODE_SQLCL_CONNECTION", "CODE_EXPECTED_USER", "CODE_REQUIRED_ROLE",
  "APEX_PARSING_SCHEMA", "APEX_SQLCL_CONNECTION", "APEX_EXPECTED_USER", "APEX_REQUIRED_ROLE",
  "INSTALL_UC_APX", "UC_APX_SKILLS_AGENT"
)
foreach ($key in $required) {
  if (-not $seen.ContainsKey($key) -or [string]::IsNullOrWhiteSpace((Get-Item -LiteralPath "Env:$key").Value)) {
    throw "project environment error: $key is required in $EnvFile"
  }
}
if ($env:APEX_APP_ID -notmatch '^[1-9][0-9]*$') { throw "APEX_APP_ID must be a positive integer" }
if ($env:APEX_APP_SLUG -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw "APEX_APP_SLUG contains unsafe path characters" }
if ($env:DB_ENVIRONMENT -notin @("development", "test", "staging", "production")) { throw "DB_ENVIRONMENT is invalid" }
if ($env:INSTALL_UC_APX -notin @("true", "false")) { throw "INSTALL_UC_APX must be true or false" }
if ($env:UC_APX_SKILLS_AGENT -notin @("universal", "claude-code")) { throw "UC_APX_SKILLS_AGENT is invalid" }
foreach ($key in @("TABLES_SCHEMA", "TABLES_EXPECTED_USER", "CODE_SCHEMA", "CODE_EXPECTED_USER", "APEX_PARSING_SCHEMA", "APEX_EXPECTED_USER")) {
  if ((Get-Item -LiteralPath "Env:$key").Value -notmatch '^[A-Z][A-Z0-9_$#]{0,127}$') {
    throw "$key must be an uppercase Oracle identifier"
  }
}
foreach ($key in @("TABLES_SQLCL_CONNECTION", "CODE_SQLCL_CONNECTION", "APEX_SQLCL_CONNECTION")) {
  if ((Get-Item -LiteralPath "Env:$key").Value -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
    throw "$key contains unsupported characters"
  }
}
foreach ($key in @("TABLES_REQUIRED_ROLE", "CODE_REQUIRED_ROLE", "APEX_REQUIRED_ROLE")) {
  if ((Get-Item -LiteralPath "Env:$key").Value -notmatch '^[A-Z][A-Z0-9_$#]{0,127}$') {
    throw "$key must be an uppercase Oracle role name or NONE"
  }
}
