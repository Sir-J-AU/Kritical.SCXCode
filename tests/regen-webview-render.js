/** Regenerate the static webview render HTML from the current bundle (visual proof the dropdown preseeds). */
const fs = require('fs'), path = require('path'), Module = require('module');
const b = path.join(__dirname, '..', 'src', 'out', 'extension.js');
let c = fs.readFileSync(b, 'utf8') + '\nmodule.exports.__h=(typeof chatHtml==="function")?chatHtml:null;';
const oL = Module._load; Module._load = function (r, ...a) { if (r === 'vscode') return new Proxy({}, { get: () => () => ({}) }); return oL.call(this, r, ...a); };
const m = new Module(b, null); m.filename = b; m.paths = Module._nodeModulePaths(path.dirname(b)); m._compile(c, b);
const out = path.join(__dirname, 'emitted', 'scxcode-webview-render.html');
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, m.exports.__h());
const html = m.exports.__h();
const preseedCount = (html.match(/id="model"/g) || []).length;
console.log('  regenerated -> ' + out);
console.log('  preseed block present: ' + html.includes('PRESEED the model dropdown'));
