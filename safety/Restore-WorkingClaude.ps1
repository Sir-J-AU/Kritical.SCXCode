<#
.SYNOPSIS
  EMERGENCY ESCAPE — stop Kritical-owned SCX local routing without touching native provider settings.
  Stops the local SCX/LiteLLM proxy. It never reads, prints, writes, or removes Anthropic/OpenAI env vars.

  HR29: Claude must ALWAYS work with the Kritical layer off. This is that off-switch.

.PARAMETER Status   Only report current routing + running Kritical processes (no changes).
.EXAMPLE  pwsh C:\KriticalSCX\safety\Restore-WorkingClaude.ps1            # restore + verify
.EXAMPLE  pwsh C:\KriticalSCX\safety\Restore-WorkingClaude.ps1 -Status    # just look
#>
[CmdletBinding()] param([switch]$Status)
$ErrorActionPreference = 'Continue'
$PROXY_PORT = 4180

function Show-Routing {
  Write-Host "`n=== Kritical SCX local routing ===" -ForegroundColor Cyan
  Write-Host '  Native Anthropic/OpenAI env vars: UNINSPECTED and UNTOUCHED'
  $claude = (Get-Command claude -ErrorAction SilentlyContinue).Source
  if (-not $claude) { $claude = '(not found)' }
  Write-Host "  claude on PATH: $claude"
  $proxy = try { (Get-NetTCPConnection -LocalPort $PROXY_PORT -State Listen -ErrorAction Stop).OwningProcess } catch { $null }
  Write-Host "  LiteLLM proxy on :$PROXY_PORT : $(if($proxy){"RUNNING (pid $proxy)"}else{'not running'})" -ForegroundColor $(if($proxy){'Yellow'}else{'Green'})
}

Show-Routing
if ($Status) { return }

Write-Host "`n=== RESTORING working Claude ===" -ForegroundColor Green

# Kill the LiteLLM proxy if listening. Do not inspect or mutate native provider env.
try {
  $pids = (Get-NetTCPConnection -LocalPort $PROXY_PORT -State Listen -ErrorAction Stop).OwningProcess | Select-Object -Unique
  foreach ($p in $pids) {
    $proc = Get-Process -Id $p -ErrorAction SilentlyContinue
    # .5231 (bughunt) — verify the :$PROXY_PORT owner really is the LiteLLM proxy (python/litellm) before
    # force-killing. The old code nuked whatever held the port — an unrelated process would be collateral.
    if ($proc -and $proc.ProcessName -match 'python|litellm') {
      Write-Host "  stopping proxy pid $p ($($proc.ProcessName))" -ForegroundColor Yellow
      Stop-Process -Id $p -Force -ErrorAction SilentlyContinue
    } elseif ($proc) {
      Write-Host "  :$PROXY_PORT held by '$($proc.ProcessName)' (pid $p) — not a LiteLLM proxy; leaving it alone." -ForegroundColor DarkYellow
    }
  }
} catch { Write-Host "  no proxy listening on :$PROXY_PORT" }

# Verify Claude binary responds.
Write-Host "`n=== VERIFY ===" -ForegroundColor Cyan
$claude = (Get-Command claude -ErrorAction SilentlyContinue).Source
if ($claude) { try { $v = & claude --version 2>&1 | Select-Object -First 1; Write-Host "  claude OK: $v" -ForegroundColor Green } catch { Write-Host "  claude present but --version failed: $_" -ForegroundColor Red } }
else { Write-Host "  claude NOT on PATH — check npm global bin" -ForegroundColor Red }
Show-Routing
Write-Host "`nKritical SCX local proxy is OFF. Native provider settings were not inspected or changed." -ForegroundColor Green
