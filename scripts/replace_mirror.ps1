#Requires -Version 5.1
# Replace one generated mirror with a completed staging directory.
param(
  [Parameter(Mandatory = $true)][string]$StagedDir,
  [Parameter(Mandatory = $true)][string]$Destination
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not (Test-Path -LiteralPath $StagedDir -PathType Container)) {
  throw "staging directory does not exist or is not a directory: $StagedDir"
}
$stagedPath = (Resolve-Path -LiteralPath $StagedDir).Path
$scratchPath = Join-Path $repoRoot "scratch"
New-Item -ItemType Directory -Force -Path $scratchPath | Out-Null
$scratchRoot = (Resolve-Path -LiteralPath $scratchPath).Path

if (-not $stagedPath.StartsWith($scratchRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "staging directory must be inside scratch/: $stagedPath"
}

if ([System.IO.Path]::IsPathRooted($Destination)) {
  throw "destination must be a repository-relative mirror path: $Destination"
}

$destinationParts = $Destination -split '[\\/]'
$approvedDestination = ($destinationParts[0] -eq "database" -and $destinationParts.Count -eq 2) -or
  ($destinationParts[0] -eq "apps" -and $destinationParts.Count -eq 3)
if (-not $approvedDestination -or ($destinationParts | Where-Object { $_ -in @("", ".", "..") })) {
  throw "destination is not an approved generated mirror: $Destination"
}

$destinationPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Destination))

if (-not $destinationPath.StartsWith($repoRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "destination must be inside the repository: $destinationPath"
}

$relativeDestination = $Destination

$stagedFiles = Get-ChildItem -LiteralPath $stagedPath -File -Recurse | Select-Object -First 1
if ($null -eq $stagedFiles) {
  throw "staging directory is empty: $stagedPath"
}
$stagedLink = Get-ChildItem -LiteralPath $stagedPath -Force -Recurse |
  Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint } |
  Select-Object -First 1
if ($null -ne $stagedLink) {
  throw "staging directory contains a symbolic link or junction: $($stagedLink.FullName)"
}

# Create the destination parent before the first Git query. With apps/ present
# but apps/<schema>/ still absent -- every project's first APEX export -- a
# `git status -- apps/<schema>/<app-id>` prints a "could not open directory"
# warning that reads like an export failure.
$destinationParent = Split-Path -Parent $destinationPath
New-Item -ItemType Directory -Force -Path $destinationParent | Out-Null

$dirty = @(git -C $repoRoot status --porcelain --untracked-files=all -- $destinationPath)
$gitExitCode = $LASTEXITCODE
if ($gitExitCode -ne 0) {
  throw "unable to inspect Git status for mirror: $relativeDestination"
}
if (-not [string]::IsNullOrWhiteSpace(($dirty -join "`n"))) {
  throw "refusing to replace dirty mirror: $Destination"
}

$resolvedDestinationParent = (Resolve-Path -LiteralPath $destinationParent).Path
$destinationPath = Join-Path $resolvedDestinationParent (Split-Path -Leaf $destinationPath)
if (-not $destinationPath.StartsWith($repoRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "resolved destination escaped the repository: $destinationPath"
}
# Single-quoted PowerShell strings do not process escapes, so the separators
# are written as one character each: '\\' would be a two-character string and
# fail to cast to [char].
$canonicalRelativeDestination = $destinationPath.Substring($repoRoot.Length).TrimStart([char[]]@('/', '\'))
$canonicalDestinationParts = $canonicalRelativeDestination -split '[\\/]'
$canonicalApproved = ($canonicalDestinationParts[0] -eq "database" -and $canonicalDestinationParts.Count -eq 2) -or
  ($canonicalDestinationParts[0] -eq "apps" -and $canonicalDestinationParts.Count -eq 3)
if (-not $canonicalApproved) {
  throw "resolved destination is not an approved generated mirror: $canonicalRelativeDestination"
}
if ([System.IO.Path]::GetPathRoot($stagedPath) -ne [System.IO.Path]::GetPathRoot($destinationPath)) {
  throw "staging and destination must be on the same filesystem volume"
}
$mirrorName = Split-Path -Leaf $destinationPath
$backupPath = Join-Path $scratchPath (".mirror-backup.{0}.{1}" -f $mirrorName, $PID)
if (Test-Path -LiteralPath $backupPath) {
  throw "temporary replacement path already exists: $backupPath"
}

$lockRoot = Join-Path $scratchRoot ".mirror-locks"
New-Item -ItemType Directory -Force -Path $lockRoot | Out-Null
# SHA256::HashData and Convert::ToHexString are .NET 5+, so they are missing on
# Windows PowerShell 5.1. Create()/ComputeHash and BitConverter work on both.
$sha256 = [System.Security.Cryptography.SHA256]::Create()
try {
  $hashBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($canonicalRelativeDestination))
} finally {
  $sha256.Dispose()
}
$lockName = ([System.BitConverter]::ToString($hashBytes) -replace '-', '').Substring(0, 16) + ".lock"
$lockPath = Join-Path $lockRoot $lockName
try {
  $lockHandle = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
} catch {
  throw "another mirror replacement is already running for $canonicalRelativeDestination"
}

$hadOldMirror = Test-Path -LiteralPath $destinationPath
try {
  # Recheck after taking the lock to minimize the check-to-replace window.
  $dirty = @(git -C $repoRoot status --porcelain --untracked-files=all -- $destinationPath)
  if ($LASTEXITCODE -ne 0) {
    throw "unable to recheck Git status for mirror: $canonicalRelativeDestination"
  }
  if (-not [string]::IsNullOrWhiteSpace(($dirty -join "`n"))) {
    throw "refusing to replace dirty mirror: $canonicalRelativeDestination"
  }
  if ($hadOldMirror) {
    Move-Item -LiteralPath $destinationPath -Destination $backupPath
  }
  Move-Item -LiteralPath $stagedPath -Destination $destinationPath
} catch {
  $originalErrorMessage = $_.Exception.Message
  if ((Test-Path -LiteralPath $backupPath) -and -not (Test-Path -LiteralPath $destinationPath)) {
    try {
      Move-Item -LiteralPath $backupPath -Destination $destinationPath -ErrorAction Stop
    } catch {
      throw "replacement failed and rollback failed; old mirror is at $backupPath. Original error: $originalErrorMessage"
    }
  }
  throw
} finally {
  if ($null -ne $lockHandle) { $lockHandle.Dispose() }
  if (Test-Path -LiteralPath $lockPath -PathType Leaf) { Remove-Item -LiteralPath $lockPath -Force }
}

if (Test-Path -LiteralPath $backupPath) {
  Remove-Item -LiteralPath $backupPath -Recurse -Force
}
