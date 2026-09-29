import Foundation
@testable import iosApp

enum JobsFixtures {
    static let queuedJobJSON = """
    {
      "data": {
        "jobId": "550e8400-e29b-41d4-a716-446655440000",
        "status": "queued",
        "poseId": null,
        "result": null,
        "error": null,
        "updatedAt": "2026-09-26T12:00:00.000Z"
      }
    }
    """

    static let processingJobJSON = """
    {
      "data": {
        "jobId": "550e8400-e29b-41d4-a716-446655440000",
        "status": "processing",
        "poseId": null,
        "result": null,
        "error": null,
        "updatedAt": "2026-09-26T12:00:02.000Z"
      }
    }
    """

    static let succeededJobJSON = """
    {
      "data": {
        "jobId": "550e8400-e29b-41d4-a716-446655440000",
        "status": "succeeded",
        "poseId": "550e8400-e29b-41d4-a716-446655440001",
        "result": {
          "imageBase64": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
          "mimeType": "image/png",
          "processingTimeMs": 1450
        },
        "error": null,
        "updatedAt": "2026-09-26T12:00:05.000Z"
      }
    }
    """

    static let failedJobJSON = """
    {
      "data": {
        "jobId": "550e8400-e29b-41d4-a716-446655440000",
        "status": "failed",
        "poseId": null,
        "result": null,
        "error": {
          "code": "PROVIDER_AUTH_REQUIRED",
          "message": "Provider authentication required"
        },
        "updatedAt": "2026-09-26T12:00:05.000Z"
      }
    }
    """

    static let extractionJobListJSON = """
    {
      "success": true,
      "data": [
        {
          "jobId": "550e8400-e29b-41d4-a716-446655440001",
          "status": "processing",
          "poseDraft": {
            "name": "Active Hero Pose",
            "tags": ["standing", "hero"],
            "description": "Standing tall with chest out"
          },
          "poseId": null,
          "thumbnailUrl": null,
          "errorCode": null,
          "errorMessage": null,
          "createdAt": "2026-09-26T12:00:00.000Z",
          "updatedAt": "2026-09-26T12:00:02.000Z"
        },
        {
          "jobId": "550e8400-e29b-41d4-a716-446655440002",
          "status": "succeeded",
          "poseDraft": {
            "name": "Completed Warrior Pose",
            "tags": ["warrior", "yoga"],
            "description": "Warrior stance step 1\\nStep 2"
          },
          "poseId": "550e8400-e29b-41d4-a716-446655440003",
          "thumbnailUrl": "https://example.com/thumb.jpg",
          "errorCode": null,
          "errorMessage": null,
          "createdAt": "2026-09-26T11:50:00.000Z",
          "updatedAt": "2026-09-26T11:50:05.000Z"
        },
        {
          "jobId": "550e8400-e29b-41d4-a716-446655440004",
          "status": "failed",
          "poseDraft": {
            "name": "Failed Tree Pose",
            "tags": ["balance"],
            "description": null
          },
          "poseId": null,
          "thumbnailUrl": null,
          "errorCode": "LINEART_BG_REMOVAL_FAILED",
          "errorMessage": "Background removal failed",
          "createdAt": "2026-09-26T11:40:00.000Z",
          "updatedAt": "2026-09-26T11:40:05.000Z"
        }
      ],
      "meta": {
        "nextCursor": null
      }
    }
    """

    static let guidePoseDetailJSON = """
    {
      "data": {
        "poseId": "550e8400-e29b-41d4-a716-446655440003",
        "ownerAccountId": "550e8400-e29b-41d4-a716-446655440099",
        "name": "Completed Warrior Pose",
        "description": "Warrior stance step 1\\nStep 2",
        "tags": ["warrior", "yoga"],
        "difficulty": "intermediate",
        "bodyParts": ["full_body"],
        "status": "local",
        "originalUrl": "https://example.com/poses/original.jpg",
        "skeletonUrl": "https://example.com/poses/skeleton.png",
        "thumbnailUrl": "https://example.com/poses/thumbnail.png",
        "currentJobId": "550e8400-e29b-41d4-a716-446655440002",
        "createdAt": "2026-09-26T11:50:00.000Z",
        "updatedAt": "2026-09-26T11:50:05.000Z"
      }
    }
    """

    static let startPoseExtractionJSON = """
    {
      "success": true,
      "data": {
        "jobId": "550e8400-e29b-41d4-a716-446655440000",
        "status": "queued"
      },
      "meta": {
        "pollUrl": "/api/extract-jobs/550e8400-e29b-41d4-a716-446655440000"
      }
    }
    """
}

