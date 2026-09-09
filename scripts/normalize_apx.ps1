#Requires -Version 5.1
# Normalize *.apx files under the given directory to LF line endings with
# exactly one trailing newline. This script only changes the files in the
# supplied directory and never consults or modifies Git.
param(
  [Parameter(Mandatory = $true)][string]$TargetDir
)
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $TargetDir -PathType Container)) {
  throw "directory does not exist: $TargetDir"
}

# -LiteralPath, because a clone under a directory containing [ or ] must work.
Get-ChildItem -LiteralPath $TargetDir -Filter *.apx -Recurse | ForEach-Object {
  $path = $_.FullName
  # perl -pi is byte-oriented and preserves a BOM. Detect and re-emit it so the
  # two normalizers produce identical bytes for identical input.
  $bytes = [System.IO.File]::ReadAllBytes($path)
  $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
  $text = [System.IO.File]::ReadAllText($path) -replace "`r`n", "`n" -replace "`r", "`n"
  $text = $text.TrimEnd("`n") + "`n"
  [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($hasBom)))
}
