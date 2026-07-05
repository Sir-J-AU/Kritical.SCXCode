// Kritical SCX agentic flatten-shim.
//
// Localhost Responses proxy that lets codex (wire_api="responses") drive SCX agentically.
// Codex serialises its shell/apply_patch tools as types SCX rejects (namespace/custom/local_shell/
// freeform). SCX accepts `function` tools and emits `function_call`. This shim rewrites the outbound
// `tools` to `function`, forwards to SCX, and streams the response back (SSE passthrough in v1).
//
// HR1/HR29: SCX_API_KEY only; never reads OPENAI_*/ANTHROPIC_*; binds localhost only.
// See ../docs/SCX-AGENTIC-BRIDGE-SPEC.md §3. No dependencies (Node >= 20 global fetch).
//
// Author: Joshua Finley — Kritical Pty Ltd — (c) 2026

import http from 'node:http';
import { appendFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const HOST = '127.0.0.1';
const PORT = parseInt(process.env.KRIT_SHIM_PORT || '4199', 10);
const UPSTREAM = (process.env.KRIT_SHIM_UPSTREAM || 'https://api.scx.ai/v1').replace(/\/$/, '');
const KEY = process.env.SCX_API_KEY || '';
const LOG = process.env.KRIT_SHIM_LOG || join(tmpdir(), 'krit-shim.log');
const DEBUG = process.env.KRIT_SHIM_DEBUG === '1';

// SCX's accepted server tool types (from live probe) — everything else from a client is treated as a
// local function tool.
const SERVER_TOOLS = new Set([
  'web_search', 'code_interpreter', 'file_retrieval', 'academic_search', 'youtube_search', 'reddit_search',
  'x_search', 'mcp_search', 'trove_search', 'retrieve', 'movie_tv_search', 'trending_movies', 'trending_tv',
  'mermaid_diagram', 'coin_data', 'coin_data_by_contract', 'coin_ohlc', 'currency_converter', 'stock_chart',
  'stock_price', 'find_place_on_map', 'nearby_places_search', 'weather', 'travel_advisor', 'flight_tracker',
  'flight_live_tracker', 'datetime', 'greeting', 'text_translate', 'memory_manager',
]);

function log(...a) { try { appendFileSync(LOG, a.map((x) => (typeof x === 'string' ? x : JSON.stringify(x))).join(' ') + '\n'); } catch {} }

/** Rewrite one tool into something SCX accepts. Returns an array (namespace flattens to many). */
function flattenTool(t, dropServer) {
  if (!t || typeof t !== 'object') return [t];
  const type = t.type;
  if (SERVER_TOOLS.has(type)) return dropServer ? [] : [t];                    // plan-gated; drop on retry
  if (type === 'function') return [t];                                         // already fine
  // namespace grouping -> spread its inner tools (usually already function)
  if (type === 'namespace' && Array.isArray(t.tools)) {
    return t.tools.flatMap((inner) => {
      if (inner && inner.type === 'function') return [inner];
      const fn = inner && inner.function ? inner.function : inner;
      return [{ type: 'function', name: fn?.name || t.name || 'tool', description: fn?.description || '', parameters: fn?.parameters || { type: 'object', properties: {} } }];
    });
  }
  // local_shell / custom / freeform / anything else -> a plain function tool, name preserved
  return [{
    type: 'function',
    name: t.name || (type === 'local_shell' ? 'shell' : type) || 'tool',
    description: t.description || `Local ${type} tool`,
    parameters: t.parameters || t.input_schema || { type: 'object', properties: { input: { type: 'string' } } },
  }];
}

function transformRequestBody(body, dropServer = false) {
  if (!body || !Array.isArray(body.tools)) return body;
  const before = body.tools.map((t) => t?.type).join(',');
  const tools = body.tools.flatMap((t) => flattenTool(t, dropServer));
  const after = tools.map((t) => t?.type).join(',');
  if (before !== after) log('[req] tools', before, '->', after, dropServer ? '(server dropped)' : '');
  return { ...body, tools };
}

function isPlanGateError(status, text) {
  return status === 400 && /current plan|model_not_in_plan|not available on your/i.test(text || '');
}

export { flattenTool, transformRequestBody, isPlanGateError, SERVER_TOOLS };

const server = http.createServer((req, res) => {
  const chunks = [];
  req.on('data', (c) => chunks.push(c));
  req.on('end', async () => {
    const raw = Buffer.concat(chunks).toString('utf8');
    const url = new URL(req.url, `http://${HOST}`);
    const target = UPSTREAM + url.pathname.replace(/^\/v1/, '') + url.search;

    const isResponses = req.method === 'POST' && url.pathname.endsWith('/responses');
    let parsed = null;
    if (isResponses) { try { parsed = JSON.parse(raw); if (DEBUG) log('[req.raw.tools]', JSON.stringify(parsed.tools || []).slice(0, 4000)); } catch (e) { log('[req] parse fail', e.message); } }

    const call = (bodyStr) => fetch(target, {
      method: req.method,
      headers: { 'content-type': 'application/json', authorization: `Bearer ${KEY}`, accept: req.headers['accept'] || 'application/json' },
      body: req.method === 'GET' || req.method === 'HEAD' ? undefined : bodyStr,
    });

    try {
      const firstBody = isResponses && parsed ? JSON.stringify(transformRequestBody(parsed)) : raw;
      let upstream = await call(firstBody);

      // On a plan-gate 400 (a server tool the model's plan can't run), retry with server tools dropped.
      if (isResponses && parsed && upstream.status >= 400) {
        const errText = await upstream.text();
        if (isPlanGateError(upstream.status, errText)) {
          log('[retry] plan-gate — dropping server tools and retrying');
          upstream = await call(JSON.stringify(transformRequestBody(parsed, true)));
        } else {
          res.writeHead(upstream.status, { 'content-type': upstream.headers.get('content-type') || 'application/json' });
          res.end(errText);
          log('[resp]', upstream.status, errText.slice(0, 160));
          return;
        }
      }

      res.writeHead(upstream.status, { 'content-type': upstream.headers.get('content-type') || 'application/json' });
      const reader = upstream.body?.getReader();
      if (reader) { while (true) { const { done, value } = await reader.read(); if (done) break; res.write(Buffer.from(value)); } }
      res.end();
      if (upstream.status >= 400) log('[resp]', upstream.status, target);
    } catch (e) {
      log('[proxy] error', e.message);
      res.writeHead(502, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: { message: `shim upstream error: ${e.message}` } }));
    }
  });
});

// Only bind the port when run directly (so tests can import the transforms without starting a server).
if (process.argv[1] && import.meta.url === `file://${process.argv[1].replace(/\\/g, '/')}`) {
  server.listen(PORT, HOST, () => {
    console.log(`Kritical SCX agentic shim -> ${UPSTREAM}  on http://${HOST}:${PORT}  (log: ${LOG})`);
    console.log(`Kill switch: stop this process; point codex base_url back to ${UPSTREAM} to go raw.`);
  });
}
