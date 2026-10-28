import test from 'node:test';
import assert from 'node:assert/strict';
import { mapProxyError } from './proxyError.js';

async function readError(response) {
  return { status: response.status, body: await response.json() };
}

test('mapProxyError falls back to 500 for untyped errors', async () => {
  const result = await readError(mapProxyError(new Error('socket hang up')));

  assert.equal(result.status, 500);
  assert.equal(result.body.code, 'ADMIN_PROXY_ERROR');
  assert.equal(result.body.error, 'Upstream request failed');
});

test('mapProxyError keeps upstream status from error.status', async () => {
  const result = await readError(
    mapProxyError(Object.assign(new Error('Invalid admin secret'), { status: 401, code: 'UNAUTHORIZED' }))
  );

  assert.equal(result.status, 401);
  assert.equal(result.body.code, 'UNAUTHORIZED');
  assert.equal(result.body.error, 'Upstream request failed');
});

test('mapProxyError keeps upstream status from error.statusCode', async () => {
  const result = await readError(mapProxyError(Object.assign(new Error('API key not found'), { statusCode: 404 })));

  assert.equal(result.status, 404);
  assert.equal(result.body.code, 'ADMIN_PROXY_ERROR');
});

test('mapProxyError ignores out-of-range status values', async () => {
  const result = await readError(mapProxyError(Object.assign(new Error('weird'), { status: 302 })));

  assert.equal(result.status, 500);
});

test('mapProxyError still reports misconfiguration as 500 ADMIN_PROXY_MISCONFIG', async () => {
  const result = await readError(mapProxyError(new Error('Missing POSE_EXTRACT_ADMIN_SECRET')));

  assert.equal(result.status, 500);
  assert.equal(result.body.code, 'ADMIN_PROXY_MISCONFIG');
});

test('mapProxyError handles non-error inputs', async () => {
  const result = await readError(mapProxyError(undefined));

  assert.equal(result.status, 500);
  assert.equal(result.body.error, 'Upstream request failed');
  assert.equal(result.body.code, 'ADMIN_PROXY_ERROR');
});
