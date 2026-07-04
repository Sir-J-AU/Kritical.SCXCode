#!/usr/bin/env node
// kritical-codex — cross-platform Node/Bun sibling of kritical-codex.ps1
//
// Same semantics as the PS wrapper: launches operator's `codex` CLI with
// Kritical + SCX defaults + brand banner. HR29-compliant — per-invocation
// env only, no HKCU / no dotfile mutation. Removing the wrapper leaves
// operator's plain codex unchanged.
//
// Author: Joshua Finley — Kritical Pty Ltd — (c) 2026
// Contact: sales@kritical.net — ph. 1300 274 655

import { spawn } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const assetsDir = join(__dirname, 'assets');
const bannerPath = join(assetsDir, 'KriticalLogo.txt');
const brandSpecPath = join(assetsDir, 'brand-spec.json');
const repoRoot = resolve(__dirname, '..');

// -----------------------------------------------------------------------------
// arg parsing (minimal — pass everything else through)
// -----------------------------------------------------------------------------

const argv = process.argv.slice(2);
let model = null;
let baseUrl = null;
let noBanner = false;
let noLog = false;
const passthrough = [];

for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--model' || a === '-m') { model = argv[++i]; continue; }
  if (a === '--base-url') { baseUrl = argv[++i]; continue; }
  if (a === '--no-banner') { noBanner = true; continue; }
  if (a === '--no-log') { noLog = true; continue; }
  if (a === '--') { passthrough.push(...argv.slice(i + 1)); break; }
  passthrough.push(a);
}

// -----------------------------------------------------------------------------
// HR29 preflight — remember original env, never mutate globally
// -----------------------------------------------------------------------------

const origOpenAIBaseUrl = process.env.OPENAI_BASE_URL;
const origOpenAIKey = process.env.OPENAI_API_KEY;

// HR29 hard invariant: NEVER touch ANTHROPIC_BASE_URL.

// -----------------------------------------------------------------------------
// Provider slot detection
// -----------------------------------------------------------------------------

const scxKey = process.env.SCX_API_KEY;
const openaiKey = process.env.OPENAI_API_KEY;

if (!model) {
  if (scxKey) model = 'scx-coder';
  else if (openaiKey) model = 'openai/gpt-5-codex';
}

// -----------------------------------------------------------------------------
// Probe local LiteLLM proxy
// -----------------------------------------------------------------------------

async function probeProxy() {
  try {
    const ac = new AbortController();
    const timer = setTimeout(() => ac.abort(), 2000);
    const r = await fetch('http://127.0.0.1:4180/health/liveliness', { signal: ac.signal });
    clearTimeout(timer);
    return r.ok;
  } catch { return false; }
}

// -----------------------------------------------------------------------------
// Brand banner
// -----------------------------------------------------------------------------

function loadBrandSpec() {
  if (!existsSync(brandSpecPath)) return null;
  try { return JSON.parse(readFileSync(brandSpecPath, 'utf8')); } catch { return null; }
}

function emitBanner(effectiveBaseUrl) {
  if (noBanner) return;
  if (existsSync(bannerPath)) {
    process.stdout.write(readFileSync(bannerPath, 'utf8'));
  } else {
    console.log('\n  Kritical.SCXCode — kritical-codex wrapper');
  }
  const spec = loadBrandSpec() || {};
  const tagline     = spec.messaging?.tagline     || 'Your last call. And your first move.';
  const positioning = spec.messaging?.positioning || 'Geelong & The Bellarine\'s IT & Cybersecurity Specialists';
  const phone       = spec.contact?.phoneMain     || '1300 274 655';
  const email       = spec.contact?.emailSales    || 'sales@kritical.net';

  console.log('');
  console.log(`  ${tagline}`);
  console.log(`  ${positioning}`);
  console.log(`  Kritical Pty Ltd · ${email} · ph. ${phone}`);
  console.log('  Sovereign Australian AI — powered by Southern Cross AI (SCX)');
  console.log('');
  if (effectiveBaseUrl) {
    console.log(`  Codex endpoint: ${effectiveBaseUrl}  (model -> ${model || '(codex default)'})`);
  } else {
    console.log('  Codex endpoint: (codex CLI default — api.openai.com)');
  }
  console.log('');
}

// -----------------------------------------------------------------------------
// HR27 write-through (best effort — silently no-op if PS logger absent)
// -----------------------------------------------------------------------------

async function logInvocation(effectiveBaseUrl) {
  if (noLog) return;
  const loggerPath = join(repoRoot, 'ps-module', 'KriticalDecisionLogger.psm1');
  if (!existsSync(loggerPath)) return;
  const payload = JSON.stringify({
    wrapper: 'kritical-codex.mjs',
    model,
    base_url: effectiveBaseUrl,
    codex_args: passthrough.join(' '),
    cwd: process.cwd(),
  });
  const cmd = `Import-Module '${loggerPath}' -Force -ErrorAction SilentlyContinue; ` +
              `if (Get-Command Add-KriticalAIResponse -EA SilentlyContinue) { ` +
              `Add-KriticalAIResponse -Content 'kritical-codex invocation: ${payload.replaceAll("'", "''")}' ` +
              `-Category action -Source 'kritical-codex-wrapper' ` +
              `-Provider 'openai-via-litellm' ${model ? `-Model '${model}'` : ''} | Out-Null }`;
  try {
    const p = spawn('pwsh', ['-NoProfile', '-Command', cmd], { stdio: 'ignore' });
    p.unref();
  } catch { /* silently ignore */ }
}

// -----------------------------------------------------------------------------
// Main
// -----------------------------------------------------------------------------

async function main() {
  const proxyHealthy = await probeProxy();
  let effectiveBaseUrl = null;
  if (baseUrl) {
    effectiveBaseUrl = baseUrl;
  } else if (proxyHealthy) {
    effectiveBaseUrl = 'http://127.0.0.1:4180';
  } else if (origOpenAIBaseUrl) {
    effectiveBaseUrl = origOpenAIBaseUrl;
  }

  emitBanner(effectiveBaseUrl);
  logInvocation(effectiveBaseUrl);

  // Verify codex CLI
  const which = spawn(process.platform === 'win32' ? 'where' : 'which', ['codex'], { stdio: 'pipe' });
  let codexFound = false;
  which.stdout.on('data', (chunk) => { if (chunk.toString().trim().length) codexFound = true; });
  await new Promise((resolve) => which.on('close', resolve));

  if (!codexFound) {
    console.log('\ncodex CLI not found on PATH.');
    console.log('\nInstall OpenAI Codex CLI (Rust, MIT):');
    console.log('  winget install OpenAI.Codex   # Windows');
    console.log('  brew install codex             # macOS');
    console.log('  cargo install --git https://github.com/openai/codex codex-cli\n');
    console.log('Then re-run kritical-codex.\n');
    process.exit(2);
  }

  // Per-invocation env only
  const childEnv = { ...process.env };
  if (effectiveBaseUrl) childEnv.OPENAI_BASE_URL = effectiveBaseUrl;
  if (effectiveBaseUrl === 'http://127.0.0.1:4180') {
    childEnv.OPENAI_API_KEY = 'sk-kritical-scx-local';
  }
  if (model) childEnv.KRITICAL_CODEX_DEFAULT_MODEL = model;

  const finalArgs = [...passthrough];
  if (model && !finalArgs.includes('--model') && !finalArgs.includes('-m')) {
    finalArgs.unshift('--model', model);
  }

  const child = spawn('codex', finalArgs, { stdio: 'inherit', env: childEnv });
  child.on('close', (code) => process.exit(code ?? 0));
}

main().catch((err) => {
  console.error('kritical-codex fatal:', err);
  process.exit(1);
});
