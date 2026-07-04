<#
.SYNOPSIS
  Apply / remove / heal / status the Kritical Codex Pack — the additive overlay over stock Codex.
  HR16 modes. HR29: additive only — stock `codex` is never modified and always works with the pack off.

.PARAMETER Mode  Install | Remove | Heal | Status  (default Status — safe)
.EXAMPLE  pwsh Apply-KriticalCodexPack.ps1 -Mode Status
.EXAMPLE  pwsh Apply-KriticalCodexPack.ps1 -Mode Install
.EXAMPLE  pwsh Apply-KriticalCodexPack.ps1 -Mode Remove
#>
[CmdletBinding()]
param([ValidateSet('Install','Remove','Heal','Status')][string]$Mode = 'Status',
      [string]$Manifest = "$PSScriptRoot\pack-manifest.json")
$ErrorActionPreference = 'Stop'
$m = Get-Content $Manifest -Raw | ConvertFrom-Json
$binDir = $m.bin_dir
$shimPath = Join-Path $binDir 'kcodex.cmd'
$wrapper = $m.wrapper.ps1
$receipt = Join-Path $binDir '.kritical-codex-pack.receipt.json'

function Test-OnUserPath($dir) {
  $p = [Environment]::GetEnvironmentVariable('PATH','User')
  return ($p -split ';') -contains $dir
}
function Show-Status {
  Write-Host "`n=== Kritical Codex Pack — Status ===" -ForegroundColor Cyan
  Write-Host "  pack version   : $($m.pack_version)"
  Write-Host "  wrapper        : $(if(Test-Path $wrapper){'present'}else{'MISSING'}) $wrapper"
  Write-Host "  shim kcodex    : $(if(Test-Path $shimPath){'installed'}else{'not installed'}) $shimPath"
  Write-Host "  bin on PATH    : $(if(Test-OnUserPath $binDir){'yes'}else{'no'})"
  $codex = (Get-Command codex -ErrorAction SilentlyContinue).Source
  $ver = if($codex){ try { (& codex --version 2>&1 | Select-Object -First 1) } catch { 'unknown' } } else { '(not found)' }
  Write-Host "  stock codex    : $ver  ($codex)"
  Write-Host "  source clone   : $(if(Test-Path (Join-Path $m.source_clone '.git')){'present'}else{'absent'}) $($m.source_clone)"
  $proxy = try { [bool]((Get-NetTCPConnection -LocalPort 4180 -State Listen -ErrorAction Stop)) } catch { $false }
  Write-Host "  LiteLLM :4180  : $(if($proxy){'running'}else{'stopped'})"
  Write-Host "`n  KILL SWITCH: pwsh Apply-KriticalCodexPack.ps1 -Mode Remove   (or emergency: C:\KriticalSCX\safety\Restore-WorkingClaude.ps1)" -ForegroundColor Yellow
}

switch ($Mode) {
  'Install' {
    if (-not (Test-Path $wrapper)) { throw "Wrapper not found: $wrapper" }
    New-Item -ItemType Directory -Force $binDir | Out-Null
    # additive shim: kcodex -> pwsh wrapper
    @"
@echo off
REM Kritical Codex Pack shim — SCX-routed codex. Stock 'codex' is untouched.
pwsh -NoProfile -ExecutionPolicy Bypass -File "$wrapper" %*
"@ | Set-Content $shimPath -Encoding ascii
    $pathAdded = $false
    if (-not (Test-OnUserPath $binDir)) {
      $cur = [Environment]::GetEnvironmentVariable('PATH','User')
      [Environment]::SetEnvironmentVariable('PATH', ($cur.TrimEnd(';') + ';' + $binDir), 'User')
      $pathAdded = $true
    }
    @{ when=(Get-Date -Format o); shim=$shimPath; pathAdded=$pathAdded; binDir=$binDir } | ConvertTo-Json | Set-Content $receipt -Encoding utf8
    Write-Host "Installed. 'kcodex' -> SCX-routed codex. Stock 'codex' unchanged." -ForegroundColor Green
    Write-Host "(Open a new terminal for PATH to take effect.)" -ForegroundColor Gray
    Show-Status
  }
  'Remove' {
    if (Test-Path $shimPath) { Remove-Item $shimPath -Force; Write-Host "removed shim $shimPath" -ForegroundColor Yellow }
    if (Test-Path $receipt) {
      $r = Get-Content $receipt -Raw | ConvertFrom-Json
      if ($r.pathAdded) {
        $cur = [Environment]::GetEnvironmentVariable('PATH','User')
        $new = (($cur -split ';') | Where-Object { $_ -and $_ -ne $binDir }) -join ';'
        [Environment]::SetEnvironmentVariable('PATH', $new, 'User')
        Write-Host "removed $binDir from User PATH" -ForegroundColor Yellow
      }
      Remove-Item $receipt -Force
    }
    Write-Host "Kritical Codex Pack removed. Stock 'codex' is your only codex now." -ForegroundColor Green
  }
  'Heal' {
    if (-not (Test-Path $shimPath) -or -not (Test-OnUserPath $binDir)) {
      Write-Host "healing -> re-running Install" -ForegroundColor Yellow
      & $PSCommandPath -Mode Install -Manifest $Manifest
    } else { Write-Host "pack healthy — nothing to heal" -ForegroundColor Green; Show-Status }
  }
  'Status' { Show-Status }
}
