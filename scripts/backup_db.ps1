# Refresh database/{{SCHEMA}}/ from live DB state via DBMS_METADATA.
# Requires a saved SQLcl connection named {{CONN_NAME}}.
$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$scratchPath = Join-Path $repoRoot "scratch"
New-Item -ItemType Directory -Force -Path $scratchPath | Out-Null
$stagingPath = Join-Path $scratchPath ("db-backup-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path @(
  (Join-Path $stagingPath "database/{{SCHEMA}}/tables"),
  (Join-Path $stagingPath "database/{{SCHEMA}}/views"),
  (Join-Path $stagingPath "database/{{SCHEMA}}/packages"),
  (Join-Path $stagingPath "scripts")
) | Out-Null

try {
  $locationPushed = $false
  Push-Location $stagingPath
  $locationPushed = $true
  & sql -S -noupdates -name "{{CONN_NAME}}" "@$(Join-Path $repoRoot 'scripts/backup_db.sql')"
  if ($LASTEXITCODE -ne 0) { throw "SQLcl database backup failed with exit code $LASTEXITCODE" }
  $dbStage = Join-Path $stagingPath "database/{{SCHEMA}}"
  if (-not (Test-Path -LiteralPath $dbStage -PathType Container)) { throw "database backup did not create $dbStage" }
  & (Join-Path $PSScriptRoot "replace_mirror.ps1") $dbStage "database/{{SCHEMA}}"
} finally {
  if ($locationPushed) { Pop-Location }
  if (Test-Path -LiteralPath $stagingPath) {
    Remove-Item -LiteralPath $stagingPath -Recurse -Force -ErrorAction Stop
  }
}
