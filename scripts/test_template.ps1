$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$testRoot = Join-Path $repoRoot "scratch/template-ps-$([Guid]::NewGuid().ToString('N'))"
$testRepo = Join-Path $testRoot "repo"

function Assert-True([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "FAIL: $Message" }
}

try {
  New-Item -ItemType Directory -Force -Path @(
    (Join-Path $testRepo "scripts"),
    (Join-Path $testRepo "database/mirror"),
    (Join-Path $testRepo "scratch/staged")
  ) | Out-Null
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot "replace_mirror.ps1") -Destination (Join-Path $testRepo "scripts/replace_mirror.ps1")
  [System.IO.File]::WriteAllText((Join-Path $testRepo "database/mirror/stale.txt"), "stale`n")
  [System.IO.File]::WriteAllText((Join-Path $testRepo "scratch/staged/new.txt"), "new`n")
  & git -C $testRepo init -q
  & git -C $testRepo add database/mirror/stale.txt
  & git -C $testRepo -c user.name=TemplateTest -c user.email=test@example.invalid commit -qm initial

  & (Join-Path $testRepo "scripts/replace_mirror.ps1") `
    -StagedDir (Join-Path $testRepo "scratch/staged") -Destination "database/mirror"
  Assert-True (Test-Path -LiteralPath (Join-Path $testRepo "database/mirror/new.txt")) "new mirror content was not installed"
  Assert-True (-not (Test-Path -LiteralPath (Join-Path $testRepo "database/mirror/stale.txt"))) "stale mirror content was retained"

  New-Item -ItemType Directory -Force -Path (Join-Path $testRepo "scratch/dotdot") | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $testRepo "scratch/dotdot/file.txt"), "content`n")
  $rejected = $false
  try {
    & (Join-Path $testRepo "scripts/replace_mirror.ps1") `
      -StagedDir (Join-Path $testRepo "scratch/dotdot") -Destination "apps/schema/.."
  } catch {
    $rejected = $true
  }
  Assert-True $rejected "dot-dot destination was accepted"

  $envFile = Join-Path $testRoot "project.env"
  $envText = @'
PROJECT_NAME=$(throw should-not-run)
DB_TARGET_SCHEMA=SAMPLE
APEX_APP_ID=100
APEX_APP_SLUG=sample-app
SQLCL_CONNECTION=dev1_SAMPLE
DB_ENVIRONMENT=development
DB_EXPECTED_USER=SAMPLE
DB_REQUIRED_ROLE=NONE
INSTALL_UC_APX=false
UC_APX_SKILLS_AGENT=universal
'@
  [System.IO.File]::WriteAllText($envFile, $envText)
  . (Join-Path $PSScriptRoot "load_env.ps1") -EnvFile $envFile
  Assert-True ($env:PROJECT_NAME -eq '$(throw should-not-run)') ".env literal value was changed or executed"

  $env:PROJECT_ENV_FILE = $envFile
  & (Join-Path $PSScriptRoot "check_db_target.ps1") -Operation read

  $mislabeledFile = Join-Path $testRoot "mislabeled.env"
  [System.IO.File]::WriteAllText($mislabeledFile, $envText.Replace("dev1_SAMPLE", "sample-prod1"))
  $env:PROJECT_ENV_FILE = $mislabeledFile
  $rejected = $false
  try {
    & (Join-Path $PSScriptRoot "check_db_target.ps1") -Operation read
  } catch {
    $rejected = $true
  }
  Assert-True $rejected "production-like connection was accepted as development"

  Write-Host "PASS: native PowerShell template checks"
} finally {
  Remove-Item Env:PROJECT_ENV_FILE -ErrorAction SilentlyContinue
  if (Test-Path -LiteralPath $testRoot) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
  }
}
