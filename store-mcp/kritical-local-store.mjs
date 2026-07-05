// Kritical SCXCode — LOCAL embeddable corpus store (node:sqlite, zero native deps, Node >= 22).
//
// The portable alternative to KriticalSCXCodeStore (SQL Express) for the synthetic-context /
// mega-context feature — so you get the whole "retrieve real code, mux over it" experience WITHOUT
// installing SQL Server. A single .db file under ~/.kritical-scx that the VS Code extension can carry.
//
//   node kritical-local-store.mjs mine <repoRoot>      build/refresh the local corpus
//   node kritical-local-store.mjs search "<keywords>"  retrieve matching files (synthetic context)
//   node kritical-local-store.mjs symbols <name>       find a symbol across the corpus
//   node kritical-local-store.mjs stats                corpus summary
//
// Author: Joshua Finley — Kritical Pty Ltd — (c) 2026.
import { DatabaseSync } from 'node:sqlite';
import { readdirSync, statSync, readFileSync, mkdirSync } from 'node:fs';
import { join, extname, relative, dirname } from 'node:path';
import { homedir } from 'node:os';
import { createHash } from 'node:crypto';

const DB_PATH = process.env.KRIT_LOCAL_STORE || join(homedir(), '.kritical-scx', 'scxcode-store.db');
mkdirSync(dirname(DB_PATH), { recursive: true });

const CODE = new Set(['.ps1', '.psm1', '.py', '.ts', '.js', '.mjs', '.cjs', '.md', '.json', '.toml', '.sql']);
const SKIP = /(^|[\\/])(node_modules|\.git|out|dist|receipts|sources|emitted|__pycache__)([\\/]|$)/;

// language function extractors (mirrors the SQL miner, incl. TS arrow-fns/exports/classes)
const FUNC = {
  ps1: /^\s*function\s+([A-Za-z][\w-]*)/gm, psm1: /^\s*function\s+([A-Za-z][\w-]*)/gm,
  py: /^\s*def\s+([A-Za-z_]\w*)/gm,
  ts: /^\s*(?:export\s+)?(?:async\s+)?function\s+([A-Za-z_]\w*)|^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z_]\w*)\s*=\s*(?:async\s*)?\([^)]*\)\s*(?::\s*[^={]+)?=>|^\s*(?:export\s+)?(?:abstract\s+)?class\s+([A-Za-z_]\w*)/gm,
};
FUNC.js = FUNC.ts; FUNC.mjs = FUNC.ts; FUNC.cjs = FUNC.ts;

function db() { const d = new DatabaseSync(DB_PATH); d.exec('PRAGMA journal_mode=WAL;'); return d; }
function ensure(d) {
  d.exec(`CREATE TABLE IF NOT EXISTS files(path TEXT PRIMARY KEY, lang TEXT, loc INT, sha TEXT, fn_count INT, content TEXT, mined_utc TEXT);
          CREATE TABLE IF NOT EXISTS symbols(path TEXT, name TEXT, kind TEXT, line INT);
          CREATE INDEX IF NOT EXISTS ix_sym_name ON symbols(name);`);
}

function* walk(root) {
  for (const name of readdirSync(root)) {
    const p = join(root, name);
    if (SKIP.test(p)) continue;
    let s; try { s = statSync(p); } catch { continue; }
    if (s.isDirectory()) yield* walk(p);
    else if (CODE.has(extname(p).toLowerCase())) yield p;
  }
}

function mine(root) {
  const d = db(); ensure(d);
  d.exec('DELETE FROM files; DELETE FROM symbols;');
  const insF = d.prepare('INSERT OR REPLACE INTO files VALUES(?,?,?,?,?,?,?)');
  const insS = d.prepare('INSERT INTO symbols VALUES(?,?,?,?)');
  const now = new Date().toISOString();
  let nf = 0, ns = 0;
  d.exec('BEGIN');
  for (const p of walk(root)) {
    let src; try { src = readFileSync(p, 'utf8'); } catch { continue; }
    const rel = relative(root, p).replace(/\\/g, '/');
    const lang = extname(p).slice(1).toLowerCase();
    const sha = createHash('sha256').update(src).digest('hex');
    const loc = src.split('\n').length;
    const re = FUNC[lang]; let funcs = 0;
    if (re) { re.lastIndex = 0; let m; while ((m = re.exec(src)) !== null) { const name = m[1] || m[2] || m[3]; if (name && !['if', 'for', 'while', 'switch', 'catch', 'return', 'function'].includes(name)) { insS.run(rel, name, 'function', src.slice(0, m.index).split('\n').length); funcs++; ns++; } } }
    insF.run(rel, lang, loc, sha, funcs, src, now);
    nf++;
  }
  d.exec('COMMIT');
  console.log(`[local-store] mined ${nf} files · ${ns} symbols -> ${DB_PATH}`);
}

function search(keywords, maxChars = 11000) {
  const d = db(); ensure(d);
  const terms = String(keywords || '').split(/\s+/).filter(Boolean);
  // .5231 (bughunt) — empty/whitespace keywords yield no terms, which built an invalid `WHERE` clause
  // (SQL syntax error). Return an empty result cleanly instead of throwing.
  if (!terms.length) { console.log('[local-store] no search terms supplied — nothing to search.'); return ''; }
  const where = terms.map(() => 'path LIKE ? OR content LIKE ?').join(' OR ');
  const args = terms.flatMap((t) => [`%${t}%`, `%${t}%`]);
  const rows = d.prepare(`SELECT path, lang, content FROM files WHERE ${where} ORDER BY LENGTH(content) LIMIT 8`).all(...args);
  let used = 0; const out = [];
  for (const r of rows) {
    const snippet = r.content.slice(0, 4500);
    const block = `### FILE: ${r.path}\n\`\`\`${r.lang}\n${snippet}\n\`\`\`\n`;
    if (used + block.length > maxChars) break;
    out.push(block); used += block.length;
  }
  console.log(`[local-store] ${out.length} files / ${used} chars for: ${keywords}\n`);
  console.log(out.join('\n'));
  return out.join('\n');
}

function symbols(name) {
  const d = db(); ensure(d);
  const rows = d.prepare('SELECT name, path, line FROM symbols WHERE name LIKE ? ORDER BY name LIMIT 40').all(`%${name}%`);
  rows.forEach((r) => console.log(`  ${r.name}  —  ${r.path}:${r.line}`));
}

function stats() {
  const d = db(); ensure(d);
  console.log('DB:', DB_PATH);
  for (const r of d.prepare('SELECT lang, COUNT(*) c, SUM(loc) loc, SUM(fn_count) fns FROM files GROUP BY lang ORDER BY c DESC').all())
    console.log(`  ${String(r.lang).padEnd(6)} ${r.c} files · ${r.loc} loc · ${r.fns} fns`);
  console.log('  total symbols:', d.prepare('SELECT COUNT(*) c FROM symbols').get().c);
}

const [cmd, arg] = process.argv.slice(2);
if (cmd === 'mine') mine(arg || '.');
else if (cmd === 'search') search(arg || '');
else if (cmd === 'symbols') symbols(arg || '');
else if (cmd === 'stats') stats();
else console.log('usage: kritical-local-store.mjs mine <repo> | search "<kw>" | symbols <name> | stats');
