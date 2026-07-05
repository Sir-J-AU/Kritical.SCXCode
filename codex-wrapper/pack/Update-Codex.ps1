<#
.SYNOPSIS
  Pull upstream Codex source and rebuild Kritical.SCXCodex.exe.

.DESCRIPTION
  This does not install or modify stock codex. It updates the upstream source clone,
  applies the SCX branding overlay in a disposable worktree, recompiles, packages,
  and verifies Kritical.SCXCodex.exe.
#>
[CmdletBinding()]
param(
  [switch]$DryRun,
  [string]$Manifest = "$PSScriptRoot\pack-manifest.json"
)

$ErrorActionPreference = 'Stop'
$manifestData = Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json
$clone = $manifestData.source_clone
$pack = Join-Path $PSScriptRoot 'Apply-KriticalCodexPack.ps1'

Write-Host "=== Update Kritical.SCXCodex from upstream ($(if($DryRun){'DRY RUN'}else{'LIVE'})) ===" -ForegroundColor Cyan
Write-Host "source clone : $clone"
Write-Host "entrypoint   : $($manifestData.compiled_entrypoint)"
Write-Host "stock codex  : untouched"
Write-Host "provider auth: native OpenAI/Anthropic/Codex settings unread + unchanged"

if ($DryRun) {
  Write-Host "`n[DRY RUN] would run:" -ForegroundColor Magenta
  Write-Host "  git -C `"$clone`" pull --ff-only"
  Write-Host "  Apply-KriticalCodexPack.ps1 -Mode Install"
  Write-Host "  verify compiled branding inside Kritical.SCXCodex.exe"
  return
}

if (-not (Test-Path -LiteralPath (Join-Path $clone '.git'))) {
  throw "Upstream Codex source clone is missing: $clone"
}

Write-Host "`n[1/3] pulling upstream source clone ..." -ForegroundColor Yellow
git -C $clone pull --ff-only
if ($LASTEXITCODE -ne 0) { throw "git pull failed for $clone" }

Write-Host "[2/3] rebuilding branded package ..." -ForegroundColor Yellow
& $pack -Mode Install -Manifest $Manifest

Write-Host "[3/3] verifying branded package ..." -ForegroundColor Yellow
& (Join-Path $PSScriptRoot 'Build-KriticalSCXCodex.ps1') -Mode Verify -Manifest $Manifest
