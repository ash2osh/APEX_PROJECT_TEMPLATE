# Export the configured APEX application as an APEXlang mirror.
$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "load_env.ps1") -EnvFile $env:PROJECT_ENV_FILE
& (Join-Path $PSScriptRoot "check_db_target.ps1") -Operation read -Target apex
$dbRoleArg = $env:APEX_REQUIRED_ROLE

$scratchPath = Join-Path $repoRoot "scratch"
New-Item -ItemType Directory -Force -Path $scratchPath | Out-Null
$stagingPath = Join-Path $scratchPath ("apex-export-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path (Join-Path $stagingPath "apps/$($env:APEX_PARSING_SCHEMA)") | Out-Null

try {
  $locationPushed = $false
  Push-Location $stagingPath
  $locationPushed = $true
  & sql -S -noupdates -name $env:APEX_SQLCL_CONNECTION `
    "@$(Join-Path $repoRoot 'scripts/export_apps.sql')" `
    $env:APEX_PARSING_SCHEMA $env:APEX_APP_ID $env:DB_ENVIRONMENT `
    $env:APEX_EXPECTED_USER $dbRoleArg
  if ($LASTEXITCODE -ne 0) { throw "SQLcl application export failed with exit code $LASTEXITCODE" }
  $appStage = Join-Path $stagingPath "apps/$($env:APEX_PARSING_SCHEMA)/$($env:APEX_APP_SLUG)"
  if (-not (Test-Path -LiteralPath (Join-Path $appStage "application.apx") -PathType Leaf)) {
    throw "APEX export did not create application.apx directly under $appStage"
  }
  if (-not (Test-Path -LiteralPath (Join-Path $appStage ".apex/apexlang.json") -PathType Leaf)) {
    throw "APEX export did not create .apex/apexlang.json directly under $appStage"
  }
  & (Join-Path $PSScriptRoot "normalize_apx.ps1") $appStage
  & (Join-Path $PSScriptRoot "replace_mirror.ps1") $appStage "apps/$($env:APEX_PARSING_SCHEMA)/$($env:APEX_APP_SLUG)"
} finally {
  if ($locationPushed) { Pop-Location }
  if (Test-Path -LiteralPath $stagingPath) {
    Remove-Item -LiteralPath $stagingPath -Recurse -Force -ErrorAction Stop
  }
}
