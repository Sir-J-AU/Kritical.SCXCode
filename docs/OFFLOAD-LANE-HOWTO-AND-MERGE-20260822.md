# Offload Lane — HOWTO + LM Studio Client Merge Record (2026-08-22)

**Date/time:** 2026-08-22 17:51 AEST (+10:00) — merge and refactor session start.
**Machine:** Stacktrace (`C:\Users\joshl\...`).
**Repo:** `Kritical.SCXCode` (real content reached on this machine ONLY via the `Kritical.Lens`
submodule mount — see path note below).
**Branch/commits at time of writing:** `master` @ `e24a62b` (merge commit) + one follow-up commit
landing this doc + the refactor + the test fix (see "Commit ledger" below for exact SHAs once
pushed).
**How established:** `VERIFIED-BY-EXECUTION` throughout unless marked otherwise. All commands and
their real output are quoted verbatim below, not summarised.
**Recheck trigger:** re-verify LM Studio reachability (`GET http://127.0.0.1:1234/v1/models`) and
re-run `mux\Invoke-KritOffload.test.ps1` before trusting this doc's "17/17 GREEN" claim again — LM
Studio is a locally-run desktop app the operator can stop at any time, and this doc's proof is a
point-in-time snapshot, not a standing guarantee.

---

## 1. What this session was asked to do

Finish wiring LM Studio (local inference, `http://127.0.0.1:1234`) as the estate's Tier-1
"cheapest fanout lane" per the estate's design:

1. Re-verify LM Studio is actually running.
2. Locate the real `Kritical.SCXCode` repo root and confirm branch state.
3. Merge the pre-pushed, untouched-for-days branch `thegrid-lmstudio-w365-routes-20260802` into
   `master`, under the estate's mandatory repo-lease protocol.
4. Refactor `Invoke-KritOffloadLmStudioCall` (inside `mux\Invoke-KritOffload.ps1`) to call the
   already-built `Kritical.PS.LMStudioAPI` client (`New-KritLMStudioChatcompletion`) instead of
   hand-rolling its own `Invoke-RestMethod` POST — per this estate's RULE ZERO ("extend, never
   rebuild").
5. Prove the test suite (`mux\Invoke-KritOffload.test.ps1`) is still green.
6. Prove a REAL live completion round-trips through the local LM Studio tier.
7. Push, and document all of it here.

---

## 2. Repo location — real path, not the hollow placeholder

`Github\Kritical.SCXCode` (a direct child of the operator's `Github\` folder) is a **hollow
OneDrive placeholder** on this machine — confirmed by this estate's own prior finding (see
`C:\Users\joshl\.claude\CLAUDE.md`, "A HOLLOW ONEDRIVE PLACEHOLDER READ AS A DESTROYED REPO").

The real, working checkout is reached as a git submodule of `Kritical.Lens`:

```
C:\Users\joshl\OneDrive - Kritical Pty Ltd\Github\Kritical.Lens\components\external-lineage\Kritical.SCXCode
```

`git rev-parse --show-toplevel` from that path returns exactly that path (not the Lens
superproject root), and `git rev-parse --git-dir` resolves to
`...\Kritical.Lens\.git\modules\components\external-lineage\Kritical.SCXCode` — i.e. a real,
independent git history stored inside Lens's superproject `.git`, checked out at that working-tree
path. `git remote -v` from there confirms `origin = https://github.com/Sir-J-AU/Kritical.SCXCode.git`
— the genuine `Kritical.SCXCode` repo, not a fork or a different project.

**This is the path every command in this document was run against.**

---

## 3. Branch state found, and a real defect caught before merging

### 3.1 LM Studio reachability (re-verified first, per the task instructions)

```powershell
Invoke-WebRequest -Uri 'http://127.0.0.1:1234/v1/models' -UseBasicParsing -TimeoutSec 5
```
Result: `HTTP 200`, 11 models loaded, including (among others) `openai/gpt-oss-20b`,
`google/gemma-4-e4b`, `qwen/qwen3.5-9b`, `deepseek/deepseek-r1-0528-qwen3-8b`,
`liquid/lfm2-24b-a2b`, and two embedding models (`nomic-ai/nomic-embed-text-v1.5-GGUF`,
`text-embedding-nomic-embed-text-v1.5`). **This list differs from the briefing's example model
names** (`openai/gpt-oss-20b`, `google/gemma-4-e4b`, `qwen/qwen3.5-9b` were named as examples in
the task and ARE present; the full 11-model set is broader and includes different additional
entries) — expected, since this is a locally-managed model set that changes as the operator swaps
models in/out. LM Studio being up at all was the load-bearing fact, and it was confirmed.

### 3.2 Local `master` was 46 commits STALE, not genuinely 2-commits-ahead

The task briefing said the feature branch was "2 commits ahead of master". That was true **against
`origin/master`**, but **local `master` on this checkout was NOT `origin/master`** — it was pinned
at the exact commit from this repo's original `git clone` (`d43e029`, dated 2026-07-27 per
`git reflog show master`) and had never been fast-forwarded since. Measured:

```
git rev-parse master        -> d43e029cc6fea5f36c4136bb2c49df1862a094b1
git rev-parse origin/master  -> 591dd7aac7a0522964883504437731a551795750
git merge-base --is-ancestor d43e029 origin/master   -> exit 0 (true: d43e029 IS an ancestor)
git merge-base --is-ancestor origin/master d43e029   -> exit 1 (false)
```

So local `master` was **46 commits behind** `origin/master`, not diverged — a simple staleness, not
a real conflict. Comparing the feature branch against the STALE local `master` produced a
misleadingly large diff (`252 files changed, 30589 insertions(+), 923 deletions(-)`, because it
included everything `origin/master` had already gained since the 2026-07-27 clone). Comparing
against the TRUE current tip (`origin/master`) gave the real, small diff:

```
git diff origin/master...thegrid-lmstudio-w365-routes-20260802 --stat
```
```
 .gitignore                                          |    3 +
 .../kritical_scx_logger.cpython-314.pyc              |  Bin 7643 -> 7685 bytes
 litellm/kritical-scx-openrouter.config.yaml          |   14 +-
 mux/Invoke-KritOffload.ps1                           | 1030 ++++++++++++++++++++
 mux/Invoke-KritOffload.test.ps1                      |  190 ++++
 5 files changed, 1230 insertions(+), 7 deletions(-)
```

— exactly matching the task's "2 real commits, small diff" description. Also found:
`origin/master` itself carries one commit the feature branch never had —
`591dd7a` "ci: gate all 5 CI jobs behind KRITICAL_GW_HOSTED_GATES_ENABLED (local gating only) (#3)"
— which is the estate's own GitHub-Actions-off switch already applied to THIS repo's CI workflow
(see §7 below).

**Fix applied:** fast-forwarded local `master` to `origin/master` first
(`git merge --ff-only origin/master`, `Updating d43e029..591dd7a, Fast-forward`), THEN merged the
feature branch on top of the now-current tip. This avoids creating a merge commit against a stale
base and avoids re-introducing 44 commits' worth of already-shipped history as a spurious diff.

---

## 4. GitHub Actions safety check (estate hard rule: no runner minutes before 2026-09-01)

Before pushing anything to `master`, verified this repo's CI cannot spend runner minutes:

```
gh api repos/Sir-J-AU/Kritical.SCXCode/actions/workflows
```
```json
{"total_count":1,"workflows":[{"id":306444557,"name":"CI","path":".github/workflows/ci.yml",
"state":"disabled_manually", ...}]}
```
— the workflow itself is `disabled_manually` (the estate's switch script already turned it off).
**Second, independent layer**, also checked:

```
gh api repos/Sir-J-AU/Kritical.SCXCode/actions/variables/KRITICAL_GW_HOSTED_GATES_ENABLED
-> 404 Not Found
```
— the repo variable `ci.yml`'s 5 jobs gate on (`if: vars.KRITICAL_GW_HOSTED_GATES_ENABLED == 'true'`)
does not exist, so even if the workflow were re-enabled, every job would still `if:`-skip (near-zero
billed minutes). Both checks agree: pushing to `master` here is safe under the standing directive.

---

## 5. The merge

```
git checkout master
git merge --ff-only origin/master     # d43e029 -> 591dd7a, fast-forward, clean
git merge --no-ff thegrid-lmstudio-w365-routes-20260802 -m "merge: land LM Studio offload lane ..."
```
Result: `Merge made by the 'ort' strategy.` — clean, **zero conflicts**. Merge commit: `e24a62b`.
`git status` immediately after: `nothing to commit, working tree clean`, `ahead of origin/master by
3 commits` (the fast-forward was already-published history, so only the merge commit + its two
parents-worth-of-newly-brought-in commits count as "ahead").

Files landed by the merge: `mux/Invoke-KritOffload.ps1` (new), `mux/Invoke-KritOffload.test.ps1`
(new), plus the small `.gitignore` / `litellm/kritical-scx-openrouter.config.yaml` / logger `.pyc`
changes already shown in the diff-stat above.

**Repo-lease protocol used** (estate hard rule):
```powershell
Import-Module "...\Kritical.PS.GitHub\src\Kritical.PS.GitHub.psd1" -Force
Enter-KritRepoLease -RepoPath <repo> -LaneId 'lmstudio-offload-merge-20260822' -Reason '...'
# ... all git add/commit/push wrapped inside the lease ...
Exit-KritRepoLease -RepoPath <repo> -LaneId 'lmstudio-offload-merge-20260822'
```
Lease acquired cleanly (`AcquiredUtc: 2026-08-22T07:43:02Z`, `TimeoutMinutes: 120`), no contention.

---

## 6. The refactor — `Invoke-KritOffloadLmStudioCall` now calls `Kritical.PS.LMStudioAPI`

### 6.1 Why

`mux\Invoke-KritOffload.ps1`'s `Invoke-KritOffloadLmStudioCall` hand-rolled its own
`Invoke-RestMethod -Uri "$Base/chat/completions" -Method Post ...`. A real, tested, generated
PowerShell client for exactly LM Studio's OpenAI-compatible API already exists:
`C:\Users\joshl\OneDrive - Kritical Pty Ltd\Github\Kritical.PS.LMStudioAPI\src\Krit.LMStudioOpenApi.psm1`
(single commit `12cd28d` on `main`, clean tree, pushed; `New-KritLMStudioChatcompletion` proven
live 2026-08-02 with 5 real generator bugs found/fixed — see that repo's
`docs\GATE-FINDINGS-20260802.md`). Per this estate's standing RULE ZERO ("extend, never rebuild"),
duplicating that HTTP call here is exactly the waste class the rule exists to stop.

### 6.2 What changed, and what did NOT

**Changed:** only the body of `Invoke-KritOffloadLmStudioCall` — the actual HTTP call now goes
through `New-KritLMStudioChatcompletion`. Added a helper,
`Resolve-KritOffloadLmStudioApiModulePath`, that locates
`Kritical.PS.LMStudioAPI\src\Krit.LMStudioOpenApi.psm1` via (in order): an explicit
`$env:KRIT_LMSTUDIOAPI_MODULE_PATH` override (RULE ZERO-C — settings-owned, not a hardcoded-only
path), a sibling-checkout-relative path (for a hypothetical standalone `Kritical.SCXCode` checkout
next to `Kritical.PS.LMStudioAPI` under a common `Github\` root), then the known absolute OneDrive
path on this operator's machine as the last-resort default (since, per §2 above, `Kritical.SCXCode`
is reached here only via the Lens submodule mount, not a standalone sibling checkout).

**Unchanged:** every tier-routing decision, the egress credential scan, the `-Sensitive`
never-downgrade-to-hosted rule, the judgement-work `-Purpose` refusal gate, the audit-log writer,
and the `-DryRun`/`-StatusOnly` paths — none of that logic was touched. `Invoke-KritOffloadLmStudioCall`
is called from exactly two places in `MAIN` (the `lmstudio` and `lmstudio-w365` resolved-route
branches), both unchanged.

### 6.3 A real integration bug found and fixed while proving the live smoke test

`New-KritLMStudioChatcompletion` does **not** accept a `-Base` parameter — it resolves its base URI
from `$env:KRIT_LMSTUDIO_BASE_URI` (module default `http://127.0.0.1:1234`, no `/v1` suffix; the
client appends `/v1/...` itself). The offload script's own convention is a `$Base` carrying a
trailing `/v1` (e.g. `http://127.0.0.1:1234/v1`, or a W365-forwarded-port equivalent). Fixed by
stripping the trailing `/v1` and save/restoring `$env:KRIT_LMSTUDIO_BASE_URI` around exactly one
call (save/restore, not set-and-forget, because this function can legitimately be called twice in
one process for `-Route auto` — once against `-LmStudioBase`, once against `-LmStudioW365Base` — and
the env var is process-wide state).

**Second, more consequential bug, caught only by actually running a live completion (not by the
offline test suite, which never sends a real Tier-1 payload):** the original hand-rolled call sent
`model: 'local-model'` and LM Studio's older behaviour apparently accepted that as a passthrough
alias. Against `New-KritLMStudioChatcompletion` on the SAME live server, that literal is now
**rejected**:

```
[Error] New-KritLMStudioChatcompletion failed: Response status code does not indicate success: 400 (Bad Request).
{ "error": { "message": "Invalid model identifier \"local-model\". Please specify a valid downloaded
model (e.g., microsoft/phi-4-reasoning-plus@q4_k_m, microsoft/phi-4-reasoning-plus,
phi-4-reasoning-plus).", "type": "invalid_request_error", "param": "model", "code": "model_not_found" } }
```

**Fix:** `Invoke-KritOffloadLmStudioCall` no longer hardcodes any model id at all (that would also
be RULE ZERO-C-adjacent — a specific model literal breaks the moment the operator swaps loaded
models). It now calls `Get-KritLMStudioModelsopenai` against the resolved base and picks the first
returned model id that does not match `(?i)embed` (LM Studio's own naming convention always
includes "embed" for embeddings models, e.g. `nomic-ai/nomic-embed-text-v1.5-GGUF` — those 400 on
`/chat/completions` too, so they are excluded from the candidate pool). If every loaded model looks
like an embedding model, the function throws a named error rather than guessing.

This was found and fixed live, in this session, by actually sending a prompt — not by the test
suite, which is offline-first by design (see its own header: "WHAT THIS DOES NOT TEST: an actual
LM Studio send"). **This is exactly why the task's step 7 (a real live smoke test) mattered — the
17/17-green offline suite alone would NOT have caught this.**

---

## 7. Test suite — before/after, full output quoted

Command: `pwsh -File mux\Invoke-KritOffload.test.ps1` (from the repo's `mux\` directory; standalone
script, not Pester — see its own header).

### 7.1 First run, immediately after the merge + client-call refactor (before the model-id fix)

Same run also surfaced a SECOND, pre-existing defect, unrelated to this session's refactor:

```
TOTAL: 17   PASS: 16   FAIL: 1
lmstudio-w365-configured-but-unreachable-refuses  False  threw, but message did not match /UNREACHABLE/ — got: Invoke-Kr...
```

**Root cause, proven, not guessed:** `git show 52df5a4 -- mux/Invoke-KritOffload.ps1` (the SECOND
commit on the merged feature branch, "Correct W365 offload tunnel semantics", 2026-08-07) shows
this line changed:
```
- $refusalReason = "Explicit -Route lmstudio-w365 requested but is UNREACHABLE at $LmStudioW365Base ..."
+ $refusalReason = "Explicit -Route lmstudio-w365 requested but is TUNNEL-NOT-ESTABLISHED at $LmStudioW365Base ..."
```
— a deliberate, real precision improvement (an unreachable LOCAL loopback port means the reverse
tunnel is down, not that LM Studio itself is unreachable; the header docstring devotes several
paragraphs to this exact distinction). `git show 52df5a4 --stat` confirms
`mux/Invoke-KritOffload.test.ps1` was **not** among the files that commit touched — so test case 10
(`lmstudio-w365-configured-but-unreachable-refuses`, asserting `-ExpectMessageMatch 'UNREACHABLE'`)
has been silently broken since 2026-08-07, entirely predating this session and unrelated to the
`Kritical.PS.LMStudioAPI` client refactor (that refactor only touches
`Invoke-KritOffloadLmStudioCall`, which this refusal path never reaches — it throws in `MAIN`
before any LM Studio call is attempted).

**Fix (this session):** updated the test's expected regex to `'TUNNEL-NOT-ESTABLISHED'`, matching
the current, intentional production wording — the production message was NOT reverted, since its
2026-08-07 change was a deliberate improvement.

### 7.2 Second run, after the test-regex fix, before the model-id fix

```
TOTAL: 17   PASS: 17   FAIL: 0
```
(All green — but note this run still could not have caught the `model_not_found` bug, since none
of the 17 cases exercises a real Tier-1 send; see the suite's own documented non-coverage.)

### 7.3 Third run, after the model-id fix (final state)

```
Case                                             Pass Detail
----                                             ---- ------
egress-refuses-fake-aws-key                      True
egress-refuses-fake-secret-assign                True
egress-allows-clean-payload                      True
thegrid-denylist-blocks-kritical-scx             True
thegrid-denylist-blocks-kritical-coding          True
sensitive-refuses-when-lmstudio-unreachable      True
dryrun-no-send                                   True
purpose-refuses-judgement                        True
purpose-refuses-gate-verdict                     True
purpose-refuses-adversarial-refutation           True
purpose-refuses-correctness-decision             True
purpose-default-not-blocked-by-judgement-gate    True
direct-provider-invalid-key-fails-loud           True Correctly failed on the invalid key (real network round-trip made...
lmstudio-w365-not-configured-refuses-fast        True
lmstudio-w365-configured-but-unreachable-refuses True
legacy-route-lmstudio-still-works-as-local-alias True
statusonly-reports-two-distinct-lmstudio-rows    True

TOTAL: 17   PASS: 17   FAIL: 0
EXIT CODE: 0
```

**What this suite tests:** egress credential-scan refusal (planted fake AWS key + generic secret
assignment), a clean payload NOT being falsely flagged, the thegrid-budget route denylist
(`ValidateSet` refusal), the `-Sensitive` + Tier-1-unreachable refusal, `-DryRun` making no network
call, the judgement-work `-Purpose` gate (4 forbidden values + the default not being blocked), a
real direct-HTTPS provider auth-rejection round-trip (nvidia-direct, deliberately wrong key), the
`lmstudio-w365` `NOT-CONFIGURED` vs `TUNNEL-NOT-ESTABLISHED` distinction, the legacy `-Route
lmstudio` alias, and `-StatusOnly` reporting two distinct LM Studio rows.

**What this suite explicitly does NOT test** (per its own header, unchanged by this session): an
actual LM Studio send, a genuinely successful direct-provider completion (proven separately), and
the Docker-hosted Tier-2 path. **§8 below is what closes that specific gap.**

---

## 8. Live smoke test — real completions through Tier 1, quoted in full

### 8.1 `-Route lmstudio-local`, default output (Content only)

```powershell
& $scriptPath -Prompt "Reply with exactly one short sentence confirming you are a local LM Studio model, and name yourself." -Route lmstudio-local -MaxTokens 60
```
Output (the function's default, non-`-Raw` return is just the completion string):
```
Yes, I am LM Studio's local model named "LM Studio".
```

### 8.2 Same call with `-Raw`, full structured result

```
Route         : lmstudio
ReportedModel : liquid/lfm2-24b-a2b
Content       : Yes, I am LM Studio's local model named "LM Studio".
FinishReason  : stop
Usage         : @{prompt_tokens=28; completion_tokens=15; total_tokens=43; completion_tokens_details=}
Sent          : True
AuditLogPath  : C:\Users\joshl\.claude\process-harness\logs\offload-egress\offload-egress-2026-08-22.jsonl
```

Audit log entry (real file, tail -1, redacted-payload field intact per design):
```json
{"timestampUtc":"2026-08-22T07:50:21.4409296Z","egressReasons":[],"resolvedRoute":"lmstudio",
"promptChars":100,"egressSafe":true,"lmReachable":true,"outcome":"SENT",
"reportedModel":"liquid/lfm2-24b-a2b","finishReason":"stop","dryRun":false,
"hostedReachable":false,"promptRedacted":"Reply with exactly one short sentence confirming you are
a local LM Studio model, and name yourself.","sensitive":false,"responseChars":52,
"lmW365Reachable":false,"requestedRoute":"lmstudio-local"}
```

### 8.3 `-Sensitive` path, proving the never-downgrade route also actually sends

```powershell
& $scriptPath -Prompt "Say only the word: confirmed" -Sensitive -MaxTokens 10 -Raw
```
```
Route         : lmstudio
ReportedModel : liquid/lfm2-24b-a2b
Content       : confirmed
FinishReason  : stop
Sent          : True
```

**This proves, end to end, live:** route resolution -> egress scan -> real HTTP call via
`Kritical.PS.LMStudioAPI`'s `New-KritLMStudioChatcompletion` -> real model inference on this
machine's local GPU/NPU -> real response parsed back into the offload script's own result shape ->
audit log written with the real model id and finish reason. Both the default (non-sensitive) and
`-Sensitive` code paths were exercised live, not just the offline guard tests.

### 8.4 `-StatusOnly` snapshot at the time of this session

```
Provider                                   State                  Detail
--------                                   -----                  ------
lmstudio-local (this laptop)               RUNNING-AND-ANSWERING  binary=True models=4(37GB) port1234=True
lmstudio-w365 (Cloud PC)                   NOT-CONFIGURED         No -LmStudioW365Base was supplied...
nvidia-direct                              OK                     GET /models returned HTTP 200
openrouter-direct                          OK                     GET /models returned HTTP 200
mistral-direct                             OK                     GET /models returned HTTP 200
kritical-litellm-docker (Tier 2, optional) UNREACHABLE (Docker daemon not required/running)
```

---

## 9. Discoverability — how a lane finds this without re-deriving it

Per the task's own instruction to check the estate's convention for "here's how an agent finds the
cheap local lane" rather than inventing a new registry: checked
`krit-api-registry.json`
(`C:\Users\joshl\OneDrive - Kritical Pty Ltd\Github\Kritical.Lens\components\data-infra\Kritical.Lens.Toolkit\api-mapper\krit-api-registry.json`)
— it already carries an `"lmstudio"` entry (per the task briefing) covering the API surface
itself, but that registry is about API SPECS (REST/GraphQL diffing), not "which script to call for
bulk offload work". **A full search for any existing "how does an agent find the cheap local
fanout lane" registry/convention did not turn one up** — `Invoke-KritOffload.ps1` itself is
discoverable only by knowing its path or by reading this repo's own `mux\` folder / this doc.

**This is a genuine gap, recorded honestly rather than invented around:** there is no estate-wide
"capability index" entry pointing at `Invoke-KritOffload.ps1` as *the* cheap-fanout lane. The
closest existing mechanism is `Kritical.Lens`'s own component index
(`lens-components.json` / `LENS-COMPONENT-INDEX.md`), but `Kritical.SCXCode`'s `mux\` scripts are
not separately indexed there as callable tools (the Lens index tracks components/analyzers, not
individual utility scripts inside a component). **Recommendation, not built this session (out of
the merge's scope, and building a new registry mechanism without operator sign-off would risk
re-deriving something that already exists elsewhere unseen — RULE ZERO applies to NOT inventing
new indices too):** register `Invoke-KritOffload.ps1` as an entry in whatever mechanism the ES
(`Kritical.GreatWhite.Control.EngineeringSystem`) uses for "reusable capability" lookups
(`find_reusable_components` tool exists on the ES MCP per this estate's plugin list) — flagged here
as the next actionable step, not silently left undocumented.

---

## 10. Known gaps and honest limits — carried forward, not fixed this session

- **W365 leg genuinely unverified.** `-LmStudioW365Base` was never supplied in this session (no
  reverse tunnel address was available to test against), so `lmstudio-w365 (Cloud PC)` still
  correctly reports `NOT-CONFIGURED`. This session did not attempt to bring up the
  `Kritical.SecureRemoteNetworking` reverse tunnel (that remains an OPERATOR-driven step per the
  script's own header docstring: no automatic service startup / no credentialed remote session
  without a typed ack). **Recheck trigger:** re-run `-StatusOnly` after the operator brings the
  tunnel up; the `lmstudio-w365` row must read `RUNNING-AND-ANSWERING` before that route is relied
  on for anything.
- **Streaming is not implemented.** `New-KritLMStudioChatcompletion`'s own doc comment states it
  does not parse SSE; `-Stream` would return raw unparsed SSE text. `Invoke-KritOffloadLmStudioCall`
  never passes `-Stream`, so this is consistent, but genuinely unbuilt if a future caller wants
  streaming.
- **Model-unload path unverified.** `Kritical.PS.LMStudioAPI` exports
  `New-KritLMStudioModelunload`; this session's refactor uses `Get-KritLMStudioModelsopenai` +
  `New-KritLMStudioChatcompletion` only. Unload was neither needed nor exercised.
  `New-KritLMStudioModelload`'s "loading an already-loaded model's config is undefined by the
  docs" caveat (from that module's own synopsis) also was not tested here, since this refactor
  only ever picks an ALREADY-loaded model rather than loading a new one.
- **The capability-discoverability gap in §9** is real and not closed by this session.
- **The "estate cheapest-correct SCX pick" heuristic does not apply to this laptop's LM Studio
  models** — this was already known/documented in the script's own header (2026-08-02 correction:
  none of the locally-installed models is `Gemma-4-31B`) and remains true; the live smoke test in
  §8 used whatever model LM Studio happened to have loaded (`liquid/lfm2-24b-a2b`), picked
  automatically by the new model-resolution logic in §6.3, not by any quality/cost ranking.

---

## 11. Commit ledger (fill in exact SHAs after push — see the same-session chat transcript for the
   authoritative values if this section is ever out of sync with `git log`)

| Commit | What |
|---|---|
| `e24a62b` | merge: land LM Studio offload lane (`thegrid-lmstudio-w365-routes-20260802`) into `master` |
| (next)   | refactor: `Invoke-KritOffloadLmStudioCall` calls `Kritical.PS.LMStudioAPI` instead of hand-rolled REST; fix stale `TUNNEL-NOT-ESTABLISHED` test regex (pre-existing, unrelated defect); fix `model_not_found` (dynamic model resolution); this doc |

`git log --oneline -5` on `master` after the follow-up commit is the authoritative source if this
table ever drifts — regenerate rather than trust a stale copy, per this estate's own documentation
standard.
