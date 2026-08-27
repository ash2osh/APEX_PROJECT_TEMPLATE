# Normalize *.apx files under the given directory to LF line endings with
# exactly one trailing newline, and revert any file whose only change vs the
# last commit is whitespace/line-ending noise.
param(
  [Parameter(Mandatory = $true)][string]$TargetDir
)
$ErrorActionPreference = "Stop"
$repoRoot = Join-Path $PSScriptRoot ".."

if (Test-Path $TargetDir) {
  Get-ChildItem -Path $TargetDir -Filter *.apx -Recurse | ForEach-Object {
    $path = $_.FullName
    $text = [System.IO.File]::ReadAllText($path) -replace "`r`n", "`n"
    $text = $text.TrimEnd("`n") + "`n"
    [System.IO.File]::WriteAllText($path, $text)

    Push-Location $repoRoot
    try {
      $realDiff = git diff --ignore-space-at-eol --ignore-blank-lines -- $path
      $anyDiff = git diff -- $path
      if ([string]::IsNullOrWhiteSpace($realDiff) -and -not [string]::IsNullOrWhiteSpace($anyDiff)) {
        git checkout -- $path
      }
    } finally {
      Pop-Location
    }
  }
}
