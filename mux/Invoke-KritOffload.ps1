<#
.SYNOPSIS
  THE bulk-offload shell-out helper. Sends genuinely-outstanding bulk/mechanical work to a LOCAL
  or FREE model instead of spending Claude/Opus quota on it. This is the thing that makes
  "offload" real: a lane that calls THIS and gets text back has actually moved the work off
  Claude's meter. A sub-agent that just "thinks harder" is not offload.

.DESCRIPTION
  ROUTING TIERS (operator directive 2026-08-01 — DATA LOCALITY is the reason, not just cost;
  record it here so nobody later "optimises" this back to a hosted provider by default):

    TIER 1 (default for EVERYTHING, and the ONLY allowed destination for -Sensitive) —
      LM Studio on the W365 Cloud PC's GPU, reached via a LiteLLM instance running ON THAT SAME
      BOX (server-class hardware in a datacentre). FREE, UNMETERED, and NOTHING LEAVES THE
      ESTATE. The design win: LiteLLM -> LM Studio is a localhost call on the W365 box, so GPU
      inference traffic never crosses the tunnel — only the small request/response body does,
      over ONE forwarded port. -LmStudioBase is that forwarded endpoint.
      🔴 STATUS AS OF 2026-08-01 (W365 leg): NOT YET LIVE. The W365 tailnet tunnel scripts have
      never been run on that box (ports 22/5986/1234 all measured closed) and LM Studio there
      shows "Status: Stopped". This is BUILT-AND-DOCUMENTED-ONLY — see
      docs/OFFLOAD-LANE-HOWTO-20260801.md for exactly what is proven vs pending. This helper
      fails closed honestly: if -LmStudioBase is unreachable it says so by name and does not
      guess.

      🔴 CORRECTED 2026-08-02 — THIS SAME CODE PATH ALSO SERVES A LOCAL LM STUDIO ON THIS
      LAPTOP, NO TUNNEL NEEDED. `Test-KritOffloadRouteReachable -BaseUrl $LmStudioBase` TCP-
      probes `127.0.0.1:1234` regardless of whether what answers there is a W365 tunnel or a
      LOCAL LM Studio process — the mechanism is identical either way. Verified live 2026-08-02
      on THIS machine (an ARM64 Snapdragon X Elite with a working Hexagon NPU, `Status: OK`):
      `C:\Users\joshl\.lmstudio\bin\lms.exe` is INSTALLED, 4 GGUF models totalling 37 GB are
      already downloaded (`DeepSeek-R1-0528-Qwen3-8B-Q4_K_M`, `ERNIE-4.5-21B-A3B-PT-Q4_K_M`,
      `gpt-oss-20b-MXFP4`, `Phi-4-reasoning-plus-Q4_K_M` — none of these is Gemma-4-31B, so the
      "prefer the estate's cheapest-correct SCX pick" heuristic does not transfer here; these are
      four different, unbenchmarked local models). 🔴 A DIRECT CLAIM THIS HELPER MEASURED AND
      FOUND WRONG: a claim reached this session that an `lms` process was "ALREADY RUNNING, pid
      29132" — **checked live, false**: `Get-Process -Id 29132` returns nothing, no process
      named `lms`/`lmstudio` is running, and `Test-NetConnection 127.0.0.1 -Port 1234` returns
      `TcpTestSucceeded: False`. The true, verified state is **INSTALLED-NOT-RUNNING**, not
      running. This helper NEVER starts the LM Studio server itself — see the standing rule
      "never Automatic service startup without typed-ack + rehearsal" — it only detects whether
      one is already up (locally OR via a W365 tunnel) and uses it if so. `-StatusOnly` (see
      below) reports this three-way state (`NOT-INSTALLED` / `INSTALLED-NOT-RUNNING` /
      `RUNNING-AND-ANSWERING`) honestly, plus the exact one-line command the OPERATOR would run
      to start it (`lms.exe server start`) — this script prints that command, it does not run it.
      🔴 OPEN ITEM, NOT FABRICATED: the operator has been asked which LM Studio "safety options"
      (thermal/context/memory limits) he wants set before this box loads a large local model
      unattended, and has not yet answered. No specific setting name is asserted here because
      none has been verified — inventing one would be exactly the kind of unverified claim RULE
      ZERO exists to prevent. Until that answer lands, `-StatusOnly` reports LM Studio's real
      state but this script does not add it to any AUTOMATIC non-sensitive routing preference
      beyond what already existed (Tier 1 first-if-reachable, unchanged) — it does not start it,
      and it does not silently assume any safety posture on the operator's behalf.

      🔴 OPERATOR-ONLY — EXACT STEPS TO MAKE `-Route lmstudio-w365` REAL (added 2026-08-02, per
      operator: "AND OR TO LM STUDIO @W365BOX"). This script does not, and per standing rule must
      not, perform any of these — no automatic service startup without typed-ack + rehearsal, and
      no credentialed remote session was opened to check current state (a sibling lane correctly
      declined that). Last MEASURED state (2026-08-01): W365 ports 22/5986/1234 all closed, LM
      Studio "Status: Stopped" — treat as UNVERIFIED/likely still off until re-checked.
        1. On the W365 Cloud PC itself (RDP/console session, operator-driven): start LM Studio's
           local server — `lms.exe server start` (same binary/command as the laptop) — ONLY after
           setting whatever thermal/context/memory safety options the operator decides on for that
           box (same open item as the laptop leg above; no specific values are assumed here).
        2. Bind LM Studio's OpenAI-compatible server to localhost on the W365 box (default
           127.0.0.1:1234) — never 0.0.0.0. Do NOT forward port 1234 itself across any tunnel (that
           would push raw GPU inference traffic over the wire).
        3. Run a LiteLLM instance ON THE SAME W365 BOX, pointed at that localhost LM Studio server,
           so only LiteLLM's port needs to leave the box.
        4. Forward/tunnel ONLY LiteLLM's port back to wherever this script runs from, and prefer
           binding that tunnel to the TAILNET address only (not a public interface) — consistent
           with "nothing leaves the estate" being the entire point of Tier 1.
        5. Pass that forwarded LiteLLM address as `-LmStudioW365Base 'http://<tailnet-addr>:<port>/v1'`
           (or set it as the script's default once it is confirmed stable — not done here, since an
           unverified address must never become a silent default).
        6. Confirm with `Invoke-KritOffload -StatusOnly` — the `lmstudio-w365 (Cloud PC)` row must
           read `RUNNING-AND-ANSWERING` before relying on `-Route auto` or `-Route lmstudio-w365`
           for anything. Until then it correctly reports `NOT-CONFIGURED` (no base given) or
           `UNREACHABLE-OR-STOPPED` (base given, port closed) — both are HONEST, not failures of
           this script.

    TIER 2 (overflow, NON-sensitive payloads ONLY, ONLY after the egress scan passes) —
      the canonical `kritical-litellm-router` Docker container on the LAPTOP,
      http://127.0.0.1:4000/v1 (see docker-compose.yml at Kritical.AgenticDevelopment\docker\).
      🔴 CORRECTED 2026-08-02 (operator: "so you get it fucking working on our own tokens as
      well"): a prior doc (OFFLOAD-CAPACITY-AND-ROUTING-20260802.md) claimed this route was
      "LIVE via Docker LiteLLM container, verified via `docker ps` (Up, healthy)". **That was
      FALSE.** Measured live 2026-08-02: `docker version` fails — `open
      //./pipe/dockerDesktopLinuxEngine: The system cannot find the file specified` — the
      Docker daemon is not running, so this Tier-2-via-Docker path has never actually been
      reachable. This helper does NOT start Docker and does not depend on it. Kept in the code
      (Test-KritOffloadRouteReachable still probes $HostedProxyBase) purely as an optional path
      IF a lane later brings the container up — it is not required and is not the primary path.
      🔴 NEVER request model `kritical-coding` or `kritical-scx` or anything named
      `kritical-thegrid*` through this helper — see the hard guard below.

    TIER 2b (the REAL working overflow path, added 2026-08-02 — DIRECT HTTPS, NO Docker, NO
      LiteLLM, NO localhost proxy of any kind. Fewer moving parts than a container we would
      have to keep alive). Each provider is called on its OWN vendor endpoint with its OWN
      per-service credential (per-service isolation, never cross-wired):
        - `nvidia-direct`     -> https://integrate.api.nvidia.com/v1/chat/completions
                                 model `nvidia/nvidia-nemotron-nano-9b-v2`, key
                                 KRITICAL_NVIDIA_API_KEY. PROVEN LIVE 2026-08-02: HTTP 200, real
                                 completion text, `finish_reason=stop`. Nemotron is a
                                 reasoning-capable model — it spends real completion tokens on
                                 a hidden `reasoning`/`reasoning_content` field before the
                                 visible answer (measured: 20-token budget came back EMPTY,
                                 200-token budget returned "OK" content plus ~90 completion
                                 tokens of reasoning). Give it real headroom (200+ tokens) or a
                                 short reply will look like a dead route when it is not.
                                 **THIS IS THE DEFAULT** — proven most reliable, so `-Route auto`
                                 tries this first among the hosted tiers.
        - `openrouter-direct` -> https://openrouter.ai/api/v1/chat/completions, key
                                 KRITICAL_OPENROUTER_API_KEY. Model id is NOT hardcoded from
                                 memory — `Test-KritOffloadDirectProviderStatus` (and the
                                 one-off discovery command in the routing doc) queries
                                 `GET https://openrouter.ai/api/v1/models` live and the model
                                 used here, `openai/gpt-oss-20b:free`, was picked from that live
                                 response 2026-08-02 and PROVEN with a real completion (HTTP 200,
                                 content "OK", `cost:0`). The previously-assumed
                                 `kritical-openrouter`/whatever free model id had NEVER been
                                 verified against the live catalogue — that was the actual bug
                                 behind the operator's measured 404, not an auth problem (the key
                                 itself was always fine — `/models` returned 200 the whole time).
                                 OpenRouter's shared free pool CAN return 429 (measured live on
                                 `google/gemma-4-31b-it:free` the same session) — that is a rate
                                 limit, not a dead route; a caller seeing 429 should NOT conclude
                                 OpenRouter is down, just that this specific free model's shared
                                 quota is busy right now.
        - `mistral-direct`    -> https://api.mistral.ai/v1/chat/completions, key
                                 KRITICAL_MISTRAL_API_KEY. 🔴 CONFIRMED DEGRADED, not removed:
                                 `GET https://api.mistral.ai/v1/models` returns HTTP 401 with the
                                 CURRENT key, measured live 2026-08-02. This is an authentication
                                 failure at the vendor, not a bug in this script and not
                                 something prompt quality can fix. Per operator instruction the
                                 env var `KRITICAL_MISTRAL_API_KEY` is LEFT UNTOUCHED — replacing
                                 a rejected key is the operator's action at console.mistral.ai,
                                 never this script's. `Test-KritOffloadDirectProviderStatus`
                                 distinguishes DEGRADED (401 — key rejected, listed and skipped
                                 with a named reason) from UNREACHABLE (network/timeout) so a
                                 caller never has to guess which failure mode this is.
      Each direct-provider route is probed live (`Test-KritOffloadDirectProviderStatus`, a GET
      against the provider's own `/models` endpoint, ~8s timeout) before being resolved or
      offered as an `auto` candidate — never assumed reachable from a cached belief.

    NEVER thegrid.ai in any form. DISABLED-BY-BUDGET (operator, 2026-08-01: "$0.50 remaining").
      🔴 THE HARD GUARD THIS FILE ENFORCES, NOT JUST DOCUMENTS: the canonical container's own
      config (Kritical.AgenticDevelopment\config\litellm-proxy-config.yaml) makes `kritical-coding`
      a load-balanced group whose PRIMARY (order:1) deployment IS thegrid — calling it spends the
      remaining budget. Separately, `kritical-scx`'s OWN configured fallback chain begins
      `["kritical-thegrid", ...]`, and SCX is independently known-broken (402 insufficient
      credit, verified 2026-08-01 direct against api.scx.ai) — so calling `kritical-scx` fails
      immediately and cascades straight into thegrid. This helper's -ValidateSet on -Route
      physically does not include 'kritical-coding' or 'kritical-scx' or any thegrid alias, so a
      typo cannot reach them. Do not widen that set without re-reading
      config/litellm-proxy-config.yaml's `fallbacks:` block first.

    TIER 3 (OPTIONAL, tunnel-down fallback ONLY — NOT implemented by this script, NOT installed)
      A small quantised local model ON THE LAPTOP. Documented, not built: the laptop
      (`stacktrace`) is a FANLESS ARM64 machine that has already crashed TWICE in one day under
      agent load with C: as low as 0.5% free. Local inference there is thermally throttled by
      design — this tier is for trivial one-off tasks when the tunnel is down, not a working bulk
      tier, and routing real bulk work there would reproduce the exact failure mode that already
      cost two crashes. If ever built: a small (~1-3B parameter) quantised GGUF model via
      llama.cpp or Ollama, never anything that keeps the CPU/GPU pegged for minutes.

  🔴 SENSITIVE PAYLOADS NEVER GO TO A HOSTED PROVIDER. If -Sensitive is set and Tier 1 (LM
  Studio) is not reachable, this REFUSES the send outright (throws) rather than silently
  downgrading to Tier 2 or Tier 3. "LM Studio unreachable on W365, tunnel not up" is the correct,
  useful failure — a silent downgrade is exactly how sensitive data would end up at a hosted
  provider, or how a weak local model would end up doing work the operator believes was done
  properly. See Invoke-KritOffload.test.ps1 for the proof this actually refuses.

  🔴 EGRESS REVIEW IS BUILT IN, NOT LEFT TO THE CALLER (operator, 2026-08-01: "check what the
  fuck it is we send before sending requests externally"). Every non-sensitive payload destined
  for Tier 2 (hosted) is scanned for credential-shaped strings and a denylist of sensitive-topic
  markers before it leaves this machine. A match REFUSES the send — fail closed, never
  send-and-warn. Tier 1 (LM Studio) sends are not scanned for refusal purposes (nothing leaves
  the estate), but are still logged the same way for one consistent audit trail.

  Every outbound payload — sent or refused — is written to a local JSONL audit log FIRST, with
  any credential-shaped span already replaced by "[REDACTED:<rule>]" before it ever touches
  disk. See -LogDir. The log is the answer to "what did we actually send, and when."

  PREFER A SPECIFICATION OVER SOURCE. The egress-safest and cheapest prompt is "write tests for
  a function with this signature and these behaviours," not "here is my file, fix it." If a
  Tier-2 payload looks like a large block of raw source (heuristic, not a hard gate), this prints
  a warning recommending you send a spec instead — it does not block the send, because sometimes
  source really is the right thing to send (and only after the egress scan already cleared it of
  anything credential-shaped).

  ALREADY-DONE-WORK TRAP. Before offloading, check the work is not already built (this estate's
  single largest documented waste is re-deriving something that already exists). -OutFile refuses
  to overwrite an existing non-empty file unless -Force is passed — a mechanical last line, not a
  substitute for actually checking git log / FINDINGS-REGISTER / the component index first.

.PARAMETER Prompt
  The user-turn content to send. For Tier 2, prefer a SPECIFICATION (signature + expected
  behaviour + one worked example) over pasting real source — see DESCRIPTION.

.PARAMETER System
  Optional system prompt. Mistral is currently broken (401) regardless of prompting — but for
  ANY model routed through Tier 2, weak/free models need strong, explicit prompting to be
  usable (operator, 2026-08-01, re: Codestral: "had no fucking idea" on a vague brief). Always
  set -System with an explicit output format + complete context + ONE narrow task. See the HOWTO
  doc for the worked pattern.

.PARAMETER Sensitive
  Marks the payload as containing (or possibly containing) material that must never leave the
  estate: credentials, HireGummy legal-matter data, real customer/merchant/PII/backup content, or
  anything from the frozen KRTPax8ToShopifyConnector mega-repo. Forces Tier 1 (LM Studio) as the
  ONLY allowed destination. If Tier 1 is unreachable, this REFUSES rather than falling back.

.PARAMETER Route
  'auto' (default) | 'lmstudio-local' | 'lmstudio-w365' | 'lmstudio' (legacy synonym for
  'lmstudio-local') | 'kritical-openrouter' | 'kritical-nvidia' | 'kritical-mistral' |
  'nvidia-direct' | 'openrouter-direct' | 'mistral-direct'.
  'auto' tries LM Studio local (Tier 1) first, then LM Studio W365 (also Tier 1, same
  data-locality guarantee) if configured and local is unreachable, then falls to
  'kritical-openrouter' on the hosted container (the Tier-2 route proven reliable as of
  2026-08-01 — see the HOWTO doc's per-route PASS/FAIL table before relying on kritical-mistral).
  'kritical-coding', 'kritical-scx', and any 'kritical-thegrid*' name are DELIBERATELY NOT in this
  set — see the thegrid-budget guard above.
  An EXPLICIT route is honoured exactly — if it is unreachable this errors rather than silently
  substituting another route, because the caller asked for a specific model for a reason.
  🔴 'lmstudio-w365' with no -LmStudioW365Base configured REFUSES FAST with a NOT-CONFIGURED
  message — it never attempts a network call against a guessed address, and 'auto' never treats
  an unconfigured W365 leg as "reachable" (silently skips it, does not hang waiting on it).

.PARAMETER DryRun
  Show EXACTLY what would be sent (resolved route + the redacted payload + the audit-log entry
  that would be written) WITHOUT sending it or writing the "sent" log entry. Native -WhatIf also
  works (CmdletBinding SupportsShouldProcess).

.PARAMETER OutFile
  Optional. If given and the file already exists with real content, this REFUSES to overwrite
  unless -Force is passed — see the ALREADY-DONE-WORK TRAP above.

.PARAMETER Force
  Overwrite -OutFile even if it already has content.

.PARAMETER MaxTokens
  Response token budget. WARNING (measured 2026-08-01): free-tier / reasoning-capable models
  (OpenRouter free pool, Nemotron) spend real tokens on hidden reasoning before the visible
  answer — a 10-token budget came back EMPTY or truncated mid-thought on both openrouter-free and
  the NVIDIA Nemotron lane. 60-80 tokens was enough for a one-word answer in testing; give
  structured-output or multi-sentence asks real headroom (300+). Do not treat a low-budget
  empty/truncated response as "the route is down" — it may just be starved.

.PARAMETER LmStudioBase
  Tier 1 endpoint — THIS LAPTOP's local LM Studio (`-Route lmstudio-local`, or the legacy
  `-Route lmstudio` name kept as a synonym for it). Default http://127.0.0.1:1234/v1. Verified
  live 2026-08-02: INSTALLED-NOT-RUNNING on this machine (binary + 37GB/4 models present, port
  closed).

.PARAMETER LmStudioW365Base
  🔴 ADDED 2026-08-02 (operator: "AND OR TO LM STUDIO @W365BOX" — mechanical bulk should also be
  routable to LM Studio on the W365 Cloud PC, not just this laptop). Tier 1 endpoint for the
  SEPARATE machine — `-Route lmstudio-w365`. Default is EMPTY STRING, deliberately: no tailnet/
  tunnel address for the W365 box's LiteLLM-fronted LM Studio has been verified reachable as of
  this session (last measured 2026-08-01: ports 22/5986/1234 all closed, LM Studio "Status:
  Stopped"), and a sibling lane declined to re-check it live because doing so would require
  entering a stored credential to open a remote session — prohibited regardless of authorisation.
  **This param is therefore UNKNOWN-by-default, not guessed.** Supply the real forwarded-LiteLLM
  address once the operator brings it up (see the OPERATOR-ONLY section in this script's own
  README/docs entry for exactly what he needs to do). An empty value means `-Route lmstudio-w365`
  and the W365 row in `-StatusOnly` both report NOT-CONFIGURED without attempting any network call
  — fail fast, never hang on a guessed address. Same rule as LmStudioBase: tunnel LiteLLM's port,
  never LM Studio's 1234 directly, so GPU inference traffic never crosses the tunnel itself.

.PARAMETER HostedProxyBase
  Tier 2 endpoint. Default http://127.0.0.1:4000/v1/chat/completions — the canonical
  `kritical-litellm-router` Docker container on the laptop.

.PARAMETER HostedProxyKey
  Tier 2 auth. Default: read from the SAME sanctioned local file the container's own starter
  script (Start-KriticalLitellmProxyDocker.ps1) generates/reads —
  Kritical.AgenticDevelopment\.kritical\litellm-proxy-master-key.txt. This is a LOCAL,
  auto-generated, loopback-only secret (not a vendor credential); it is never printed by this
  script. Override with -HostedProxyKey if calling a differently-configured proxy.

.PARAMETER Raw
  Return the full result object (Route/ReportedModel/Content/FinishReason/Usage/Sent/AuditLogPath)
  instead of just the text.

.PARAMETER StatusOnly
  Report the LIVE state of every provider (LM Studio local-or-tunneled, nvidia-direct,
  openrouter-direct, mistral-direct, and the Docker-hosted Tier 2) and return WITHOUT sending
  anything and WITHOUT requiring -Prompt. LM Studio's state is reported honestly as one of
  NOT-INSTALLED / INSTALLED-NOT-RUNNING / RUNNING-AND-ANSWERING, plus the exact one-line
  operator command to start it — this switch NEVER starts anything itself.

.PARAMETER Purpose
  🔴 THE JUDGEMENT-WORK REFUSAL BOUNDARY, BUILT INTO THE TOOL — not just documented (operator,
  2026-08-02: "Offloaded and local models are a HAIKU-TIER SUBSTITUTE ONLY — NEVER a gate
  verdict, NEVER an adversarial refutation... Build that boundary into the tool itself — a
  mode/parameter that refuses judgement work, not just a line in a doc."). Every call declares
  WHY it is offloading. Default 'bulk-text' (mechanical/first-draft work — always allowed).
  Passing 'gate-verdict', 'adversarial-refutation', 'correctness-decision', or 'judgement' makes
  this function THROW UNCONDITIONALLY before any route resolution, egress scan, or network call
  — a caller cannot route around this by picking a different -Route. See
  Invoke-KritOffload.test.ps1 case 'purpose-refuses-judgement-work' for the RED proof.

.PARAMETER NvidiaApiKey
  Override for the NVIDIA direct-HTTPS route's credential. Default: reads
  $env:KRITICAL_NVIDIA_API_KEY by NAME (never hardcoded, never logged). Exists so tests can
  inject a deliberately-invalid key WITHOUT touching the real environment variable — see the
  'direct-provider-invalid-key-fails-loud' proof in the test file.

.PARAMETER OpenRouterApiKey
  Same pattern as -NvidiaApiKey, for the openrouter-direct route. Default: $env:KRITICAL_OPENROUTER_API_KEY.

.PARAMETER MistralApiKey
  Same pattern, for the mistral-direct route. Default: $env:KRITICAL_MISTRAL_API_KEY. NOTE: this
  route is measured DEGRADED (401 at api.mistral.ai/v1/models, live 2026-08-02) — the default
  env var is intentionally never modified by this script; only a caller's own test harness
  should ever pass an override here.

.EXAMPLE
  # Non-sensitive bulk doc generation, auto-routed (LM Studio if up, else direct HTTPS NVIDIA,
  # then direct HTTPS OpenRouter — no Docker involved anywhere in this chain):
  Invoke-KritOffload -Prompt "Write 5 Pester test case DESCRIPTIONS (titles only, one per line) for a function that validates a Shopify webhook HMAC." -MaxTokens 300

.EXAMPLE
  # Explicit direct-HTTPS route, strong prompting pattern (needed for weak/free models):
  Invoke-KritOffload -Route openrouter-direct -System "Output ONLY a PowerShell function body, no prose, no markdown fences." -Prompt "..." -MaxTokens 400

.EXAMPLE
  # Sensitive payload — Tier 1 ONLY, refuses if the tunnel isn't up:
  Invoke-KritOffload -Sensitive -Prompt "..."

.EXAMPLE
  # See exactly what would be sent, without sending it:
  Invoke-KritOffload -Prompt "..." -DryRun

.EXAMPLE
  # This THROWS immediately, before any network call — judgement work is refused by design:
  Invoke-KritOffload -Prompt "Is this fix correct?" -Purpose gate-verdict
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Prompt,
    [switch]$StatusOnly,
    [string]$System,
    [switch]$Sensitive,
    [ValidateSet('auto','lmstudio','lmstudio-local','lmstudio-w365','kritical-openrouter','kritical-nvidia','kritical-mistral','nvidia-direct','openrouter-direct','mistral-direct')]
    [string]$Route = 'auto',
    [ValidateSet('bulk-text','scan','inventory','draft','boilerplate','judgement','gate-verdict','adversarial-refutation','correctness-decision')]
    [string]$Purpose = 'bulk-text',
    [switch]$DryRun,
    [string]$OutFile,
    [switch]$Force,
    [int]$MaxTokens = 512,
    [double]$Temperature = 0,
    [string]$LmStudioBase = 'http://127.0.0.1:1234/v1',
    [string]$LmStudioW365Base = '',
    [string]$HostedProxyBase = 'http://127.0.0.1:4000/v1/chat/completions',
    [string]$HostedProxyKeyFile = 'C:\Users\joshl\OneDrive - Kritical Pty Ltd\Github\Kritical.AgenticDevelopment\.kritical\litellm-proxy-master-key.txt',
    [string]$NvidiaApiKey,
    [string]$OpenRouterApiKey,
    [string]$MistralApiKey,
    [string]$HostedProxyKey,
    [switch]$Raw,
    [string]$LogDir = (Join-Path $env:USERPROFILE '.claude\process-harness\logs\offload-egress')
)
$ErrorActionPreference = 'Stop'

# NEVER include thegrid or the two routes that lead to it here, no matter what future callers
# ask for. See the "thegrid-budget guard" in the comment-based help above.
$script:KritOffloadForbiddenRoutes = @('kritical-coding','kritical-scx','kritical-thegrid','kritical-thegrid-prime','kritical-thegrid-standard','kritical-thegrid-text-max','kritical-thegrid-text-prime','kritical-thegrid-text-standard','kritical-thegrid-agent-max','kritical-thegrid-agent-prime','kritical-thegrid-agent-standard','kritical-thegrid-claude-opus','kritical-thegrid-gpt-sol','kritical-thegrid-gemini-pro','kritical-thegrid-kimi','kritical-thegrid-deepseek-pro','kritical-thegrid-glm','kritical-thegrid-minimax','kritical-thegrid-bytedance-pro')
if ($script:KritOffloadForbiddenRoutes -contains $Route) {
    throw "Invoke-KritOffload: -Route '$Route' is on the thegrid-budget denylist (thegrid has ~`$0.50 remaining) and is refused unconditionally, regardless of caller intent."
}

# ============================================================================
# 🔴 JUDGEMENT-WORK REFUSAL — THE BOUNDARY LIVES IN THE TOOL, NOT JUST A DOC.
# Operator, 2026-08-02: "Build that boundary into the tool itself — a mode/parameter that
# refuses judgement work, not just a line in a doc." This check runs BEFORE route resolution,
# BEFORE the egress scan, BEFORE any network call — no -Route can route around it, and no
# future caller can "just this once" bypass it by picking a different provider.
# ============================================================================
$script:KritOffloadForbiddenPurposes = @('judgement','gate-verdict','adversarial-refutation','correctness-decision')
if ($script:KritOffloadForbiddenPurposes -contains $Purpose) {
    throw "Invoke-KritOffload REFUSED: -Purpose '$Purpose' is judgement work. Offloaded/local models are a HAIKU-TIER SUBSTITUTE ONLY (bulk text, scanning, first drafts) — NEVER a gate verdict, NEVER an adversarial refutation. An offload lane quietly issuing verdicts would silently strip the verification layer off the whole program. This call is refused unconditionally, before any route was resolved or any network call was made. Use Sonnet/Opus (or the operator) for this decision."
}

# ============================================================================
# EGRESS SCAN — credential-shaped strings + sensitive-topic denylist.
# FAIL CLOSED: any match => Safe=$false. Never "send and warn."
# ============================================================================
$script:KritOffloadEgressRules = [ordered]@{
    'shopify-token'        = '(?i)\bshp(at|ss|ca|pa)_[a-f0-9]{16,}\b'
    'azure-account-key'    = '(?i)\bAccountKey\s*=\s*[A-Za-z0-9+/=]{20,}'
    'azure-sas-sig'        = '(?i)[?&]sig=[A-Za-z0-9%._-]{16,}'
    'azure-conn-string'    = '(?i)\bDefaultEndpointsProtocol\s*=\s*https?'
    'sql-conn-string'      = '(?i)(Server|Data Source)\s*=\s*[^;]+;.*(Password|Pwd)\s*=\s*[^;]+'
    'pem-private-key'      = '-----BEGIN\s+((RSA|EC|OPENSSH|DSA)\s+)?PRIVATE KEY-----'
    'jwt-bearer'           = '(?i)Bearer\s+eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'
    'aws-access-key-id'    = '\bAKIA[0-9A-Z]{16}\b'
    'anthropic-key'        = '(?i)\bsk-ant-[A-Za-z0-9_-]{20,}\b'
    'openai-shaped-key'    = '(?i)\bsk-[A-Za-z0-9]{20,}\b'
    'generic-secret-assign'= '(?i)\b(api[_-]?key|secret|token|password|passwd|client[_-]?secret)\b\s*[:=]\s*[''"]?[A-Za-z0-9/_\-\.\+]{16,}[''"]?'
    'topic-hiregummy'      = '(?i)\bhiregummy\b'
    'topic-frozen-megarepo'= '(?i)\bKRTPax8ToShopifyConnector\b'
}

function Test-KritOffloadEgressSafe {
    <#
      .SYNOPSIS
        Scan text for credential-shaped strings and sensitive-topic markers. Returns
        Safe=$false + Reasons (rule names only — never the matched substring, so a caller
        printing Reasons can never leak the very thing it is refusing) if anything matches.
        Also returns Redacted — the input with every match replaced by [REDACTED:<rule>].
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $reasons = New-Object System.Collections.Generic.List[string]
    $redacted = $Text
    foreach ($ruleName in $script:KritOffloadEgressRules.Keys) {
        $pattern = $script:KritOffloadEgressRules[$ruleName]
        if ($redacted -match $pattern) {
            $reasons.Add($ruleName)
            $redacted = [regex]::Replace($redacted, $pattern, "[REDACTED:$ruleName]")
        }
    }
    [pscustomobject]@{
        Safe     = ($reasons.Count -eq 0)
        Reasons  = @($reasons)
        Redacted = $redacted
    }
}

function Test-KritOffloadRouteReachable {
    <#
      .SYNOPSIS
        TCP-probe a route's host:port with a short timeout. Never throws — returns $false on
        any failure (closed port, no route, DNS failure, timeout). FAIL CLOSED means "unreachable"
        is the safe default answer, not an exception that a caller might swallow into "assume ok."

      .NOTES
        🔴 BUG FOUND + FIXED 2026-08-01 (offline proof test on the sibling W365 health-check
        function found this first — same pattern, fixed here too): TcpClient.Close() on a socket
        with a PENDING BeginConnect can BLOCK for the OS-level connect timeout (~21s on Windows)
        against a BLACK-HOLED target (packets silently dropped — e.g. a stalled tunnel or a
        tailnet ACL that drops rather than refuses), defeating -TimeoutMs entirely. Reproduced
        live against a non-routable address: >30s instead of the intended ~1.5s. FIX: on timeout,
        abandon the handle rather than Close()/Dispose() it synchronously — the finalizer absorbs
        the block later, off this thread.
    #>
    param([Parameter(Mandatory)][string]$BaseUrl, [int]$TimeoutMs = 1500)
    try {
        $u = [uri]$BaseUrl
        $tcp = New-Object System.Net.Sockets.TcpClient
        $iar = $tcp.BeginConnect($u.Host, $u.Port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne($TimeoutMs)
        if ($ok -and $tcp.Connected) {
            try { $tcp.EndConnect($iar) } catch { }
            $tcp.Close()
            return $true
        }
        # Do NOT Close()/Dispose() here on the timeout path — see the BUG note above.
        return $false
    } catch {
        return $false
    }
}

function Write-KritOffloadAuditLog {
    <#
      .SYNOPSIS
        Append one JSONL row to the local egress audit log. ALWAYS writes the REDACTED payload,
        never the raw one — so the log itself can never become the leak.
    #>
    param(
        [Parameter(Mandatory)][string]$LogDir,
        [Parameter(Mandatory)][hashtable]$Entry
    )
    if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
    $day = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
    $path = Join-Path $LogDir "offload-egress-$day.jsonl"
    $row = [ordered]@{ timestampUtc = (Get-Date).ToUniversalTime().ToString('o') }
    foreach ($k in $Entry.Keys) { $row[$k] = $Entry[$k] }
    ($row | ConvertTo-Json -Compress -Depth 8) | Add-Content -LiteralPath $path -Encoding utf8
    return $path
}

# ============================================================================
# 🔴 TIER 2b — DIRECT HTTPS PROVIDER REGISTRY. No Docker. No LiteLLM. No localhost proxy.
# Added 2026-08-02 (operator: "so you get it fucking working on our own tokens as well").
# Each provider's model list is a FALLTHROUGH CANDIDATE ORDER, not a single hardcoded id —
# "silent success is failure": a live model can return HTTP 200 with EMPTY content (measured
# 2026-08-02 on nvidia/nemotron-nano-9b-v2:free via OpenRouter — 200 OK, completion_tokens
# spent, content = ""), so Invoke-KritOffloadDirectProviderCall walks the list and only accepts
# a response with real non-empty content, moving to the next candidate otherwise.
# ============================================================================
$script:KritOffloadDirectProviders = [ordered]@{
    'nvidia-direct'     = [ordered]@{
        ChatUrl   = 'https://integrate.api.nvidia.com/v1/chat/completions'
        ModelsUrl = 'https://integrate.api.nvidia.com/v1/models'
        KeyEnvVar = 'KRITICAL_NVIDIA_API_KEY'
        # PROVEN LIVE 2026-08-02: HTTP 200, real non-empty content "OK", finish_reason=stop
        # (needs >=200 max_tokens — this is a reasoning model; it burns tokens on a hidden
        # `reasoning`/`reasoning_content` field before the visible answer).
        Models    = @('nvidia/nvidia-nemotron-nano-9b-v2')
    }
    'openrouter-direct' = [ordered]@{
        ChatUrl   = 'https://openrouter.ai/api/v1/chat/completions'
        ModelsUrl = 'https://openrouter.ai/api/v1/models'
        KeyEnvVar = 'KRITICAL_OPENROUTER_API_KEY'
        # Live-queried from GET /v1/models 2026-08-02 (337 models, 14 free-tier). Order matters:
        # gpt-oss-20b:free and ling-3.0-flash:free were BOTH proven live with real non-empty
        # content this session. gemma-4-31b-it:free is a real free-tier id but was measured
        # HTTP 429 (shared-pool rate limit) twice in a row the same session — kept as a further
        # fallback candidate, not first, because "proven reachable right now" beats "believed
        # cheapest" for a tool whose whole job is actually sending the request.
        Models    = @('openai/gpt-oss-20b:free', 'inclusionai/ling-3.0-flash:free', 'google/gemma-4-31b-it:free')
    }
    'mistral-direct'    = [ordered]@{
        ChatUrl   = 'https://api.mistral.ai/v1/chat/completions'
        ModelsUrl = 'https://api.mistral.ai/v1/models'
        KeyEnvVar = 'KRITICAL_MISTRAL_API_KEY'
        # 🔴 DEGRADED, not removed: GET /v1/models returns HTTP 401 with the CURRENT key,
        # measured live 2026-08-02. Never touch $env:KRITICAL_MISTRAL_API_KEY from this script —
        # replacing a rejected key is the operator's action at console.mistral.ai.
        Models    = @('mistral-small-latest')
    }
}

function Resolve-KritOffloadProviderKey {
    <# .SYNOPSIS  Resolve a direct-provider's API key: explicit override param wins (so tests
       can inject an invalid key without touching the real env var), else $env:<KeyEnvVar> by
       NAME (never hardcoded, never logged, never rendered). Returns $null if neither is set. #>
    param([Parameter(Mandatory)][string]$KeyEnvVar, [string]$OverrideKey)
    if ($OverrideKey) { return $OverrideKey }
    return [Environment]::GetEnvironmentVariable($KeyEnvVar)
}

function Test-KritOffloadDirectProviderStatus {
    <#
      .SYNOPSIS
        Live GET against a direct provider's own /models endpoint with its own key. Never
        throws. Distinguishes three outcomes so a caller never has to guess which failure mode
        it hit:
          Status='OK'          -> HTTP 200, key accepted, safe to route a completion here
          Status='DEGRADED'    -> HTTP 401/403, key REJECTED (e.g. Mistral, live 2026-08-02) —
                                   named explicitly, never confused with "unreachable"
          Status='UNREACHABLE' -> no key configured, DNS/network failure, or timeout
      .NOTES
        This is a LIVE probe, not a cached belief — RULE ZERO / "verify before repeating": the
        estate has already shipped a false "Docker LiteLLM is Up (healthy)" claim once
        (corrected 2026-08-02) precisely because a status was asserted instead of measured.
    #>
    param(
        [Parameter(Mandatory)][string]$ModelsUrl,
        [Parameter(Mandatory)][string]$KeyEnvVar,
        [string]$OverrideKey,
        [int]$TimeoutSec = 8
    )
    $key = Resolve-KritOffloadProviderKey -KeyEnvVar $KeyEnvVar -OverrideKey $OverrideKey
    if (-not $key) {
        return [pscustomobject]@{ Status = 'UNREACHABLE'; Reason = "no key resolved (checked override param and `$env:$KeyEnvVar)" }
    }
    try {
        $null = Invoke-WebRequest -Uri $ModelsUrl -Method Get -Headers @{ Authorization = "Bearer $key" } -TimeoutSec $TimeoutSec -ErrorAction Stop
        return [pscustomobject]@{ Status = 'OK'; Reason = 'GET /models returned HTTP 200' }
    } catch {
        $resp = $_.Exception.Response
        $code = 0
        if ($resp -and $resp.StatusCode) { $code = [int]$resp.StatusCode }
        if ($code -eq 401 -or $code -eq 403) {
            return [pscustomobject]@{ Status = 'DEGRADED'; Reason = "GET /models returned HTTP $code — key REJECTED by the vendor (not a network problem; do not retry, do not touch the env var, operator must replace the key)" }
        }
        return [pscustomobject]@{ Status = 'UNREACHABLE'; Reason = "GET /models failed: $($_.Exception.Message)" }
    }
}

function script:Invoke-KritOffloadDirectProviderCall {
    <#
      .SYNOPSIS
        Send one completion directly to a provider's own HTTPS endpoint (no Docker, no
        LiteLLM, no localhost proxy) walking its ordered Models fallthrough list. Accepts the
        first candidate that returns HTTP 200 AND non-empty content — "silent success is
        failure": a 200 with an empty body is treated as a miss, not a pass, and the next
        candidate is tried.
    #>
    param(
        [Parameter(Mandatory)][string]$ProviderRoute,
        [Parameter(Mandatory)][string]$Prompt,
        [string]$System,
        [int]$MaxTokens,
        [double]$Temperature,
        [string]$OverrideKey,
        [int]$TimeoutSec = 90
    )
    $cfg = $script:KritOffloadDirectProviders[$ProviderRoute]
    if (-not $cfg) { throw "Invoke-KritOffloadDirectProviderCall: unknown provider route '$ProviderRoute'." }
    $key = Resolve-KritOffloadProviderKey -KeyEnvVar $cfg.KeyEnvVar -OverrideKey $OverrideKey
    if (-not $key) { throw "Invoke-KritOffloadDirectProviderCall: no key resolved for '$ProviderRoute' (checked override and `$env:$($cfg.KeyEnvVar))." }

    $messages = @()
    if ($System) { $messages += @{ role = 'system'; content = $System } }
    $messages += @{ role = 'user'; content = $Prompt }

    $attempts = New-Object System.Collections.Generic.List[string]
    foreach ($model in $cfg.Models) {
        $body = @{ model = $model; messages = $messages; max_tokens = $MaxTokens; temperature = $Temperature } | ConvertTo-Json -Depth 8
        try {
            $r = Invoke-RestMethod -Uri $cfg.ChatUrl -Method Post -TimeoutSec $TimeoutSec -Headers @{ Authorization = "Bearer $key" } -ContentType 'application/json' -Body $body
            $content = [string]$r.choices[0].message.content
            if ([string]::IsNullOrWhiteSpace($content)) {
                $attempts.Add("$model -> HTTP 200 but EMPTY content (reasoning-only or starved token budget) — trying next candidate")
                continue
            }
            return [pscustomobject]@{
                ReportedModel  = $model
                Content        = $content
                FinishReason   = $r.choices[0].finish_reason
                Usage          = $r.usage
                AttemptedFirst = ($model -eq $cfg.Models[0])
                Attempts       = @($attempts)
            }
        } catch {
            $attempts.Add("$model -> FAILED: $($_.Exception.Message)")
        }
    }
    throw "Invoke-KritOffloadDirectProviderCall: ALL candidates for '$ProviderRoute' failed or returned empty content. Attempts: $($attempts -join ' | ')"
}

function script:Invoke-KritOffloadHostedCall {
    param([string]$Model, [string]$Prompt, [string]$System, [int]$MaxTokens, [double]$Temperature,
          [string]$Base, [string]$Key)
    $messages = @()
    if ($System) { $messages += @{ role = 'system'; content = $System } }
    $messages += @{ role = 'user'; content = $Prompt }
    $body = @{ model = $Model; messages = $messages; max_tokens = $MaxTokens; temperature = $Temperature } | ConvertTo-Json -Depth 8
    $r = Invoke-RestMethod -Uri $Base -Method Post -TimeoutSec 120 -Headers @{ Authorization = "Bearer $Key" } -ContentType 'application/json' -Body $body
    [pscustomobject]@{
        ReportedModel = $r.model
        Content       = [string]$r.choices[0].message.content
        FinishReason  = $r.choices[0].finish_reason
        Usage         = $r.usage
    }
}

function script:Invoke-KritOffloadLmStudioCall {
    param([string]$Prompt, [string]$System, [int]$MaxTokens, [double]$Temperature, [string]$Base)
    $messages = @()
    if ($System) { $messages += @{ role = 'system'; content = $System } }
    $messages += @{ role = 'user'; content = $Prompt }
    $body = @{ model = 'local-model'; messages = $messages; max_tokens = $MaxTokens; temperature = $Temperature } | ConvertTo-Json -Depth 8
    $uri = "$($Base.TrimEnd('/'))/chat/completions"
    $r = Invoke-RestMethod -Uri $uri -Method Post -TimeoutSec 300 -ContentType 'application/json' -Body $body
    $content = [string]$r.choices[0].message.content
    if ([string]::IsNullOrWhiteSpace($content)) {
        # "silent success is failure" — an OpenAI-compatible 200 with an empty message body is a
        # real observed failure mode (measured 2026-08-02 on a reasoning model via a different
        # route), never a pass. Callers of this function see FinishReason/Usage to diagnose.
        Write-Warning "Invoke-KritOffloadLmStudioCall: HTTP 200 from $uri but EMPTY content (finish_reason=$($r.choices[0].finish_reason)). Treat as a failed call, not a quiet success."
    }
    [pscustomobject]@{
        ReportedModel = $r.model
        Content       = $content
        FinishReason  = $r.choices[0].finish_reason
        Usage         = $r.usage
    }
}

function Get-KritOffloadLmStudioStatus {
    <#
      .SYNOPSIS
        Report LM Studio's HONEST three-way state — NEVER starts it, never assumes it. Distinct
        from Test-KritOffloadRouteReachable (which only answers "is something answering on this
        port"): this also tells the caller whether the binary/models are even installed when the
        port is closed, and gives the exact operator command to bring it up.
      .NOTES
        The default binary/model paths checked here are THIS operator's known install location
        (verified live 2026-08-02: C:\Users\joshl\.lmstudio\bin\lms.exe, 37 GB / 4 GGUF models
        under C:\Users\joshl\.lmstudio\models). On a different machine these paths may not exist
        even with LM Studio installed elsewhere — that reports NOT-INSTALLED-AT-DEFAULT-PATH
        honestly rather than a false NOT-INSTALLED, since this function does not scan the whole
        disk for it.
    #>
    param([string]$BaseUrl = 'http://127.0.0.1:1234/v1', [switch]$RemoteNoLocalBinaryCheck)
    # RemoteNoLocalBinaryCheck: for a REMOTE box (W365), THIS machine's C:\Users\<me>\.lmstudio\
    # binary/model presence tells you nothing about whether LM Studio is installed over there -
    # skip that (local-only) check and report binary/model fields as $null/UNKNOWN rather than a
    # false NOT-INSTALLED derived from the wrong machine's filesystem.
    if ($RemoteNoLocalBinaryCheck) {
        if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
            return [pscustomobject]@{
                State = 'NOT-CONFIGURED'; BinaryPath = $null; BinaryPresent = $null
                ModelsOnDiskCount = $null; ModelsOnDiskGB = $null; PortOpen = $false; LiveModelIds = @()
                StartCommand = ''
                Note = 'No -LmStudioW365Base was supplied - UNKNOWN whether the W365 box is reachable at all. No network call was attempted against a guessed address.'
            }
        }
        $portOpenRemote = Test-KritOffloadRouteReachable -BaseUrl $BaseUrl -TimeoutMs 1200
        $liveModelsRemote = @()
        if ($portOpenRemote) {
            try {
                $mr = Invoke-RestMethod -Uri "$($BaseUrl.TrimEnd('/'))/models" -Method Get -TimeoutSec 5
                $liveModelsRemote = @($mr.data | ForEach-Object { $_.id })
            } catch {
                Write-Verbose "Get-KritOffloadLmStudioStatus(remote): /models probe failed: $($_.Exception.Message)"
            }
        }
        return [pscustomobject]@{
            State             = if ($portOpenRemote) { 'RUNNING-AND-ANSWERING' } else { 'UNREACHABLE-OR-STOPPED' }
            BinaryPath        = $null
            BinaryPresent     = $null
            ModelsOnDiskCount = $null
            ModelsOnDiskGB    = $null
            PortOpen          = $portOpenRemote
            LiveModelIds      = $liveModelsRemote
            StartCommand      = ''
            Note              = 'Remote (W365) target - local-machine binary/model-on-disk checks do not apply; only the network probe is meaningful here.'
        }
    }
    $binaryPath = Join-Path $env:USERPROFILE '.lmstudio\bin\lms.exe'
    $modelsRoot = Join-Path $env:USERPROFILE '.lmstudio\models'
    $binaryPresent = Test-Path -LiteralPath $binaryPath
    $modelFiles = @()
    if (Test-Path -LiteralPath $modelsRoot) {
        $modelFiles = @(Get-ChildItem -LiteralPath $modelsRoot -Recurse -Filter '*.gguf' -ErrorAction SilentlyContinue)
    }
    $portOpen = Test-KritOffloadRouteReachable -BaseUrl $BaseUrl -TimeoutMs 1200

    $liveModels = @()
    if ($portOpen) {
        try {
            $mr = Invoke-RestMethod -Uri "$($BaseUrl.TrimEnd('/'))/models" -Method Get -TimeoutSec 5
            $liveModels = @($mr.data | ForEach-Object { $_.id })
        } catch {
            # Best-effort model-list enrichment only — the port is already confirmed open above,
            # so a failure here just means /models didn't answer the same way; $liveModels stays
            # empty and the caller still gets an accurate PortOpen=$true state.
            Write-Verbose "Get-KritOffloadLmStudioStatus: /models probe failed: $($_.Exception.Message)"
        }
    }

    $state = if ($portOpen) { 'RUNNING-AND-ANSWERING' }
             elseif ($binaryPresent) { 'INSTALLED-NOT-RUNNING' }
             else { 'NOT-INSTALLED-AT-DEFAULT-PATH' }

    [pscustomobject]@{
        State             = $state
        BinaryPath        = $binaryPath
        BinaryPresent     = $binaryPresent
        ModelsOnDiskCount = $modelFiles.Count
        ModelsOnDiskGB    = [math]::Round((($modelFiles | Measure-Object Length -Sum).Sum / 1GB), 1)
        PortOpen          = $portOpen
        LiveModelIds      = $liveModels
        StartCommand      = "$binaryPath server start"
        Note              = 'This function NEVER starts the server. Starting it is an operator action requiring typed ack + rehearsal per standing rule.'
    }
}

# ============================================================================
# MAIN
# ============================================================================

if ($StatusOnly) {
    $lmStatus = Get-KritOffloadLmStudioStatus -BaseUrl $LmStudioBase
    $lmW365Status = Get-KritOffloadLmStudioStatus -BaseUrl $LmStudioW365Base -RemoteNoLocalBinaryCheck
    $nvidiaStatus = Test-KritOffloadDirectProviderStatus -ModelsUrl $script:KritOffloadDirectProviders['nvidia-direct'].ModelsUrl -KeyEnvVar $script:KritOffloadDirectProviders['nvidia-direct'].KeyEnvVar -OverrideKey $NvidiaApiKey
    $orStatus = Test-KritOffloadDirectProviderStatus -ModelsUrl $script:KritOffloadDirectProviders['openrouter-direct'].ModelsUrl -KeyEnvVar $script:KritOffloadDirectProviders['openrouter-direct'].KeyEnvVar -OverrideKey $OpenRouterApiKey
    $mistralStatus = Test-KritOffloadDirectProviderStatus -ModelsUrl $script:KritOffloadDirectProviders['mistral-direct'].ModelsUrl -KeyEnvVar $script:KritOffloadDirectProviders['mistral-direct'].KeyEnvVar -OverrideKey $MistralApiKey
    $dockerReachable = Test-KritOffloadRouteReachable -BaseUrl $HostedProxyBase

    $report = @(
        [pscustomobject]@{ Provider = 'lmstudio-local (this laptop)'; State = $lmStatus.State; Detail = "binary=$($lmStatus.BinaryPresent) models=$($lmStatus.ModelsOnDiskCount)($($lmStatus.ModelsOnDiskGB)GB) port1234=$($lmStatus.PortOpen)"; StartCommand = $(if ($lmStatus.State -eq 'INSTALLED-NOT-RUNNING') { $lmStatus.StartCommand } else { '' }) }
        [pscustomobject]@{ Provider = 'lmstudio-w365 (Cloud PC)'; State = $lmW365Status.State; Detail = $(if ($lmW365Status.State -eq 'NOT-CONFIGURED') { $lmW365Status.Note } else { "port=$($lmW365Status.PortOpen) base=$LmStudioW365Base" }); StartCommand = '' }
        [pscustomobject]@{ Provider = 'nvidia-direct';     State = $nvidiaStatus.Status;  Detail = $nvidiaStatus.Reason;  StartCommand = '' }
        [pscustomobject]@{ Provider = 'openrouter-direct'; State = $orStatus.Status;      Detail = $orStatus.Reason;      StartCommand = '' }
        [pscustomobject]@{ Provider = 'mistral-direct';    State = $mistralStatus.Status; Detail = $mistralStatus.Reason; StartCommand = '' }
        [pscustomobject]@{ Provider = 'kritical-litellm-docker (Tier 2, optional)'; State = $(if ($dockerReachable) { 'REACHABLE' } else { 'UNREACHABLE (Docker daemon not required/running)' }); Detail = $HostedProxyBase; StartCommand = '' }
    )
    # Returned as objects, not printed via Write-Host (PSAvoidUsingWriteHost) — PowerShell's
    # default formatter renders this table when the caller doesn't capture the return value;
    # a caller that DOES capture it (`$s = Invoke-KritOffload -StatusOnly`) gets real objects.
    return $report
}

if ([string]::IsNullOrEmpty($Prompt)) {
    throw "Invoke-KritOffload: -Prompt is required unless -StatusOnly is set."
}

# already-done-work trap (mechanical last line, not a substitute for a real history check)
if ($OutFile -and (Test-Path -LiteralPath $OutFile) -and -not $Force) {
    $existing = Get-Item -LiteralPath $OutFile
    if ($existing.Length -gt 0) {
        throw "Invoke-KritOffload: -OutFile '$OutFile' already exists and is non-empty ($($existing.Length) bytes). " +
              "Refusing to regenerate possibly-already-done work. Check git log / FINDINGS-REGISTER first; pass -Force to overwrite deliberately."
    }
}

if (-not $HostedProxyKey) {
    if (Test-Path -LiteralPath $HostedProxyKeyFile) {
        $HostedProxyKey = (Get-Content -LiteralPath $HostedProxyKeyFile -Raw).Trim()
    }
}

$lmReachable     = Test-KritOffloadRouteReachable -BaseUrl $LmStudioBase
# Fail-fast, never guess: only probe the W365 leg at all if a real base URL was configured. An
# empty -LmStudioW365Base means "not configured" and $lmW365Reachable stays $false with zero
# network calls attempted against a made-up address.
$lmW365Reachable = if ([string]::IsNullOrWhiteSpace($LmStudioW365Base)) { $false } else { Test-KritOffloadRouteReachable -BaseUrl $LmStudioW365Base }
$hostedReachable = Test-KritOffloadRouteReachable -BaseUrl $HostedProxyBase

# ---- Tier 2b direct-HTTPS provider status (live probes, never cached beliefs) ----
# Skipped for -Sensitive: that path only ever considers Tier 1 and refuses otherwise, so these
# probes would be pure overhead (3 extra HTTPS round-trips) on the one path that can never use them.
$directStatus = @{}
if (-not $Sensitive) {
    $directStatus['nvidia-direct']     = Test-KritOffloadDirectProviderStatus -ModelsUrl $script:KritOffloadDirectProviders['nvidia-direct'].ModelsUrl     -KeyEnvVar $script:KritOffloadDirectProviders['nvidia-direct'].KeyEnvVar     -OverrideKey $NvidiaApiKey
    $directStatus['openrouter-direct'] = Test-KritOffloadDirectProviderStatus -ModelsUrl $script:KritOffloadDirectProviders['openrouter-direct'].ModelsUrl -KeyEnvVar $script:KritOffloadDirectProviders['openrouter-direct'].KeyEnvVar -OverrideKey $OpenRouterApiKey
    $directStatus['mistral-direct']    = Test-KritOffloadDirectProviderStatus -ModelsUrl $script:KritOffloadDirectProviders['mistral-direct'].ModelsUrl    -KeyEnvVar $script:KritOffloadDirectProviders['mistral-direct'].KeyEnvVar    -OverrideKey $MistralApiKey
}

# ---- resolve the route ----
$resolvedRoute = $null
$refusalReason = $null

if ($Sensitive) {
    # Both lmstudio-local and lmstudio-w365 are Tier 1 (nothing leaves the estate) - try local
    # first (fewer moving parts - no tunnel involved), then W365 if configured and local is down.
    if ($lmReachable) {
        $resolvedRoute = 'lmstudio'
    } elseif ($lmW365Reachable) {
        $resolvedRoute = 'lmstudio-w365'
    } else {
        $w365Detail = if ([string]::IsNullOrWhiteSpace($LmStudioW365Base)) { 'not configured (-LmStudioW365Base empty)' } else { "unreachable at $LmStudioW365Base" }
        $refusalReason = "SENSITIVE payload and Tier 1 (LM Studio) is UNREACHABLE - local at ${LmStudioBase}: unreachable; W365 leg: $w365Detail. " +
                          "Refusing to send — sensitive payloads are NEVER downgraded to a hosted provider."
    }
} elseif ($Route -ne 'auto') {
    if ($Route -eq 'lmstudio' -or $Route -eq 'lmstudio-local') {
        if ($lmReachable) { $resolvedRoute = 'lmstudio' }
        else { $refusalReason = "Explicit -Route $Route requested but Tier 1 (local) is UNREACHABLE at $LmStudioBase." }
    } elseif ($Route -eq 'lmstudio-w365') {
        if ([string]::IsNullOrWhiteSpace($LmStudioW365Base)) {
            $refusalReason = "Explicit -Route lmstudio-w365 requested but -LmStudioW365Base was not supplied (NOT-CONFIGURED) - no network call was attempted against a guessed address. Supply the real W365 LiteLLM-forwarded address once the operator brings that box up."
        } elseif ($lmW365Reachable) {
            $resolvedRoute = 'lmstudio-w365'
        } else {
            $refusalReason = "Explicit -Route lmstudio-w365 requested but is UNREACHABLE at $LmStudioW365Base (box/tunnel/LM Studio server not up)."
        }
    } elseif ($script:KritOffloadDirectProviders.Contains($Route)) {
        $st = $directStatus[$Route]
        if ($st.Status -eq 'OK') { $resolvedRoute = $Route }
        elseif ($st.Status -eq 'DEGRADED') { $refusalReason = "Explicit -Route $Route requested but is DEGRADED: $($st.Reason)" }
        else { $refusalReason = "Explicit -Route $Route requested but is UNREACHABLE: $($st.Reason)" }
    } else {
        if (-not $hostedReachable) {
            $refusalReason = "Explicit -Route $Route requested but the hosted LiteLLM container is UNREACHABLE at $HostedProxyBase (Docker daemon confirmed NOT RUNNING 2026-08-02 — this Tier-2-via-Docker path is not the working one; use -Route nvidia-direct or -Route openrouter-direct instead, or -Route auto)."
        } elseif (-not $HostedProxyKey) {
            $refusalReason = "Explicit -Route $Route requested but no Tier-2 auth key is available (checked -HostedProxyKey and $HostedProxyKeyFile)."
        } else {
            $resolvedRoute = $Route
        }
    }
} else {
    # auto: Tier 1 (LM Studio) -> Tier 2b DIRECT HTTPS (nvidia-direct first — proven most
    # reliable live 2026-08-02; then openrouter-direct) -> Tier 2 Docker-hosted (only if a lane
    # happens to have brought the container up) -> mistral-direct (only if not DEGRADED) ->
    # explicit FAIL LOUD. There is NO path anywhere in this function that falls back to Anthropic
    # or any other non-offload provider — total failure always throws, on purpose (operator,
    # 2026-08-02: "on total failure it must FAIL LOUDLY, never silently fall back to Anthropic —
    # that would defeat the entire point and burn the tokens this exists to save").
    if ($lmReachable) { $resolvedRoute = 'lmstudio' }
    elseif ($lmW365Reachable) { $resolvedRoute = 'lmstudio-w365' }
    elseif ($directStatus['nvidia-direct'].Status -eq 'OK') { $resolvedRoute = 'nvidia-direct' }
    elseif ($directStatus['openrouter-direct'].Status -eq 'OK') { $resolvedRoute = 'openrouter-direct' }
    elseif ($hostedReachable -and $HostedProxyKey) { $resolvedRoute = 'kritical-openrouter' }
    elseif ($directStatus['mistral-direct'].Status -eq 'OK') { $resolvedRoute = 'mistral-direct' }
    else {
        $reasons = @(
            "lmstudio-local ($LmStudioBase): unreachable"
            "lmstudio-w365: $(if ([string]::IsNullOrWhiteSpace($LmStudioW365Base)) { 'not configured' } else { "unreachable at $LmStudioW365Base" })"
            "nvidia-direct: $($directStatus['nvidia-direct'].Status) -- $($directStatus['nvidia-direct'].Reason)"
            "openrouter-direct: $($directStatus['openrouter-direct'].Status) -- $($directStatus['openrouter-direct'].Reason)"
            "kritical-litellm-docker ($HostedProxyBase): $(if ($hostedReachable) { 'reachable but no key' } else { 'unreachable (Docker daemon not running)' })"
            "mistral-direct: $($directStatus['mistral-direct'].Status) -- $($directStatus['mistral-direct'].Reason)"
        )
        $refusalReason = "NO ROUTE AVAILABLE -- every tier refused or failed. FAILING LOUDLY -- this NEVER silently falls back to Anthropic or any other provider, because that would defeat the entire point of offload and burn the tokens it exists to save. Detail: $($reasons -join ' | ')"
    }
}

# ---- egress scan (Tier 2 / hosted routes only — nothing leaves the estate via Tier 1) ----
$egress = Test-KritOffloadEgressSafe -Text ($(if ($System) { "$System`n$Prompt" } else { $Prompt }))
$isHostedRoute = ($resolvedRoute -and $resolvedRoute -ne 'lmstudio' -and $resolvedRoute -ne 'lmstudio-w365')

if (-not $refusalReason -and $isHostedRoute -and -not $egress.Safe) {
    $refusalReason = "Egress scan REFUSED this payload for hosted route '$resolvedRoute' — matched rule(s): $($egress.Reasons -join ', '). " +
                      "Fail-closed: this payload is NOT sent anywhere. If this is a false positive, rephrase as a specification instead of pasting the flagged text."
}

# "prefer a spec, not source" — soft warning only, hosted routes only, only once egress already clear
if (-not $refusalReason -and $isHostedRoute -and $egress.Safe) {
    $looksLikeSource = ($Prompt.Length -gt 1500) -and ($Prompt -match '(?m)^\s*(function |def |class |\{|\}|;\s*$)')
    if ($looksLikeSource) {
        Write-Warning "Invoke-KritOffload: this payload looks like a large block of raw source going to a HOSTED (Tier 2) route. Prefer sending a SPECIFICATION (signature + behaviour + one example) instead — it leaks far less. Proceeding because the egress scan found no credential-shaped content."
    }
}

# ---- audit log: written BEFORE any send attempt, always redacted ----
$auditBase = @{
    requestedRoute = $Route
    resolvedRoute  = $resolvedRoute
    sensitive      = [bool]$Sensitive
    lmReachable    = $lmReachable
    lmW365Reachable= $lmW365Reachable
    hostedReachable= $hostedReachable
    egressSafe     = $egress.Safe
    egressReasons  = $egress.Reasons
    promptChars    = $Prompt.Length
    promptRedacted = $egress.Redacted
    dryRun         = [bool]($DryRun -or $WhatIfPreference)
}

if ($refusalReason) {
    $auditBase['outcome'] = 'REFUSED'
    $auditBase['refusalReason'] = $refusalReason
    $logPath = Write-KritOffloadAuditLog -LogDir $LogDir -Entry $auditBase
    throw "Invoke-KritOffload REFUSED: $refusalReason (audit: $logPath)"
}

if ($DryRun -or $WhatIfPreference -or -not $PSCmdlet.ShouldProcess("route=$resolvedRoute", 'Send offload prompt')) {
    $auditBase['outcome'] = 'DRY-RUN — nothing sent'
    $logPath = Write-KritOffloadAuditLog -LogDir $LogDir -Entry $auditBase
    [pscustomobject]@{
        Route         = $resolvedRoute
        WouldSend     = $true
        Sent          = $false
        RedactedPayload = $egress.Redacted
        AuditLogPath  = $logPath
    }
    return
}

# ---- actually send ----
try {
    if ($resolvedRoute -eq 'lmstudio') {
        $result = script:Invoke-KritOffloadLmStudioCall -Prompt $Prompt -System $System -MaxTokens $MaxTokens -Temperature $Temperature -Base $LmStudioBase
    } elseif ($resolvedRoute -eq 'lmstudio-w365') {
        $result = script:Invoke-KritOffloadLmStudioCall -Prompt $Prompt -System $System -MaxTokens $MaxTokens -Temperature $Temperature -Base $LmStudioW365Base
    } elseif ($script:KritOffloadDirectProviders.Contains($resolvedRoute)) {
        $overrideKey = switch ($resolvedRoute) {
            'nvidia-direct'     { $NvidiaApiKey }
            'openrouter-direct' { $OpenRouterApiKey }
            'mistral-direct'    { $MistralApiKey }
        }
        $result = script:Invoke-KritOffloadDirectProviderCall -ProviderRoute $resolvedRoute -Prompt $Prompt -System $System -MaxTokens $MaxTokens -Temperature $Temperature -OverrideKey $overrideKey
    } else {
        $result = script:Invoke-KritOffloadHostedCall -Model $resolvedRoute -Prompt $Prompt -System $System -MaxTokens $MaxTokens -Temperature $Temperature -Base $HostedProxyBase -Key $HostedProxyKey
    }
    $auditBase['outcome']       = 'SENT'
    $auditBase['reportedModel'] = $result.ReportedModel
    $auditBase['finishReason']  = $result.FinishReason
    $auditBase['responseChars'] = $result.Content.Length
    $logPath = Write-KritOffloadAuditLog -LogDir $LogDir -Entry $auditBase

    if ($OutFile) { Set-Content -LiteralPath $OutFile -Value $result.Content -Encoding utf8 }

    $out = [pscustomobject]@{
        Route         = $resolvedRoute
        ReportedModel = $result.ReportedModel
        Content       = $result.Content
        FinishReason  = $result.FinishReason
        Usage         = $result.Usage
        Sent          = $true
        AuditLogPath  = $logPath
    }
    if ($Raw) { $out } else { $out.Content }
} catch {
    $auditBase['outcome'] = 'SEND-FAILED'
    $auditBase['error'] = $_.Exception.Message
    $logPath = Write-KritOffloadAuditLog -LogDir $LogDir -Entry $auditBase
    throw
}
