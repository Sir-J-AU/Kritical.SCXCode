<#
.SYNOPSIS
  Resolve the SCX model catalogue with a live-query -> cache -> hardcoded fallback chain.
  1) If SCX_API_KEY present, live-query (proxy :4180 first, else api.scx.ai) and refresh the cache.
  2) Else use the on-disk cache (populated by the first successful live query).
  3) Else use the bundled hardcoded fallback (kept current from queries; covers offline gaps).

.PARAMETER Refresh   Force a live query even if the cache is fresh.
.PARAMETER Offline   Never hit the network; cache -> fallback only.
.PARAMETER MaxAgeHrs Cache considered stale after this many hours (default 24) -> triggers live refresh.
.OUTPUTS  Array of { id, source } and writes cache to C:\KriticalSCX\cache\scx-models.json.
.EXAMPLE  $models = .\Get-KritScxModels.ps1            # smart: live if key, else cache/fallback
.EXAMPLE  .\Get-KritScxModels.ps1 -Refresh            # force refresh
#>
[CmdletBinding()]
param([switch]$Refresh, [switch]$Offline, [int]$MaxAgeHrs=24,
      [int]$ProxyPort=4180, [string]$ScxBase='https://api.scx.ai/v1')
$ErrorActionPreference='Continue'
$cacheDir='C:\KriticalSCX\cache'; $cacheFile=Join-Path $cacheDir 'scx-models.json'
New-Item -ItemType Directory -Force $cacheDir | Out-Null

# --- Hardcoded fallback (SCX published catalogue; refreshed from live queries when online) ---
$FALLBACK = @(
  'minimax-m2.7','scx-coder','gpt-oss-120b','deepseek-v3.1','deepseek-v3.1-terminus',
  'deepseek-r1-0528','deepseek-v3-0324','magpie','llama-4-maverick','llama-3.3-70b',
  'llama-3.1-8b','qwen3-32b','qwen3-235b','e5-mistral-embeddings','whisper-large-v3'
)

function Save-Cache($ids,$src){
  @{ updated=(Get-Date -Format o); source=$src; models=$ids } | ConvertTo-Json -Depth 5 | Set-Content $cacheFile -Encoding utf8
}
function Read-Cache {
  if (Test-Path $cacheFile) { try { return Get-Content $cacheFile -Raw | ConvertFrom-Json } catch {} }
  return $null
}
function Query-Endpoint($uri,$key){
  try {
    $h = @{}; if ($key) { $h['Authorization'] = "Bearer $key" }
    $r = Invoke-RestMethod -Uri "$uri/models" -Headers $h -TimeoutSec 10 -ErrorAction Stop
    return @($r.data.id | Where-Object { $_ })
  } catch { return $null }
}

$scxKey = [Environment]::GetEnvironmentVariable('SCX_API_KEY','User')
$cache  = Read-Cache
$cacheFresh = $cache -and ((New-TimeSpan -Start ([datetime]$cache.updated) -End (Get-Date)).TotalHours -lt $MaxAgeHrs)

$ids=$null; $source=$null
if (-not $Offline -and ($Refresh -or -not $cacheFresh)) {
  # Prefer the local proxy (aggregates aliases) when healthy; else direct SCX with the key.
  $proxyHealthy = try { (Invoke-WebRequest "http://127.0.0.1:$ProxyPort/health/liveliness" -UseBasicParsing -TimeoutSec 3).StatusCode -eq 200 } catch { $false }
  if ($proxyHealthy) { $ids = Query-Endpoint "http://127.0.0.1:$ProxyPort/v1" 'sk-kritical-scx-local'; if ($ids) { $source='live:proxy' } }
  if (-not $ids -and $scxKey) { $ids = Query-Endpoint $ScxBase $scxKey; if ($ids) { $source='live:scx' } }
  if ($ids) { Save-Cache $ids $source }
}
if (-not $ids) {
  if ($cache) { $ids = @($cache.models); $source = "cache($($cache.source))" }
  else        { $ids = $FALLBACK;        $source = 'fallback:hardcoded'; Save-Cache $ids $source }
}

Write-Host "SCX models: $($ids.Count)  [source: $source]" -ForegroundColor Cyan
$ids | ForEach-Object { [pscustomobject]@{ id=$_; source=$source } }
