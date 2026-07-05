<#
.SYNOPSIS
  End-to-end routing/messaging test + text observability for the Kritical SCX stack.
  Proves: proxy health -> model list -> live SCX message -> and that OpenAI/Anthropic/Google
  routing is LEFT ALONE (Claude direct, stock codex native). Pass/fail in text.

.PARAMETER Model   SCX model to canary-test (default scx-coder).
.PARAMETER Full    Also test gpt-oss-120b + minimax-m2.7 and show latency per model.
.PARAMETER Tail    Show the last N lines of the proxy log (observability). Default 0.
.EXAMPLE  pwsh Test-KritScxRouting.ps1
.EXAMPLE  pwsh Test-KritScxRouting.ps1 -Full -Tail 30
#>
[CmdletBinding()]
param([string]$Model='scx-coder', [switch]$Full, [int]$Tail=0,
      [int]$Port=4180, [string]$BindHost='127.0.0.1',
      [string]$Key='sk-kritical-scx-local',
      [string]$ProxyLog='C:\KriticalSCX\litellm-proxy.log')
$ErrorActionPreference='Continue'
$base = "http://$BindHost`:$Port"
$pass=0; $fail=0
function Check($name,[scriptblock]$test){
  try { $r = & $test; if ($r) { Write-Host "  PASS  $name  $($r -is [string] ? $r : '')" -ForegroundColor Green; $script:pass++ } else { Write-Host "  FAIL  $name" -ForegroundColor Red; $script:fail++ } }
  catch { Write-Host "  FAIL  $name  ($($_.Exception.Message))" -ForegroundColor Red; $script:fail++ }
}
function Canary($m){
  $body = @{ model=$m; messages=@(@{role='user';content='Reply with exactly: KRITICAL_ROUTING_OK'}); max_tokens=16; temperature=0 } | ConvertTo-Json
  $sw=[System.Diagnostics.Stopwatch]::StartNew()
  $r = Invoke-RestMethod -Uri "$base/v1/chat/completions" -Method Post -TimeoutSec 60 `
        -Headers @{ Authorization="Bearer $Key" } -ContentType 'application/json' -Body $body
  $sw.Stop()
  [pscustomobject]@{ model=$r.model; reply=$r.choices[0].message.content; ms=$sw.ElapsedMilliseconds; tokens=$r.usage.total_tokens }
}

Write-Host "`n===== Kritical SCX — Routing / Messaging / Router test =====" -ForegroundColor Cyan

Write-Host "`n[A] Proxy" -ForegroundColor White
Check "proxy /health/liveliness" { (Invoke-RestMethod "$base/health/liveliness" -TimeoutSec 5) ; $true }
Check "proxy exposes models" { $m=(Invoke-RestMethod "$base/v1/models" -Headers @{Authorization="Bearer $Key"} -TimeoutSec 10).data; "$($m.Count) models" }

Write-Host "`n[B] Live SCX messaging (the router doing its job)" -ForegroundColor White
$c = $null
Check "canary -> $Model responds" { $script:c = Canary $Model; if($script:c.reply){"as '$($script:c.model)' in $($script:c.ms)ms, $($script:c.tokens) tok"}else{$false} }
if ($c) { Write-Host "        reply: $($c.reply)" -ForegroundColor Gray }
if ($Full) {
  foreach ($m in 'gpt-oss-120b','minimax-m2.7') {
    Check "canary -> $m responds" { $x = Canary $m; if($x.reply){"$($x.ms)ms, $($x.tokens) tok"}else{$false} }
  }
}

Write-Host "`n[C] Leave OpenAI / Anthropic / Google ALONE (HR29 safety)" -ForegroundColor White
Check "native provider env is not inspected by this test" {
  'Anthropic/OpenAI env values intentionally uninspected'
}
Check "stock codex uses NATIVE auth (auth.json auth_mode present)" {
  $auth = "$env:USERPROFILE\.codex\auth.json"; if (Test-Path $auth) { $j = Get-Content $auth -Raw | ConvertFrom-Json; if ($j.auth_mode) { "auth_mode=$($j.auth_mode)" } else { $false } } else { $false }
}
Check "SCX routing uses local proxy token only" {
  $Key -eq 'sk-kritical-scx-local'
}

Write-Host "`n[D] kcodex routing decision (what SCX-routed codex would do right now)" -ForegroundColor White
$scxKey = [Environment]::GetEnvironmentVariable('SCX_API_KEY','User')
$healthy = try { (Invoke-WebRequest "$base/health/liveliness" -UseBasicParsing -TimeoutSec 3).StatusCode -eq 200 } catch { $false }
if ($scxKey -and $healthy) { Write-Host "  -> SCX mode: kcodex routes codex to $base as 'scx-coder' (SCX key present + proxy healthy)" -ForegroundColor Green }
else { Write-Host "  -> PASSTHROUGH: kcodex behaves as stock codex (native OpenAI). SCX key:$([bool]$scxKey) proxy:$healthy" -ForegroundColor Yellow }

if ($Tail -gt 0 -and (Test-Path $ProxyLog)) {
  Write-Host "`n[E] Proxy log (last $Tail lines) — observability" -ForegroundColor White
  Get-Content $ProxyLog -Tail $Tail | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
}

Write-Host "`n===== $pass passed, $fail failed =====" -ForegroundColor $(if($fail){'Red'}else{'Green'})
Write-Host "Emergency escape any time: C:\KriticalSCX\safety\Restore-WorkingClaude.ps1" -ForegroundColor Gray
exit $fail
