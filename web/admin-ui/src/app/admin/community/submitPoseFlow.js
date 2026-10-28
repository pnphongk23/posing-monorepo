export const COMMUNITY_ADMIN_API = '/api/admin/community/poses';
export const DEFAULT_OWNER_ACCOUNT_ID = '00000000-0000-0000-0000-000000000001';

const LIST_QUERY = '?limit=100';

export function normalizeList(raw) {
  return String(raw || '')
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
}

export async function parseResponse(response) {
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const message =
      payload.error?.message ||
      payload.error ||
      payload.message ||
      `Request failed (${response.status})`;
    throw new Error(message);
  }
  return payload;
}

export function upsertPose(list, pose) {
  if (!pose?.poseId) return list;

  const index = list.findIndex((item) => item.poseId === pose.poseId);
  if (index === -1) return [pose, ...list];

  const next = list.slice();
  next[index] = { ...list[index], ...pose };
  return next;
}

export async function fetchCommunityPoses(fetchImpl) {
  const response = await fetchImpl(`${COMMUNITY_ADMIN_API}${LIST_QUERY}`, { cache: 'no-store' });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(
      payload.error?.message || payload.error || payload.message || `Request failed (${response.status})`
    );
  }
  return payload.data ?? [];
}

const defaultSleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Creates a pose from an uploaded image and, when requested, publishes it.
 *
 * The community list is only reconciled after the publish step settles, so the
 * row an admin can open always carries the status the server actually stored.
 */
export async function runCreatePoseSubmit({
  fetchImpl,
  form,
  file,
  setPoses,
  onNotice = () => {},
  onError = () => {},
  onListError = () => {},
  onCreated = () => {},
  sleep = defaultSleep,
  maxPollAttempts = 60,
  pollIntervalMs = 1000,
}) {
  const refreshList = async () => {
    try {
      const list = await fetchCommunityPoses(fetchImpl);
      setPoses(list);
      return true;
    } catch (error) {
      onListError(error.message);
      return false;
    }
  };

  try {
    const extractForm = new FormData();
    extractForm.append('image', file);
    const extractPayload = await parseResponse(
      await fetchImpl('/api/admin/extract-pose', { method: 'POST', body: extractForm })
    );
    const jobId = extractPayload.data?.jobId;
    if (!jobId) throw new Error('Extraction did not return jobId.');

    let job;
    for (let attempt = 0; attempt < maxPollAttempts; attempt += 1) {
      const jobPayload = await parseResponse(
        await fetchImpl(`/api/admin/extract-jobs/${jobId}`, { cache: 'no-store' })
      );
      job = jobPayload.data;
      if (job?.status === 'succeeded' || job?.status === 'failed') break;
      await sleep(pollIntervalMs);
    }
    if (!job || job.status !== 'succeeded') throw new Error('Extraction did not succeed.');

    const created = await parseResponse(
      await fetchImpl(COMMUNITY_ADMIN_API, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          jobId,
          ownerAccountId: form.ownerAccountId.trim(),
          name: form.name.trim(),
          tags: normalizeList(form.tags),
          description: form.description.trim() || null,
          bodyParts: ['full-body'],
          difficulty: null,
        }),
      })
    );

    const createdPose = created.data?.pose ?? null;
    const createdPoseId = createdPose?.poseId;
    if (createdPose) {
      setPoses((list) => upsertPose(list, createdPose));
    }
    onCreated();

    if (form.status !== 'published' || !createdPoseId) {
      onNotice('Đã extraction và tạo Pose thành công.');
      await refreshList();
      return { ok: true, pose: createdPose };
    }

    let publishedPose = null;
    try {
      // Publish is a server-validated step: it is refused while the pose media is
      // not ready, and that error has to reach the admin instead of a success note.
      const published = await parseResponse(
        await fetchImpl(`${COMMUNITY_ADMIN_API}/${createdPoseId}`, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ status: 'published' }),
        })
      );
      publishedPose = published.data?.pose ?? published.data ?? { poseId: createdPoseId, status: 'published' };
      setPoses((list) => upsertPose(list, publishedPose));
      onNotice('Đã extraction, tạo Pose và publish thành công.');
    } catch (publishError) {
      onError(`Pose đã được tạo ở trạng thái LOCAL. ${publishError.message}`);
    }

    await refreshList();
    return { ok: Boolean(publishedPose), pose: publishedPose ?? createdPose };
  } catch (error) {
    onError(error.message);
    return { ok: false, pose: null };
  }
}
