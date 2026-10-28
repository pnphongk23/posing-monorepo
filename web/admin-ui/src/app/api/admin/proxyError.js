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

export function mapProxyError(error) {
  const rawMessage = error?.message || 'Proxy request failed';
  const isMisconfig = MISCONFIG_MARKERS.some((marker) => rawMessage.includes(marker));

  if (isMisconfig) {
    return Response.json(
      {
        error: MISCONFIG_MESSAGE,
        code: 'ADMIN_PROXY_MISCONFIG',
      },
      { status: 500 }
    );
  }

  const upstreamStatus = resolveUpstreamStatus(error);
  const upstreamCode = upstreamStatus && typeof error?.code === 'string' && error.code ? error.code : null;

  return Response.json(
    {
      error: rawMessage,
      code: upstreamCode || 'ADMIN_PROXY_ERROR',
    },
    { status: upstreamStatus ?? 500 }
  );
}
