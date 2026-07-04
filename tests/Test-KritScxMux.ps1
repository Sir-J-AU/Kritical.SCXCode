<#  HR21 paired test for the muxing engine. Structural + a small live 2-shard run (needs the proxy up). #>
[CmdletBinding()] param([switch]$SkipLive)
$ErrorActionPreference='Continue'
$mux="$PSScriptRoot\..\mux\Invoke-KritScxMux.ps1"
$py ="$PSScriptRoot\..\mux\mux_shards_ingest.py"
$pass=0;$fail=0
function T($n,$c){ if($c){"  PASS $n";$script:pass++}else{"  FAIL $n";$script:fail++} }

Write-Host "Kritical SCX Mux — paired test" -ForegroundColor Cyan
$e=$null;[void][System.Management.Automation.Language.Parser]::ParseFile($mux,[ref]$null,[ref]$e); T "mux script parses" (-not $e)
T "shard-ingest helper present" (Test-Path $py)
T "context_shard table exists" ([bool]((sqlcmd -S '.\SQLEXPRESS' -d KriticalSCXCodeStore -E -h -1 -W -Q "SELECT COUNT(*) FROM sys.tables WHERE name='context_shard';" 2>&1) -match '1'))

if (-not $SkipLive) {
  $proxy = try { (Invoke-WebRequest 'http://127.0.0.1:4180/health/liveliness' -UseBasicParsing -TimeoutSec 3).StatusCode -eq 200 } catch { $false }
  if ($proxy) {
    $sess="muxtest-$(Get-Random)"
    $r = & $mux -Task "Name the two components." -SessionId $sess -Concurrency 2 -Shards @("Component A is the proxy.","Component B is the store.") 2>&1
    $rows = (sqlcmd -S '.\SQLEXPRESS' -d KriticalSCXCodeStore -E -h -1 -W -Q "SELECT COUNT(*) FROM dbo.context_shard WHERE session_id='$sess';" 2>&1)
    T "2-shard live run persisted rows" ([bool]($rows -match '2'))
    sqlcmd -S '.\SQLEXPRESS' -d KriticalSCXCodeStore -E -Q "DELETE FROM dbo.context_shard WHERE session_id='$sess';" 2>&1 | Out-Null
  } else { Write-Host "  SKIP live (proxy down)" -ForegroundColor DarkGray }
}
Write-Host "`n$pass passed, $fail failed" -ForegroundColor $(if($fail){'Red'}else{'Green'})
exit $fail
