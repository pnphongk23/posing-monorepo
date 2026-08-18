# ERD — Server

Hợp đồng quan hệ phía server theo [domain model](../domain-model.md).

```mermaid
erDiagram
    ACCOUNT ||--o{ POSE_GUIDE : "owns"
    ACCOUNT ||--o{ SAVED_ENTRY : "saves"
    POSE_GUIDE ||--|{ MEDIA_ASSET : "has"
    POSE_GUIDE ||--o{ EXTRACTION_JOB : "tracks"
    POSE_GUIDE ||--o| COMMUNITY_POSE : "publishes as"
    COMMUNITY_POSE ||--o{ SAVED_ENTRY : "saved as"
    API_KEY_CREDENTIAL ||--o{ PROVIDER_REQUEST_LOG : "logged as"

    ACCOUNT {
        text id PK
        text displayName
        datetime createdAt
    }
    POSE_GUIDE {
        text id PK
        text ownerAccountId FK
        text name
        text status
        text sourceAssetId FK
        text renderAssetId FK
        text thumbnailAssetId FK
        text currentJobId FK
        datetime createdAt
        datetime updatedAt
    }
    COMMUNITY_POSE {
        text id PK
        text name
        text imagePath
        text thumbnailPath
        text status
        datetime uploadedAt
        integer downloadCount
    }
    MEDIA_ASSET {
        text id PK
        text guideId FK
        text role
        text locator
        text mimeType
        text readiness
    }
    EXTRACTION_JOB {
        text id PK
        text guideId FK
        text status
        text sourceAssetId FK
        text resultAssetId FK
        integer attempts
        integer maxAttempts
    }
    SAVED_ENTRY {
        text id PK
        text accountId FK
        text poseId FK
        datetime savedAt
    }
    API_KEY_CREDENTIAL {
        text id PK
        text name
        text status
        integer requestsToday
    }
    PROVIDER_REQUEST_LOG {
        integer id PK
        text keyId FK
        datetime timestamp
        integer success
    }
```

`CommunityPose` là projection: cùng `id` với `PoseGuide` khi `status = published`. Public API không trả owner hay job.
