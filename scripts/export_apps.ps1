#Requires -Version 5.1
# Export the configured APEX application as an APEXlang mirror.
$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "load_env.ps1") -EnvFile $env:PROJECT_ENV_FILE
. (Join-Path $PSScriptRoot "invoke_sqlcl.ps1")
& (Join-Path $PSScriptRoot "check_db_target.ps1") -Operation read -Target apex
$appIds = @($env:APEX_APP_ID.Split(','))

# Refuse any dirty destination before making the first database connection.
foreach ($appId in $appIds) {
  $destination = "apps/$($env:APEX_PARSING_SCHEMA)/$appId"
  $dirty = @(git -C $repoRoot status --porcelain --untracked-files=all -- $destination)
  if ($LASTEXITCODE -ne 0) { throw "unable to inspect Git status for mirror: $destination" }
  if (-not [string]::IsNullOrWhiteSpace(($dirty -join "`n"))) {
    throw "refusing to export over dirty mirror: $destination; commit, stash, or remove local changes first"
  }
}

$scratchPath = Join-Path $repoRoot "scratch"
New-Item -ItemType Directory -Force -Path $scratchPath | Out-Null
$stagingPath = Join-Path $scratchPath ("apex-export-" + [Guid]::NewGuid().ToString("N"))
$stageParent = Join-Path $stagingPath "staged/apps/$($env:APEX_PARSING_SCHEMA)"
New-Item -ItemType Directory -Force -Path $stageParent | Out-Null

try {
  foreach ($appId in $appIds) {
    $runPath = Join-Path $stagingPath "runs/$appId"
    $runStageParent = Join-Path $runPath "apps/$($env:APEX_PARSING_SCHEMA)"
    New-Item -ItemType Directory -Force -Path $runStageParent | Out-Null

    $sqlclExit = Invoke-Sqlcl -WorkingDirectory $runPath `
      -StdInFile (Join-Path $stagingPath ".sqlcl-stdin") `
      -Arguments @(
        "-S", "-noupdates", "-name", $env:APEX_SQLCL_CONNECTION,
        "@$(Join-Path $repoRoot 'scripts/export_apps.sql')",
        $env:APEX_PARSING_SCHEMA, $appId, $env:DB_ENVIRONMENT,
        $env:APEX_EXPECTED_USER
      )
    if ($sqlclExit -ne 0) {
      throw "SQLcl export for application $appId failed with exit code $sqlclExit"
    }

    # SQLcl names each export directory after the application alias, which can
    # change independently of the immutable application id used by the mirror.
    $exported = @(Get-ChildItem -LiteralPath $runStageParent -Directory)
    if ($exported.Count -ne 1) {
      throw "expected exactly one exported directory for application $appId, found $($exported.Count)"
    }
    $exportedDir = $exported[0].FullName
    if (-not (Test-Path -LiteralPath (Join-Path $exportedDir "application.apx") -PathType Leaf)) {
      throw "APEX export for application $appId did not create application.apx"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $exportedDir ".apex/apexlang.json") -PathType Leaf)) {
      throw "APEX export for application $appId did not create .apex/apexlang.json"
    }

    $appStage = Join-Path $stageParent $appId
    Move-Item -LiteralPath $exportedDir -Destination $appStage
    & (Join-Path $PSScriptRoot "normalize_apx.ps1") $appStage
  }

  # Install only after every requested application has exported and verified.
  foreach ($appId in $appIds) {
    & (Join-Path $PSScriptRoot "replace_mirror.ps1") `
      (Join-Path $stageParent $appId) "apps/$($env:APEX_PARSING_SCHEMA)/$appId"
  }
} finally {
  if (Test-Path -LiteralPath $stagingPath) {
    Remove-Item -LiteralPath $stagingPath -Recurse -Force -ErrorAction Stop
  }
}
