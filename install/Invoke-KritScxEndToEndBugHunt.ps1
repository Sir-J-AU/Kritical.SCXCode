<#
.SYNOPSIS
  Kritical SCX end-to-end installer, mux, Codex pack, and bughunt loop.

.DESCRIPTION
  One command to exercise the whole local Kritical.SCXCode stack without relying on memory:
    - inventory and installer status
    - Codex pack and kcodex status/heal
    - PowerShell and JavaScript syntax gates
    - offline regression self-test
    - optional live proxy, mux, and Lens bughunt checks

  The loop writes receipts under receipts/ and keeps going after failures so the final output is a
  complete defect list instead of the first crash.

.PARAMETER Mode
  Status: read-only inventory and status checks.
  Smoke: Status plus syntax gates and offline self-test.
  Heal: Smoke plus additive pack heal/install steps.
  Full: Heal plus live proxy, mux, and optional Lens bughunt.

.PARAMETER IncludeLens
  Run the SCX-offloaded Lens bughunt against TargetFile. Requires proxy + SQL store.

.PARAMETER SkipLive
  Skip proxy, live routing, mux, and Lens calls.

.EXAMPLE
  pwsh ./install/Invoke-KritScxEndToEndBugHunt.ps1 -Mode Smoke -SkipLive

.EXAMPLE
  pwsh ./install/Invoke-KritScxEndToEndBugHunt.ps1 -Mode Full -IncludeLens -TargetFile ./src/extension.ts
#>
[CmdletBinding()]
param(
  [ValidateSet('Status','Smoke','Heal','Full')][string]$Mode = 'Smoke',
  [switch]$IncludeLens,
  [switch]$SkipLive,
  [string]$TargetFile,
  [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
  [int]$MuxConcurrency = 4
)

$ErrorActionPreference = 'Continue'
$script:Pass = 0
$script:Fail = 0
$script:Warn = 0
$script:Findings = New-Object System.Collections.Generic.List[object]

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$receiptsDir = Join-Path $RepoRoot 'receipts'
$logDir = Join-Path $receiptsDir 'bughunt'
New-Item -ItemType Directory -Force $logDir | Out-Null
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')

function Add-Finding {
  param(
    [ValidateSet('PASS','FAIL','WARN','SKIP')][string]$Status,
    [string]$Name,
    [int]$ExitCode = 0,
    [string]$Log = '',
    [string]$Detail = ''
  )
  if ($Status -eq 'PASS') { $script:Pass++ }
  elseif ($Status -eq 'FAIL') { $script:Fail++ }
  elseif ($Status -eq 'WARN') { $script:Warn++ }
  $script:Findings.Add([pscustomobject]@{
    status = $Status
    name = $Name
    exit_code = $ExitCode
    log = $Log
    detail = $Detail
  }) | Out-Null
  $color = switch ($Status) {
    'PASS' { 'Green' }
    'FAIL' { 'Red' }
    'WARN' { 'Yellow' }
    default { 'DarkGray' }
  }
  Write-Host ("  {0,-4} {1}" -f $Status, $Name) -ForegroundColor $color
  if ($Detail) { Write-Host "       $Detail" -ForegroundColor DarkGray }
}

function Invoke-Step {
  param(
    [string]$Name,
    [string]$File,
    [string[]]$Arguments = @(),
    [switch]$AllowFail
  )
  if (-not (Test-Path -LiteralPath $File)) {
    Add-Finding -Status FAIL -Name $Name -Detail "missing: $File"
    return $false
  }
  $safeName = ($Name -replace '[^A-Za-z0-9_.-]', '_')
  $log = Join-Path $logDir "$stamp-$safeName.log"
  $output = & pwsh -NoProfile -ExecutionPolicy Bypass -File $File @Arguments 2>&1
  $code = if ($LASTEXITCODE -ne $null) { [int]$LASTEXITCODE } else { 0 }
  [System.IO.File]::WriteAllText($log, (($output | Out-String).TrimEnd() + [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
  if ($code -eq 0 -or $AllowFail) {
    Add-Finding -Status $(if ($code -eq 0) { 'PASS' } else { 'WARN' }) -Name $Name -ExitCode $code -Log $log
    return ($code -eq 0)
  }
  Add-Finding -Status FAIL -Name $Name -ExitCode $code -Log $log -Detail "see $log"
  return $false
}

function Test-ProxyHealth {
  try {
    (Invoke-WebRequest 'http://127.0.0.1:4180/health/liveliness' -UseBasicParsing -TimeoutSec 3).StatusCode -eq 200
  } catch {
    $false
  }
}

function Invoke-SyntaxGate {
  Write-Host "`n[syntax]" -ForegroundColor Cyan
  $psFiles = Get-ChildItem -LiteralPath $RepoRoot -Recurse -Filter *.ps1 -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\node_modules\\|\\\.git\\' }
  $badPs = @()
  foreach ($file in $psFiles) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    if ($errors) { $badPs += "$($file.FullName): $($errors[0].Message)" }
  }
  if ($badPs.Count) {
    $log = Join-Path $logDir "$stamp-powershell-parse-errors.log"
    [System.IO.File]::WriteAllLines($log, $badPs, [System.Text.UTF8Encoding]::new($false))
    Add-Finding -Status FAIL -Name "PowerShell parse gate ($($psFiles.Count) files)" -Log $log -Detail "see $log"
  } else {
    Add-Finding -Status PASS -Name "PowerShell parse gate ($($psFiles.Count) files)"
  }

  $node = Get-Command node -ErrorAction SilentlyContinue
  if (-not $node) {
    Add-Finding -Status WARN -Name 'JavaScript parse gate' -Detail 'node not found'
    return
  }
  $jsFiles = Get-ChildItem -LiteralPath $RepoRoot -Recurse -Include *.js,*.mjs -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\node_modules\\|\\out\\|\\\.git\\|\\tests\\emitted\\' }
  $badJs = @()
  foreach ($file in $jsFiles) {
    $out = & node --check $file.FullName 2>&1
    if ($LASTEXITCODE -ne 0) { $badJs += "$($file.FullName): $($out | Out-String)" }
  }
  if ($badJs.Count) {
    $log = Join-Path $logDir "$stamp-javascript-parse-errors.log"
    [System.IO.File]::WriteAllLines($log, $badJs, [System.Text.UTF8Encoding]::new($false))
    Add-Finding -Status FAIL -Name "JavaScript parse gate ($($jsFiles.Count) files)" -Log $log -Detail "see $log"
  } else {
    Add-Finding -Status PASS -Name "JavaScript parse gate ($($jsFiles.Count) files)"
  }
}

Write-Host "`n===== Kritical SCX end-to-end bughunt loop ($Mode) =====" -ForegroundColor Cyan
Write-Host "repo: $RepoRoot" -ForegroundColor DarkGray
Write-Host "receipts: $logDir" -ForegroundColor DarkGray

$install = Join-Path $RepoRoot 'install\Install-KriticalSCX.ps1'
$codexInstall = Join-Path $RepoRoot 'install\Install-KriticalSCXCodex.ps1'
$pack = Join-Path $RepoRoot 'codex-wrapper\pack\Apply-KriticalCodexPack.ps1'
$proxy = Join-Path $RepoRoot 'litellm\Manage-KritScxProxy.ps1'
$selfTest = Join-Path $RepoRoot 'tests\Invoke-KritScxSelfTest.ps1'
$envIsolationTest = Join-Path $RepoRoot 'tests\Test-KritScxProviderEnvIsolation.ps1'
$vsixPackageTest = Join-Path $RepoRoot 'tests\Test-KritScxVsixPackage.ps1'
$mux = Join-Path $RepoRoot 'mux\Invoke-KritScxMux.ps1'
$lens = Join-Path $RepoRoot 'lens\Invoke-KritLensBrainBugHunt.py'

Write-Host "`n[status]" -ForegroundColor Cyan
[void](Invoke-Step -Name 'whole-stack installer status' -File $install -Arguments @('-Mode','Status') -AllowFail)
[void](Invoke-Step -Name 'SCX Codex installer status' -File $codexInstall -Arguments @('-Mode','Status') -AllowFail)
[void](Invoke-Step -Name 'Codex pack status' -File $pack -Arguments @('-Mode','Status') -AllowFail)
[void](Invoke-Step -Name 'LiteLLM proxy status' -File $proxy -Arguments @('-Mode','Status') -AllowFail)

if ($Mode -in @('Smoke','Heal','Full')) {
  Invoke-SyntaxGate

  Write-Host "`n[self-test]" -ForegroundColor Cyan
  [void](Invoke-Step -Name 'provider env isolation' -File $envIsolationTest)
  [void](Invoke-Step -Name 'VSIX package integrity' -File $vsixPackageTest)
  $selfArgs = if ($SkipLive -or $Mode -ne 'Full') { @('-SkipLive') } else { @() }
  [void](Invoke-Step -Name 'regression self-test' -File $selfTest -Arguments $selfArgs -AllowFail)
}

if ($Mode -in @('Heal','Full')) {
  Write-Host "`n[heal]" -ForegroundColor Cyan
  [void](Invoke-Step -Name 'Codex pack heal' -File $pack -Arguments @('-Mode','Heal') -AllowFail)
  [void](Invoke-Step -Name 'SCX Codex installer heal' -File $codexInstall -Arguments @('-Mode','Heal','-Apply') -AllowFail)
}

if ($Mode -eq 'Full' -and -not $SkipLive) {
  Write-Host "`n[live]" -ForegroundColor Cyan
  if (-not (Test-ProxyHealth)) {
    [void](Invoke-Step -Name 'start LiteLLM proxy' -File $proxy -Arguments @('-Mode','Start') -AllowFail)
  }
  if (Test-ProxyHealth) {
    Add-Finding -Status PASS -Name 'LiteLLM proxy live health'
    $shards = @(
      (Join-Path $RepoRoot 'README.md'),
      (Join-Path $RepoRoot 'codex-wrapper\README.md'),
      (Join-Path $RepoRoot 'docs\ARCHITECTURE.md')
    ) | Where-Object { Test-Path -LiteralPath $_ }
    if ($shards.Count -ge 2) {
      $muxArgs = @('-Task','Summarise the SCX installer, Codex wrapper, and mux state; list likely defects.','-Shards') + @($shards) + @('-Concurrency',"$MuxConcurrency")
      [void](Invoke-Step -Name 'mux synthetic-context smoke' -File $mux -Arguments $muxArgs -AllowFail)
    } else {
      Add-Finding -Status WARN -Name 'mux synthetic-context smoke' -Detail 'not enough shard files found'
    }
  } else {
    Add-Finding -Status FAIL -Name 'LiteLLM proxy live health' -Detail 'proxy is not healthy on 127.0.0.1:4180'
  }
}

if ($Mode -eq 'Full' -and $IncludeLens -and -not $SkipLive) {
  Write-Host "`n[lens]" -ForegroundColor Cyan
  if (-not $TargetFile) { $TargetFile = Join-Path $RepoRoot 'src\extension.ts' }
  $targetPath = if ([System.IO.Path]::IsPathRooted($TargetFile)) { $TargetFile } else { Join-Path $RepoRoot $TargetFile }
  if ((Test-Path -LiteralPath $lens) -and (Test-Path -LiteralPath $targetPath)) {
    $log = Join-Path $logDir "$stamp-lens-bughunt.log"
    $output = & python $lens $targetPath 'DeepSeek-V3.1' "$MuxConcurrency" 2>&1
    $code = if ($LASTEXITCODE -ne $null) { [int]$LASTEXITCODE } else { 0 }
    [System.IO.File]::WriteAllText($log, (($output | Out-String).TrimEnd() + [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
    Add-Finding -Status $(if ($code -eq 0) { 'PASS' } else { 'FAIL' }) -Name "Lens bughunt: $targetPath" -ExitCode $code -Log $log -Detail $(if ($code) { "see $log" } else { '' })
  } else {
    Add-Finding -Status FAIL -Name 'Lens bughunt' -Detail "missing lens script or target: $targetPath"
  }
}

$receipt = Join-Path $receiptsDir "end-to-end-bughunt-$stamp.json"
[ordered]@{
  wave = '.5232'
  utc = $stamp
  mode = $Mode
  repo = $RepoRoot
  pass = $Pass
  fail = $Fail
  warn = $Warn
  skip_live = [bool]$SkipLive
  include_lens = [bool]$IncludeLens
  findings = $Findings
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $receipt -Encoding utf8

Write-Host "`n===== result: $Pass passed, $Warn warnings, $Fail failed =====" -ForegroundColor $(if ($Fail) { 'Red' } elseif ($Warn) { 'Yellow' } else { 'Green' })
Write-Host "receipt: $receipt" -ForegroundColor Cyan
exit $Fail
