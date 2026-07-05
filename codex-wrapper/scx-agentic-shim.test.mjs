// HR21 paired test for the SCX agentic flatten-shim (transform logic only — no network).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { flattenTool, transformRequestBody, isPlanGateError } from './scx-agentic-shim.mjs';

test('function tools pass through unchanged', () => {
  const t = { type: 'function', name: 'shell_command', parameters: { type: 'object', properties: {} } };
  assert.deepEqual(flattenTool(t, false), [t]);
});

test('local_shell / custom / freeform become function tools with the name preserved', () => {
  for (const type of ['local_shell', 'custom', 'freeform']) {
    const out = flattenTool({ type, name: 'shell' }, false);
    assert.equal(out.length, 1);
    assert.equal(out[0].type, 'function');
    assert.equal(out[0].name, 'shell');
    assert.ok(out[0].parameters);
  }
});

test('namespace tool flattens to its inner function tools', () => {
  const ns = { type: 'namespace', namespace: 'apps', tools: [
    { type: 'function', name: 'a', parameters: { type: 'object', properties: {} } },
    { type: 'function', name: 'b', parameters: { type: 'object', properties: {} } },
  ] };
  const out = flattenTool(ns, false);
  assert.equal(out.length, 2);
  assert.deepEqual(out.map((t) => t.type), ['function', 'function']);
  assert.deepEqual(out.map((t) => t.name), ['a', 'b']);
});

test('server tools kept normally, dropped on retry', () => {
  const ws = { type: 'web_search' };
  assert.deepEqual(flattenTool(ws, false), [ws]);      // normal request keeps it
  assert.deepEqual(flattenTool(ws, true), []);         // plan-gate retry drops it
});

test('transformRequestBody rewrites a realistic codex tool array', () => {
  const body = { model: 'gpt-oss-120b', tools: [
    { type: 'function', name: 'shell_command', parameters: { type: 'object', properties: {} } },
    { type: 'namespace', tools: [{ type: 'function', name: 'x', parameters: { type: 'object', properties: {} } }] },
    { type: 'web_search' },
  ] };
  const normal = transformRequestBody(body, false);
  assert.deepEqual(normal.tools.map((t) => t.type), ['function', 'function', 'web_search']);
  const retry = transformRequestBody(body, true);
  assert.deepEqual(retry.tools.map((t) => t.type), ['function', 'function']); // web_search dropped
  assert.ok(retry.tools.every((t) => t.type === 'function'));
});

test('isPlanGateError detects SCX plan-gate 400s only', () => {
  assert.equal(isPlanGateError(400, 'The model `gpt-oss-120b` is not available on your current plan.'), true);
  assert.equal(isPlanGateError(400, '{"code":"model_not_in_plan"}'), true);
  assert.equal(isPlanGateError(400, 'some other bad request'), false);
  assert.equal(isPlanGateError(200, 'current plan'), false);
});
