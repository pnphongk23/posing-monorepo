import { callPoseExtractAdmin } from '@/lib/poseExtractAdminServer';
import { mapProxyError } from '../../proxyError';

export async function GET(request) {
  try {
    const { search } = new URL(request.url);
    const result = await callPoseExtractAdmin(`/api/admin/community/poses${search}`);
    return Response.json(result.payload, { status: result.status });
  } catch (error) {
    return mapProxyError(error);
  }
}

export async function POST(request) {
  try {
    const contentType = request.headers.get('content-type') || '';
    const body = contentType.includes('multipart/form-data')
      ? await request.formData()
      : await request.json();
    const result = await callPoseExtractAdmin('/api/admin/community/poses', {
      method: 'POST',
      body,
    });

    return Response.json(result.payload, { status: result.status });
  } catch (error) {
    return mapProxyError(error);
  }
}
