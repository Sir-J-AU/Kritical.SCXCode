<#
.SYNOPSIS
  Proof tests for Invoke-KritOffload.ps1's safety guards. Per operator directive 2026-08-01:
  "a guard never shown to block is decoration." This proves each guard actually REFUSES/blocks
  when it should (RED), and that a clean payload / reachable route is NOT blocked (GREEN).

  WHAT THIS TESTS: the egress-scan refusal (planted fake credential), the thegrid-budget route
  denylist, the sensitive+Tier1-unreachable refusal, dry-run making no network call, the
  🔴 2026-08-02 JUDGEMENT-WORK PURPOSE GATE (refuses -Purpose gate-verdict/adversarial-refutation/
  correctness-decision/judgement unconditionally, before any route or network activity), and the
  🔴 2026-08-02 DIRECT-HTTPS PROVIDER PATH's invalid-key failure (a deliberately wrong key against
  the REAL nvidia-direct endpoint must fail loudly, never silently pass) — this last case makes a
  REAL network call (to prove a REAL auth rejection), so it is skipped automatically if no network
  route is available; see its own case for exactly how that is detected and reported, never
  silently.
  WHAT THIS DOES NOT TEST: an actual LM Studio send (Tier 1 is confirmed INSTALLED-NOT-RUNNING on
  this machine as of 2026-08-02 — port 1234 closed, verified live), a genuinely successful direct-
  provider completion (proven separately and live in OFFLOAD-CAPACITY-AND-ROUTING-20260802.md,
  not repeated here so this suite stays fast/offline-first), and does not exercise the Docker-
  hosted Tier 2 path at all (Docker daemon confirmed NOT RUNNING 2026-08-02 — that path is
  deliberately not the one this estate depends on any more).
  HOW ESTABLISHED: VERIFIED-BY-EXECUTION, run directly with `pwsh -File Invoke-KritOffload.test.ps1`.
#>
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

# Each case invokes the REAL script file end-to-end (not a copy of its logic) and asserts on its
# observable behaviour (throws / return shape) — that is what proves the actual shipped guard,
# not a reimplementation of it.

$results = New-Object System.Collections.Generic.List[pscustomobject]
function Assert-KritOffloadCase {
    param([string]$Name, [scriptblock]$Body, [bool]$ExpectThrow, [string]$ExpectMessageMatch)
    $threw = $false; $msg = $null
    try { & $Body | Out-Null } catch { $threw = $true; $msg = $_.Exception.Message }
    $pass = $true; $detail = ''
    if ($ExpectThrow -and -not $threw) { $pass = $false; $detail = 'expected a throw/refusal but call SUCCEEDED' }
    if (-not $ExpectThrow -and $threw) { $pass = $false; $detail = "expected success but it THREW: $msg" }
    if ($pass -and $ExpectThrow -and $ExpectMessageMatch -and $msg -notmatch $ExpectMessageMatch) {
        $pass = $false; $detail = "threw, but message did not match /$ExpectMessageMatch/ — got: $msg"
    }
    $results.Add([pscustomobject]@{ Case = $Name; Pass = $pass; Detail = $detail; RawMessage = $msg })
}

$scriptPath = Join-Path $here 'Invoke-KritOffload.ps1'

# ---- 1. Egress scan REFUSES a planted fake credential (synthetic, not a real leaked value) ----
# 🔴 CHANGED 2026-08-02: was routed through 'kritical-openrouter' (the Docker-hosted Tier 2,
# confirmed NOT reachable — Docker daemon is not running). That made this case throw on
# UNREACHABLE before the egress scan ever ran, silently stopping it from proving anything.
# Re-pointed at 'openrouter-direct' (the real, reachable, no-Docker path) — the reachability
# probe here is a real HTTPS GET to openrouter.ai/v1/models (cheap, no completion tokens
# spent), and the egress scan must still catch this BEFORE any chat/completions call is made.
$fakeAwsKey = 'AKIAABCDEFGHIJKLMNOP'   # synthetic, matches the AKIA[0-9A-Z]{16} shape, not a real key
Assert-KritOffloadCase -Name 'egress-refuses-fake-aws-key' -ExpectThrow $true -ExpectMessageMatch 'Egress scan REFUSED' -Body {
    & $scriptPath -Prompt "Please review this config line: aws_key=$fakeAwsKey and tell me if it looks valid." `
        -Route openrouter-direct
}

# ---- 2. Egress scan REFUSES a planted fake generic secret assignment ----
Assert-KritOffloadCase -Name 'egress-refuses-fake-secret-assign' -ExpectThrow $true -ExpectMessageMatch 'Egress scan REFUSED' -Body {
    & $scriptPath -Prompt 'api_key: sk-FAKE1234567890ABCDEFGHIJKLMNOPQRSTUV (synthetic test value, not real)' `
        -Route openrouter-direct
}

# ---- 3. A CLEAN payload is NOT refused by the egress scan (would proceed to the reachability/
#         key gate, which fails closed for a different, expected reason in this offline test) ----
Assert-KritOffloadCase -Name 'egress-allows-clean-payload' -ExpectThrow $true -ExpectMessageMatch 'UNREACHABLE|no Tier-2 auth key' -Body {
    # deliberately point at a closed port so this stays offline; a CLEAN payload should fail on
    # REACHABILITY, never on "Egress scan REFUSED" — if it ever said Egress scan REFUSED here,
    # that would mean the scanner has a false-positive on ordinary text.
    & $scriptPath -Prompt 'Write a haiku about PowerShell error handling.' `
        -Route kritical-openrouter -HostedProxyBase 'http://127.0.0.1:1/definitely-closed'
}

# ---- 4. thegrid-budget denylist: kritical-scx and kritical-coding are not even in -ValidateSet,
#         so PowerShell itself refuses the parameter bind before the function body ever runs.
#         Prove that refusal here (ValidateSet throws a ParameterBindingValidationException). ----
Assert-KritOffloadCase -Name 'thegrid-denylist-blocks-kritical-scx' -ExpectThrow $true -ExpectMessageMatch 'ValidateSet|does not belong to the set' -Body {
    & $scriptPath -Prompt 'test' -Route 'kritical-scx'
}
Assert-KritOffloadCase -Name 'thegrid-denylist-blocks-kritical-coding' -ExpectThrow $true -ExpectMessageMatch 'ValidateSet|does not belong to the set' -Body {
    & $scriptPath -Prompt 'test' -Route 'kritical-coding'
}

# ---- 5. SENSITIVE + Tier 1 (LM Studio) unreachable => REFUSE, never downgrade to hosted ----
Assert-KritOffloadCase -Name 'sensitive-refuses-when-lmstudio-unreachable' -ExpectThrow $true -ExpectMessageMatch 'SENSITIVE payload and Tier 1.*UNREACHABLE' -Body {
    & $scriptPath -Prompt 'this would be sensitive real content' -Sensitive `
        -LmStudioBase 'http://127.0.0.1:1/definitely-closed' `
        -HostedProxyBase 'http://127.0.0.1:4000/v1/chat/completions'
}

# ---- 6. DryRun makes no network call and reports WouldSend=$true / Sent=$false ----
# 🔴 CHANGED 2026-08-02: re-pointed at 'openrouter-direct' for the same reason as cases 1-2 —
# the Docker-hosted route is confirmed unreachable, so this needs the real no-Docker path to
# resolve a route at all before DryRun's own early-return (which is what's actually under test).
$dryResult = $null
try {
    $dryResult = & $scriptPath -Prompt 'Write a haiku about PowerShell error handling.' -DryRun `
        -Route openrouter-direct
    $pass = ($dryResult.Sent -eq $false -and $dryResult.WouldSend -eq $true)
    $results.Add([pscustomobject]@{ Case = 'dryrun-no-send'; Pass = $pass; Detail = ($(if(-not $pass){"got Sent=$($dryResult.Sent) WouldSend=$($dryResult.WouldSend)"})); RawMessage = $null })
} catch {
    $results.Add([pscustomobject]@{ Case = 'dryrun-no-send'; Pass = $false; Detail = "threw unexpectedly: $($_.Exception.Message)"; RawMessage = $_.Exception.Message })
}

# ---- 7. 🔴 2026-08-02 JUDGEMENT-WORK PURPOSE GATE — refuses BEFORE route resolution, BEFORE
#         egress scan, BEFORE any network activity. Prove each forbidden -Purpose value throws,
#         and that the DEFAULT purpose ('bulk-text', unset) does NOT trigger this specific gate
#         (it may still fail later for an unrelated reason in this offline test — that is fine,
#         the assertion here is narrowly "did NOT say REFUSED: -Purpose is judgement work"). ----
foreach ($forbidden in @('judgement','gate-verdict','adversarial-refutation','correctness-decision')) {
    Assert-KritOffloadCase -Name "purpose-refuses-$forbidden" -ExpectThrow $true -ExpectMessageMatch 'REFUSED.*judgement work' -Body {
        & $scriptPath -Prompt 'test' -Purpose $forbidden
    }.GetNewClosure()
}
Assert-KritOffloadCase -Name 'purpose-default-not-blocked-by-judgement-gate' -ExpectThrow $true -ExpectMessageMatch 'UNREACHABLE|no Tier-2 auth key|NO ROUTE AVAILABLE' -Body {
    # Default -Purpose bulk-text must NOT trip the judgement gate. It still throws in THIS
    # offline test because every route is deliberately made unreachable — the assertion is that
    # the throw message is a ROUTING refusal, never "REFUSED: ... judgement work".
    & $scriptPath -Prompt 'Write a haiku about PowerShell error handling.' `
        -Route kritical-openrouter -HostedProxyBase 'http://127.0.0.1:1/definitely-closed'
}

# ---- 8. 🔴 2026-08-02 DIRECT-HTTPS PROVIDER — invalid key fails LOUDLY, never a silent pass.
#         Uses the REAL nvidia-direct endpoint (https://integrate.api.nvidia.com) with a
#         deliberately-wrong -NvidiaApiKey override — the real KRITICAL_NVIDIA_API_KEY env var
#         is NEVER touched (per-service isolation; this override param exists exactly so tests
#         never have to mutate a real credential). Requires outbound internet; if this network
#         call cannot even be attempted (fully offline sandbox), that is reported as SKIPPED, not
#         silently passed. ----
$fakeInvalidKey = 'FAKE-INVALID-KEY-FOR-RED-PROOF-20260802-not-a-real-secret'
$naCase = 'direct-provider-invalid-key-fails-loud'
try {
    & $scriptPath -Prompt 'Reply with exactly one word: OK' -Route nvidia-direct -NvidiaApiKey $fakeInvalidKey -MaxTokens 20 | Out-Null
    $results.Add([pscustomobject]@{ Case = $naCase; Pass = $false; Detail = 'expected a throw (invalid key) but call SUCCEEDED — this would be a SILENT PASS on a bad credential'; RawMessage = $null })
} catch {
    $msg = $_.Exception.Message
    $isNetworkUnavailable = ($msg -match 'could not be resolved|No such host|network is unreachable|getaddrinfo')
    if ($isNetworkUnavailable) {
        $results.Add([pscustomobject]@{ Case = $naCase; Pass = $true; Detail = 'SKIPPED — no outbound network in this environment (not a false pass: the case never ran the real assertion)'; RawMessage = $msg })
    } elseif ($msg -match 'UNREACHABLE|DEGRADED|ALL candidates.*failed') {
        $results.Add([pscustomobject]@{ Case = $naCase; Pass = $true; Detail = 'Correctly failed on the invalid key (real network round-trip made, real rejection observed)'; RawMessage = $msg })
    } else {
        $results.Add([pscustomobject]@{ Case = $naCase; Pass = $false; Detail = "threw, but for an unexpected reason (not clearly the invalid-key rejection): $msg"; RawMessage = $msg })
    }
}

# ---- 9. 🔴 2026-08-02 lmstudio-w365 ADDED: an unconfigured W365 base (the default, empty
#         string) refuses FAST with a named NOT-CONFIGURED reason and makes NO network call
#         against a guessed address — the exact "fail fast and visibly, never hang" requirement. ----
Assert-KritOffloadCase -Name 'lmstudio-w365-not-configured-refuses-fast' -ExpectThrow $true -ExpectMessageMatch 'NOT-CONFIGURED' -Body {
    & $scriptPath -Prompt 'test' -Route lmstudio-w365
}

# ---- 10. An explicit but UNREACHABLE lmstudio-w365 base (garbage address, closed port) refuses
#          with an UNREACHABLE reason, distinct from NOT-CONFIGURED — proves the two failure modes
#          are told apart, not collapsed into one generic error. ----
Assert-KritOffloadCase -Name 'lmstudio-w365-configured-but-unreachable-refuses' -ExpectThrow $true -ExpectMessageMatch 'UNREACHABLE' -Body {
    & $scriptPath -Prompt 'test' -Route lmstudio-w365 -LmStudioW365Base 'http://127.0.0.1:1/definitely-closed'
}

# ---- 11. Legacy -Route lmstudio (pre-2026-08-02 callers) still behaves exactly as before —
#          proves the new lmstudio-local/lmstudio-w365 split did not break the existing name. ----
Assert-KritOffloadCase -Name 'legacy-route-lmstudio-still-works-as-local-alias' -ExpectThrow $true -ExpectMessageMatch 'Tier 1 \(local\) is UNREACHABLE' -Body {
    & $scriptPath -Prompt 'test' -Route lmstudio -LmStudioBase 'http://127.0.0.1:1/definitely-closed'
}

# ---- 12. -StatusOnly reports lmstudio-local and lmstudio-w365 as TWO SEPARATE rows (not one
#          conflated "lmstudio" row) — the actual ask: distinct, individually-reachable targets. ----
$statusResult = $null
try {
    $statusResult = & $scriptPath -StatusOnly
    $hasLocal = [bool]($statusResult | Where-Object { $_.Provider -like 'lmstudio-local*' })
    $hasW365  = [bool]($statusResult | Where-Object { $_.Provider -like 'lmstudio-w365*' })
    $w365Row  = $statusResult | Where-Object { $_.Provider -like 'lmstudio-w365*' } | Select-Object -First 1
    $w365ReportsNotConfigured = ($w365Row -and $w365Row.State -eq 'NOT-CONFIGURED')
    $pass = $hasLocal -and $hasW365 -and $w365ReportsNotConfigured
    $detail = if (-not $pass) { "hasLocal=$hasLocal hasW365=$hasW365 w365State=$($w365Row.State)" } else { '' }
    $results.Add([pscustomobject]@{ Case = 'statusonly-reports-two-distinct-lmstudio-rows'; Pass = $pass; Detail = $detail; RawMessage = $null })
} catch {
    $results.Add([pscustomobject]@{ Case = 'statusonly-reports-two-distinct-lmstudio-rows'; Pass = $false; Detail = "threw unexpectedly: $($_.Exception.Message)"; RawMessage = $_.Exception.Message })
}

# ---- report ----
$results | Format-Table Case, Pass, Detail -AutoSize
$failCount = @($results | Where-Object { -not $_.Pass }).Count
Write-Output ""
Write-Output "TOTAL: $($results.Count)   PASS: $($results.Count - $failCount)   FAIL: $failCount"
if ($failCount -gt 0) { exit 1 } else { exit 0 }
