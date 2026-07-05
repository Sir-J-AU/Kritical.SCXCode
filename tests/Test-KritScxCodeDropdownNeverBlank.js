/**
 * Regression gate for the BLANK-DROPDOWN bug (operator screenshot, v0.1.10).
 * Proves the model dropdown is populated even with NO host: no acquireVsCodeApi, no config message.
 * This is the exact condition that produced the blank dropdown. Preseed must fill it.
 * Run: node tests/Test-KritScxCodeDropdownNeverBlank.js
 */
const fs = require('fs'), path = require('path'), Module = require('module'), vm = require('vm');
const bundle = path.join(__dirname, '..', 'src', 'out', 'extension.js');
let code = fs.readFileSync(bundle, 'utf8') + '\nmodule.exports.__chatHtml=(typeof chatHtml==="function")?chatHtml:null;';
const oL = Module._load; Module._load = function (r, ...a) { if (r === 'vscode') return new Proxy({}, { get: () => () => ({}) }); return oL.call(this, r, ...a); };
const m = new Module(bundle, null); m.filename = bundle; m.paths = Module._nodeModulePaths(path.dirname(bundle)); m._compile(code, bundle);
const html = m.exports.__chatHtml();
const script = html.match(/<script[^>]*>([\s\S]*?)<\/script>/)[1];

function el(id) {
  return { id, _t:'', value:'', title:'', disabled:false, options:[], dataset:{}, style:{},
    classList:{toggle(){},add(){},remove(){}},
    set textContent(v){this._t=v;}, get textContent(){return this._t;},
    set innerHTML(v){this._h=v; if(v==='') this.options=[];}, get innerHTML(){return this._h||'';},
    appendChild(c){this.options.push(c);}, querySelectorAll(){return[];},
    set onclick(f){}, set onchange(f){}, set oninput(f){}, set onkeydown(f){}, scrollTop:0, scrollHeight:0 };
}
const els = {};
// NOTE: deliberately NO acquireVsCodeApi in the sandbox -> the .5227 guard must kick in, not crash.
const sb = {
  document: { getElementById: id => (els[id] = els[id] || el(id)), createElement: () => el('opt') },
  window: { addEventListener: () => {} }, navigator: { clipboard: { writeText(){} } },
  Math, JSON, setTimeout, console, parseInt, parseFloat, String, Array, Boolean
};
vm.createContext(sb);
let pass = 0, fail = 0; function ok(n,c){ if(c){pass++;}else{fail++;console.log('  FAIL '+n);} }

let crashed = false;
try { vm.runInContext(script, sb, { timeout: 3000 }); }
catch (e) { crashed = true; console.log('  script threw: ' + e.message); }

ok('script runs with NO host (acquireVsCodeApi absent)', !crashed);
ok('model dropdown is NOT blank (preseed populated it)', els.model && els.model.options.length > 0);
console.log('  preseeded option count = ' + (els.model ? els.model.options.length : 0));

console.log('\n===== NEVER-BLANK DROPDOWN: ' + pass + ' passed, ' + fail + ' failed =====');
process.exit(fail === 0 ? 0 : 1);
