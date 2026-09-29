import test from 'node:test';
import assert from 'node:assert/strict';
import { callPoseExtractExtractPose } from './poseExtractExtractPoseProxy.js';

test('callPoseExtractExtractPose sends Authorization Bearer header with admin secret', async (t) => {
  const originalEnvUrl = process.env.POSE_EXTRACT_SERVER_URL;
  const originalEnvSecret = process.env.POSE_EXTRACT_ADMIN_SECRET;
  const originalFetch = globalThis.fetch;

  process.env.POSE_EXTRACT_SERVER_URL = 'http://127.0.0.1:3001';
  process.env.POSE_EXTRACT_ADMIN_SECRET = 'test-admin-secret-xyz';

  let capturedUrl = null;
  let capturedOptions = null;

  globalThis.fetch = async (url, options) => {
    capturedUrl = url;
    capturedOptions = options;
    return new Response(JSON.stringify({ success: true, data: { jobId: 'job-123', status: 'queued' } }), {
      status: 202,
      headers: { 'Content-Type': 'application/json' },
    });
  };

  t.after(() => {
    process.env.POSE_EXTRACT_SERVER_URL = originalEnvUrl;
    process.env.POSE_EXTRACT_ADMIN_SECRET = originalEnvSecret;
    globalThis.fetch = originalFetch;
  });

  const dummyFormData = new FormData();
  dummyFormData.append('name', 'Test');

  const result = await callPoseExtractExtractPose(dummyFormData);

  assert.equal(result.ok, true);
  assert.equal(result.status, 202);
  assert.equal(capturedUrl, 'http://127.0.0.1:3001/api/extract-pose');
  assert.equal(capturedOptions.method, 'POST');
  assert.equal(capturedOptions.headers.Authorization, 'Bearer test-admin-secret-xyz');
});
