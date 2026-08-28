# Refresh table and code DBMS_METADATA mirrors through independent read targets.
$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "load_env.ps1") -EnvFile $env:PROJECT_ENV_FILE
& (Join-Path $PSScriptRoot "check_db_target.ps1") -Operation read -Target tables
& (Join-Path $PSScriptRoot "check_db_target.ps1") -Operation read -Target code

$backupTargets = @(
  [PSCustomObject]@{
    Scope = "tables"
    Schema = $env:TABLES_SCHEMA
    Connection = $env:TABLES_SQLCL_CONNECTION
    ExpectedUser = $env:TABLES_EXPECTED_USER
    RequiredRole = $env:TABLES_REQUIRED_ROLE
  },
  [PSCustomObject]@{
    Scope = "code"
    Schema = $env:CODE_SCHEMA
    Connection = $env:CODE_SQLCL_CONNECTION
    ExpectedUser = $env:CODE_EXPECTED_USER
    RequiredRole = $env:CODE_REQUIRED_ROLE
  }
)
$backupSchemas = @($backupTargets.Schema | Select-Object -Unique)

# Refuse local mirror edits before making either database connection.
foreach ($schema in $backupSchemas) {
  $destination = "database/$schema"
  $dirty = @(git -C $repoRoot status --porcelain --untracked-files=all -- $destination)
  if ($LASTEXITCODE -ne 0) { throw "unable to inspect Git status for mirror: $destination" }
  if (-not [string]::IsNullOrWhiteSpace(($dirty -join "`n"))) {
    throw "refusing to back up over dirty mirror: $destination; commit, stash, or remove local changes first"
  }
}

$scratchPath = Join-Path $repoRoot "scratch"
New-Item -ItemType Directory -Force -Path $scratchPath | Out-Null
$stagingPath = Join-Path $scratchPath ("db-backup-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path (Join-Path $stagingPath "scripts") | Out-Null
foreach ($schema in $backupSchemas) {
  $dbStage = Join-Path $stagingPath "database/$schema"
  New-Item -ItemType Directory -Force -Path @(
    (Join-Path $dbStage "tables"), (Join-Path $dbStage "views"),
    (Join-Path $dbStage "packages"), (Join-Path $dbStage "procedures"),
    (Join-Path $dbStage "functions"), (Join-Path $dbStage "triggers")
  ) | Out-Null
}

try {
  $locationPushed = $false
  Push-Location $stagingPath
  $locationPushed = $true

  # Both exports and manifests must complete before any generated mirror changes.
  foreach ($target in $backupTargets) {
    & sql -S -noupdates -name $target.Connection `
      "@$(Join-Path $repoRoot 'scripts/backup_db.sql')" `
      $target.Schema $target.Scope $env:DB_ENVIRONMENT `
      $target.ExpectedUser $target.RequiredRole
    if ($LASTEXITCODE -ne 0) {
      throw "SQLcl $($target.Scope) metadata backup failed with exit code $LASTEXITCODE"
    }
    $manifestPath = Join-Path $stagingPath "database/$($target.Schema)/manifest-$($target.Scope).txt"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
      throw "database backup did not create manifest-$($target.Scope).txt under database/$($target.Schema)"
    }
  }

  Pop-Location
  $locationPushed = $false
  foreach ($schema in $backupSchemas) {
    & (Join-Path $PSScriptRoot "replace_mirror.ps1") `
      (Join-Path $stagingPath "database/$schema") "database/$schema"
  }
} finally {
  if ($locationPushed) { Pop-Location }
  if (Test-Path -LiteralPath $stagingPath) {
    Remove-Item -LiteralPath $stagingPath -Recurse -Force -ErrorAction Stop
  }
}
