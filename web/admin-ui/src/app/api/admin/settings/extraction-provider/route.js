import { callPoseExtractAdmin } from '@/lib/poseExtractAdminServer';
import { mapProxyError } from '../../proxyError';

export async function GET() {
  try {
    const result = await callPoseExtractAdmin('/api/admin/settings/extraction-provider');
    return Response.json(result.payload, { status: result.status });
  } catch (error) {
    return mapProxyError(error);
  }
}

export async function PUT(request) {
  try {
    const body = await request.json();
    const result = await callPoseExtractAdmin('/api/admin/settings/extraction-provider', {
      method: 'PUT',
      body,
    });
    return Response.json(result.payload, { status: result.status });
  } catch (error) {
    return mapProxyError(error);
  }
}
