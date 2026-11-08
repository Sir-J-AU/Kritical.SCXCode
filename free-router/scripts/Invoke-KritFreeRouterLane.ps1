#requires -Version 7.0
<#
.SYNOPSIS
  Send one brief file to the local free router (LiteLLM, OpenAI-compatible) and write the answer to a file.

.DESCRIPTION
  Free-tier offload lane. Reads -BriefPath, POSTs it to <BaseUri>/v1/chat/completions, writes the
  answer to -OutPath, and appends one JSON line per event (START / DONE / FAIL) to the ledger with
  model, bytes and ms. FAILS CLOSED: an empty or whitespace answer, an HTTP error, a timeout, a
  malformed response or a brief that looks like it carries a secret all end in FAIL, a thrown error
  (non-zero exit when run as a script) and NO out file. Output is a CANDIDATE, never a conclusion: gate it.

  Never send secrets, customer data or money decisions to a free model. The provider key is never
  read here; the router holds it by name (OPENROUTER_API_KEY). The router token is the local-only
  value from the repo config, overridable by env KRIT_FREE_ROUTER_TOKEN.

.PARAMETER BriefPath   Brief text file (UTF-8).
.PARAMETER OutPath     Answer file. Written only for a non-empty answer.
.PARAMETER Model       Router model name (default free-nemotron-ultra; see litellm\kritical-openrouter-free-only.config.yaml).
.PARAMETER BaseUri     Router base, default http://127.0.0.1:4180.
.PARAMETER LedgerPath  Append-only JSONL ledger, default <repo>\out\ledger.jsonl.
.PARAMETER LaneId      Label written into every ledger line.

.EXAMPLE
  pwsh scripts\Invoke-KritFreeRouterLane.ps1 -BriefPath C:\x\brief.txt -OutPath C:\x\answer.txt -LaneId classify-01
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $BriefPath,
  [Parameter(Mandatory)] [string] $OutPath,
  [string] $Model = 'free-nemotron-ultra',
  [string] $BaseUri = 'http://127.0.0.1:4180',
  [string] $LedgerPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'out\ledger.jsonl'),
  [string] $LaneId = 'free-lane',
  [int] $MaxTokens = 1500,
  [int] $TimeoutSec = 120
)

$ErrorActionPreference = 'Stop'

function Add-LedgerLine {
  param([string] $Event, [hashtable] $Extra = @{})
  $dir = Split-Path -Parent $LedgerPath
  if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $row = [ordered]@{ ts_utc = (Get-Date).ToUniversalTime().ToString('o'); event = $Event; lane = $LaneId; requested_model = $Model; brief = $BriefPath; out = $OutPath }
  foreach ($k in $Extra.Keys) { $row[$k] = $Extra[$k] }
  Add-Content -LiteralPath $LedgerPath -Value ($row | ConvertTo-Json -Compress) -Encoding utf8
}

function Fail {
  param([string] $Reason, [int] $Ms = 0)
  Add-LedgerLine -Event 'FAIL' -Extra @{ reason = $Reason; ms = $Ms; bytes = 0 }
  if (Test-Path -LiteralPath $OutPath) { Remove-Item -LiteralPath $OutPath -Force }
  throw "FREE-LANE FAIL [$LaneId]: $Reason"
}

Add-LedgerLine -Event 'START'
$sw = [Diagnostics.Stopwatch]::StartNew()

if (-not (Test-Path -LiteralPath $BriefPath)) { Fail "brief not found: $BriefPath" }
$brief = [IO.File]::ReadAllText($BriefPath)
if (-not $brief.Trim()) { Fail 'brief is empty' }

# Fail closed on anything that looks like a credential: free models must never see one.
$secretPattern = '(?i)(sk-[a-z0-9_-]{16,}|AIza[0-9A-Za-z_-]{20,}|gsk_[A-Za-z0-9]{20,}|xox[bap]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|bearer\s+[a-z0-9._-]{20,})'
if ($brief -match $secretPattern) { Fail 'brief matches a secret pattern; not sent to a free model' }

$token = if ($env:KRIT_FREE_ROUTER_TOKEN) { $env:KRIT_FREE_ROUTER_TOKEN } else { 'sk-kritical-free-local' }
$body = @{ model = $Model; max_tokens = $MaxTokens; messages = @(@{ role = 'user'; content = $brief }) } | ConvertTo-Json -Depth 6

$resp = $null
try {
  $resp = Invoke-RestMethod -Uri ($BaseUri.TrimEnd('/') + '/v1/chat/completions') -Method Post `
    -Headers @{ Authorization = "Bearer $token" } -Body ([Text.Encoding]::UTF8.GetBytes($body)) `
    -ContentType 'application/json; charset=utf-8' -TimeoutSec $TimeoutSec
} catch {
  Fail ('request failed: ' + $_.Exception.Message) ([int]$sw.ElapsedMilliseconds)
}

$answer = $null
try { $answer = [string]$resp.choices[0].message.content } catch { Fail 'malformed response (no choices[0].message.content)' ([int]$sw.ElapsedMilliseconds) }
if ([string]::IsNullOrWhiteSpace($answer)) { Fail 'EMPTY ANSWER from model' ([int]$sw.ElapsedMilliseconds) }

$outDir = Split-Path -Parent $OutPath
if ($outDir) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
[IO.File]::WriteAllText($OutPath, $answer, [Text.UTF8Encoding]::new($false))
$bytes = (Get-Item -LiteralPath $OutPath).Length
$answered = [string]$resp.model
Add-LedgerLine -Event 'DONE' -Extra @{ model = $answered; bytes = $bytes; ms = [int]$sw.ElapsedMilliseconds }
[pscustomobject]@{ Lane = $LaneId; RequestedModel = $Model; AnsweredBy = $answered; Bytes = $bytes; Ms = [int]$sw.ElapsedMilliseconds; OutPath = $OutPath }
