# ERD — Server

Hợp đồng quan hệ phía server theo [domain model](../domain-model.md). Entity
canonical duy nhất là `Pose`; catalogue công khai là view/DTO (`status=published`),
không phải entity riêng.

```mermaid
erDiagram
    ACCOUNT ||--o{ POSE : "owns"
    ACCOUNT ||--o{ SAVED_ENTRY : "saves"
    POSE ||--|{ MEDIA_ASSET : "has exactly 3 (original|skeleton|thumbnail)"
    POSE ||--o{ EXTRACTION_JOB : "tracks"
    POSE ||--o{ SAVED_ENTRY : "saved as"
    API_KEY_CREDENTIAL ||--o{ PROVIDER_REQUEST_LOG : "logged as"

    ACCOUNT {
        text id PK
        text displayName
        datetime createdAt
    }
    POSE {
        text poseId PK
        text ownerAccountId FK "REQUIRED on every Pose"
        text name
        text status
        text originalMediaId FK
        text skeletonMediaId FK
        text thumbnailMediaId FK
        text currentJobId FK
        datetime createdAt
        datetime updatedAt
    }
    MEDIA_ASSET {
        text mediaId PK
        text poseId FK
        text role
        text locator
        text mimeType
        text readiness
    }
    EXTRACTION_JOB {
        text id PK "jobId (correlation key)"
        text poseId FK "nullable until pose created"
        text status
        text sourceMediaId FK
        text skeletonMediaId FK
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

`Pose.status = published` chỉ có trên public view (DTO `CommunityPose`); public API
không trả owner, original, hay job. `poseId` ổn định từ `local` → `published` và
được gán tại lúc tạo — **`Pose` chỉ được tạo sau khi extraction `succeeded`**
(trong lúc extraction, job được theo dõi bằng `jobId`). `ownerAccountId` bắt buộc
(non-nullable) trên mọi `Pose`; `ExtractionJob.poseId` nullable tới khi pose tạo.
Xem glossary [`pose-domain-glossary.md`](../../../harness/specs/pose-domain-glossary.md).