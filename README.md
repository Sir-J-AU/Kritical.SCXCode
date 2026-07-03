# Kritical SCXCode — SCX in VS Code

> **The Kritical VS Code extension for [SCX](https://api.scx.ai)** — 12+ open-source
> LLMs (MiniMax-M2.7 · MAGPiE · gpt-oss-120b · DeepSeek-V3.1 · coder · gemma-4 ·
> Qwen3 · Llama-4-Maverick · Meta-Llama-3.3-70B) plus embeddings (E5-Mistral),
> speech (Whisper), and moderation (opir) — all through one Anthropic-shape
> gateway priced in AUD.

**One-click install** (Windows, PowerShell 7):

```powershell
pwsh ./install/Install-KritScxVsCode.ps1 -Mode Install
```

This does everything: reads the SCX key from the Kritical secrets folder,
persists it to HKCU, installs the extension into VS Code (stable **and**
Insiders — `.5165g-H` install-script fix), drops the config, and verifies
auth. HR16-compliant: **Install / Remove / Heal / Status** modes.

---

## What's new

- **v0.1.2 (`.5165g` + `.5165h`)** — sidebar view **PROVIDER** + **markdown rendering** with fenced code + per-message **copy buttons** + **auto key-switch on 429**. CI relaxed to accept ≥10 PS module exports (Switch-KritScxKey added the 11th). New 50KB Kritical icon (up from 830 B).
- **v0.1.1 (`.5165f`)** — plugin-first VSIX built + installed + `Switch-KritScxKey` shipped.
- **v0.1.0 (`.5165e`)** — multi-key SCX rotation + auto-context + Kritical icon + CI + repo hygiene.
- **v0.1.0-preview (`.5165`)** — kritical.vscode.SCXCode extension + Kritical.PS.SCXCode module + kritical-scxcode MCP server.

Full log: [`CHANGELOG.md`](CHANGELOG.md).

---

## What the extension does

Ships as `kritical.scxcode@0.1.2`, ~19-25 KB VSIX (grows a bit with the sidebar UI).

- **Kritical-branded sidebar view** (`.5165g`) — dedicated activity-bar view
  container **PROVIDER** with the SCXCode icon on the left rail. Dark-navy
  `#13365C` header + gold `#F2B500` accents. Model picker + status bar item.
- **Markdown rendering** (`.5165g`) — model responses render as full markdown
  (headings, lists, fenced code with language tags). Each message header carries
  a **copy button** — one click puts either the assistant response OR the full
  turn to clipboard.
- **Auto-context** — every chat / slash command auto-prepends your active
  editor's file path, language, selection, and ± 30-line cursor window so the
  model always knows what you're looking at. Configurable
  (`kritical.scxcode.autoContext = off | file | file+selection | workspace-tree`).
- **Auto-failover + auto-key-switch** (`.5165g`) — SCX 429 or `5xx` walks a
  fallback chain of models (defaults `MiniMax-M2.7 → MAGPiE → gpt-oss-120b`).
  On persistent 429, `Switch-KritScxKey` swaps to the next HKCU-registered
  backup key (`SCX_API_KEY_2..9`) automatically — no reload.
- **7 commands** (Command Palette → `Kritical:` prefix):
  - `Kritical: Open SCX Chat` — dedicated webview chat
  - `Kritical: Pick SCX Model` — quick-pick from the 9 chat models with AUD/1M pricing shown inline
  - `Kritical: Test SCX Connection` — 20-token round-trip probe with latency
  - `Kritical: Show SCX Status` — config + endpoint + fallback chain summary
  - `Kritical: Explain Selected Code` — right-click any selection
  - `Kritical: Refactor Selection` — right-click, applies Kritical style guide
  - `Kritical: Audit Current Diff` — pre-commit safety pass against Kritical HARD RULES
- **8 typed config properties** with enum-driven quick pickers for model,
  autocomplete model, autocompact behavior, telemetry level, auto-context
  scope, plus the fallback chain.

**No API key ends up in source.** The extension reads `SCX_API_KEY` from HKCU
(Kritical convention) at request time so key rotation is instant — no reload.
The `.5165g` auto-key-switch on 429 makes the rotation happen without you
noticing.

---

## Install

### Path 1 — one-line installer (recommended)

```powershell
pwsh ./install/Install-KritScxVsCode.ps1 -Mode Install
```

Detects VS Code **stable** or **Insiders**, installs the latest built VSIX
(`src/SCXCode-0.1.2.vsix`), seeds HKCU env vars from the Kritical secrets
folder, and verifies auth. HR16-compliant: `-Mode` accepts `Install` /
`Remove` / `Heal` / `Status`.

### Path 2 — build + install from source

```powershell
git clone https://github.com/Sir-J-AU/scx-vscode.git
cd scx-vscode/src
npm install
npm run build                                                    # esbuild bundles extension.ts -> out/extension.js
npx --yes @vscode/vsce package --allow-missing-repository        # emits SCXCode-0.1.2.vsix
code-insiders --install-extension SCXCode-0.1.2.vsix             # or 'code' for stable
```

Then run one of the installer helpers to seed the HKCU env vars from
the Kritical secrets folder:

```powershell
pwsh ../install/Install-KritScxVsCode.ps1 -Mode Install
```

### Path 3 — Visual Studio Marketplace / OpenVSX

Not yet published. See [`CHANGELOG.md`](CHANGELOG.md) `[Unreleased]` for progress.

---

## Optional companion pieces (same repo, same env-vars)

The extension is the main event. These are optional friends that share the
`SCX_API_KEY` HKCU env, so if you have a preferred surface it Just Works.

| Component | Path | For when you want |
|---|---|---|
| Continue.dev config template | [`config-templates/continue-config.json`](config-templates/continue-config.json) | Continue.dev extension chat + inline-complete pointing at SCX |
| `Kritical.PS.SCXCode` PowerShell 7 module | [`ps-module/`](ps-module/) | Terminal-first: `scx 'what is 47*3?'` from any pwsh session |
| `kritical-scxcode` MCP server | [`mcp-server/`](mcp-server/) | Register in Claude Desktop / Cline / any MCP-capable agent for agentic SCX access |

Each has its own README-quality header explaining what it is and how to use it.

---

## Kritical env-var convention (single source of truth)

Everything reads from HKCU (never files in git). Filename pattern
`scx-<purpose>-MMDDYYYY-vNNN.txt` in `Github-SecretsOutsideOfGitRepos/` (outside
every git repo). Sort desc → newest wins.

| HKCU env var | Purpose |
|---|---|
| `SCX_API_KEY` | Active SCX API key (39 chars, `sk-scx-...`) |
| `SCX_API_KEY_2..9` | Backup keys for `Switch-KritScxKey` rotation |
| `ANTHROPIC_BASE_URL` | `https://api.scx.ai` |
| `KRIT_SCX_MODEL_DEFAULT` | e.g. `MiniMax-M2.7` |
| `KRIT_SCX_FALLBACK_CHAIN` | `MiniMax-M2.7,MAGPiE,gpt-oss-120b` |

---

## Docs

- [`docs/PROVIDERS.md`](docs/PROVIDERS.md) — full 12-model SCX catalogue with
  AUD pricing, context length, features (verified live via `GET /v1/models`)
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — Kritical env flow + test recipes
- [`docs/OSS-UNIVERSE-CATALOG.md`](docs/OSS-UNIVERSE-CATALOG.md) — every OSS
  package we evaluated / reused / passed on and why
- [`CHANGELOG.md`](CHANGELOG.md) — semver / Keep-a-Changelog
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — Kritical HR16 style contribution rules

---

## Marketing angle

The `#13365C` + `#F2B500` chat button lives next to any Claude / Copilot /
Continue button in your activity bar. Every message header shows
`Kritical SCXCode · MiniMax-M2.7`. That's every developer session you run
telling anyone glancing over your shoulder that Kritical + SCX did the work.

---

## License

Apache 2.0.  © Kritical Pty Ltd 2026. Attribution to reused Anthropic-shape
plumbing conventions (Anthropic SDK) + Continue.dev config schema.
