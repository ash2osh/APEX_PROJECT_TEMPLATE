#Requires -Version 5.1
$ErrorActionPreference = "Stop"
$sourceRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$testRoot = Join-Path $sourceRoot "scratch/orchestration-ps-$([Guid]::NewGuid().ToString('N'))"
$testRepo = Join-Path $testRoot "repo"
$testScripts = Join-Path $testRepo "scripts"
$envFile = Join-Path $testRoot "project.env"
$sqlclLog = Join-Path $testRoot "sqlcl.log"

function Assert-Orchestration([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "FAIL: $Message" }
}

try {
  New-Item -ItemType Directory -Force -Path $testScripts | Out-Null
  foreach ($fileName in @(
    "backup_db.ps1", "backup_db.sql", "check_db_target.ps1", "export_apps.ps1",
    "export_apps.sql", "load_env.ps1", "normalize_apx.ps1", "replace_mirror.ps1",
    "verify_db_access.sql"
  )) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $fileName) -Destination $testScripts
  }

  # Replace only the SQLcl launcher in the disposable fixture. The wrappers
  # otherwise run unchanged, including staging, completeness, and replacement.
  $fakeInvoker = @'
function Invoke-Sqlcl {
  param(
    [Parameter(Mandatory = $true)][string[]] $Arguments,
    [Parameter(Mandatory = $true)][string] $WorkingDirectory,
    [Parameter(Mandatory = $true)][string] $StdInFile
  )
  $scriptArgument = $Arguments[4]
  $schema = $Arguments[5]
  if ($scriptArgument -like '*backup_db.sql') {
    $scope = $Arguments[6]
    $prefixes = $Arguments[9]
    if (-not (Test-Path -LiteralPath (Join-Path $env:FAKE_REPO_ROOT 'database/DEMO/old.txt'))) {
      throw 'a database mirror was replaced before both SQLcl passes completed'
    }
    [System.IO.File]::AppendAllText($env:FAKE_SQLCL_LOG, "backup:${scope}:$prefixes`n")
    $databaseRoot = Join-Path $WorkingDirectory "database/$schema"
    New-Item -ItemType Directory -Force -Path @(
      (Join-Path $databaseRoot 'tables'), (Join-Path $databaseRoot 'views')
    ) | Out-Null
    if ($scope -eq 'tables') {
      [System.IO.File]::WriteAllText((Join-Path $databaseRoot 'tables/TAB_ONE.sql'), "table one`n")
      [System.IO.File]::WriteAllText((Join-Path $databaseRoot 'tables/COMMON_TWO.sql'), "table two`n")
      [System.IO.File]::WriteAllText((Join-Path $databaseRoot 'manifest-tables.txt'), "TABLE=2`r`n")
    } else {
      [System.IO.File]::WriteAllText((Join-Path $databaseRoot 'views/CODE_ONE.sql'), "view one`n")
      [System.IO.File]::WriteAllText((Join-Path $databaseRoot 'manifest-code.txt'), "VIEW=1`r`nPACKAGE=0`r`nPACKAGE BODY=0`r`nPROCEDURE=0`r`nFUNCTION=0`r`nTRIGGER=0`r`n")
    }
    return 0
  }

  $appId = $Arguments[6]
  [System.IO.File]::AppendAllText($env:FAKE_SQLCL_LOG, "export:$appId`n")
  if ($env:FAKE_FAIL_APP_ID -eq $appId) { return 42 }
  $appRoot = Join-Path $WorkingDirectory "apps/$schema/alias-$appId"
  New-Item -ItemType Directory -Force -Path @(
    (Join-Path $appRoot 'pages'), (Join-Path $appRoot '.apex')
  ) | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $appRoot 'application.apx'), "prompt application $appId`r`n")
  [System.IO.File]::WriteAllText((Join-Path $appRoot 'pages/p00001.apx'), "prompt page $appId`r`n")
  [System.IO.File]::WriteAllText((Join-Path $appRoot '.apex/apexlang.json'), "{`"format`":`"APEXLANG`"}`n")
  return 0
}
'@
  [System.IO.File]::WriteAllText((Join-Path $testScripts "invoke_sqlcl.ps1"), $fakeInvoker)

  $envText = @'
PROJECT_NAME=orchestration-test
DB_ENVIRONMENT=development
APEX_APP_ID=100,101
TABLES_SCHEMA=DEMO
TABLES_PREFIXES=TAB_,COMMON_
TABLES_SQLCL_CONNECTION=dev_DEMO
TABLES_EXPECTED_USER=DEMO
CODE_SCHEMA=DEMO
CODE_PREFIXES=CODE_,COMMON_
CODE_SQLCL_CONNECTION=dev_DEMO
CODE_EXPECTED_USER=DEMO
APEX_PARSING_SCHEMA=DEMO
APEX_SQLCL_CONNECTION=dev_DEMO
APEX_EXPECTED_USER=DEMO
INSTALL_UC_APX=false
UC_APX_SKILLS_AGENT=universal
'@
  [System.IO.File]::WriteAllText($envFile, $envText)
  $env:PROJECT_ENV_FILE = $envFile
  $env:FAKE_REPO_ROOT = $testRepo
  $env:FAKE_SQLCL_LOG = $sqlclLog

  New-Item -ItemType Directory -Force -Path (Join-Path $testRepo "database/DEMO") | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $testRepo "database/DEMO/old.txt"), "old`n")
  & git -C $testRepo init -q
  & git -C $testRepo add -A
  & git -C $testRepo -c user.name=TemplateTest -c user.email=test@example.invalid commit -qm seed

  & (Join-Path $testScripts "backup_db.ps1")
  $backupLog = @(Get-Content -LiteralPath $sqlclLog)
  Assert-Orchestration ($backupLog.Count -eq 2) "PowerShell backup did not make exactly two SQLcl calls"
  Assert-Orchestration ($backupLog[0] -eq "backup:tables:TAB_,COMMON_") "PowerShell backup did not pass table prefixes"
  Assert-Orchestration ($backupLog[1] -eq "backup:code:CODE_,COMMON_") "PowerShell backup did not pass code prefixes"
  Assert-Orchestration (Test-Path -LiteralPath (Join-Path $testRepo "database/DEMO/tables/TAB_ONE.sql")) "PowerShell table mirror was not installed"
  Assert-Orchestration (Test-Path -LiteralPath (Join-Path $testRepo "database/DEMO/views/CODE_ONE.sql")) "PowerShell code mirror was not installed"

  & git -C $testRepo add database
  & git -C $testRepo -c user.name=TemplateTest -c user.email=test@example.invalid commit -qm backup
  foreach ($appId in @("100", "101")) {
    $appPath = Join-Path $testRepo "apps/DEMO/$appId"
    New-Item -ItemType Directory -Force -Path $appPath | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $appPath "old.txt"), "old $appId`n")
  }
  & git -C $testRepo add apps
  & git -C $testRepo -c user.name=TemplateTest -c user.email=test@example.invalid commit -qm apps
  [System.IO.File]::WriteAllText($sqlclLog, "")

  & (Join-Path $testScripts "export_apps.ps1")
  $exportLog = @(Get-Content -LiteralPath $sqlclLog)
  Assert-Orchestration (($exportLog -join ',') -eq "export:100,export:101") "PowerShell export did not call both application ids"
  foreach ($appId in @("100", "101")) {
    $appPath = Join-Path $testRepo "apps/DEMO/$appId"
    Assert-Orchestration (Test-Path -LiteralPath (Join-Path $appPath "application.apx")) "PowerShell app $appId mirror was not installed"
    $bytes = [System.IO.File]::ReadAllBytes((Join-Path $appPath "application.apx"))
    Assert-Orchestration (-not ($bytes -contains 13)) "PowerShell app $appId retained CR line endings"
  }

  & git -C $testRepo add apps
  & git -C $testRepo -c user.name=TemplateTest -c user.email=test@example.invalid commit -qm export
  $env:FAKE_FAIL_APP_ID = "101"
  $rejected = $false
  try {
    & (Join-Path $testScripts "export_apps.ps1")
  } catch {
    $rejected = $true
  }
  Assert-Orchestration $rejected "PowerShell export accepted failure of the second application"
  $dirtyApps = @(git -C $testRepo status --porcelain -- apps)
  Assert-Orchestration ([string]::IsNullOrWhiteSpace(($dirtyApps -join "`n"))) "PowerShell second-app failure changed existing mirrors"

  Write-Host "PASS: native PowerShell orchestration checks"
} finally {
  Remove-Item Env:PROJECT_ENV_FILE, Env:FAKE_REPO_ROOT, Env:FAKE_SQLCL_LOG,
    Env:FAKE_FAIL_APP_ID -ErrorAction SilentlyContinue
  if (Test-Path -LiteralPath $testRoot) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
  }
}
