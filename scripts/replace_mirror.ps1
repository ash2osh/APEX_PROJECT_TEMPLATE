# Replace one generated mirror with a completed staging directory.
param(
  [Parameter(Mandatory = $true)][string]$StagedDir,
  [Parameter(Mandatory = $true)][string]$Destination
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
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

$dirty = @(git -C $repoRoot status --porcelain --untracked-files=all -- $destinationPath)
$gitExitCode = $LASTEXITCODE
if ($gitExitCode -ne 0) {
  throw "unable to inspect Git status for mirror: $relativeDestination"
}
if (-not [string]::IsNullOrWhiteSpace(($dirty -join "`n"))) {
  throw "refusing to replace dirty mirror: $Destination"
}

$destinationParent = Split-Path -Parent $destinationPath
New-Item -ItemType Directory -Force -Path $destinationParent | Out-Null
$resolvedDestinationParent = (Resolve-Path -LiteralPath $destinationParent).Path
$destinationPath = Join-Path $resolvedDestinationParent (Split-Path -Leaf $destinationPath)
if (-not $destinationPath.StartsWith($repoRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "resolved destination escaped the repository: $destinationPath"
}
$canonicalRelativeDestination = $destinationPath.Substring($repoRoot.Length).TrimStart([char[]]@('/', '\\'))
$canonicalDestinationParts = $canonicalRelativeDestination -split '[\\/]'
$canonicalApproved = ($canonicalDestinationParts[0] -eq "database" -and $canonicalDestinationParts.Count -eq 2) -or
  ($canonicalDestinationParts[0] -eq "apps" -and $canonicalDestinationParts.Count -eq 3)
if (-not $canonicalApproved) {
  throw "resolved destination is not an approved generated mirror: $canonicalRelativeDestination"
}
$mirrorName = Split-Path -Leaf $destinationPath
$backupPath = Join-Path $scratchPath (".mirror-backup.{0}.{1}" -f $mirrorName, $PID)
if (Test-Path -LiteralPath $backupPath) {
  throw "temporary replacement path already exists: $backupPath"
}

$hadOldMirror = Test-Path -LiteralPath $destinationPath
try {
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
}

if (Test-Path -LiteralPath $backupPath) {
  Remove-Item -LiteralPath $backupPath -Recurse -Force
}
