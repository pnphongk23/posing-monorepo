import { getAdminConfig } from './poseExtractAdminServer.js';

const EXTRACT_TIMEOUT_MS = 120_000;
const MAX_EXTRACT_PROXY_RESPONSE_BYTES = 25_000_000;

function assertNotSelfProxy(baseUrl, requestUrl) {
  if (!requestUrl) return;

  let proxyOrigin;
  let currentOrigin;
  try {
    proxyOrigin = new URL(baseUrl).origin;
    currentOrigin = new URL(requestUrl).origin;
  } catch {
    return;
  }

  if (proxyOrigin === currentOrigin) {
    throw new Error(
      'POSE_EXTRACT_SERVER_URL is pointing to this Next.js app, causing recursive proxy calls.'
    );
  }
}

function safeParseJson(rawText) {
  try {
    return JSON.parse(rawText);
  } catch {
    return { error: { code: 'INVALID_JSON', message: rawText.slice(0, 500) } };
  }
}

/**
 * Proxies multipart POST to pose-extract-server POST /api/extract-pose with admin Bearer.
 * Requires the same env as admin proxy so misconfig is caught early.
 */
export async function callPoseExtractExtractPose(formData, options = {}) {
  const { baseUrl, adminSecret } = getAdminConfig();
  const { requestUrl } = options;

  assertNotSelfProxy(baseUrl, requestUrl);

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), EXTRACT_TIMEOUT_MS);

  try {
    const response = await fetch(`${baseUrl}/api/extract-pose`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${adminSecret}`,
      },
      body: formData,
      cache: 'no-store',
      signal: controller.signal,
    });

    const contentLength = response.headers.get('content-length');
    if (contentLength && Number(contentLength) > MAX_EXTRACT_PROXY_RESPONSE_BYTES) {
      throw new Error('Extract proxy response is too large');
    }

    const rawText = await response.text();
    if (rawText.length > MAX_EXTRACT_PROXY_RESPONSE_BYTES) {
      throw new Error('Extract proxy response is too large');
    }

    let payload = {};
    if (rawText) {
      payload = safeParseJson(rawText);
    }

    return {
      ok: response.ok,
      status: response.status,
      payload,
    };
  } finally {
    clearTimeout(timeout);
  }
}
