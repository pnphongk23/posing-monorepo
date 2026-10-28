import test from 'node:test';
import assert from 'node:assert/strict';
import { mapProxyError } from './proxyError.js';

const SAFE_MESSAGE = 'Upstream request failed';

const SECRETS = [
  'test-secret',
  'operator',
  'pose.example.test',
  'sk-live-abcdef1234567890',
  'ghp_abcdefghijklmnopqrstuvwxyz0123456789',
];

function assertNoSecrets(payload) {
  const serialized = JSON.stringify(payload);
  for (const secret of SECRETS) {
    assert.equal(serialized.includes(secret), false, `response leaked ${secret}`);
  }
  assert.equal(serialized.includes('at '), false, 'response leaked a stack frame');
}

async function readError(response) {
  return { status: response.status, body: await response.json() };
}

function captureConsoleError(t) {
  const calls = [];
  const original = console.error;
  console.error = (...args) => calls.push(args);
  t.after(() => {
    console.error = original;
  });
  return calls;
}

test('userinfo URL in a fetch error message is never echoed to the client', async (t) => {
  const logs = captureConsoleError(t);
  const error = new TypeError('fetch failed for https://operator:test-secret@pose.example.test/api/admin/keys');

  const result = await readError(mapProxyError(error));

  assert.equal(result.status, 500);
  assert.equal(result.body.error, SAFE_MESSAGE);
  assert.equal(result.body.code, 'ADMIN_PROXY_ERROR');
  assertNoSecrets(result.body);
  assert.equal(logs.length, 1);
  assert.equal(JSON.stringify(logs[0]).includes('test-secret'), false, 'server log leaked the password');
});

test('bearer and api-key tokens in an error message are never echoed to the client', async (t) => {
  captureConsoleError(t);
  const error = new Error(
    'request failed with Authorization: Bearer sk-live-abcdef1234567890 and token ghp_abcdefghijklmnopqrstuvwxyz0123456789'
  );

  const result = await readError(mapProxyError(error));

  assert.equal(result.body.error, SAFE_MESSAGE);
  assertNoSecrets(result.body);
});

test('error stacks are never echoed to the client', async (t) => {
  captureConsoleError(t);
  const error = new Error('https://operator:test-secret@pose.example.test/api/admin/keys returned 502');
  error.stack = `Error: ${error.message}\n    at fetch (https://operator:test-secret@pose.example.test)`;

  const result = await readError(mapProxyError(error));

  assert.equal(result.body.error, SAFE_MESSAGE);
  assertNoSecrets(result.body);
});

test('an upstream status is preserved while the message stays safe', async (t) => {
  const logs = captureConsoleError(t);
  const error = Object.assign(
    new Error('https://operator:test-secret@pose.example.test rejected the admin secret'),
    { status: 401, code: 'UNAUTHORIZED' }
  );

  const result = await readError(mapProxyError(error));

  assert.equal(result.status, 401);
  assert.equal(result.body.error, SAFE_MESSAGE);
  assert.equal(result.body.code, 'UNAUTHORIZED');
  assertNoSecrets(result.body);
  assert.equal(JSON.stringify(logs[0]).includes('test-secret'), false, 'server log leaked the password');
});

test('the server-side log keeps a redacted hint of the failure', async (t) => {
  const logs = captureConsoleError(t);

  await readError(mapProxyError(new TypeError('fetch failed for https://operator:test-secret@pose.example.test/x')));

  const logged = logs[0].map((entry) => (typeof entry === 'string' ? entry : JSON.stringify(entry))).join(' ');
  assert.match(logged, /\[redacted\]/);
  assert.equal(logged.includes('test-secret'), false);
});

test('a non-identifier error code is not forwarded to the client', async (t) => {
  captureConsoleError(t);
  const error = Object.assign(new Error('boom https://operator:test-secret@pose.example.test'), {
    status: 502,
    code: 'https://operator:test-secret@pose.example.test',
  });

  const result = await readError(mapProxyError(error));

  assert.equal(result.status, 502);
  assert.equal(result.body.code, 'ADMIN_PROXY_ERROR');
  assertNoSecrets(result.body);
});

test('GET /api/admin/keys does not echo credential-bearing upstream URLs', async (t) => {
  captureConsoleError(t);
  process.env.POSE_EXTRACT_SERVER_URL = 'https://operator:test-secret@pose.example.test';
  process.env.POSE_EXTRACT_ADMIN_SECRET = 'test-admin-secret';

  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => {
    throw new TypeError(
      'fetch failed for https://operator:test-secret@pose.example.test/api/admin/keys with Bearer sk-live-abcdef1234567890'
    );
  };
  t.after(() => {
    globalThis.fetch = originalFetch;
    delete process.env.POSE_EXTRACT_SERVER_URL;
    delete process.env.POSE_EXTRACT_ADMIN_SECRET;
  });

  const { GET } = await import('./keys/route.js');
  const response = await GET();
  const payload = await response.json();

  assert.equal(response.status, 500);
  assert.equal(payload.error, SAFE_MESSAGE);
  assertNoSecrets(payload);
});
