# Stale-scope truncation findings — Kritical.SCXCode

**Provenance**

| Field | Value |
|---|---|
| Date (UTC, absolute) | 2026-07-25T04:11Z – 05:20Z |
| Repo | `Kritical.SCXCode` |
| Branch | `refactor/extract-chat-compaction-20260722` |
| Commit SHA at observation | `ec40427739fc41e42bdee77548b2d30915494bf6` |
| Working tree at observation | dirty (1 entries) — other lanes may be active; **nothing in this repo was modified**, this is a findings document only |
| Estate-level report | `C:\temp\STALE-SCOPE-TRUNCATION-HUNT-20260725.md` |

**Bug class hunted.** A filter, range, list, limit or timeout is hardcoded once; the codebase
or its upstream data grows past it; the code keeps reporting SUCCESS while covering only a
fraction of what it claims. It never errors. It always looks green.

> **No code in this repo was changed by this hunt.** Findings are reports. Severity ranking and
> the estate-wide picture are in the estate-level report above.

---
## L2 (LOW) — corpus augmentation truncates on an 8s wall clock with no marker

`codex-wrapper/scx-corpus-augment.mjs:96`

```js
setTimeout(() => finish(out.slice(0, maxChars).trim()), 8_000); // hard timeout — never block the shim
```

plus `:77` `.slice(0, 24)` on the hit list.

A partial corpus is returned as though complete, with nothing marking the truncation. Rated LOW
because it degrades prompt quality rather than producing a false gate result — no verdict
depends on it.

**Authoritative source:** the full hit set, or an explicit `truncated: true` marker the consumer
can see.

**Evidence:** READ-FROM-SOURCE.

## Recommended fix
Return a `truncated` flag alongside the payload so a downstream consumer can tell a complete
corpus from a clipped one.
---

## Method

Multiple independent detection methods were used throughout, because **a low count from one
detector means the detector missed, not that the code is clean**: ripgrep regex sweeps,
PowerShell `Select-String` over enumerated file censuses, and — where quantification was
needed — direct execution, AST introspection, manifest parsing, or filesystem enumeration.

**Note on tooling:** `rg` is **not** on PATH inside the Bash tool on this host. The first
sweep of this hunt returned 0 hits for every pattern; that was a detector failure, not a clean
result. Use the Grep tool or PowerShell `Select-String`, and verify any zero with a second
method.

**Evidence tags** used above: VERIFIED-BY-EXECUTION (command run, output quoted) /
READ-FROM-SOURCE / INFERRED / UNKNOWN. A skip is never recorded as a pass.
