<#
.SYNOPSIS
  Install / Remove / Heal / Status for compiled Kritical.SCXCodex.

.DESCRIPTION
  Delegates to codex-wrapper/pack so the installed artifact is a real compiled
  Kritical.SCXCodex.exe package, not a cmd shim. Stock codex and native provider
  auth/settings remain untouched and uninspected.
#>
[CmdletBinding()]
param(
  [ValidateSet('Install','Remove','Heal','Status')][string]$Mode = 'Status',
  [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$pack = Join-Path $repoRoot 'codex-wrapper\pack\Apply-KriticalCodexPack.ps1'

function Say([string]$Message, [string]$Color = 'Gray') {
  Write-Host $Message -ForegroundColor $Color
}

function Invoke-Pack([string]$PackMode) {
  & $pack -Mode $PackMode
}

switch ($Mode) {
  'Install' {
    Say "=== Install compiled Kritical.SCXCodex.exe ===" 'Cyan'
    if ($Apply) {
      Invoke-Pack 'Install'
    } else {
      Say "  [dry-run] would compile and package C:\KriticalSCX\dist\Kritical.SCXCodex\bin\Kritical.SCXCodex.exe" 'DarkYellow'
      Say "  [dry-run] would leave stock codex and native provider auth/settings untouched" 'DarkYellow'
      Say "`nDRY-RUN complete. Re-run with -Apply to execute." 'Cyan'
      Invoke-Pack 'Status'
    }
  }
  'Heal' {
    Say "=== Heal compiled Kritical.SCXCodex.exe ===" 'Cyan'
    if ($Apply) {
      Invoke-Pack 'Heal'
    } else {
      Say "  [dry-run] would verify compiled branding, rebuilding if missing" 'DarkYellow'
      Say "`nDRY-RUN complete. Re-run with -Apply to execute." 'Cyan'
      Invoke-Pack 'Status'
    }
  }
  'Remove' {
    Say "=== Remove compiled Kritical.SCXCodex package ===" 'Cyan'
    if ($Apply) {
      Invoke-Pack 'Remove'
    } else {
      Say "  [dry-run] would remove only C:\KriticalSCX\dist\Kritical.SCXCodex and SCX build cache" 'DarkYellow'
      Say "`nDRY-RUN complete. Re-run with -Apply to execute." 'Cyan'
    }
  }
  'Status' {
    Invoke-Pack 'Status'
  }
}
