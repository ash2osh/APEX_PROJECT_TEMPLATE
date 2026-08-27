# Refresh the configured schema's read-only DBMS_METADATA mirror.
$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "load_env.ps1") -EnvFile $env:PROJECT_ENV_FILE
& (Join-Path $PSScriptRoot "check_db_target.ps1") -Operation read
$dbRoleArg = if ([string]::IsNullOrWhiteSpace($env:DB_REQUIRED_ROLE)) { "NONE" } else { $env:DB_REQUIRED_ROLE }

$scratchPath = Join-Path $repoRoot "scratch"
New-Item -ItemType Directory -Force -Path $scratchPath | Out-Null
$stagingPath = Join-Path $scratchPath ("db-backup-" + [Guid]::NewGuid().ToString("N"))
$dbStage = Join-Path $stagingPath "database/$($env:DB_TARGET_SCHEMA)"
New-Item -ItemType Directory -Force -Path @(
  (Join-Path $dbStage "tables"), (Join-Path $dbStage "views"),
  (Join-Path $dbStage "packages"), (Join-Path $dbStage "procedures"),
  (Join-Path $dbStage "functions"), (Join-Path $dbStage "triggers"),
  (Join-Path $stagingPath "scripts")
) | Out-Null

try {
  $locationPushed = $false
  Push-Location $stagingPath
  $locationPushed = $true
  & sql -S -noupdates -name $env:SQLCL_CONNECTION `
    "@$(Join-Path $repoRoot 'scripts/backup_db.sql')" `
    $env:DB_TARGET_SCHEMA $env:DB_ENVIRONMENT $env:DB_EXPECTED_USER $dbRoleArg
  if ($LASTEXITCODE -ne 0) { throw "SQLcl database backup failed with exit code $LASTEXITCODE" }
  if (-not (Test-Path -LiteralPath (Join-Path $dbStage "manifest.txt") -PathType Leaf)) {
    throw "database backup did not create manifest.txt under $dbStage"
  }
  & (Join-Path $PSScriptRoot "replace_mirror.ps1") $dbStage "database/$($env:DB_TARGET_SCHEMA)"
} finally {
  if ($locationPushed) { Pop-Location }
  if (Test-Path -LiteralPath $stagingPath) {
    Remove-Item -LiteralPath $stagingPath -Recurse -Force -ErrorAction Stop
  }
}
