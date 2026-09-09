#Requires -Version 5.1
# Refresh table and code DBMS_METADATA mirrors through independent read targets.
$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "load_env.ps1") -EnvFile $env:PROJECT_ENV_FILE
. (Join-Path $PSScriptRoot "invoke_sqlcl.ps1")
& (Join-Path $PSScriptRoot "check_db_target.ps1") -Operation read -Target tables
& (Join-Path $PSScriptRoot "check_db_target.ps1") -Operation read -Target code

# A failed SPOOL inside the generated driver prints an SP2- message that does
# not stop SQLcl, so an object can go missing without any non-zero exit code.
# The manifest states how many objects each scope should have produced; refuse
# to install a mirror that does not have exactly that many files.
function Get-ScopeDirectory {
  param([Parameter(Mandatory = $true)][ValidateSet("tables", "code")][string] $Scope)
  if ($Scope -eq "tables") { return @("tables") }
  return @("views", "packages", "procedures", "functions", "triggers")
}

function Test-ScopeComplete {
  param(
    [string] $Scope,
    [string] $Schema,
    [string] $StagingPath
  )
  $manifestPath = Join-Path $StagingPath "database/$Schema/manifest-$Scope.txt"
  $expected = 0
  $counted = 0
  foreach ($line in (Get-Content -LiteralPath $manifestPath)) {
    $separator = $line.LastIndexOf('=')
    if ($separator -lt 0) { continue }
    $count = $line.Substring($separator + 1).Trim()
    $parsed = 0
    if ([int]::TryParse($count, [ref] $parsed)) {
      $expected += $parsed
      $counted += 1
    }
  }

  # No parsable counts at all means the manifest itself is unusable. Fail
  # closed rather than approving whatever happens to be staged.
  if ($counted -eq 0) {
    throw ("database backup manifest for $Schema ($Scope) has no readable " +
      "object counts; the mirror was not replaced")
  }

  $scopeDirs = Get-ScopeDirectory -Scope $Scope
  $actual = 0
  foreach ($scopeDir in $scopeDirs) {
    $scopePath = Join-Path $StagingPath "database/$Schema/$scopeDir"
    if (Test-Path -LiteralPath $scopePath) {
      $actual += @(Get-ChildItem -LiteralPath $scopePath -File -Filter *.sql).Count
    }
  }

  if ($expected -ne $actual) {
    throw ("database backup is incomplete for $Schema ($Scope): manifest expects " +
      "$expected object file(s) but $actual were written; the mirror was not replaced")
  }
}

$backupTargets = @(
  [PSCustomObject]@{
    Scope = "tables"
    Schema = $env:TABLES_SCHEMA
    Connection = $env:TABLES_SQLCL_CONNECTION
    ExpectedUser = $env:TABLES_EXPECTED_USER
    Prefixes = $env:TABLES_PREFIXES
  },
  [PSCustomObject]@{
    Scope = "code"
    Schema = $env:CODE_SCHEMA
    Connection = $env:CODE_SQLCL_CONNECTION
    ExpectedUser = $env:CODE_EXPECTED_USER
    Prefixes = $env:CODE_PREFIXES
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

try {
  $locationPushed = $false
  Push-Location $stagingPath
  $locationPushed = $true

  # Both exports and manifests must complete before any generated mirror changes.
  foreach ($target in $backupTargets) {
    foreach ($scopeDir in (Get-ScopeDirectory -Scope $target.Scope)) {
      New-Item -ItemType Directory -Force `
        -Path (Join-Path $stagingPath "database/$($target.Schema)/$scopeDir") | Out-Null
    }
    $sqlclExit = Invoke-Sqlcl -WorkingDirectory $stagingPath `
      -StdInFile (Join-Path $stagingPath ".sqlcl-stdin") `
      -Arguments @(
        "-S", "-noupdates", "-name", $target.Connection,
        "@$(Join-Path $repoRoot 'scripts/backup_db.sql')",
        $target.Schema, $target.Scope, $env:DB_ENVIRONMENT,
        $target.ExpectedUser, $target.Prefixes
      )
    if ($sqlclExit -ne 0) {
      throw "SQLcl $($target.Scope) metadata backup failed with exit code $sqlclExit"
    }
    $manifestPath = Join-Path $stagingPath "database/$($target.Schema)/manifest-$($target.Scope).txt"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
      throw "database backup did not create manifest-$($target.Scope).txt under database/$($target.Schema)"
    }
    Test-ScopeComplete -Scope $target.Scope -Schema $target.Schema -StagingPath $stagingPath
  }

  Pop-Location
  $locationPushed = $false
  $replaceArgs = @()
  foreach ($schema in $backupSchemas) {
    # A scope that produced no objects of one type leaves an empty directory
    # that would otherwise be installed. Prune after verification. Descending
    # order empties the deepest directories first, so a parent left empty by
    # its own pruned children is removed in the same pass.
    Get-ChildItem -LiteralPath (Join-Path $stagingPath "database/$schema") -Recurse -Directory |
      Sort-Object -Property FullName -Descending |
      ForEach-Object {
        if (-not (Get-ChildItem -LiteralPath $_.FullName -Force)) {
          Remove-Item -LiteralPath $_.FullName -Force
        }
      }
    $replaceArgs += (Join-Path $stagingPath "database/$schema")
    $replaceArgs += "database/$schema"
  }
  & (Join-Path $PSScriptRoot "replace_mirror.ps1") @replaceArgs
} finally {
  if ($locationPushed) { Pop-Location }
  if (Test-Path -LiteralPath $stagingPath) {
    # This runs after the mirrors are already installed. A file handle Windows
    # has not released yet must not convert a completed backup into a failure,
    # which is why Bash uses `rm -rf` in a trap and ignores the result.
    Remove-Item -LiteralPath $stagingPath -Recurse -Force -ErrorAction SilentlyContinue
  }
}
