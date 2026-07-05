# Kritical.SCXCode &nbsp;·&nbsp; SCX inside VS Code

> **The Kritical VS Code extension for [SCX](https://api.scx.ai)** — twelve open-source
> LLMs (MiniMax-M2.7 · MAGPiE · gpt-oss-120b · DeepSeek-V3.1 · coder · gemma-4 ·
> Qwen3 · Llama-4-Maverick · Meta-Llama-3.3-70B) plus embeddings (E5-Mistral),
> speech (Whisper), and moderation (opir) — all through one Anthropic-shape
> gateway priced in AUD.

Made in Australia by **[Kritical Pty Ltd](https://kritical.net)** — a
Seriously Kritical&trade; Production.

<div align="center">

[![Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-13365C)](./LICENSE)
[![VS Code](https://img.shields.io/badge/VS%20Code-stable%20%2B%20insiders-007ACC?logo=visualstudiocode&logoColor=white)](https://code.visualstudio.com/)
[![SCX](https://img.shields.io/badge/SCX-api.scx.ai-15AFD1)](https://api.scx.ai)
[![PowerShell 7](https://img.shields.io/badge/PowerShell-7%2B-5391FE?logo=powershell&logoColor=white)](https://learn.microsoft.com/powershell/)

</div>

---

## One-line install

```powershell
pwsh ./install/Install-KritScxVsCode.ps1 -Mode Install
```

The installer reads your SCX key from the Kritical secrets folder,
persists it to `HKCU`, installs the extension into VS Code (**stable**
and **Insiders**), drops the default configuration, and verifies auth.
Idempotent — runs cleanly again and again. Supports
`-Mode Install | Remove | Heal | Status`.

---

## What you get

- **Kritical-branded sidebar** — dedicated activity-bar view with the
  SCXCode icon on the left rail. Dark-navy `#13365C` header with cyan
  `#15AFD1` accents. Model picker and status-bar item.
- **Markdown-rendered responses** — headings, lists, fenced code with
  language tags. Every message header carries a **copy button** — one
  click puts either the assistant response or the full turn onto the
  clipboard.
- **Automatic context** — every chat and slash-command auto-prepends the
  active editor's file path, language, current selection, and a
  &plusmn;30-line cursor window so the model always knows what you're
  looking at. Configurable
  (`kritical.scxcode.autoContext = off | file | file+selection | workspace-tree`).
- **Automatic failover and key rotation** — on SCX `429` or `5xx`, the
  extension walks a fallback chain of models (defaults
  `MiniMax-M2.7 → MAGPiE → gpt-oss-120b`). On persistent `429`,
  `Switch-KritScxKey` swaps to the next `HKCU`-registered backup key
  (`SCX_API_KEY_2..9`) automatically — no reload required.
- **Seven Command-Palette commands** (`Kritical:` prefix):

  | Command | What it does |
  |---|---|
  | `Kritical: Open SCX Chat` | Dedicated webview chat |
  | `Kritical: Pick SCX Model` | Quick-pick from the nine chat models with AUD/1M pricing shown inline |
  | `Kritical: Test SCX Connection` | 20-token round-trip probe with latency |
  | `Kritical: Show SCX Status` | Config + endpoint + fallback chain summary |
  | `Kritical: Explain Selected Code` | Right-click any selection |
  | `Kritical: Refactor Selection` | Right-click, applies the Kritical style guide |
  | `Kritical: Audit Current Diff` | Pre-commit safety pass |

- **Eight typed configuration properties** with enum-driven quick pickers
  for model, autocomplete model, autocompact behaviour, telemetry level,
  auto-context scope, and the fallback chain.
- **No API key ever ends up in source.** The extension reads `SCX_API_KEY`
  from `HKCU` at request time so key rotation is instant — no reload —
  and the auto-key-switch on `429` makes rotation happen without you
  noticing.

---

## Install options

### 1 &nbsp;·&nbsp; One-line installer (recommended)

```powershell
pwsh ./install/Install-KritScxVsCode.ps1 -Mode Install
```

Detects VS Code stable or Insiders, installs the latest built VSIX
(`src/SCXCode-0.1.2.vsix`), seeds the `HKCU` environment variables from
the Kritical secrets folder, and verifies auth. Idempotent — supports
`-Mode Install | Remove | Heal | Status`.

### 2 &nbsp;·&nbsp; Build and install from source

```powershell
git clone https://github.com/Sir-J-AU/Kritical.SCXCode.git
cd Kritical.SCXCode/src
npm install
npm run build
npx --yes @vscode/vsce package --allow-missing-repository
code-insiders --install-extension SCXCode-0.1.2.vsix    # or 'code' for stable
```

Then seed the `HKCU` environment variables from the Kritical secrets
folder:

```powershell
pwsh ../install/Install-KritScxVsCode.ps1 -Mode Install
```

### 3 &nbsp;·&nbsp; Visual Studio Marketplace / OpenVSX

Marketplace listing planned. See [`CHANGELOG.md`](CHANGELOG.md) for progress.

---

## Companion pieces (same repo, same environment)

The extension is the main event. These optional friends share the
`SCX_API_KEY` environment variable — whichever surface you prefer, it
just works.

| Component | Path | For when you want |
|---|---|---|
| Continue.dev config template | [`config-templates/continue-config.json`](config-templates/continue-config.json) | Continue.dev chat and inline-complete pointing at SCX |
| `Kritical.PS.SCXCode` PowerShell 7 module | [`ps-module/`](ps-module/) | Terminal-first: `scx 'what is 47 * 3?'` from any pwsh session |
| `kritical-scxcode` MCP server | [`mcp-server/`](mcp-server/) | Register in Claude Desktop, Cline, or any MCP-capable agent for agentic SCX access |

Each carries its own README explaining what it is and how to use it.

---

## Environment convention

Everything reads from `HKCU`. Secret files never live in git. The
canonical filename pattern is `scx-<purpose>-MMDDYYYY-vNNN.txt` under
`Github-SecretsOutsideOfGitRepos/` (outside every git repo). Sort
descending — newest wins.

| HKCU variable | Purpose |
|---|---|
| `SCX_API_KEY` | Active SCX API key (`sk-scx-...`) — **the only thing you must set** |
| `SCX_API_KEY_2..9` | Backup keys for `Switch-KritScxKey` rotation |
| `KRIT_SCX_MODEL_DEFAULT` | e.g. `MiniMax-M2.7` |
| `KRIT_SCX_FALLBACK_CHAIN` | `MiniMax-M2.7,MAGPiE,gpt-oss-120b` |

> **`ANTHROPIC_BASE_URL` is deliberately NOT set at User/Machine scope.** The extension reads its own
> `kritical.scxcode.baseUrl` (default `https://api.scx.ai`), so it routes to SCX **without** touching the
> global env. That keeps the `claude` CLI talking direct to `api.anthropic.com` (HR29 — the layer is
> additive, never intercepting). Only set `ANTHROPIC_BASE_URL` per-process if you deliberately want the
> `claude` CLI itself routed through SCX.

---

## Enable Claude/AI via SCX — configure *only* SCXCode

The extension is self-contained: it reads `SCX_API_KEY` from `HKCU` and defaults `baseUrl` to
`https://api.scx.ai`. **Set `SCX_API_KEY` once and nothing else needs touching** — the `claude` CLI,
`codex`, and every other agent keep working exactly as before (verified: `ANTHROPIC_BASE_URL` unset →
`claude` direct; LiteLLM bound to `127.0.0.1:4180` only).

| Task | Command | Notes |
|---|---|---|
| **Enable** | set `SCX_API_KEY` in HKCU; reload VS Code | extension uses it + its own baseUrl. No global env change. |
| **SCX Codex** (in VS Code) | `✦ SCX Codex` button / `Kritical: Open SCX Codex` | opens `kritical-codex.ps1` in a terminal — SCX-branded, HR29-safe, **never touches your real `codex` config**. |
| **Update the Codex pack from upstream** | `pwsh codex-wrapper/pack/Update-Codex.ps1` (`-DryRun` first) | pulls latest stock `@openai/codex` + re-applies the additive Kritical pack; auto-rolls-back stock Codex on failure. The pack flies over the top — upstream self-updates conflict-free. |
| **Claude off-switch / backout** | `pwsh C:\KriticalSCX\safety\Restore-WorkingClaude.ps1` (`-Status` to look) | guarantees Claude Code talks direct to `api.anthropic.com`; undoes any SCX/LiteLLM routing. Safe to run anytime. |
| **Verify nothing's intercepted** | `Restore-WorkingClaude.ps1 -Status` + `curl 127.0.0.1:4180/health/liveliness` | shows routing per scope + proxy liveness. |

Full naming/branding of the stack: [BRANDING-REGISTER.md](BRANDING-REGISTER.md) (Kritical SCX™ · `Kritical.SCX.*`).

---

## Documentation

- [`docs/PROVIDERS.md`](docs/PROVIDERS.md) — full twelve-model SCX catalogue
  with AUD pricing, context length, features (verified live via
  `GET /v1/models`).
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — the Kritical environment
  flow and test recipes.
- [`docs/OSS-UNIVERSE-CATALOG.md`](docs/OSS-UNIVERSE-CATALOG.md) — every
  open-source package evaluated, reused, or passed on, and why.
- [`CHANGELOG.md`](CHANGELOG.md) — Keep-a-Changelog / SemVer.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — how to contribute.

---

## Design at a glance

The `#13365C` navy + `#15AFD1` cyan chat panel sits next to any Claude,
Copilot, or Continue button in your activity bar. Every message header
reads `Kritical.SCXCode · MiniMax-M2.7`. Every developer session
quietly tells anyone glancing over your shoulder that Kritical and SCX
did the work.

---

## What's new at `.5182`

- **HR27 — every prompt and every response is captured.** Append-only JSONL under `documentation/human/` + `documentation/ai/`, SHA+SimHash deduped, optionally streamed to SQL Express `KriticalBrain.dbo.decision_log`. Sibling module [`ps-module/KriticalDecisionLogger.psm1`](ps-module/KriticalDecisionLogger.psm1) — 8/8 gate paired test in [`tests/`](tests/Test-KriticalDecisionLogger.ps1) live green.
- **Multi-turn auto-continuation.** [`ps-module/Kritical.PS.SCXCode.AutoContinue.psm1`](ps-module/Kritical.PS.SCXCode.AutoContinue.psm1) turns SCX's per-turn `max_tokens` ceiling into arbitrarily-long responses via `Invoke-KritScxAutoContinue`. Loops SCX with `continue verbatim, no meta` prompts across N turns, dedups adjacent near-repeats via SimHash, respects natural terminators, emits ONE HR27 row for the merged response — not N fragments.
- **Kritical.SCX.LiteLLM — universal front for SCX.** [`litellm/`](litellm/) install artefacts stand up a localhost LiteLLM proxy (`http://127.0.0.1:4180`) presenting SCX under both OpenAI-shape and Anthropic-shape, so **any OSS coding agent** — Codex CLI / Aider / Cline / Continue / OpenCode / goose / kritical.SCXCode — points at it and Just Works with SCX under the hood.
- **`sources/www.scx.ai/`** — locally versioned crawl of scx.ai marketing + models + partner program. Recursive crawler [`install/Save-KritScxSourcesRecursively.ps1`](install/Save-KritScxSourcesRecursively.ps1) refreshes on demand.
- **`sources/api.scx.ai/v1/`** — authoritative live capture of the 12-model catalogue Ben's SCX key sees. Marketing lists 15, API returns 12; **MiniMax-M2.5** in the homepage code sample **does not exist in the API** — use M2.7.
- **Architecture doc** — [`docs/ARCHITECTURE-SCX-BRIDGE-5182.md`](docs/ARCHITECTURE-SCX-BRIDGE-5182.md) — the three layers (Supervisor → AIRouter → Kritical.SCX.LiteLLM bridge → SCX), why LiteLLM was NOT already wired, and the roadmap through `.5186`.

## Kritical &nbsp;+&nbsp; SCX &nbsp;— the sovereign Australian AI stack, built by IT experts who show up

> **When the AI providers themselves need something wired properly — Australians call the Kriticals.**

**Kritical Pty Ltd** is a Geelong-based Australian systems integrator. We deliver Microsoft Dynamics 365 Business Central connectors, Shopify commerce integrations, Microsoft 365 hardening + eDiscovery + Chokidar-branded compliance monitoring, Pax8-linked MSP automation, CrowdStrike Falcon Complete alignment — the hard-yakka technical work most consultancies avoid. If it's too hard for everyone else, just give us a call: **[1300 274 655](tel:+611300274655)** &nbsp;·&nbsp; [sales@kritical.net](mailto:sales@kritical.net).

**Southern Cross AI (SCX)** is Australia's Sovereign AI Infrastructure Provider — onshore inference, no prompt caching, no training on your data, IRAP-aligned, up to 10× performance per watt on ASIC-based dataflow accelerators. `Kritical.SCXCode` is Kritical's reference implementation of the SCX stack — adopt it in 30 seconds, or use it as a starting point for the deeper systems-integration engagement Kritical is set up to deliver end-to-end.

**Why the pairing matters**:

- **Sovereign by construction** — data, compute, logs all stay in Australia (SCX) and are wired into Australian systems by an Australian team (Kritical).
- **No vendor lock, no rip-and-replace** — Kritical.SCXCode + Kritical.SCX.LiteLLM is drop-in against your existing Codex / Aider / Cline / Continue / Claude Code stack. Point at localhost, get sovereign SCX under the hood.
- **Real production wiring** — Kritical maintains the reference [Pax8 ↔ Business Central ↔ Shopify connector](https://github.com/Sir-J-AU/KRTPax8ToShopifyConnector), Kritical.M365DSC, Kritical.PS.UTCM (Microsoft Graph UTCM), Kritical.PS.OmniFramework — this is the same team, same conventions, same brand.
- **Kritical Lens™** — the umbrella brand for our end-to-end code intelligence stack. Kritical.SCXCode is the operator-facing head of that stack.

**Call us for**: SCX partner-tier onboarding for your team · Business Central × Shopify × Pax8 connector work · Microsoft 365 hardening and eDiscovery under Kritical Chokidar · CrowdStrike Falcon Complete alignment · anything an AL / PowerShell / TypeScript / Node.js / SQL Server integration touches.

**[sales@kritical.net](mailto:sales@kritical.net)** &nbsp;·&nbsp; **1300 274 655** &nbsp;·&nbsp; **[kritical.net](https://kritical.net)**

---

## License and credits

Apache 2.0. Copyright &copy; 2026 **Kritical Pty Ltd**. Author:
**Joshua Finley**.

Built on top of the Anthropic SDK's message envelope and the
Continue.dev configuration schema — thank you to both projects.

`Kritical.SCX.LiteLLM` layer builds on [BerriAI/litellm](https://github.com/BerriAI/litellm) (MIT) as the provider-translation engine — thank you to that project too.

---

<div align="center">

<sub>Kritical Pty Ltd &nbsp;·&nbsp; ABN 39 687 048 086 &nbsp;·&nbsp; Geelong VIC, Australia
<br/>+61 1300 274 655 &nbsp;·&nbsp; [sales@kritical.net](mailto:sales@kritical.net) &nbsp;·&nbsp; [kritical.net](https://kritical.net)</sub>

</div>
