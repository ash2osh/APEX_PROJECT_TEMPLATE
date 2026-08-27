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

Get-ChildItem -Path $TargetDir -Filter *.apx -Recurse | ForEach-Object {
  $path = $_.FullName
  $text = [System.IO.File]::ReadAllText($path) -replace "`r`n", "`n" -replace "`r", "`n"
  $text = $text.TrimEnd("`n") + "`n"
  [System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false))
}
