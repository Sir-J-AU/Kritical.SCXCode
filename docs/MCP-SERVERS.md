# Kritical SCX — Useful MCP Servers (for the selector)
_What you already have + high-value additions, so MCP becomes a tick-box loadout like extensions._

## Already configured (Codex `config.toml`)
| MCP | Backend | Status | Use |
|---|---|---|---|
| shopify-dev-mcp | `npx @shopify/dev-mcp` | ✅ works | Shopify Admin/theme dev |
| falcon-mcp | `uvx falcon-mcp` | ✅ works | CrowdStrike Falcon (detections/hosts/intel) |
| pax8 | https url | ✅ works | Pax8 distributor API |
| node_repl | exe | ✅ works | Codex's JS REPL |
| **bc_al (AL)** | `altool` | ⚠️ **broken** | AL/Business Central — see fix below |

### 🔧 AL MCP fix (ready)
`altool` isn't on PATH; the win binary exists. In `~/.codex/config.toml` set:
```toml
[mcp_servers.bc_al]
command = "C:\\Users\\joshl\\.vscode-insiders\\extensions\\ms-dynamics-smb.al-18.0.2498801\\bin\\win32\\altool.exe"
args = ["launchmcpserver --transport stdio"]
```

## High-value ADDITIONS for your stack (all MIT/official, OpenAI-shape MCP)
| MCP | Install | Why for Kritical |
|---|---|---|
| **filesystem** | `npx @modelcontextprotocol/server-filesystem` | scoped file access for agents |
| **git** | `uvx mcp-server-git` | repo history/blame/diff as tools |
| **github** | `npx @modelcontextprotocol/server-github` | issues/PRs/releases (pairs with Kritical.PS.GitHub) |
| **sqlite / mssql** | `uvx mcp-server-sqlite` / community mssql MCP | **query `KriticalSCXCodeStore` directly** — the mined store as a tool |
| **memory** | `npx @modelcontextprotocol/server-memory` | persistent knowledge graph (complements HR27 store) |
| **sequential-thinking** | `npx @modelcontextprotocol/server-sequential-thinking` | structured reasoning for the muxing engine |
| **fetch** | `uvx mcp-server-fetch` | clean URL→markdown for research |
| **playwright** | `npx @playwright/mcp` | browser automation / theme QA (you already have Puppeteer via Codex) |
| **azure-mcp** | `npx @azure/mcp` | you have the VS Code Azure MCP ext; CLI MCP for agents |
| **microsoft-docs** | (hosted) | you already use Microsoft Learn MCP |
| **time** | `uvx mcp-server-time` | tz-aware timestamps (HR27 logging) |

## Selector integration (planned)
`ext-manifest.json` gains an `"mcp"` block (server → command/args/scope), and the tick-box webview lists MCP servers alongside extension stacks. Enabling an MCP loadout writes/uncomments the matching `[mcp_servers.*]` entries in `config.toml` (additive, reversible) — same pattern as extension `--disable-extension`. Claude/Codex native MCP untouched unless you tick it.

## Standout picks for the mega-context vision
- **sqlite/mssql MCP** → agents query the mined store (`decision_log`, `context_shard`, `LensSqlCatalog`) as a first-class tool = the retrieval half of "context from thin air".
- **sequential-thinking** → the planner/synthesiser in the muxing engine.
- **memory** → cross-session knowledge graph on top of the store.
