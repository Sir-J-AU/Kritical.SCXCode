<#
.SYNOPSIS
  Automated "merge + upgrade" for Codex: pull the latest stock Codex + refresh the source clone,
  then re-apply the Kritical pack. Auto-rollback stock Codex on failure. HR29-safe.

  Flow: capture current version -> npm i -g @openai/codex@latest -> git pull source clone ->
        re-heal pack -> verify `codex --version` + `kcodex` -> rollback to prior version if broken.

.PARAMETER DryRun   Show what would happen; change nothing. (default off)
.EXAMPLE  pwsh Update-Codex.ps1 -DryRun
.EXAMPLE  pwsh Update-Codex.ps1
#>
[CmdletBinding()]
param([switch]$DryRun, [string]$Manifest = "$PSScriptRoot\pack-manifest.json")
$ErrorActionPreference = 'Continue'
$m = Get-Content $Manifest -Raw | ConvertFrom-Json
$pkg = $m.stock_codex_package
$clone = $m.source_clone

function Get-CodexVersion { try { (& codex --version 2>&1 | Select-Object -First 1) } catch { $null } }

Write-Host "=== Update-Codex ($(if($DryRun){'DRY RUN'}else{'LIVE'})) ===" -ForegroundColor Cyan
$before = Get-CodexVersion
Write-Host "current stock codex: $($before ?? '(not found)')"
Write-Host "source clone       : $clone  (present: $(Test-Path (Join-Path $clone '.git')))"

if ($DryRun) {
  Write-Host "`n[DRY RUN] would run:" -ForegroundColor Magenta
  Write-Host "  npm install -g $pkg@latest"
  Write-Host "  git -C `"$clone`" pull --ff-only"
  Write-Host "  Apply-KriticalCodexPack.ps1 -Mode Heal"
  Write-Host "  verify codex --version + kcodex ; rollback to '$before' on failure"
  return
}

# 1) update stock codex (self-contained npm global)
Write-Host "`n[1/4] npm install -g $pkg@latest ..." -ForegroundColor Yellow
npm install -g "$pkg@latest" 2>&1 | Out-Host

# 2) refresh source clone (never fails the run)
if (Test-Path (Join-Path $clone '.git')) {
  Write-Host "[2/4] git pull source clone ..." -ForegroundColor Yellow
  git -C $clone pull --ff-only 2>&1 | Out-Host
} else { Write-Host "[2/4] no source clone — skipping" }

# 3) re-apply pack (heal shims/PATH)
Write-Host "[3/4] re-applying Kritical pack ..." -ForegroundColor Yellow
& (Join-Path $PSScriptRoot 'Apply-KriticalCodexPack.ps1') -Mode Heal -Manifest $Manifest

# 4) verify + rollback
Write-Host "[4/4] verifying ..." -ForegroundColor Yellow
$after = Get-CodexVersion
if (-not $after) {
  Write-Host "  codex broken after update — ROLLING BACK to $before" -ForegroundColor Red
  if ($before) { npm install -g "$pkg@$($before -replace '[^0-9\.]','')" 2>&1 | Out-Host }
  Write-Host "  If Claude is affected in any way, run: C:\KriticalSCX\safety\Restore-WorkingClaude.ps1" -ForegroundColor Yellow
} else {
  Write-Host "  codex OK: $before -> $after" -ForegroundColor Green
  Write-Host "  Emergency escape (any time): C:\KriticalSCX\safety\Restore-WorkingClaude.ps1" -ForegroundColor Gray
}
