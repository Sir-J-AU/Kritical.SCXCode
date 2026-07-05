<!-- Tick-off ledger for the .5231 deep-bughunt fix wave. Findings from the `scx-deep-bughunt`
     34-agent adversarial workflow (task w3z724m1b): 27 confirmed bugs. -->

# .5231 — Deep Bughunt Fix Wave (tick-off)

The `scx-deep-bughunt` workflow (34 agents, adversarially verified) confirmed **27 bugs**.
This wave fixed **18**, verified: extension rebuilds clean (v0.1.27), shim tests 6/6, every edited
PowerShell/Python file parses.

## Fixed

| # | Sev | File | Bug | Fix |
|---|-----|------|-----|-----|
| 1 | HIGH | `src/extension.ts` | `switchKey` had no handler in the panel webview — the 429 "Switch SCX key" button was dead there | Added the `switchKey` case to the panel handler |
| 2 | HIGH | `src/extension.ts` | `switchKey` mutated `process.env.SCX_API_KEY`; `getConfig()` re-derived+re-deduped from it, shrinking the key set and losing keys | Rotate a **stable** deduped list by `_keyRotation` in `getConfig()`; never mutate env |
| 3 | HIGH | `src/extension.ts` | Failed send left the orphaned user turn in history → next send 400s "roles must alternate" → chat bricked | Pop the trailing user turn on error in **both** panel + sidebar catch blocks |
| 4 | MED | `src/extension.ts` | `temperature` sent verbatim; out-of-range value → hard 400 | Clamp to SCX's proven `[0,2]` in `scxPost` |
| 5 | MED | `codex-wrapper/scx-agentic-shim.mjs` | A failed plan-gate **retry** streamed an opaque error via the byte reader | Clean error return + logging + telemetry when the retry itself ≥400 |
| 6 | MED | `codex-wrapper/scx-agentic-shim.mjs` | Telemetry `tools_out`/`flattened` reflected the first attempt, not the retried (server-tools-dropped) payload | Recompute both from the retry body |
| 9 | MED | `codex-wrapper/kritical-codex.ps1` | Kill-switch force-killed whatever owned :4199 at teardown — could nuke an innocent process | Track the exact launched node PID; identity-check before `Stop-Process` |
| 10 | HIGH | `codex-wrapper/kritical-codex.ps1` | Shim launched without pinning `KRIT_SHIM_PORT`/`KRIT_SHIM_UPSTREAM`/`SCX_API_KEY` — non-default port silently mismatched; HKCU key might not reach the child | Export the three vars before `Start-Process` (inherited by the child) |
| 16 | HIGH | `litellm/Install-KritScxLiteLLM.ps1` | `$pid = …` — assigning the **read-only** automatic `$pid` threw, breaking `Get-KritLiteLLMPid` | Renamed to `$procId` |
| 17 | HIGH | `litellm/Install-KritScxLiteLLM.ps1` | Same `$pid` write in `-Mode Status` | Renamed to `$litellmPid` |
| 18 | MED | `ps-module/Kritical.PS.SCXCode.psm1` | `$currentKey.Substring(0,8)` threw when the key was null/short | Null + length guard |
| 19 | LOW | `safety/Restore-WorkingClaude.ps1` | Rescue script force-killed the :4180 owner with no identity check | Only kill a `python`/`litellm` owner; otherwise leave it |
| 20 | MED | `install/Install-KriticalSCX.ps1` | "litellm installed" ✅/❌ reused the venv-exists predicate — green even when litellm absent | Drive it off an actual `import litellm` |
| 22 | LOW | `litellm/Install-KritScxLiteLLM.ps1` | `"…".PadRight(60) + '║'` bound `+ '║'` as extra `Write-Host` args, mangling the banner | Parenthesised the expression |
| 23 | HIGH | `mux/Invoke-KritScxSyntheticContext.py` | No per-stream error isolation — one stream's `HTTPError` re-raised through `ex.map`, discarding all successful streams | try/except per stream; synthesise from survivors; guard all-failed + baseline |
| 24 | HIGH | `lens/Invoke-KritScxSourceIngest.py` | "byte-exact" storage decoded utf-8/replace into NVARCHAR (mangling non-UTF-8 bytes); the "reassembly proof" compared lossy-text vs lossy-text (same U+FFFD both sides) so it always passed; `stored_sha` never checked | Store **raw bytes** via `COMPRESS(<varbinary>)`; prove at byte level (`DECOMPRESS` bytes == original bytes **and** re-hash == stored sha256) |
| 25 | MED | `store-mcp/kritical-local-store.mjs` | `search('')` built an invalid `WHERE` → SQL throw | Guard empty terms; return empty cleanly |
| 26 | LOW | `mux/Invoke-KritScxSyntheticContext.py` | Context cap 11 000 chars (~2.7k tok) — far under the real gpt-oss-120b ~108k ceiling | Raised default to 90 000 |

## Not yet fixed (tracked)

| # | Sev | File | Why deferred |
|---|-----|------|--------------|
| 7, 8 | LOW | `scx-agentic-shim.mjs` | URL-prefix strip / content-type passthrough — cosmetic robustness |
| 11–14 | MED | `codex-wrapper/pack/*` | Build/Apply pack scripts — **owned by the live compile sessions**; not touched to avoid collision |
| 15 | LOW | `kritical-codex.ps1` | Model auto-correct already warns; message wording only |
| 21 | MED | `install/Install-KritScxVsCode.ps1` | Heal re-runs full install on any ABSENT — needs `Invoke-InstallContinue` idempotency review before changing |
| 27 | LOW | `lens/Invoke-KritScxCorpusMine.py` | Call-graph edge matcher false-positives inside comments/strings |
