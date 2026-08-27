# Export the {{APP_ID}} APEX application to apps/{{SCHEMA}}/{{APP_SLUG}}/ (APEXLANG format).
# Requires a saved SQLcl connection named {{CONN_NAME}}.
$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$scratchPath = Join-Path $repoRoot "scratch"
New-Item -ItemType Directory -Force -Path $scratchPath | Out-Null
$stagingPath = Join-Path $scratchPath ("apex-export-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path (Join-Path $stagingPath "apps/{{SCHEMA}}/{{APP_SLUG}}") | Out-Null

try {
  $locationPushed = $false
  Push-Location $stagingPath
  $locationPushed = $true
  & sql -S -noupdates -name "{{CONN_NAME}}" "@$(Join-Path $repoRoot 'scripts/export_apps.sql')"
  if ($LASTEXITCODE -ne 0) { throw "SQLcl application export failed with exit code $LASTEXITCODE" }
  $appStage = Join-Path $stagingPath "apps/{{SCHEMA}}/{{APP_SLUG}}"
  if (-not (Test-Path -LiteralPath $appStage -PathType Container)) { throw "APEX export did not create $appStage" }
  & (Join-Path $PSScriptRoot "normalize_apx.ps1") $appStage
  & (Join-Path $PSScriptRoot "replace_mirror.ps1") $appStage "apps/{{SCHEMA}}/{{APP_SLUG}}"
} finally {
  if ($locationPushed) { Pop-Location }
  if (Test-Path -LiteralPath $stagingPath) {
    Remove-Item -LiteralPath $stagingPath -Recurse -Force -ErrorAction Stop
  }
}
