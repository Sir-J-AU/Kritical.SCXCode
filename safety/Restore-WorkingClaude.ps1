<#
.SYNOPSIS
  EMERGENCY ESCAPE — guarantee Claude Code talks directly to the real Anthropic API.
  Surgically undoes any SCX/LiteLLM routing and kills any local interceptor. Safe to run anytime.

  HR29: Claude must ALWAYS work with the Kritical layer off. This is that off-switch.

.PARAMETER Status   Only report current routing + running Kritical processes (no changes).
.EXAMPLE  pwsh C:\KriticalSCX\safety\Restore-WorkingClaude.ps1            # restore + verify
.EXAMPLE  pwsh C:\KriticalSCX\safety\Restore-WorkingClaude.ps1 -Status    # just look
#>
[CmdletBinding()] param([switch]$Status)
$ErrorActionPreference = 'Continue'
$OFFICIAL = 'https://api.anthropic.com'
$PROXY_PORT = 4180

function Show-Routing {
  Write-Host "`n=== Claude / agent routing ===" -ForegroundColor Cyan
  foreach ($scope in 'Process','User','Machine') {
    # .5228 — precomputed (no ?? / no inline-if in -f args): this emergency off-switch must parse under
    # BOTH Windows PowerShell 5.1 and pwsh 7 so it can never fail to run when it's needed most.
    $a = [Environment]::GetEnvironmentVariable('ANTHROPIC_BASE_URL', $scope)
    $o = [Environment]::GetEnvironmentVariable('OPENAI_BASE_URL', $scope)
    if (-not $a) { $a = '(unset)' }
    if (-not $o) { $o = '(unset)' }
    Write-Host ("  [{0,-7}] ANTHROPIC_BASE_URL={1}  OPENAI_BASE_URL={2}" -f $scope, $a, $o)
  }
  $claude = (Get-Command claude -ErrorAction SilentlyContinue).Source
  if (-not $claude) { $claude = '(not found)' }
  Write-Host "  claude on PATH: $claude"
  $proxy = try { (Get-NetTCPConnection -LocalPort $PROXY_PORT -State Listen -ErrorAction Stop).OwningProcess } catch { $null }
  Write-Host "  LiteLLM proxy on :$PROXY_PORT : $(if($proxy){"RUNNING (pid $proxy)"}else{'not running'})" -ForegroundColor $(if($proxy){'Yellow'}else{'Green'})
}

Show-Routing
if ($Status) { return }

Write-Host "`n=== RESTORING working Claude ===" -ForegroundColor Green

# 1) If ANTHROPIC_BASE_URL points at a local interceptor, reset it to the official endpoint.
foreach ($scope in 'User','Process') {
  $a = [Environment]::GetEnvironmentVariable('ANTHROPIC_BASE_URL', $scope)
  if ($a -and ($a -match '127\.0\.0\.1|localhost|:' + $PROXY_PORT)) {
    Write-Host "  [$scope] ANTHROPIC_BASE_URL was '$a' -> resetting to $OFFICIAL" -ForegroundColor Yellow
    [Environment]::SetEnvironmentVariable('ANTHROPIC_BASE_URL', $OFFICIAL, $scope)
  }
}
# also clear any OPENAI_BASE_URL override in the current process so nothing lingers here
if ($env:OPENAI_BASE_URL) { Write-Host "  clearing process OPENAI_BASE_URL ($env:OPENAI_BASE_URL)"; Remove-Item Env:OPENAI_BASE_URL -ErrorAction SilentlyContinue }

# 2) Kill the LiteLLM proxy if listening (nothing should intercept during an emergency).
try {
  $pids = (Get-NetTCPConnection -LocalPort $PROXY_PORT -State Listen -ErrorAction Stop).OwningProcess | Select-Object -Unique
  foreach ($p in $pids) { Write-Host "  stopping proxy pid $p" -ForegroundColor Yellow; Stop-Process -Id $p -Force -ErrorAction SilentlyContinue }
} catch { Write-Host "  no proxy listening on :$PROXY_PORT" }

# 3) Verify Claude binary responds.
Write-Host "`n=== VERIFY ===" -ForegroundColor Cyan
$claude = (Get-Command claude -ErrorAction SilentlyContinue).Source
if ($claude) { try { $v = & claude --version 2>&1 | Select-Object -First 1; Write-Host "  claude OK: $v" -ForegroundColor Green } catch { Write-Host "  claude present but --version failed: $_" -ForegroundColor Red } }
else { Write-Host "  claude NOT on PATH — check npm global bin" -ForegroundColor Red }
Show-Routing
Write-Host "`nClaude restored to direct Anthropic API. SCX layer is OFF." -ForegroundColor Green
