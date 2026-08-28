#Requires -Version 5.1
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

  $baseEnvFile = Join-Path $testRoot "project.env"
  $envText = @'
PROJECT_NAME=$(throw should-not-run)
DB_ENVIRONMENT=development
APEX_APP_ID=100,200
TABLES_SCHEMA=SAMPLE_DATA
TABLES_PREFIXES=SAMPLE_,COMMON_
TABLES_SQLCL_CONNECTION=dev1_SAMPLE_DATA
TABLES_EXPECTED_USER=SAMPLE_DATA
CODE_SCHEMA=SAMPLE_CODE
CODE_PREFIXES=SAMPLE_,COMMON_
CODE_SQLCL_CONNECTION=dev1_SAMPLE_CODE
CODE_EXPECTED_USER=SAMPLE_CODE
APEX_PARSING_SCHEMA=SAMPLE_APEX
APEX_SQLCL_CONNECTION=dev1_SAMPLE_APEX
APEX_EXPECTED_USER=SAMPLE_APEX
INSTALL_UC_APX=false
UC_APX_SKILLS_AGENT=universal
'@
  [System.IO.File]::WriteAllText($baseEnvFile, $envText)
  function Get-Item {
    param([string]$LiteralPath)
    if ($LiteralPath.StartsWith("Env:")) {
      throw "simulated Windows PowerShell environment-provider collision"
    }
    Microsoft.PowerShell.Management\Get-Item -LiteralPath $LiteralPath
  }
  try {
    . (Join-Path $PSScriptRoot "load_env.ps1") -EnvFile $baseEnvFile
  } finally {
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath Function:Get-Item
  }
  Assert-True ($env:PROJECT_NAME -eq '$(throw should-not-run)') ".env literal value was changed or executed"

  Assert-True ($env:APEX_APP_ID -eq "100,200") "PowerShell loader changed the application id list"
  Assert-True ($env:TABLES_PREFIXES -eq "SAMPLE_,COMMON_") "PowerShell loader changed the table prefix list"

  $missingPrefixFile = Join-Path $testRoot "missing-prefix.env"
  $env:CODE_PREFIXES = "INHERITED_"
  [System.IO.File]::WriteAllText($missingPrefixFile, $envText.Replace("CODE_PREFIXES=SAMPLE_,COMMON_`n", ""))
  $rejected = $false
  try {
    . (Join-Path $PSScriptRoot "load_env.ps1") -EnvFile $missingPrefixFile
  } catch {
    $rejected = $true
  }
  Assert-True $rejected "environment loader accepted an inherited value for a missing prefix setting"

  function Assert-EnvTextRejected([string]$Text, [string]$Message) {
    $invalidFile = Join-Path $testRoot "invalid-$([Guid]::NewGuid().ToString('N')).env"
    [System.IO.File]::WriteAllText($invalidFile, $Text)
    $wasRejected = $false
    try {
      . (Join-Path $PSScriptRoot "load_env.ps1") -EnvFile $invalidFile
    } catch {
      $wasRejected = $true
    }
    Assert-True $wasRejected $Message
  }

  $starText = $envText.Replace("TABLES_PREFIXES=SAMPLE_,COMMON_", "TABLES_PREFIXES=*").Replace(
    "CODE_PREFIXES=SAMPLE_,COMMON_", "CODE_PREFIXES=*")
  [System.IO.File]::WriteAllText((Join-Path $testRoot "star-prefix.env"), $starText)
  . (Join-Path $PSScriptRoot "load_env.ps1") -EnvFile (Join-Path $testRoot "star-prefix.env")

  Assert-EnvTextRejected ($envText.Replace("APEX_APP_ID=100,200", "APEX_APP_ID=100, 200")) "PowerShell loader accepted whitespace in APEX_APP_ID"
  Assert-EnvTextRejected ($envText.Replace("APEX_APP_ID=100,200", "APEX_APP_ID=100,100")) "PowerShell loader accepted duplicate APEX application ids"
  Assert-EnvTextRejected ($envText.Replace("APEX_APP_ID=100,200", "APEX_APP_ID=100,")) "PowerShell loader accepted an empty APEX application id"
  Assert-EnvTextRejected ($envText.Replace("APEX_APP_ID=100,200", "APEX_APP_ID=0")) "PowerShell loader accepted a non-positive APEX application id"
  Assert-EnvTextRejected ($envText.Replace('PROJECT_NAME=$(throw should-not-run)', 'project_name=$(throw should-not-run)')) "PowerShell loader accepted a lowercase setting name"
  Assert-EnvTextRejected ($envText.Replace("TABLES_SCHEMA=SAMPLE_DATA", "TABLES_SCHEMA=sample_data")) "PowerShell loader accepted a lowercase Oracle identifier"
  Assert-EnvTextRejected ($envText.Replace("TABLES_PREFIXES=SAMPLE_,COMMON_", "TABLES_PREFIXES=sample_")) "PowerShell loader accepted a lowercase table prefix"
  Assert-EnvTextRejected ($envText.Replace("TABLES_PREFIXES=SAMPLE_,COMMON_", "TABLES_PREFIXES=SAMPLE_, SAMPLE2_")) "PowerShell loader accepted whitespace in table prefixes"
  Assert-EnvTextRejected ($envText.Replace("TABLES_PREFIXES=SAMPLE_,COMMON_", "TABLES_PREFIXES=SAMPLE_,SAMPLE_")) "PowerShell loader accepted duplicate table prefixes"
  Assert-EnvTextRejected ($envText.Replace("CODE_PREFIXES=SAMPLE_,COMMON_", "CODE_PREFIXES=*,SAMPLE_")) "PowerShell loader accepted a mixed star prefix list"
  Assert-EnvTextRejected ($envText.Replace("CODE_PREFIXES=SAMPLE_,COMMON_", "CODE_PREFIXES=SAMPLE_,")) "PowerShell loader accepted an empty code prefix"
  foreach ($removedRole in @("TABLES_REQUIRED_ROLE", "CODE_REQUIRED_ROLE", "APEX_REQUIRED_ROLE")) {
    Assert-EnvTextRejected ($envText + "`n$removedRole=NONE`n") "PowerShell loader accepted removed role setting $removedRole"
  }

  $examplePath = Join-Path $repoRoot ".env.example"
  $exampleLines = [System.IO.File]::ReadAllLines($examplePath)
  $expectedKeys = @(
    "PROJECT_NAME", "DB_ENVIRONMENT", "APEX_APP_ID",
    "TABLES_SCHEMA", "TABLES_PREFIXES", "TABLES_SQLCL_CONNECTION", "TABLES_EXPECTED_USER",
    "CODE_SCHEMA", "CODE_PREFIXES", "CODE_SQLCL_CONNECTION", "CODE_EXPECTED_USER",
    "APEX_PARSING_SCHEMA", "APEX_SQLCL_CONNECTION", "APEX_EXPECTED_USER",
    "INSTALL_UC_APX", "UC_APX_SKILLS_AGENT"
  )
  $actualKeys = @()
  for ($index = 0; $index -lt $exampleLines.Count; $index++) {
    if ($exampleLines[$index] -match '^([A-Z][A-Z0-9_]*)=') {
      $key = $Matches[1]
      $actualKeys += $key
      Assert-True ($index -ge 2 -and $exampleLines[$index - 2].StartsWith("# Purpose:") -and
        $exampleLines[$index - 1].StartsWith("# Example")) "$key lacks immediate Purpose and Example comments"
    }
  }
  Assert-True (($actualKeys -join ',') -eq ($expectedKeys -join ',')) ".env.example keys or order differ from the 16-key contract"
  . (Join-Path $PSScriptRoot "load_env.ps1") -EnvFile $examplePath

  $initializeSkill = [System.IO.File]::ReadAllText((Join-Path $repoRoot ".agents/skills/initialize-project/SKILL.md"))
  Assert-True ($initializeSkill -match 'TABLES_PREFIXES=<prefix-csv-or-\*>') "initialize-project does not collect table prefixes"
  Assert-True ($initializeSkill -match 'CODE_PREFIXES=<prefix-csv-or-\*>') "initialize-project does not collect code prefixes"
  Assert-True ($initializeSkill -match 'APEX_APP_ID=<positive-id-csv>') "initialize-project does not document multiple app ids"
  Assert-True (-not ($initializeSkill -match '_REQUIRED_ROLE=<role-or-NONE>')) "initialize-project still writes removed role settings"
  Assert-True ($initializeSkill -match 'obsolete unsupported settings') "initialize-project does not flag removed role settings as unsupported"

  $legacyFile = Join-Path $testRoot "legacy.env"
  [System.IO.File]::WriteAllText($legacyFile, $envText + "`nDB_TARGET_SCHEMA=LEGACY`n")
  $rejected = $false
  try {
    . (Join-Path $PSScriptRoot "load_env.ps1") -EnvFile $legacyFile
  } catch {
    $rejected = $true
  }
  Assert-True $rejected "environment loader accepted a legacy single-profile setting"

  $env:PROJECT_ENV_FILE = $baseEnvFile
  foreach ($target in @("tables", "code", "apex")) {
    & (Join-Path $PSScriptRoot "check_db_target.ps1") -Operation read -Target $target
  }

  $sameProfileFile = Join-Path $testRoot "same-profile.env"
  $sameProfileText = $envText.Replace("SAMPLE_DATA", "UNIFIED").Replace(
    "SAMPLE_CODE", "UNIFIED").Replace("SAMPLE_APEX", "UNIFIED")
  [System.IO.File]::WriteAllText($sameProfileFile, $sameProfileText)
  $env:PROJECT_ENV_FILE = $sameProfileFile
  foreach ($target in @("tables", "code", "apex")) {
    & (Join-Path $PSScriptRoot "check_db_target.ps1") -Operation read -Target $target
  }

  $mislabeledFile = Join-Path $testRoot "mislabeled.env"
  [System.IO.File]::WriteAllText($mislabeledFile, $envText.Replace("dev1_SAMPLE_CODE", "sample-prod1"))
  $env:PROJECT_ENV_FILE = $mislabeledFile
  & (Join-Path $PSScriptRoot "check_db_target.ps1") -Operation read -Target tables
  $rejected = $false
  try {
    & (Join-Path $PSScriptRoot "check_db_target.ps1") -Operation read -Target code
  } catch {
    $rejected = $true
  }
  Assert-True $rejected "production-like connection was accepted as development"

  $productionFile = Join-Path $testRoot "production.env"
  $productionText = $envText.Replace("DB_ENVIRONMENT=development", "DB_ENVIRONMENT=production").Replace(
    "TABLES_SQLCL_CONNECTION=dev1_SAMPLE_DATA", "TABLES_SQLCL_CONNECTION=primary-prod-SAMPLE_DATA").Replace(
    "TABLES_EXPECTED_USER=SAMPLE_DATA", "TABLES_EXPECTED_USER=SAMPLE_DATA_AGENT_RO")
  [System.IO.File]::WriteAllText($productionFile, $productionText)
  $env:PROJECT_ENV_FILE = $productionFile
  & (Join-Path $PSScriptRoot "check_db_target.ps1") -Operation read -Target tables
  $rejected = $false
  try {
    & (Join-Path $PSScriptRoot "check_db_target.ps1") -Operation write -Target tables
  } catch {
    $rejected = $true
  }
  Assert-True $rejected "production write operation was accepted"

  # Production is read-only by instruction, not by privilege audit. A role-less
  # owner login is accepted for reads, refused for writes, and told the rule.
  $productionOwnerFile = Join-Path $testRoot "production-owner.env"
  $productionOwnerText = $envText.Replace("DB_ENVIRONMENT=development", "DB_ENVIRONMENT=production").Replace(
    "CODE_SQLCL_CONNECTION=dev1_SAMPLE_CODE", "CODE_SQLCL_CONNECTION=primary-prod-SAMPLE_CODE")
  [System.IO.File]::WriteAllText($productionOwnerFile, $productionOwnerText)
  $env:PROJECT_ENV_FILE = $productionOwnerFile
  $notice = (& (Join-Path $PSScriptRoot "check_db_target.ps1") -Operation read -Target code) 3>&1 | Out-String
  Assert-True ($notice -match "SELECT statements only") "production read did not print the SELECT-only instruction"
  Assert-True ($notice -match "Do NOT run INSERT") "production notice does not name DML"
  Assert-True ($notice -match "Do NOT run CREATE") "production notice does not name DDL"
  $rejected = $false
  try {
    & (Join-Path $PSScriptRoot "check_db_target.ps1") -Operation write -Target code
  } catch {
    $rejected = $true
  }
  Assert-True $rejected "production write operation was accepted"

  $verifySql = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "verify_db_access.sql"))
  $exportSql = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "export_apps.sql"))
  Assert-True ($exportSql -match '(?m)^SET VERIFY OFF') "APEX export exposes SQLcl substitution before/after blocks"
  Assert-True ($verifySql -match "SELECT statements only") "post-connect production instruction is missing"
  Assert-True (-not ($verifySql -match "session_privs|session_roles|user_tab_privs_recd|role_tab_privs")) `
    "verify_db_access.sql still audits privileges"
  Assert-True (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot "audit_production_access.sql"))) `
    "the removed privilege audit script is back"

  $legacySlugFile = Join-Path $testRoot "legacy-slug.env"
  [System.IO.File]::WriteAllText($legacySlugFile, $envText + "`nAPEX_APP_SLUG=sample-app`n")
  $rejected = $false
  try {
    . (Join-Path $PSScriptRoot "load_env.ps1") -EnvFile $legacySlugFile
  } catch {
    $rejected = $true
  }
  Assert-True $rejected "environment loader accepted the legacy APEX_APP_SLUG setting"

  & (Join-Path $PSScriptRoot "test_orchestration.ps1")

  Write-Host "PASS: native PowerShell template checks"
} finally {
  Remove-Item Env:PROJECT_ENV_FILE -ErrorAction SilentlyContinue
  if (Test-Path -LiteralPath $testRoot) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
  }
}
