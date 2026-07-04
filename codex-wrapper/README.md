# kritical-codex &nbsp;·&nbsp; Kritical + SCX branded Codex wrapper

> **Wraps operator's existing OpenAI `codex` CLI with Kritical + SCX defaults.**
> Brand banner. Sensible model default. Auto-detects the local LiteLLM proxy at `127.0.0.1:4180` and points Codex at it when healthy. Falls back to whatever the operator has already configured — including plain `api.openai.com` direct.
>
> Author: **Joshua Finley** — Kritical Pty Ltd — [sales@kritical.net](mailto:sales@kritical.net) — ph. **1300 274 655**

## HR29 compliance in one line

**This wrapper never touches your HKCU env vars, dotfiles, or global codex config.** It sets `OPENAI_BASE_URL` + `OPENAI_API_KEY` for the *single child codex process it spawns* and restores everything on exit. Delete this folder → plain `codex` still works exactly as before. This is a convenience layer, not a lock-in.

## What kritical-codex does that plain codex doesn't

1. **Emits the Kritical brand banner** (bundled `assets/KriticalLogo.txt` + `assets/brand-spec.json` — canonical `#13365C` navy + `#15AFD1` cyan) at every invocation.
2. **Prints the SCX co-brand line** — *"Sovereign Australian AI — powered by Southern Cross AI (SCX)"* — the sales angle at the top of every session.
3. **Auto-detects the local LiteLLM proxy** at `127.0.0.1:4180`. If healthy → routes Codex through it → operator gets multi-provider routing (SCX + Anthropic + OpenAI + generic) with one wrapper. If down → falls back to `api.openai.com` direct.
4. **Preselects the right default model** for the environment:
   - `SCX_API_KEY` present → `scx-coder` (the sovereign path)
   - `OPENAI_API_KEY` present → `openai/gpt-5-codex`
   - Neither → leaves codex CLI to pick its own default
5. **Writes an HR27 invocation row** to `documentation/ai/<date>/action.jsonl` so you can see exactly which model/base-url each Codex session used — best-effort, silently no-ops if the PS logger module is absent.

## Install

There's nothing to install — this is a script, not a package. Just:

```powershell
# from Kritical.SCXCode root
pwsh ./codex-wrapper/kritical-codex.ps1
```

Or the cross-platform Node/Bun sibling:

```bash
node ./codex-wrapper/kritical-codex.mjs
# or, if bun is present:
bun ./codex-wrapper/kritical-codex.mjs
```

For daily use, either:

- Add `codex-wrapper/` to your PATH and alias `codex=kritical-codex`, OR
- Copy `kritical-codex.ps1` / `kritical-codex.mjs` into a folder that's already on PATH.

## The underlying `codex` CLI

You need OpenAI's [Codex CLI](https://github.com/openai/codex) installed. It's Rust, MIT, open-sourced Sept 2025:

```powershell
winget install OpenAI.Codex      # Windows
brew install codex               # macOS
cargo install --git https://github.com/openai/codex codex-cli   # any platform with Rust
```

If codex isn't on PATH, `kritical-codex` prints the install line above and exits with code 2 — no harm done.

## Usage examples

```powershell
# Interactive with all defaults (banner, LiteLLM if up, scx-coder if SCX key present)
pwsh ./codex-wrapper/kritical-codex.ps1

# Pick a specific model
pwsh ./codex-wrapper/kritical-codex.ps1 -Model minimax-m2.7 -- exec "review this file"

# Skip the banner (for CI/piped output)
pwsh ./codex-wrapper/kritical-codex.ps1 -NoBanner -- --help

# Force a specific base URL (skip proxy detection)
pwsh ./codex-wrapper/kritical-codex.ps1 -BaseUrl https://api.openai.com/v1 -- exec "..."
```

Anything after `--` (or any arg the wrapper doesn't recognise) passes through to `codex` unchanged.

## Provider slots exposed via the wrapper

When the LiteLLM proxy is running:

| Model name to pass | Slot | HKCU var required |
|---|---|---|
| `scx-coder` | SCX-native code model | `SCX_API_KEY` |
| `minimax-m2.7` | SCX-hosted MiniMax M2.7 (56.2% SWE-Bench Pro) | `SCX_API_KEY` |
| `magpie` | SCX-hosted Australian-tuned MAGPiE | `SCX_API_KEY` |
| `gpt-oss-120b` | SCX-hosted, 655 t/s | `SCX_API_KEY` |
| `openai/gpt-5-codex` | Real OpenAI Codex model | `OPENAI_API_KEY` |
| `openai/gpt-5` | Real OpenAI GPT-5 | `OPENAI_API_KEY` |
| `anthropic/claude-sonnet-4-6` | Real Anthropic (via LiteLLM anthropic passthrough) | `ANTHROPIC_API_KEY` |
| `generic/default` | Anything OpenAI-compatible | `GENERIC_API_BASE` + `GENERIC_API_KEY` |

Full list lives at [../litellm/kritical-scx.config.yaml](../litellm/kritical-scx.config.yaml).

## When the proxy is off

If `kritical-codex` can't reach `127.0.0.1:4180` in under 2 seconds, it leaves your environment untouched and codex talks to `api.openai.com` directly. **Your existing Codex workflow keeps working.** This is the HR29 refusal-to-disrupt promise made concrete.

## Kritical &nbsp;+&nbsp; SCX &nbsp;— the sovereign Australian AI stack

**Kritical Pty Ltd** — Geelong-based Australian systems integrator. If it's too hard for everyone else, just give us a call: **[1300 274 655](tel:+611300274655)** · [sales@kritical.net](mailto:sales@kritical.net).

**Southern Cross AI (SCX)** — Australia's Sovereign AI Infrastructure Provider. Onshore inference. No prompt caching. No training on your data. IRAP-aligned. Up to 10× performance per watt.

`kritical-codex` puts the two together in one binary invocation. The sovereign Australian coding stack, wrapped around the operator's existing tools with zero commitment.

## Cross-refs

- Brand spec: [assets/brand-spec.json](assets/brand-spec.json) (canonical brand values)
- Brand banner: [assets/KriticalLogo.txt](assets/KriticalLogo.txt)
- Multi-provider LiteLLM config: [../litellm/](../litellm/)
- Architecture: [../docs/ARCHITECTURE-SCX-BRIDGE-5182.md](../docs/ARCHITECTURE-SCX-BRIDGE-5182.md)
- Rulebook: [../CLAUDE.md](../CLAUDE.md) (HR29 = why this wrapper can't disrupt anything)
- SCX marketing capture: [../sources/www.scx.ai/](../sources/www.scx.ai/)
- Partner-program positioning: [../sources/www.scx.ai/partner-program.md](../sources/www.scx.ai/partner-program.md)
