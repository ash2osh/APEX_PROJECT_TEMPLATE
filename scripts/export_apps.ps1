#Requires -Version 5.1
# Export the configured APEX application as an APEXlang mirror.
$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "load_env.ps1") -EnvFile $env:PROJECT_ENV_FILE
& (Join-Path $PSScriptRoot "check_db_target.ps1") -Operation read -Target apex
$dbRoleArg = $env:APEX_REQUIRED_ROLE

$scratchPath = Join-Path $repoRoot "scratch"
New-Item -ItemType Directory -Force -Path $scratchPath | Out-Null
$stagingPath = Join-Path $scratchPath ("apex-export-" + [Guid]::NewGuid().ToString("N"))
$stageParent = Join-Path $stagingPath "apps/$($env:APEX_PARSING_SCHEMA)"
New-Item -ItemType Directory -Force -Path $stageParent | Out-Null

try {
  $locationPushed = $false
  Push-Location $stagingPath
  $locationPushed = $true
  & sql -S -noupdates -name $env:APEX_SQLCL_CONNECTION `
    "@$(Join-Path $repoRoot 'scripts/export_apps.sql')" `
    $env:APEX_PARSING_SCHEMA $env:APEX_APP_ID $env:DB_ENVIRONMENT `
    $env:APEX_EXPECTED_USER $dbRoleArg
  if ($LASTEXITCODE -ne 0) { throw "SQLcl application export failed with exit code $LASTEXITCODE" }

  # SQLcl names the export directory after the application alias, which this
  # template does not control and which can be renamed in APEX at any time.
  # Detect what SQLcl actually created instead of predicting its name.
  $exported = @(Get-ChildItem -LiteralPath $stageParent -Directory)
  if ($exported.Count -ne 1) {
    throw "expected exactly one exported application directory under apps/$($env:APEX_PARSING_SCHEMA), found $($exported.Count)"
  }
  $exportedDir = $exported[0].FullName
  if (-not (Test-Path -LiteralPath (Join-Path $exportedDir "application.apx") -PathType Leaf)) {
    throw "APEX export did not create application.apx directly under $exportedDir"
  }
  if (-not (Test-Path -LiteralPath (Join-Path $exportedDir ".apex/apexlang.json") -PathType Leaf)) {
    throw "APEX export did not create .apex/apexlang.json directly under $exportedDir"
  }

  # The mirror is named by the immutable application id, not the alias.
  $appStage = Join-Path $stageParent $env:APEX_APP_ID
  if ($exportedDir -ne $appStage) {
    if (Test-Path -LiteralPath $appStage) {
      throw "staged application id directory already exists: $appStage"
    }
    Move-Item -LiteralPath $exportedDir -Destination $appStage
  }

  & (Join-Path $PSScriptRoot "normalize_apx.ps1") $appStage
  & (Join-Path $PSScriptRoot "replace_mirror.ps1") $appStage "apps/$($env:APEX_PARSING_SCHEMA)/$($env:APEX_APP_ID)"
} finally {
  if ($locationPushed) { Pop-Location }
  if (Test-Path -LiteralPath $stagingPath) {
    Remove-Item -LiteralPath $stagingPath -Recurse -Force -ErrorAction Stop
  }
}
