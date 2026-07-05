<#
.SYNOPSIS
  Verify the packaged Kritical.SCXCode VSIX matches the source package and contains the runtime files.

.DESCRIPTION
  Read-only package sanity gate for the sideloaded extension:
    - latest SCXCode-*.vsix exists
    - embedded extension/package.json parses
    - extension id is kritical.scxcode
    - VSIX version matches src/package.json
    - out/extension.js and media assets are present
    - package does not contain a Kritical.SCXClaude.Code extension id

  Exit code = number of failures.
#>
[CmdletBinding()]
param(
  [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = 'Continue'
$fail = 0
$pass = 0
function T([string]$Name, [scriptblock]$Check) {
  try {
    if (& $Check) {
      Write-Host "  PASS  $Name" -ForegroundColor Green
      $script:pass++
    } else {
      Write-Host "  FAIL  $Name" -ForegroundColor Red
      $script:fail++
    }
  } catch {
    Write-Host "  FAIL  $Name ($($_.Exception.Message))" -ForegroundColor Red
    $script:fail++
  }
}

Write-Host "`n===== Kritical SCXCode VSIX Package Test =====" -ForegroundColor Cyan
$srcDir = Join-Path $RepoRoot 'src'
$sourcePackagePath = Join-Path $srcDir 'package.json'
$sourcePackage = Get-Content -Raw -LiteralPath $sourcePackagePath | ConvertFrom-Json
$latestVsix = Get-ChildItem -LiteralPath $srcDir -Filter 'SCXCode-*.vsix' -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

T 'latest VSIX exists' { [bool]$latestVsix }
if (-not $latestVsix) {
  Write-Host "`n===== $pass passed, $fail failed =====" -ForegroundColor Red
  exit $fail
}

Write-Host "  VSIX  $($latestVsix.FullName)" -ForegroundColor DarkGray
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("krit-scx-vsix-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
  $zip = Join-Path $tmp 'package.zip'
  Copy-Item -LiteralPath $latestVsix.FullName -Destination $zip
  Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
  $embeddedPackagePath = Join-Path $tmp 'extension\package.json'
  $embeddedPackage = if (Test-Path $embeddedPackagePath) { Get-Content -Raw -LiteralPath $embeddedPackagePath | ConvertFrom-Json } else { $null }

  T 'embedded package.json exists and parses' { [bool]$embeddedPackage }
  T 'extension id is kritical.scxcode' { $embeddedPackage.publisher -eq 'kritical' -and $embeddedPackage.name -eq 'SCXCode' }
  T 'VSIX version matches source package.json' { $embeddedPackage.version -eq $sourcePackage.version }
  T 'runtime bundle out/extension.js present' { Test-Path (Join-Path $tmp 'extension\out\extension.js') }
  T 'Kritical icon assets present' {
    (Test-Path (Join-Path $tmp 'extension\media\kritical-symbol.png')) -and
    (Test-Path (Join-Path $tmp 'extension\media\kritical-horizontal.png'))
  }
  T 'commands include SCX Codex launcher' {
    @($embeddedPackage.contributes.commands | Where-Object command -eq 'kritical.scxcode.scxCodex').Count -eq 1
  }
  T 'no packaged Kritical.SCXClaude.Code extension id' {
    $raw = Get-Content -Raw -LiteralPath $embeddedPackagePath
    $raw -notmatch 'Kritical\.SCXClaude\.Code|kritical\.scxclaude'
  }
} finally {
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n===== $pass passed, $fail failed =====" -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
exit $fail
