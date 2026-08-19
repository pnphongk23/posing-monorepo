import { callPoseExtractAdmin } from '@/lib/poseExtractAdminServer';
import { mapProxyError } from '../../../proxyError';

export async function GET(_request, { params }) {
  try {
    const { id } = await params;
    const result = await callPoseExtractAdmin(`/api/admin/community/poses/${id}`);
    return Response.json(result.payload, { status: result.status });
  } catch (error) {
    return mapProxyError(error);
  }
}

export async function PATCH(request, { params }) {
  try {
    const { id } = await params;
    const body = await request.json();
    const result = await callPoseExtractAdmin(`/api/admin/community/poses/${id}`, {
      method: 'PATCH',
      body,
    });
    return Response.json(result.payload, { status: result.status });
  } catch (error) {
    return mapProxyError(error);
  }
}

export async function DELETE(_request, { params }) {
  try {
    const { id } = await params;
    const result = await callPoseExtractAdmin(`/api/admin/community/poses/${id}`, {
      method: 'DELETE',
    });
    return Response.json(result.payload, { status: result.status });
  } catch (error) {
    return mapProxyError(error);
  }
}