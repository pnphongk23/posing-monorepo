import { callPoseExtractAdmin } from '@/lib/poseExtractAdminServer';
import { mapProxyError } from '../../proxyError';

export async function GET(_request, { params }) {
  try {
    const { jobId } = await params;
    const result = await callPoseExtractAdmin(`/api/extract-jobs/${jobId}`);
    return Response.json(result.payload, { status: result.status });
  } catch (error) {
    return mapProxyError(error);
  }
}
