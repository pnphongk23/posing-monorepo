const DEFAULT_TIMEOUT_MS = 20000;

export function getAdminConfig() {
  const baseUrl = process.env.POSE_EXTRACT_SERVER_URL;
  const adminSecret = process.env.POSE_EXTRACT_ADMIN_SECRET;

  if (!baseUrl) {
    throw new Error('Missing POSE_EXTRACT_SERVER_URL');
  }

  if (!adminSecret) {
    throw new Error('Missing POSE_EXTRACT_ADMIN_SECRET');
  }

  const normalizedBaseUrl = baseUrl.replace(/\/+$/, '');
  const currentPort = process.env.PORT || '3000';

  try {
    const parsed = new URL(normalizedBaseUrl);
    const isLocalhost = parsed.hostname === 'localhost' || parsed.hostname === '127.0.0.1';
    const targetPort = parsed.port || (parsed.protocol === 'https:' ? '443' : '80');

    if (isLocalhost && targetPort === currentPort) {
      throw new Error(`POSE_EXTRACT_SERVER_URL points to current Next server (${parsed.origin})`);
    }
  } catch (error) {
    if (error instanceof TypeError) {
      throw new Error('Invalid POSE_EXTRACT_SERVER_URL');
    }
    throw error;
  }

  return {
    baseUrl: normalizedBaseUrl,
    adminSecret,
  };
}

export async function callPoseExtractAdmin(pathname, options = {}) {
  const { baseUrl, adminSecret } = getAdminConfig();
  const { method = 'GET', body, headers: customHeaders } = options;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), DEFAULT_TIMEOUT_MS);

  try {
    const isFormData = typeof FormData !== 'undefined' && body instanceof FormData;
    const defaultHeaders = {
      Authorization: `Bearer ${adminSecret}`,
      ...(!isFormData && body ? { 'Content-Type': 'application/json' } : {}),
    };
    const fetchOptions = {
      method,
      headers: {
        ...defaultHeaders,
        ...(customHeaders || {}),
      },
      body: body ? (isFormData ? body : JSON.stringify(body)) : undefined,
      cache: 'no-store',
      signal: controller.signal,
    };

    let response;
    try {
      response = await fetch(`${baseUrl}${pathname}`, fetchOptions);
    } catch (error) {
      if (!baseUrl.includes('localhost') && !baseUrl.includes('127.0.0.1')) {
        throw error;
      }

      const fallbackBaseUrl = baseUrl.includes('localhost')
        ? baseUrl.replace('localhost', '127.0.0.1')
        : baseUrl.replace('127.0.0.1', 'localhost');
      response = await fetch(`${fallbackBaseUrl}${pathname}`, fetchOptions);
    }

    const rawText = await response.text();
    let payload = {};

    if (rawText) {
      try {
        payload = JSON.parse(rawText);
      } catch {
        payload = { error: rawText };
      }
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
