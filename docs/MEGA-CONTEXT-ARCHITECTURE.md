# Kritical SCX — Mega-Context Architecture & Roadmap
_How SCX Code becomes storage-backed, muxed, and able to synthesise arbitrarily large context — and exactly when you can see each piece working._

## The idea in one paragraph
A single model call is bounded by its context window. But **work can be split**. Kritical SCX shards a large task across **N concurrent SCX model calls**, each holding a slice of the context, then a **synthesiser call** stitches the slices together — "quietly under the hood" via templated prompts. Backing storage (KriticalSCXCodeStore (own DB — NOT the shared KriticalBrain)) holds the full corpus + every prior turn (HR27), so any shard can pull exactly the context it needs. The **effective** context = `(per-call window) × (concurrent calls) − overlap`, bounded only by `$budget`, storage, and how parallelisable the work is.

```
                       ┌─────────────── Kritical SCX Control Plane ───────────────┐
  VS Code ext ─┐       │  Planner: split task -> shards (by file/section/entity)   │
  kcodex CLI  ─┼─▶ :4180│  Mux: fan out N concurrent SCX calls (LiteLLM router)     │─▶ SCX (api.scx.ai)
  MCP clients ─┘  LiteLLM│  Synthesiser: reduce shard outputs -> one answer         │   15+ models
                       │  Memory: read/write KriticalSCXCodeStore (own DB — NOT the shared KriticalBrain) (full corpus + turns)    │
                       └──────────────────────────────────────────────────────────┘
                                 │  SQL Express KriticalSCXCodeStore (own DB — NOT the shared KriticalBrain)  +  Langfuse (trace/debug)
```

## Layers (each independently on/off — HR29)
| Layer | Job | Status | See it working via |
|---|---|---|---|
| **Router/proxy** | OpenAI-shape → SCX, fallbacks, retries | ✅ LIVE | `Test-KritScxRouting.ps1` (6/6, 477ms) |
| **Model catalogue** | live-query → cache → fallback | ✅ LIVE | `Get-KritScxModels.ps1` |
| **Backing storage** | KriticalSCXCodeStore (own DB — NOT the shared KriticalBrain): corpus + every prompt/response (HR27) | ⏳ next | SQL row count after a session |
| **Memory retrieval** | dedup (SHA+simhash), fetch relevant slices | ⏳ next | "context reconstructed from N rows" log |
| **Mux/planner** | split work → N concurrent calls | 🔜 | trace: N parallel spans in Langfuse |
| **Synthesiser** | reduce shard outputs → one answer | 🔜 | one answer citing M shards |
| **Observability** | see/debug every hop | 🟡 text now (log tail) → Langfuse visual | `-Tail`, then Langfuse UI |
| **Settings dropdown** | scale concurrency/budget up-down | 🔜 | VS Code setting + status-bar picker |

## How the "magic" works (concretely, no hand-waving)
1. **Plan** — Planner asks a cheap SCX model to split the task into K shards (by file, section, or entity) + a merge spec.
2. **Mux** — LiteLLM router fans out K `chat/completions` concurrently (it already load-balances + retries; we cap K by `$budget` and `MaxConcurrency`).
3. **Store** — every prompt+response is appended to KriticalSCXCodeStore (own DB — NOT the shared KriticalBrain) (HR27), SHA/simhash-deduped, so nothing is re-sent and history is queryable.
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
- **M1 (storage):** enable KriticalSCXCodeStore (own DB — NOT the shared KriticalBrain) sink → after one session, `SELECT COUNT(*) FROM decision_log` grows; context survives restarts.
- **M2 (observability):** Langfuse in Docker → every call/shard visible in a web UI.
- **M3 (mux):** first 4x synthetic-context answer, traced as 4 parallel spans.
- **M4 (dropdown):** flip `contextScale` in VS Code and watch concurrency scale.

## Own dedicated database (self-contained — NOT KriticalBrain)
SCX Code is its **own project** with its **own store**: DB **`KriticalSCXCodeStore`** on its **own local SQL Express instance** (`.\SCXCODE` or `.\SQLEXPRESS`). It never writes to another project's KriticalBrain.

**Self-contained installer** (`install/Install-KriticalSCXStore.ps1`, HR16 Install/Status/Repair/Uninstall) provisions the store in an **existing** SQL Server/Express instance on any Windows box:
1. **Schema** — create `KriticalSCXCodeStore` + `decision_log` / `context_shard` / `session` / `blob_store` tables (SHA-256 exact-dedup + simhash near-dedup columns per HR27, GZIP-compressed content).
2. **Connection** — LiteLLM `database_url = mssql+pyodbc://@.\SQLEXPRESS/KriticalSCXCodeStore?...trusted_connection=yes` (the proxy's own sink).

> **Correction (2026-07-20):** earlier drafts of this doc claimed the installer also does a **VC++ redist + silent SQL Express install** ("installs everything from scratch"). Checked against the actual committed script (`git log`: `3e4181e M1 storage: provision KriticalSCXCodeStore in EXISTING SQL Express (no install)`): it does **not** install SQL Server or VC++ redist — it only provisions schema in whatever instance is already running (`.\SQLEXPRESS` by default, `-Server` to target another). That "installs from scratch" framing was aspirational, never built, and is removed here per the estate rule that ground truth (the actual code) overrides prior LLM claims.

**Optional KriticalBrain connector (dev telemetry — additive, opt-in, off by default).** The primary store is always `KriticalSCXCodeStore`. When `$env:KRIT_SCXCODE_BRAIN_TELEMETRY = 'on'`, a **secondary** sink mirrors deduped decision-log rows to KriticalBrain for cross-project analytics — never a dependency, never mixing the two DBs, and private to the operator's dev telemetry unless explicitly published. Off → SCX Code runs fully standalone (HR29).

**Remote-deploy over WinRM against `golem` (192.168.1.250) — correction (2026-07-20):** this doc previously said "remote-deploy tested" against golem. That was not true. Checked against the source session transcript (`C:\Users\joshl\.claude\projects\C--\0f744f2d-440f-4796-9ee1-8270f660256a.jsonl`, 2026-07-04): `golem` answered ping + `Test-WSMan` (WinRM reachable), but the one `Invoke-Command -ComputerName golem` probe that was actually run failed with Kerberos `0x8009030e` ("a specified logon session does not exist") — the assistant's non-interactive shell had no logon session for golem. The remote **install** itself was never attempted at all; the assistant only typed the command out for the operator to run by hand with their own credential. That same session's own gap ledger recorded it as outstanding: *"WinRM E2E install test on Golem (192.168.1.250) — NOT run."* It is still not run as of this correction.
The command that was typed in chat (never previously saved as a file) is now a real, re-runnable script: [install/Invoke-KritScxRemoteStoreProvision.ps1](../install/Invoke-KritScxRemoteStoreProvision.ps1) — `-Mode Probe` (ping/WinRM/SQL-instance discovery, read-only) plus `-Mode Install|Status|Repair|Uninstall` (wraps `Invoke-Command -FilePath Install-KriticalSCXStore.ps1` with a `-Credential`, dry-run unless `-Apply`, exactly the pattern from the transcript). It is **untested end-to-end** — parse-clean and PSScriptAnalyzer-clean, but nobody has run it against golem with a real credential yet. Full backout via `-Mode Uninstall` (drops just the DB) once it has.
