import test from 'node:test';
import assert from 'node:assert/strict';
import { runCreatePoseSubmit } from './submitPoseFlow.js';

const FORM = {
  name: 'Warrior II',
  tags: 'standing, balance',
  description: 'desc',
  status: 'published',
  ownerAccountId: '00000000-0000-0000-0000-000000000001',
};

const FILE = new File(['fake'], 'pose.png', { type: 'image/png' });

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function createListStore() {
  let list = [];
  return {
    setPoses(updater) {
      list = typeof updater === 'function' ? updater(list) : updater;
    },
    get() {
      return list;
    },
  };
}

function createHarness({ publishResponse, serverList }) {
  const calls = [];
  const store = createListStore();
  const notices = [];
  const errors = [];
  const listErrors = [];

  const fetchImpl = async (url, options = {}) => {
    const method = options.method || 'GET';
    calls.push(`${method} ${url}`);

    if (url === '/api/admin/extract-pose') return json({ data: { jobId: 'job-1' } });
    if (url === '/api/admin/extract-jobs/job-1') return json({ data: { status: 'succeeded' } });
    if (url === '/api/admin/community/poses' && method === 'POST') {
      return json({ data: { pose: { poseId: 'pose-1', status: 'local', name: 'Created' } } }, 201);
    }
    if (url === '/api/admin/community/poses/pose-1' && method === 'PATCH') {
      return publishResponse();
    }
    if (url.startsWith('/api/admin/community/poses?limit=100')) {
      return json({ data: serverList() });
    }

    throw new Error(`unexpected request ${method} ${url}`);
  };

  return {
    calls,
    store,
    notices,
    errors,
    listErrors,
    run: () =>
      runCreatePoseSubmit({
        fetchImpl,
        form: FORM,
        file: FILE,
        setPoses: store.setPoses,
        onNotice: (message) => notices.push(message),
        onError: (message) => errors.push(message),
        onListError: (message) => listErrors.push(message),
        sleep: async () => {},
      }),
  };
}

test('publish success leaves the list showing the status the server stored', async () => {
  const harness = createHarness({
    publishResponse: () =>
      json({ data: { pose: { poseId: 'pose-1', status: 'published', name: 'Patched' } } }),
    serverList: () => [{ poseId: 'pose-1', status: 'published', name: 'From server' }],
  });

  const result = await harness.run();

  assert.equal(result.ok, true);
  assert.deepEqual(harness.errors, []);
  assert.deepEqual(harness.store.get(), [{ poseId: 'pose-1', status: 'published', name: 'From server' }]);
  assert.equal(harness.notices.at(-1), 'Đã extraction, tạo Pose và publish thành công.');
});

test('the list is not refreshed before the publish request settles', async () => {
  const harness = createHarness({
    publishResponse: () => json({ data: { pose: { poseId: 'pose-1', status: 'published' } } }),
    serverList: () => [{ poseId: 'pose-1', status: 'published' }],
  });

  await harness.run();

  const publishIndex = harness.calls.indexOf('PATCH /api/admin/community/poses/pose-1');
  const firstListIndex = harness.calls.findIndex((call) => call.includes('?limit=100'));

  assert.notEqual(publishIndex, -1);
  assert.notEqual(firstListIndex, -1);
  assert.ok(firstListIndex > publishIndex, `list refresh ran before publish: ${harness.calls.join(' | ')}`);
});

test('a refused publish (409 POSE_MEDIA_NOT_READY) keeps the list consistent with the server', async () => {
  const harness = createHarness({
    publishResponse: () =>
      json({ error: { code: 'POSE_MEDIA_NOT_READY', message: 'pose media is not ready' } }, 409),
    serverList: () => [{ poseId: 'pose-1', status: 'local', name: 'From server' }],
  });

  const result = await harness.run();

  assert.equal(result.ok, false);
  assert.equal(harness.errors.length, 1);
  assert.match(harness.errors[0], /LOCAL/);
  assert.match(harness.errors[0], /pose media is not ready/);
  assert.deepEqual(harness.store.get(), [{ poseId: 'pose-1', status: 'local', name: 'From server' }]);

  const publishIndex = harness.calls.indexOf('PATCH /api/admin/community/poses/pose-1');
  const firstListIndex = harness.calls.findIndex((call) => call.includes('?limit=100'));
  assert.ok(firstListIndex > publishIndex, `list refresh ran before publish: ${harness.calls.join(' | ')}`);
});

test('a local-only create still reconciles the list with the server', async () => {
  const calls = [];
  const store = createListStore();
  const notices = [];

  const fetchImpl = async (url, options = {}) => {
    const method = options.method || 'GET';
    calls.push(`${method} ${url}`);

    if (url === '/api/admin/extract-pose') return json({ data: { jobId: 'job-1' } });
    if (url === '/api/admin/extract-jobs/job-1') return json({ data: { status: 'succeeded' } });
    if (url === '/api/admin/community/poses' && method === 'POST') {
      return json({ data: { pose: { poseId: 'pose-1', status: 'local', name: 'Created' } } }, 201);
    }
    if (url.startsWith('/api/admin/community/poses?limit=100')) {
      return json({ data: [{ poseId: 'pose-1', status: 'local', name: 'From server' }] });
    }
    throw new Error(`unexpected request ${method} ${url}`);
  };

  const result = await runCreatePoseSubmit({
    fetchImpl,
    form: { ...FORM, status: 'local' },
    file: FILE,
    setPoses: store.setPoses,
    onNotice: (message) => notices.push(message),
    sleep: async () => {},
  });

  assert.equal(result.ok, true);
  assert.deepEqual(store.get(), [{ poseId: 'pose-1', status: 'local', name: 'From server' }]);
  assert.equal(notices.at(-1), 'Đã extraction và tạo Pose thành công.');
});
