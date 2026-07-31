# Kritical.SCXCode — Project Rulebook

> Repo-scoped rulebook for `Kritical.SCXCode` (SCX-in-VS-Code + PowerShell client + MCP server + Node.js agent). Auto-loaded by Codex / Codex / any agent that opens this folder. Treat as load-bearing project context.
>
> **Companion sister rulebook**: `C:\Users\joshl\OneDrive - Kritical Pty Ltd\Github\KRTPax8ToShopifyConnector\AGENTS.md` (the Pax8↔BC↔Shopify connector — much larger, upstream HARD RULE conventions we inherit).

---

## 🚨🚨🚨🚨 HARD RULE 29 (.5184) — KRITICAL LAYERS ARE ADDITIVE, NEVER DISRUPTIVE. UNDERLYING TOOLS MUST WORK WITH OUR LAYER OFF OR AT ANY LAYER FAILING. 🚨🚨🚨🚨

> Operator (.5184 paraphrased per HR12): the operator's underlying agents
> (Codex / Codex / raw SCX / raw ChatGPT / etc) must **always** work
> whether Kritical's layer is running, degraded, or absent. Being unable
> to run Codex / codex / any operator-facing agent because of a Kritical
> layer is a HARD failure.
>
> **CONTRACT**:
>
> 1. **Additive by default.** Every Kritical layer (LiteLLM proxy,
>    AIRouter, SCXCodeAgent bridge, VS Code extension, PS module) is an
>    ADD-ON. Removing it returns the operator to a working baseline —
>    direct agent-to-API.
> 2. **Zero-config disable.** Every layer honours a single "off" switch:
>    - LiteLLM proxy: `-Mode Remove` OR not started
>    - AutoContinue module: not imported
>    - Node bridge daemon: `-Mode Remove` OR port unbind
>    - VS Code extension: uninstall the VSIX
> 3. **Zero surprise breakage.** No Kritical layer intercepts, rewrites,
>    or drops requests it does not fully understand. Passthrough default;
>    augmentation is opt-in per-endpoint.
> 4. **Provider-agnostic proxy.** LiteLLM accepts SCX + Anthropic +
>    OpenAI + generic OpenAI-compatible slots in the same config. One
>    env var flip to swap providers. Zero rewrite.
> 5. **Codex + our VS Code plugin is the primary path.** Forks
>    (`krit-scx.exe`, custom binaries) are nice-to-have. Load-bearing
>    surface = operator's existing Codex CLI + Codex CLI + our VS
>    Code extension — all pointing at LiteLLM which routes to whichever
>    provider is configured.
> 6. **Kill switch always visible.** Every install / heal / status script
>    prints the "how to fully disable this layer" line at end of
>    `-Mode Status` output.
> 7. **Applies to BOTH rulebooks + every sister repo.**
>
> **REFUSAL CONDITIONS**:
>
> - Do NOT ship a Kritical layer that mandates itself for the underlying
>   tool to work.
> - Do NOT wrap an existing tool in a way that hides its native config
>   surface.
> - Do NOT bind proxies to `0.0.0.0` — localhost only.
> - Do NOT overwrite operator env vars (`ANTHROPIC_BASE_URL` /
>   `OPENAI_BASE_URL`) — add new vars alongside.
>
> **VERIFIED "OFF" BEHAVIOUR**:
>
> | Kritical layer | "OFF" means | Underlying agent still works? |
> |---|---|---|
> | LiteLLM proxy | stopped / removed / port unbound | Codex, Codex, SCX PS module -> direct API ✓ |
> | AutoContinue module | not imported | Base `Invoke-KritScxChat` single-turn ✓ |
> | Decision logger (HR27) | `$env:KRITICAL_LOGGER_TARGET=none` | Every AI call still succeeds ✓ |
> | Node bridge daemon | port unbind / stopped | VS Code ext falls back to `directBaseUrl` ✓ |
> | VS Code extension | uninstalled | Codex + Codex + terminal unchanged ✓ |

---

## 🚨🚨🚨🚨 HARD RULE 28 (.5183) — OPERATOR METAPHORS ARE VISUAL, NOT NAMING. RENAME EVERY IDENTIFIER TO WHAT IT DOES. 🚨🚨🚨🚨

> Operator (.5183 paraphrased per HR12): the operator communicates visually.
> "Like a Ferrari" is not a naming instruction; it conveys **feel** (fast,
> effortless, refined). "smashIt" is not an identifier; it's a **verb** for
> concurrency. "Commodore 64" is not a class name; it's a **critique**. When
> visual metaphors get turned into function / module / parameter names the
> resulting code reads like inside baseball and future-me can't grep for it.
> Read metaphors for **behavioural intent**, then name the code for the
> **mechanism**.
>
> **CONTRACT**:
>
> 1. **No metaphor-derived identifiers.** No `-SmashIt` param. No
>    `Ferrari.psm1` file. No `Invoke-*Mega*` / `Invoke-*Rocket*` /
>    `Invoke-*Ninja*` functions. Every identifier answers "what does this
>    DO", not "how did the operator describe it".
> 2. **Descriptive naming rubric**:
>    - Functions: `Verb-Noun` — approved PowerShell verb + noun that
>      names the OUTPUT or TARGET
>    - Modules: `Kritical.$Product.$Concern.psm1` — Concern names the
>      responsibility (`AutoContinue`, `Router`, `Logger`, `Cache`)
>    - Parameters: describe the value's role (`-Parallel`,
>      `-MaxConcurrency`, `-TimeoutSec`) — never the operator's emotion
>      about wanting them fast/big/hard
> 3. **Metaphor rot**: existing artefacts named after operator metaphors
>    are renamed **on-sight** in the SAME commit as the discovery — files,
>    docs, cross-references, tests, AGENTS.md, memory files. No
>    "grandfather in" the old names.
> 4. **What operator metaphors ARE for**: they encode intent + feel +
>    urgency + comparison to a mental model. Read them for the
>    behavioural requirement, then name the code for the mechanism.
>    - *"Like a Ferrari"* → make it feel effortless + fast + refined →
>      mechanism: auto-continuation with dedup + natural-terminator
>      heuristic → `Invoke-KritScxAutoContinue`
>    - *"SmashIt"* → high concurrency → `-Parallel` or `-MaxConcurrency`
>    - *"Commodore 64"* → primitive/underpowered feel → augment mechanism
>      with orchestration + tools + memory
>    - *"Kill the queue"* → drain to zero → `Clear-KritQueue` /
>      `Invoke-KritQueueDrain`
>    - *"Throw it at the wall"* → parallel scattergun test → `Test-*` with
>      `-Parallel` + `-FailFast:$false`
> 5. **Applies to BOTH rulebooks**: this rule lives verbatim in
>    [../KRTPax8ToShopifyConnector/AGENTS.md](../KRTPax8ToShopifyConnector/AGENTS.md)
>    AND this file. Every new sister repo seeded from Kritical MUST carry
>    HR28 verbatim.
>
> **REFUSAL CONDITIONS**:
>
> - Do NOT ship an identifier that quotes an operator metaphor verbatim.
> - Do NOT preserve historical metaphor-named artefacts once identified —
>   rename in the SAME commit.
> - Do NOT interpret every colourful word as a naming instruction; read
>   the mechanical requirement first, name the code for that.
>
> **KNOWN HISTORICAL BREACHES + FIXES** (canonical register — extend on any new discovery):
>
> | Historical name | Renamed to | Why the old name broke HR28 |
> |---|---|---|
> | `-SmashIt` supervisor parameter | `-Parallel` / `-MaxConcurrency` | "smash it" was a concurrency verb from the operator, not an identifier |
> | `Kritical.PS.SCXCode.Ferrari.psm1` (.5182) | `Kritical.PS.SCXCode.AutoContinue.psm1` (.5183) | "Ferrari" was a feel metaphor for fast/effortless; mechanism is auto-continuation across turns |
> | `Invoke-KritScxMegaResponse` (.5182) | `Invoke-KritScxAutoContinue` (.5183) | "Mega" was a size vibe; mechanism is looped multi-turn continuation with dedup |
> | `Show-KriticalFerrariBanner` (.5182) | `Show-KriticalSCXCodeBanner` (.5183) | Banner isn't Ferrari-specific — it's the SCXCode module banner |
> | `$script:FerrariTerminatorRegex` (.5182) | `$script:SCXNaturalTerminatorRegex` (.5183) | Terminator regex is not Ferrari-specific |

---

## 🚨🚨🚨🚨 HARD RULE 27 (.5182) — EVERY HUMAN PROMPT + EVERY AI RESPONSE IS AUTO-CAPTURED TO `documentation/human/` + `documentation/ai/` (JSONL APPEND-ONLY, SHA+SIMHASH DEDUPED, INGESTED TO KRITICAL BRAIN) 🚨🚨🚨🚨

> Operator (.5182 paraphrased per HR12): make sure every last detail — human
> prompts, decisions, context, direction — plus every AI response, is captured
> to a canonical dedup'd store. Default JSONL for simplicity; opt-in SQL Express
> ingest to `KriticalBrain.dbo.decision_log`. Simple enough for idiots, powerful
> enough to fold into `Kritical.NodeJS.SCXCodeAgent` as the primary session-memory
> store — enabling the synthetic-mega-context-window that motivated the rule.
>
> **CONTRACT**:
>
> 1. **Canonical folders at repo root**: `documentation/human/<yyyy-mm-dd>/<category>.jsonl` + `documentation/ai/<yyyy-mm-dd>/<category>.jsonl`.
>    Categories:
>    - human: `prompt`, `decision`, `context`, `direction`
>    - ai: `response`, `action`, `commit`
> 2. **JSONL row schema** (full spec at [documentation/human/README.md](documentation/human/README.md) §schema): `{id, ts_utc, side, category, wave, session_id, content_sha256, simhash, content_len, content_preview_120, content, model?, provider?, source}`.
> 3. **Dedup at write time**: SHA256 exact-dupe → skip write (increments occurrence_count in sidecar). SimHash 64-bit near-dupe (Hamming ≤ 3) → append with `dup_of: <id>` link, do NOT collapse.
> 4. **Default emit target = JSONL file** (simplest — idiot-safe). Opt-in SQL Express via `$env:KRITICAL_LOGGER_TARGET = 'db'` or `'both'`, or per-call `-EmitToDb` switch.
> 5. **SQL Express table**: `KriticalBrain.dbo.decision_log` — schema at [src-db/decision_log_schema.sql](src-db/decision_log_schema.sql). Sync on-demand via `Sync-KriticalDecisionLogToKriticalBrain`.
> 6. **HR23 supersedes**: NEVER purge either folder. Rotate rows ≥ 90 days old to `documentation/{human|ai}/_ARCHIVED-<utc>/` sibling.
> 7. **HR12 boundary**: profanity in raw operator prompts stays verbatim in JSONL (internal-only). Scrubbed at public-artifact emission boundary only.
> 8. **HR21 paired-test**: logger has [tests/Test-KriticalDecisionLogger.ps1](tests/Test-KriticalDecisionLogger.ps1).
> 9. **Repo-agnostic anchor**: `Resolve-KriticalLoggerRoot` walks up looking for `.git/` / `package.json` / `AGENTS.md` / `README.md`. Override via `$env:KRITICAL_DECISION_LOG_ROOT`. Works uniformly from any Kritical.* sister.
>
> **REFUSAL CONDITIONS**:
> - Do NOT design a script that writes decisions/prompts anywhere other than `documentation/{human|ai}/`.
> - Do NOT bypass dedup — every write goes through the module primitives.
> - Do NOT rename the folder names or change the JSONL schema without updating this rule + module + paired test + SQL schema in the SAME commit.
>
> **MODULE**: [ps-module/KriticalDecisionLogger.psm1](ps-module/KriticalDecisionLogger.psm1) — 9 exported primitives: `Add-KriticalHumanPrompt` / `Add-KriticalAIResponse` / `Get-KriticalDecisionLog` / `Find-KriticalDecisionByHash` / `Sync-KriticalDecisionLogToKriticalBrain` / `Import-KriticalConversationBackfill` / `Get-KriticalContentSha256` / `Get-KriticalContentSimHash` / `Get-KriticalSimHashHammingDistance`.
>
> **BACKFILL**: `Import-KriticalConversationBackfill -TranscriptPath <jsonl>` retroactively ingests any prior session. First backfill = wave `.5182` seed of the SCX-coder review + Lens-context-expansion planning session.
>
> **FEEDS SCXCODE MEGA-CONTEXT**: `Kritical.NodeJS.SCXCodeAgent` (queued next-wave sister) reads `documentation/{human|ai}/` at session boot to reconstruct prior conversation context — the primary mechanism for the synthetic mega-context-window that motivated this rule. This is what makes SCXCode's effective context longer than Codex's raw window.

---

## Path snapshot (.5165 → .5182)

`Kritical.SCXCode` ships across five deployment paths (per [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)):

| Path | Surface | Location | Status |
|---|---|---|---|
| **A** | Continue.dev config drop-in | [config-templates/continue-config.json](config-templates/continue-config.json) | shipped `.5165` |
| **B** | (reserved) — direct Anthropic SDK swap | — | planned |
| **C** | `kritical.SCXCode` VS Code extension | [src/](src/) — TypeScript + VSIX 0.1.2 | shipped `.5165` |
| **D** | `Kritical.PS.SCXCode` PowerShell 7 module | [ps-module/](ps-module/) — 11 exported functions + 4 aliases | shipped `.5165` |
| **E** | `kritical-scxcode` MCP server | [mcp-server/server.mjs](mcp-server/server.mjs) — stdio JSON-RPC 2.0 | shipped `.5165` |

12+ SCX models — MiniMax-M2.7 (default) · MAGPiE · gpt-oss-120b · DeepSeek-V3.1 · coder · gemma-4 · Qwen3 · Llama-4-Maverick · Meta-Llama-3.3-70B · E5-Mistral embeddings · Whisper · opir moderation. Fallback chain hard-wired: MiniMax-M2.7 → MAGPiE → gpt-oss-120b. Multi-key rotation via `SCX_API_KEY_2..9` in HKCU.

## Kritical brand invariants (per HR13 + brand spec)

- Primary colour: **`#13365C`** (Kritical navy)
- Secondary colour: **`#15AFD1`** (Kritical cyan) — supersedes any legacy `#F2B500` gold references in code
- Typography: Roboto Regular 42pt headings / Assistant Medium 21pt sub-headings
- Author: `Joshua Finley`
- Company: `Kritical Pty Ltd`
- Copyright stamp: `(c) 2026 Kritical Pty Ltd. All rights reserved.`
- Banner: `KriticalLogo.txt` from `OneDrive\Kritical-Branding\public\` embedded at module load per HR canonical banner rule.

## Sales positioning (operator .5182)

> **"The IT and IT Security Experts — if it's too hard for everyone else, just give us a call."**
>
> Kritical Pty Ltd's niche: the people the AI providers call when the AI providers themselves need something.

This lands on the README as the closing sales blurb. Every published Kritical.SCXCode release note carries the tagline.

## Sister-repo cross-links (Kritical Lens™ umbrella per HR13)

- **`Kritical.PS.OmniFramework`** — foundation loader (`Import-KritFoundation` etc). Depend on ≥ v1.1.14 for OneDrive share-link helpers.
- **`Kritical.PS.Toolkit`** — shared PS utility library + canonical `Krit.Banner.psm1` reader.
- **`Kritical.PS.UTCM`** — Microsoft Graph UTCM REST API client. Sister for M365DSC-adjacent flows.
- **`Kritical.Lens.CodeGraph`** — semantic AL parse cross-check. Regression-lock for AL surfaces.
- **`Kritical.Lens.SqlMiner`** — git corpus miner → SQL warehouse. Bridge for HR27 SQL ingest hook.
- **`Kritical.AISupervisor.NodeJS`** / **`.PS`** — orchestrator lanes (per `[[kritical-aisupervisor-sister-separation]]` HARD RULE).
- **`KRTPax8ToShopifyConnector`** — upstream Pax8↔BC↔Shopify connector; source of HR1–HR26 conventions we inherit here.

## Standing rules inherited from upstream connector rulebook

We inherit these load-bearing rules from `KRTPax8ToShopifyConnector/AGENTS.md` (do not violate here either):

- **HR1** — NEVER use ANY API key for AI inference; native plan client / HKCU-registered SCX key only.
- **HR9b** — **WE ARE KRITICAL**. Customer/product-facing names are Kritical-*; supplier references (Pax8, Anthropic, OpenAI) stay in source only.
- **HR10** — CODE OVER DOCS. Bulk-programmatic edits first; new reference docs only when the doc IS the deliverable.
- **HR12** — no profanity in public artifacts; internal rulebooks + JSONL logs keep operator verbatim.
- **HR13** — Kritical Lens™ umbrella brand. Customer-facing = "Kritical Lens™"; internal names stay Kritical.*.
- **HR14** — npm/pnpm install MUST route via `%TEMP%` or `D:\`, NEVER OneDrive-synced node_modules.
- **HR15** — OneDrive share-link over 10 MB email attachments for customer deliverables (`New-KritOneDriveShareLink`).
- **HR16** — every install/provision script exposes idempotent `Install` / `Remove` / `Heal` / `Status` modes.
- **HR17** — never declare a service started without active API probe (health-check the endpoint).
- **HR18** — never `Remove-Item -Recurse -Force` on a path without interrogating NTFS reparse points first.
- **HR20** — MCP Learn / Krit.OpenApi / existing scripts consulted BEFORE assuming.
- **HR21** — validate + prove + auto-test every step; no code without matching test.
- **HR22** — OneDrive lock triage → route via `%TEMP%` / `D:\` mirror.
- **HR23** — NEVER purge history (backup tags / stashes / receipts / archaeology stay). Rotate, don't delete.
- **HR26** — linter output is load-bearing evidence; every Lens tool emits a linter report.
- **HR27** — every human prompt + AI response captured to `documentation/human/` + `documentation/ai/` (this file's headline rule).

## Where SCXCode fits in the Lens umbrella

```
Kritical Lens™ (customer-facing umbrella)
├── Kritical.Lens.CodeGraph          # semantic AL cross-check
├── Kritical.Lens.SqlMiner           # git corpus → SQL
├── Kritical.Lens.SchemaCompleteness # mirror-table coverage
├── Kritical.Lens.ALDependencyMatrix # AL dep surface
├── Kritical.Lens.CompareAndBounce   # wave delta
├── Kritical.PS.OmniFramework        # foundation loader
├── Kritical.PS.UTCM                 # M365 Graph client
├── Kritical.PS.SCXCode  ◀────── (Path D — you are here for the PS surface)
├── Kritical.NodeJS.SCXCodeAgent     # queued next — the mega-context orchestrator
└── kritical.SCXCode  ◀────── (Path C — the VS Code extension)
```

SCXCode's job: be the SCX-inside-VS-Code + PowerShell + MCP entry point where operators actually type prompts and read responses. Every prompt and every response funnels through HR27 to the decision store, which the queued `Kritical.NodeJS.SCXCodeAgent` reads to reconstruct arbitrarily-long prior context.

<!-- BEGIN KRITICAL-LENS-INDICES v1 — generated by Kritical.Lens/scripts/Update-KritRepoAgentsLensSection.ps1; do not hand-edit inside the markers -->
## Lens & indices

> **Read this before you grep.** Everything below is regenerable. If it looks stale,
> re-run the commands in *Run Lens over this repo* rather than reading source by hand.

### Run Lens over this repo

```powershell
$lens = 'C:\Users\joshl\OneDrive - Kritical Pty Ltd\Github\Kritical.Lens'
Import-Module "$lens\src\Kritical.Lens.psd1" -Force

<!-- BEGIN KRITICAL-SWARM-TRACKING v1 src=d6c382954b2a — GENERATED from RULE ZERO + RULE ZERO-B in C:\Users\joshl\.claude\CLAUDE.md by Kritical.Lens/scripts/Update-KritRepoSwarmTrackingBlock.ps1. DO NOT HAND-EDIT INSIDE THESE MARKERS: edit the source file and re-run the propagator. -->
# 🔴 SWARM TRACKING + RULE ZERO (propagated — one authority, do not hand-edit)

> This section is **generated**. The single authority is `RULE ZERO` + `RULE ZERO-B` at the
> top of `C:\Users\joshl\.claude\CLAUDE.md`. Anything you change here is overwritten on the next run.
> Re-propagate: `pwsh "<Github>/Kritical.Lens/scripts/Update-KritRepoSwarmTrackingBlock.ps1"` · Drift check (exits non-zero): `-Check`

## 🔴 The three commands — run them from disk, never from memory

```
node "C:\Users\joshl\OneDrive - Kritical Pty Ltd\Github\Kritical.Lens\scripts\Get-KritSwarmLedger.mjs"
node "C:\Users\joshl\OneDrive - Kritical Pty Ltd\Github\Kritical.Lens\scripts\Get-KritAgentForensics.mjs" --unreturned
node "C:\Users\joshl\OneDrive - Kritical Pty Ltd\Github\Kritical.Lens\scripts\Export-KritSwarmJournalFindings.mjs" --out <dir>
```

🔴 **RUN `Get-KritAgentForensics.mjs --unreturned` FIRST AFTER ANY RESTART, CRASH OR SESSION
LIMIT — BEFORE RE-RUNNING ANY LANE.** The ledger says whether an agent returned; **forensics
says what a dead agent actually WROTE.**

**WHY — a missing result is NOT a missing outcome.** A `StructuredOutput` failure and a
session-limit kill both emit **no result line whatsoever**, so in the journal a lost report is
**indistinguishable from an agent still thinking**. The agent almost certainly DID the work.
Measured 2026-08-01: **1,670 agents, 173 never returned, and 36 of those HAD WRITTEN REAL
FILES** — test suites and deploy scripts sitting on disk while every status surface reported
them incomplete. Re-running a lane on the assumption *it never finished so nothing happened*
is how work gets duplicated or silently clobbered. Check `git status` and the agent's
`agent-<id>.jsonl` transcript before re-running anything.

## RULE ZERO — one line

**RULE ZERO in one line: READ THE INDEX AND THE DOCS BEFORE YOU CLAIM A THING DOES NOT EXIST.** You do not get to say a thing does not exist — only that you looked, where, and what you found. 4 false absence-claims in one session: *"No PowerShell semantic Lens ingester exists anywhere in th...* · *`UNDECLARED` read as "not built".* · *"`.github/workflows/` DOES NOT EXIST."* · *`Kritical.Lens.QAArsenal`.*.

---

## Verbatim source — RULE ZERO-B

*(copied byte-for-byte from the authority above so this copy cannot drift from it)*

# 🔴 RULE ZERO-B — NEVER SPAWN AN AGENT THAT IS NOT PROGRAMMATICALLY TRACKED (HARD RULE)

**Operator directive 2026-08-01, after ~176 agents across ~7 concurrent swarms died with nobody
able to say what they had done, written, or left half-finished.**

**Before dispatching ANY agent or swarm, and at the END of every turn that ran one, run the
ledger — never your memory:**

```
node "C:\Users\joshl\OneDrive - Kritical Pty Ltd\Github\Kritical.Lens\scripts\Get-KritSwarmLedger.mjs"
node "C:\Users\joshl\OneDrive - Kritical Pty Ltd\Github\Kritical.Lens\scripts\Get-KritAgentForensics.mjs" --unreturned
node "C:\Users\joshl\OneDrive - Kritical Pty Ltd\Github\Kritical.Lens\scripts\Export-KritSwarmJournalFindings.mjs" --out <dir>
```

🔴 **RUN `Get-KritAgentForensics.mjs --unreturned` FIRST AFTER ANY RESTART, CRASH OR SESSION
LIMIT — BEFORE RE-RUNNING ANY LANE.** It is the only thing that tells you **what a dead agent
actually WROTE**. The ledger says whether an agent returned; forensics says what it left on disk.
Measured 2026-08-01: **1,670 agents, 173 never returned, and 36 of those had written real files** —
including test suites and deploy scripts sitting on disk while every status surface reported them
incomplete. Re-running a lane on the assumption "it never finished so nothing happened" is how work
gets duplicated or silently clobbered.

Memory is not tracking. A remembered swarm count was measured **wrong by 4×** (believed ~15
running; actually 4 of 57, with 153 agents started and never returned).

**For every agent you must be able to answer, from disk and not from recall:** is it still
running · what was it asked to do · which files did it WRITE · which did it NOT · did it commit ·
did it return a result at all.

**🔴 A MISSING RESULT IS NOT A MISSING OUTCOME.** A `StructuredOutput` failure and a session-limit
kill both emit **no result line whatsoever** — verified on `wf_731e7b0d-ecc` (harness reported
`agents_empty_result=1`; journal held 15 `started`, 14 `result`). So in the journal a lost report
is indistinguishable from an agent still thinking. **The agent almost certainly DID the work.**
Check `git status` and its `agent-<id>.jsonl` transcript before re-running anything.

**Gate agents run LAST, so a session limit strips the VERIFICATION layer off every workflow while
the production layer completes.** Measured repeatedly: builds 3/3 ✓ then gates 0/6 ✗; runs 6/7 ✓
then gates 0/14 ✗ at **zero tokens**. The estate therefore accumulates **finished-but-unverified**
work, which is worse than unfinished work because it looks done.

**"Built" does not mean "safe".** Persist and push before the next step: tonight a whole component
had no git, ten docs were untracked, a 623-insertion commit was stranded on a detached HEAD, and
1,492 agent results lived only inside journal files.

<!-- END KRITICAL-SWARM-TRACKING -->

# family #1 — the six PowerShell analyzers (PSGraph / SqlMiner / CompareAndBounce /
#              CodeGraph / ALDependencyMatrix / SchemaCompleteness)
Invoke-KriticalLensSweep -Root 'C:\Users\joshl\OneDrive - Kritical Pty Ltd\Github\Kritical.SCXCode'

# family #2 — the Kritical.Lens.Language.* node analyzers. NOT covered by the call
#              above. Omitting it leaves the whole JS/CSS/HTML/Liquid surface invisible.
Invoke-KriticalLensLanguageSweep -Root 'C:\Users\joshl\OneDrive - Kritical Pty Ltd\Github\Kritical.SCXCode'

# both families, plus a combined receipt
Invoke-KriticalLensEstateSweep -Roots 'C:\Users\joshl\OneDrive - Kritical Pty Ltd\Github\Kritical.SCXCode'

# end-of-turn gate (parser + PsLint auto-fix + PSScriptAnalyzer + Lens + corpus top-up)
& "$lens\scripts\Invoke-KritEndOfTurnGate.ps1" -Repo 'C:\Users\joshl\OneDrive - Kritical Pty Ltd\Github\Kritical.SCXCode'
```

Estate-wide (all repos at once):

```powershell
& "$lens\scripts\Invoke-KritEstateWideLensSweep.ps1" -FreshOutput -TimeoutSecondsPerRepo 900
```

### Where this repo's indices live

| Index | Location | Emitted by |
| --- | --- | --- |
| PS call graph (functions, edges, HOT/COLD) | `scripts/output/lens-sweep/<utc>/Kritical.Lens.PSGraph.json` | `Invoke-KriticalLensPSGraph` |
| SQL surface | `scripts/output/lens-sweep/<utc>/Kritical.Lens.SqlMiner.json` | `Invoke-KriticalLensSqlMiner` |
| Semantic-vs-raw delta | `scripts/output/lens-sweep/<utc>/Kritical.Lens.CompareAndBounce.json` | `Invoke-KriticalLensCompareAndBounce` |
| Per-language element/call/edge index | `scripts/output/lens-sweep/<utc>/Language.<X>.json` | `Invoke-KriticalLensLanguageSweep` |
| Sweep receipt (what ran, what skipped, why) | `scripts/output/lens-sweep/<utc>/sweep-receipt-<utc>.json` | `Invoke-KriticalLensSweep` |
| Raw git corpus (every commit, every blob) | SQL Server `.\SQLEXPRESS` database `KritLens_Kritical_SCXCode` (tables `lens.git_corpus_version` / `lens.git_corpus_blob`) | `Invoke-KritLensGitCorpusFullIngest` |
| Semantic parse warehouse (shared, all repos) | SQL Server `.\SQLEXPRESS` database `KriticalBrain`, schema `lens` | language ingesters |

Corpus freshness for this repo:

```powershell
& "$lens\scripts\Test-KritLensCorpusFreshness.ps1" -Only 'Kritical.SCXCode'
```

### Analyzer applicability for this repo

A **skip is not a pass**. An analyzer marked NO is a documented blind spot for that
language or domain in this repo.

| Analyzer | Applies here | Why |
| --- | --- | --- |
| `Kritical.Lens.PSGraph` | YES (always runs) | 72 PowerShell file(s) — PS call graph, HOT/MEDIUM/COLD ranking |
| `Kritical.Lens.SqlMiner` | YES (always runs) | 4 .sql file(s) + embedded SQL in any language |
| `Kritical.Lens.CompareAndBounce` | YES (always runs) | semantic-vs-raw-vs-SQL delta |
| `Kritical.Lens.CodeGraph` | NO — skipped | no app.json in this repo — analyzer SKIPS by design, this is not a failure |
| `Kritical.Lens.ALDependencyMatrix` | NO — skipped | no app.json in this repo — analyzer SKIPS by design, this is not a failure |
| `Kritical.Lens.SchemaCompleteness` | NO unless -InventoryPath + -ModuleDir supplied | M365DSC schema analyzer; never runs from a bare sweep |
| `Language.JS` | YES — 45 file(s) | node CLI present |
| `Language.Liquid` | runs, 0 files here | node CLI present |
| `Language.CSS` | runs, 0 files here | node CLI present |
| `Language.Bash` | runs, 0 files here | node CLI present |
| `Language.HTML` | YES — 47 file(s) | node CLI present |
| `Language.CMD` | YES — 2 file(s) | node CLI present |
| `Language.CSV` | runs, 0 files here | node CLI present |
| `Language.JSON` | YES — 59 file(s) | node CLI present |
| `Language.Python` | YES — 429 file(s) | node CLI present |
| `Language.CSharp` | NO — not in the sweep default set | ingest-only src; not in the Language sweep default set |
| `Language.AzPac` | NO — not in the sweep default set | PowerShell module (not node); not in the Language sweep default set |

### File census (what this repo actually contains)

| Kind | Files |
| --- | --- |
| CMD | 2 |
| HTML | 47 |
| JS | 45 |
| JSON | 59 |
| Markdown | 114 |
| PowerShell | 72 |
| Python | 429 |
| SQL | 4 |
| **all tracked-ish files (excl. .git/node_modules/bin/obj/dist)** | **1470** |

### Read these instead of grepping source

| Read | For |
| --- | --- |
| `README-AI.md` | Machine-oriented repo overview |
| `README.md` | Human overview |
| `CLAUDE.md` | Repo-specific agent rules / verified-vs-suspect ledger |
| `CHANGELOG.md` | What changed and when |
| `docs/` | Long-form design + audit documents |
| `tests/` | Executable specification — read test names to learn behaviour |
| `scripts/output/` | Generated Lens artifacts from previous runs |

Documents in `docs/`:

- `docs/AGENTIC-CODEX.md`
- `docs/AGENTMUX-RUST-DESIGN.md`
- `docs/AGENTMUX.md`
- `docs/ARCHITECTURE-SCX-BRIDGE-5182.md`
- `docs/ARCHITECTURE.md`
- `docs/BUILD-PIPELINE.md`
- `docs/COMPLETE-AUDIT.md`
- `docs/FREE-AND-SCX-AGENT-PACKS-2026-07-07.md`
- `docs/INDEX.md`
- `docs/KILO-AND-MEGA-AGENTIC-PIPELINE-2026-07-08.md`
- `docs/KRITICAL-CODING-SYSTEM-USAGE.md`
- `docs/MCP-SERVERS.md`
- `docs/MEGA-CONTEXT-ARCHITECTURE.md`
- `docs/MODEL-PARAMETER-MATRIX.md`
- `docs/MULTI-REPO-LENS-HUNT-5231.md`
- `docs/MUX.md`
- `docs/OSS-UNIVERSE-CATALOG.md`
- `docs/PROVIDERS.md`
- `docs/RUNBOOK.md`
- `docs/SCX-AGENTIC-BRIDGE-SPEC.md`
- `docs/SCX-API-SURFACE-MATRIX-2026-07-07.md`
- `docs/SCX-ARCHITECTURE-AUTOGENERATED.md`
- `docs/SCX-BUGHUNT-FIXES-5231.md`
- `docs/SCX-CODEX-8M-RUN-RECOVERY-2026-07-07.md`
- `docs/SCX-END-TO-END-TODO-STATUS-2026-07-07.md`
- `docs/SCX-KEY-ROTATION-2026-07-07.md`
- `docs/SCX-MINED-INSTRUCTION-MANUAL-SUMMARY-2026-07-07.md`
- `docs/SCX-MODEL-BEHAVIOR-PROBE.md`
- `docs/SCX-MUX-MODEL-BENCHMARK.md`
- `docs/SCX-MUX-STORAGE-CONTEXT-PROOF.md`
- `docs/STALE-SCOPE-TRUNCATION-FINDINGS-20260725.md`

### Known limits of this section

- The census counts files on disk at generation time; it is a snapshot, not a live view.
- `scripts/output/lens-sweep/<utc>/` paths exist only after a sweep has been run here.
  If that directory is absent, this repo has **no local Lens artifacts** — run the sweep.
- Dependency graph, entrypoint list, config/secret-name reference and test inventory are
  **not yet emitted by Lens**. See `Kritical.Lens/docs` for the index specification and
  which artifacts are built vs planned. Marked UNKNOWN until they exist.

<!-- END KRITICAL-LENS-INDICES -->
