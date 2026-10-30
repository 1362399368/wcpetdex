import test from 'node:test';
import assert from 'node:assert/strict';
import { onRequest } from '../functions/[[path]].js';

test('health reaches the existing service binding with original Request', async () => {
  const request = new Request('https://pair.pages.dev/health');
  let seen;
  const response = new Response('{"ok":true}', { headers: { 'Content-Type': 'application/json' } });
  assert.equal(await onRequest({ request, env: { PET_SYNC: { fetch: async r => { seen = r; return response; } } } }), response);
  assert.equal(seen, request);
});
test('upgrade and auth headers are preserved; 101 response is never reconstructed', async () => {
  const request = new Request('https://pair.pages.dev/v1/ws', { headers: { Upgrade: 'websocket', Authorization: 'Bearer fixture-only' } });
  const upgrade = { status: 101, webSocket: { fixture: true } };
  const result = await onRequest({ request, env: { PET_SYNC: { fetch: async r => {
    assert.equal(r.headers.get('Authorization'), 'Bearer fixture-only');
    assert.equal(r.headers.get('Upgrade'), 'websocket'); return upgrade;
  } } } });
  assert.equal(result, upgrade);
});
test('upstream rejection is preserved', async () => {
  const request = new Request('https://pair.pages.dev/v1/ws');
  const rejected = new Response('Unauthorized', { status: 401 });
  assert.equal(await onRequest({ request, env: { PET_SYNC: { fetch: async () => rejected } } }), rejected);
});
test('unknown routes and writes do not invoke the service', async () => {
  let calls = 0; const env = { PET_SYNC: { fetch: () => { calls++; } } };
  assert.equal((await onRequest({ request: new Request('https://pair.pages.dev/admin'), env })).status, 404);
  assert.equal((await onRequest({ request: new Request('https://pair.pages.dev/v1/ws', { method: 'POST' }), env })).status, 405);
  assert.equal(calls, 0);
});
test('missing and failed service bindings return distinguishable failures', async () => {
  const request = new Request('https://pair.pages.dev/health');
  assert.equal((await onRequest({ request, env: {} })).status, 503);
  assert.equal((await onRequest({ request, env: { PET_SYNC: { fetch: async () => { throw new Error('private details'); } } } })).status, 502);
});
