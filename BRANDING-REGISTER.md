# Kritical SCX — Branding & Naming Register (canonical)

> Operator asked (.5228): *"work out how to brand everything to name everything together around my
> previous and current ideas etc and make sure that we register things as that so it's very clear what
> it is and where it's coming from."* This is that register — the single source of truth for how the
> sovereign AI stack is named. Ideas folded in: **SCX = Southern Cross AI**, **Kritical** the company,
> and the operator's floated forms `Kritical.SCXAI.$x` / `Kritical.SouthernCrossAITools.SCX$x` /
> `Kritical.$lang.$name inside a master bundle`.

## The decision

| Layer | Name | Why |
|---|---|---|
| **Customer-facing brand** | **Kritical SCX™** ("Southern Cross AI — sovereign Australian AI") | Short, already lives in `SCX_API_KEY`, `api.scx.ai`, "SCXCode". "Southern Cross AI" is the expansion, used in taglines/banners, not identifiers. |
| **Master code namespace** | **`Kritical.SCX`** | The umbrella. Every AI-stack component is `Kritical.SCX.<Component>`. Chosen over `Kritical.SCXAI` (redundant — SCX already = "…AI") and `Kritical.SouthernCrossAITools` (too long to type/grep). |
| **Master bundle repo** | **`Kritical.SCX`** | The meta-repo/installer that references + versions every component below. `kritical.$lang.$name` libraries are referenced inside it, per your "master bundle with all the kritical.$lang.$name inside". |

## Component register (`Kritical.SCX.<Component>`)

| Canonical name | What it is | Current artefact | Rename posture |
|---|---|---|---|
| **Kritical.SCX.Code** | The VS Code extension (chat + mux + model picker) | repo `Kritical.SCXCode`, ext id `kritical.scxcode` | displayName → "Kritical SCX Code"; **ext id `kritical.scxcode` KEPT** (settings keys + installed id are load-bearing — HR13 backcompat pattern). |
| **Kritical.SCX.Codex** | SCX-branded Codex fork = wrapper + additive pack over stock `@openai/codex` | `codex-wrapper/` (`kritical-codex.ps1` + `pack/`) | brand as "Kritical SCX Codex"; the pack `flies over the top` of stock Codex (never edits upstream → self-updates clean). |
| **Kritical.SCX.Proxy** | LiteLLM config that routes OpenAI-shape → SCX (localhost:4180) | `litellm/kritical-scx.config.yaml` | additive; localhost-only bind; verified not intercepting Claude. |
| **Kritical.SCX.Store** | SQL Express warehouse (`KriticalSCXCodeStore`) + store MCP | `store-mcp/`, `.\SQLEXPRESS` | DB name kept for backcompat. |
| **Kritical.SCX.Mux** | Synthetic-context muxing (fan-out N SCX voices → synthesise) | `scxMux` in the extension | — |
| **Kritical.SCX.Lens** | Corpus mining / archaeology / regression sweeps | `lens/`, `KriticalSCXCodeStore.Lens*` tables | sits under the existing **Kritical Lens™** umbrella (connector HR13). |

## Language libraries — stay `Kritical.<Lang>.<Name>`, referenced by the master bundle

These are **not** all SCX-specific, so they keep the language-first form and are *referenced by* `Kritical.SCX`, not renamed under it:

- `Kritical.PS.*` — PowerShell (`Kritical.PS.SCXCode.AutoContinue`, `Kritical.PS.Supervisor`, `Kritical.PS.UTCM`, …)
- `Kritical.NodeJS.*` — Node (`Kritical.NodeJS.SCXCodeAgent`, `Kritical.NodeJS.Supervisor`, …)
- `Kritical.AL.*` — AL/Business Central (`Kritical.AL.d365BCconnectorForPax8ToStorefronts`, …)
- `Krit.OmniFramework` / `Krit.OpenApi` / `Krit.Hardening` — foundation packages (published; names locked for PSGallery backcompat).

The SCX-specific PowerShell/Node pieces may ALSO be surfaced as `Kritical.SCX.<Component>` aliases in the master-bundle manifest without renaming the underlying package.

## Registration rule (so provenance is always clear)

1. Every new AI-stack artefact is created as **`Kritical.SCX.<Component>`** (customer-facing "Kritical SCX <Component>").
2. Every published/installed id that already exists (ext id `kritical.scxcode`, DB `KriticalSCXCodeStore`, PSGallery `Krit.*`) is **kept** — a coordinated rename wave only, never a silent break (HR13 pattern).
3. Every banner/README/release note carries: **Kritical SCX™ · Southern Cross AI · © Kritical Pty Ltd**.
4. HR28 still applies: identifiers describe the mechanism; "SCX"/"Southern Cross AI" is the brand, not a function name.

## One open sub-decision (non-blocking)
Master token is **`Kritical.SCX`**. If you'd rather carry the explicit "AI" (→ `Kritical.SCXAI`) or the full "Southern Cross AI Tools" umbrella, say so and I flip the register + the master-bundle manifest — nothing downstream is renamed yet, so it's cheap now.
