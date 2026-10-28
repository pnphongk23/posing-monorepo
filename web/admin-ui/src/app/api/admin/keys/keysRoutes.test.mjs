import test from 'node:test';
import assert from 'node:assert/strict';

process.env.POSE_EXTRACT_SERVER_URL = 'https://pose-extract.example.test';
process.env.POSE_EXTRACT_ADMIN_SECRET = 'test-admin-secret';

const originalFetch = globalThis.fetch;

function jsonResponse(body, status) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function mockFetch(handler) {
  globalThis.fetch = handler;
}

const { GET, POST } = await import('./route.js');
const { PATCH, DELETE } = await import('./[id]/route.js');
const { POST: RESET } = await import('./reset/route.js');

function jsonRequest(url, method, body) {
  return new Request(url, {
    method,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

test.after(() => {
  globalThis.fetch = originalFetch;
});

test('GET /api/admin/keys preserves upstream 401 instead of 500', async (t) => {
  t.after(() => mockFetch(originalFetch));
  mockFetch(async () => jsonResponse({ error: { code: 'UNAUTHORIZED', message: 'Invalid admin secret' } }, 401));

  const response = await GET();

  assert.equal(response.status, 401);
  assert.deepEqual(await response.json(), {
    error: { code: 'UNAUTHORIZED', message: 'Invalid admin secret' },
  });
});

test('POST /api/admin/keys preserves upstream 400 instead of 500', async (t) => {
  t.after(() => mockFetch(originalFetch));
  mockFetch(async () => jsonResponse({ error: { code: 'BAD_REQUEST', message: 'Invalid key payload' } }, 400));

  const response = await POST(jsonRequest('http://localhost/api/admin/keys', 'POST', { name: 'x' }));

  assert.equal(response.status, 400);
  assert.equal((await response.json()).error.code, 'BAD_REQUEST');
});

test('PATCH /api/admin/keys/:id preserves upstream 404 instead of 500', async (t) => {
  t.after(() => mockFetch(originalFetch));
  mockFetch(async () => jsonResponse({ error: { code: 'NOT_FOUND', message: 'API key not found' } }, 404));

  const response = await PATCH(jsonRequest('http://localhost/api/admin/keys/k1', 'PATCH', { status: 'active' }), {
    params: { id: 'k1' },
  });

  assert.equal(response.status, 404);
});

test('DELETE /api/admin/keys/:id preserves upstream 404 instead of 500', async (t) => {
  t.after(() => mockFetch(originalFetch));
  mockFetch(async () => jsonResponse({ error: { code: 'NOT_FOUND', message: 'API key not found' } }, 404));

  const response = await DELETE(new Request('http://localhost/api/admin/keys/k1', { method: 'DELETE' }), {
    params: { id: 'k1' },
  });

  assert.equal(response.status, 404);
});

test('POST /api/admin/keys/reset preserves upstream 409 instead of 500', async (t) => {
  t.after(() => mockFetch(originalFetch));
  mockFetch(async () => jsonResponse({ error: { code: 'CONFLICT', message: 'Reset already running' } }, 409));

  const response = await RESET();

  assert.equal(response.status, 409);
});

test('thrown upstream error keeps its status instead of collapsing to 500', async (t) => {
  t.after(() => mockFetch(originalFetch));
  mockFetch(async () => {
    throw Object.assign(new Error('Upstream rejected admin secret'), { status: 401, code: 'UNAUTHORIZED' });
  });

  const response = await GET();
  const payload = await response.json();

  assert.equal(response.status, 401);
  assert.equal(payload.error, 'Upstream rejected admin secret');
  assert.equal(payload.code, 'UNAUTHORIZED');
});
