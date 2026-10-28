import { callPoseExtractAdmin } from '@/lib/poseExtractAdminServer';
import { mapProxyError } from '../../proxyError';

export async function POST() {
  try {
    const result = await callPoseExtractAdmin('/api/admin/keys/reset', {
      method: 'POST',
    });
    return Response.json(result.payload, { status: result.status });
  } catch (error) {
    return mapProxyError(error);
  }
}
