# Kritical SCX — Mega-Context Architecture & Roadmap
_How SCX Code becomes storage-backed, muxed, and able to synthesise arbitrarily large context — and exactly when you can see each piece working._

## The idea in one paragraph
A single model call is bounded by its context window. But **work can be split**. Kritical SCX shards a large task across **N concurrent SCX model calls**, each holding a slice of the context, then a **synthesiser call** stitches the slices together — "quietly under the hood" via templated prompts. Backing storage (KriticalBrain) holds the full corpus + every prior turn (HR27), so any shard can pull exactly the context it needs. The **effective** context = `(per-call window) × (concurrent calls) − overlap`, bounded only by `$budget`, storage, and how parallelisable the work is.

```
                       ┌─────────────── Kritical SCX Control Plane ───────────────┐
  VS Code ext ─┐       │  Planner: split task -> shards (by file/section/entity)   │
  kcodex CLI  ─┼─▶ :4180│  Mux: fan out N concurrent SCX calls (LiteLLM router)     │─▶ SCX (api.scx.ai)
  MCP clients ─┘  LiteLLM│  Synthesiser: reduce shard outputs -> one answer         │   15+ models
                       │  Memory: read/write KriticalBrain (full corpus + turns)    │
                       └──────────────────────────────────────────────────────────┘
                                 │  SQL Express KriticalBrain  +  Langfuse (trace/debug)
```

## Layers (each independently on/off — HR29)
| Layer | Job | Status | See it working via |
|---|---|---|---|
| **Router/proxy** | OpenAI-shape → SCX, fallbacks, retries | ✅ LIVE | `Test-KritScxRouting.ps1` (6/6, 477ms) |
| **Model catalogue** | live-query → cache → fallback | ✅ LIVE | `Get-KritScxModels.ps1` |
| **Backing storage** | KriticalBrain: corpus + every prompt/response (HR27) | ⏳ next | SQL row count after a session |
| **Memory retrieval** | dedup (SHA+simhash), fetch relevant slices | ⏳ next | "context reconstructed from N rows" log |
| **Mux/planner** | split work → N concurrent calls | 🔜 | trace: N parallel spans in Langfuse |
| **Synthesiser** | reduce shard outputs → one answer | 🔜 | one answer citing M shards |
| **Observability** | see/debug every hop | 🟡 text now (log tail) → Langfuse visual | `-Tail`, then Langfuse UI |
| **Settings dropdown** | scale concurrency/budget up-down | 🔜 | VS Code setting + status-bar picker |

## How the "magic" works (concretely, no hand-waving)
1. **Plan** — Planner asks a cheap SCX model to split the task into K shards (by file, section, or entity) + a merge spec.
2. **Mux** — LiteLLM router fans out K `chat/completions` concurrently (it already load-balances + retries; we cap K by `$budget` and `MaxConcurrency`).
3. **Store** — every prompt+response is appended to KriticalBrain (HR27), SHA/simhash-deduped, so nothing is re-sent and history is queryable.
4. **Synthesise** — a final call receives the K shard summaries (not the raw context — that's the compression) + the merge spec → single coherent answer.
5. **Scale** — a **VS Code setting + status-bar dropdown** (`kritical.scxcode.contextScale`: `off | 2x | 4x | 8x | max`) sets `MaxConcurrency`; higher = larger synthetic context, more $/latency. Bounded automatically by `$budget` and how splittable the task is.

## MCP servers + connectors (local & cloud)
Codex already speaks MCP + connectors. Because `kcodex` routes Codex through the SCX proxy **without changing Codex's tool layer**, every MCP server and connector Codex supports keeps working — now backed by SCX models. The same proxy is OpenAI-shape, so **any** MCP-capable client (Cline, OpenCode, goose) points at `:4180` and inherits SCX + the mux. Nothing SCX-specific to configure per client beyond the base URL + `sk-kritical-scx-local`.

## One-liner install (hostable)
`Install-KriticalSCX.ps1` is idempotent (Install/Status/Repair/Uninstall). Host it (e.g. a Shopify page asset or `kritical.au`) and bootstrap any machine:
```powershell
irm https://kritical.au/scx/install.ps1 | iex        # (final URL TBD)
```
It sets up venv+LiteLLM, applies the Codex pack, installs the VS Code extension, seeds the model cache, and prints the kill-switch + `Test-KritScxRouting` command so you immediately **see it working**.

## Cost / concurrency knobs
`$budget` (tokens) × `MaxConcurrency` × `sessions` govern the synthetic context ceiling. All exposed in the settings dropdown; the mux never exceeds `$budget` (hard stop) and logs anything it drops (no silent truncation).

## When you'll see each milestone
- **M0 (now):** routing + messaging + model catalogue — run `Test-KritScxRouting.ps1`.
- **M1 (storage):** enable KriticalBrain sink → after one session, `SELECT COUNT(*) FROM decision_log` grows; context survives restarts.
- **M2 (observability):** Langfuse in Docker → every call/shard visible in a web UI.
- **M3 (mux):** first 4x synthetic-context answer, traced as 4 parallel spans.
- **M4 (dropdown):** flip `contextScale` in VS Code and watch concurrency scale.
