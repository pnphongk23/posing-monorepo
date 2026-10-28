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

const { GET, PUT } = await import('./extraction-provider/route.js');

test.after(() => {
  globalThis.fetch = originalFetch;
});

test('GET extraction-provider preserves upstream 401 instead of 500', async (t) => {
  t.after(() => {
    globalThis.fetch = originalFetch;
  });
  globalThis.fetch = async () => jsonResponse({ error: { code: 'UNAUTHORIZED', message: 'Invalid admin secret' } }, 401);

  const response = await GET();

  assert.equal(response.status, 401);
  assert.equal((await response.json()).error.code, 'UNAUTHORIZED');
});

test('PUT extraction-provider preserves upstream 422 instead of 500', async (t) => {
  t.after(() => {
    globalThis.fetch = originalFetch;
  });
  globalThis.fetch = async () => jsonResponse({ error: { code: 'INVALID_PROVIDER', message: 'Unknown provider' } }, 422);

  const request = new Request('http://localhost/api/admin/settings/extraction-provider', {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ provider: 'nope' }),
  });
  const response = await PUT(request);

  assert.equal(response.status, 422);
  assert.equal((await response.json()).error.code, 'INVALID_PROVIDER');
});
