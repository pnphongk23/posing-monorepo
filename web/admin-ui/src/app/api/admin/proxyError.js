const MISCONFIG_MARKERS = [
  'POSE_EXTRACT_SERVER_URL',
  'POSE_EXTRACT_ADMIN_SECRET',
  'ADMIN_SECRET',
  'Invalid POSE_EXTRACT_SERVER_URL',
  'recursive proxy calls',
];

const UPSTREAM_STATUS_KEYS = ['status', 'statusCode', 'upstreamStatus'];

const MISCONFIG_MESSAGE =
  'Admin proxy đang cấu hình sai. Kiểm tra POSE_EXTRACT_SERVER_URL và POSE_EXTRACT_ADMIN_SECRET.';

const UPSTREAM_ERROR_MESSAGE = 'Upstream request failed';

const SAFE_CODE_PATTERN = /^[A-Z][A-Z0-9_]{1,63}$/;

const REDACTIONS = [
  [/(\/\/)[^\s/@]+@/g, '$1[redacted]@'],
  [/\b(Bearer|Basic|Token)\s+[A-Za-z0-9._~+/=-]+/gi, '$1 [redacted]'],
  [/([?&](?:api[_-]?key|key|token|secret|password|admin[_-]?secret)=)[^&\s]*/gi, '$1[redacted]'],
  [/\b(?:sk|pk|ghp|gho|xox[abprs])[-_][A-Za-z0-9_-]{6,}\b/g, '[redacted]'],
  [/\b[A-Za-z0-9_-]{32,}\b/g, '[redacted]'],
];

function resolveUpstreamStatus(error) {
  if (!error || typeof error !== 'object') return null;

  for (const key of UPSTREAM_STATUS_KEYS) {
    const value = error[key];
    if (Number.isInteger(value) && value >= 400 && value <= 599) {
      return value;
    }
  }

  return null;
}

function redactSecrets(value) {
  const text = typeof value === 'string' ? value : '';
  return REDACTIONS.reduce((acc, [pattern, replacement]) => acc.replace(pattern, replacement), text);
}

function logUpstreamFailure({ status, code, error }) {
  console.error('[admin-proxy] upstream request failed', {
    status,
    code,
    message: redactSecrets(error?.message) || 'unknown error',
  });
}

export function mapProxyError(error) {
  const rawMessage = typeof error?.message === 'string' ? error.message : '';
  const isMisconfig = MISCONFIG_MARKERS.some((marker) => rawMessage.includes(marker));

  if (isMisconfig) {
    logUpstreamFailure({ status: 500, code: 'ADMIN_PROXY_MISCONFIG', error });
    return Response.json(
      {
        error: MISCONFIG_MESSAGE,
        code: 'ADMIN_PROXY_MISCONFIG',
      },
      { status: 500 }
    );
  }

  const upstreamStatus = resolveUpstreamStatus(error);
  const upstreamCode =
    upstreamStatus && typeof error?.code === 'string' && SAFE_CODE_PATTERN.test(error.code)
      ? error.code
      : null;

  logUpstreamFailure({ status: upstreamStatus ?? 500, code: upstreamCode, error });

  return Response.json(
    {
      error: UPSTREAM_ERROR_MESSAGE,
      code: upstreamCode || 'ADMIN_PROXY_ERROR',
    },
    { status: upstreamStatus ?? 500 }
  );
}
