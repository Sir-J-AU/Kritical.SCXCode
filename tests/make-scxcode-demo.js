/**
 * Build an INTERACTIVE demo of the SCXCode webview for the preview: injects a MOCK VS Code host so
 * every button/control actually DOES something in a plain browser (a static render can't, because there
 * is no extension host to answer its messages). Proves the wiring end-to-end without VS Code.
 * Emits tests/emitted/scxcode-demo.html (also copied to index.html so the preview root serves it).
 * Run: node tests/make-scxcode-demo.js
 */
const fs = require('fs'), path = require('path'), Module = require('module');
const b = path.join(__dirname, '..', 'src', 'out', 'extension.js');
let c = fs.readFileSync(b, 'utf8') + '\nmodule.exports.__h=(typeof chatHtml==="function")?chatHtml:null;';
const oL = Module._load; Module._load = function (r, ...a) { if (r === 'vscode') return new Proxy({}, { get: () => () => ({}) }); return oL.call(this, r, ...a); };
const m = new Module(b, null); m.filename = b; m.paths = Module._nodeModulePaths(path.dirname(b)); m._compile(c, b);
const body = m.exports.__h();

// The mock host: define acquireVsCodeApi BEFORE the webview script runs, answer each message the way the
// real extension would, and show a visible "host log" so it's obvious the button fired.
const mockHost = `<script>
(function () {
  var MODELS = [
    { id: 'MiniMax-M2.7', detail: '192K · default agentic' }, { id: 'MAGPiE', detail: '131K · reasoning' },
    { id: 'gpt-oss-120b', detail: '131K · cheapest reasoner' }, { id: 'DeepSeek-V3.1', detail: '131K · hardest problems' },
    { id: 'coder', detail: '196K · algorithms + debugging' }, { id: 'gemma-4-31B-it', detail: '131K · multimodal' },
    { id: 'Qwen3-32B', detail: '32K · 119 languages' }
  ];
  function toWebview(obj) { window.dispatchEvent(new MessageEvent('message', { data: obj })); }
  function log(t) {
    var el = document.getElementById('demoHostLog'); if (!el) return;
    var line = document.createElement('div'); line.textContent = '▶ host: ' + t; el.appendChild(line);
    el.scrollTop = el.scrollHeight;
  }
  window.acquireVsCodeApi = function () {
    return {
      getState: function () {}, setState: function () {},
      postMessage: function (msg) {
        log(JSON.stringify(msg));
        if (msg.type === 'config') {
          toWebview({ type: 'config', model: 'DeepSeek-V3.1', models: MODELS, maxTokens: 1500, concurrency: 1,
            autoContext: 'file+selection', provider: 'auto', temperature: 0.6, keyCount: 1 });
        } else if (msg.type === 'setConfig') {
          toWebview({ type: 'notice', text: 'Setting applied: ' + msg.key + ' = ' + msg.value + ' (demo host)' });
        } else if (msg.type === 'uploadFile') {
          toWebview({ type: 'fileAttached', name: 'example.ts', chars: 4096 });
        } else if (msg.type === 'attachRepo') {
          toWebview({ type: 'fileAttached', name: 'repo (37 files)', chars: 128000 });
        } else if (msg.type === 'listMcp') {
          toWebview({ type: 'notice', text: 'MCP servers (from ~/.codex/config.toml): pax8, shopify, azure — demo host' });
        } else if (msg.type === 'scxCodex') {
          toWebview({ type: 'notice', text: 'SCX Codex: the real extension opens a terminal running kritical-codex.ps1 (SCX-branded, never touches your real codex).' });
        } else if (msg.type === 'chat') {
          toWebview({ type: 'reply', text: 'Demo reply from **' + (msg.model || 'SCX') + '**. In the real extension this streams from api.scx.ai.\\n\\n\`\`\`js\\nconsole.log("wired");\\n\`\`\`', model: msg.model || 'DeepSeek-V3.1', tokensIn: 42, tokensOut: 21, shards: msg.concurrency || 1 });
        }
      }
    };
  };
})();
</script>
<div style="position:fixed;left:8px;bottom:8px;width:340px;max-height:150px;overflow:auto;background:#0b1f33;color:#8fe;border:1px solid #15AFD1;border-radius:4px;font:10px/1.4 monospace;padding:6px;z-index:9999;opacity:0.92;">
  <b style="color:#15AFD1;">DEMO MOCK HOST</b> — click any button/control; this logs what the webview sent + what a real extension would answer.
  <div id="demoHostLog"></div>
</div>`;

const outDir = path.join(__dirname, 'emitted');
fs.mkdirSync(outDir, { recursive: true });
const demo = mockHost + body;
fs.writeFileSync(path.join(outDir, 'scxcode-demo.html'), demo);
fs.writeFileSync(path.join(outDir, 'index.html'), demo);
console.log('  wrote scxcode-demo.html (+ index.html) — interactive, mock-host wired, ' + demo.length + ' bytes');
