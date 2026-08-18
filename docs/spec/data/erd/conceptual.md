# ERD — Conceptual overlay

Quan hệ Try Pose và ranh giới mobile/server. [FEAT-008](../../../harness/features/FEAT-008-use-published-poses.md).

## Try Pose (in-memory)

```mermaid
erDiagram
    POSE_REFERENCE_KEY ||--|| PERSONAL_POSE : "Personal(id)"
    POSE_REFERENCE_KEY ||--|| COMMUNITY_POSE : "Community(id)"
    POSE_REFERENCE_KEY ||--o| PREPARED_POSE_REFERENCE : "embedded as key"

    POSE_REFERENCE_KEY {
        string variant
    }
    PERSONAL_POSE {
        integer local_id
    }
    COMMUNITY_POSE {
        string server_uuid
    }
    PREPARED_POSE_REFERENCE {
        string renderLocator
        string name
    }
```

`PreparedPoseReference.renderLocator` luôn local/data URI sau khi verify. Không persist relaunch.

## Ranh giới layer

```mermaid
flowchart LR
  subgraph mobile [Mobile local]
    Photo
    PersonalPose
    PreparedPoseReference
  end
  subgraph server [Server]
    PoseGuide
    CommunityPose
    MediaAsset
    Account
    SavedEntry
  end
  CommunityPose -.->|download + verify| PreparedPoseReference
  Account -->|saves| SavedEntry
  SavedEntry --> CommunityPose
  PoseGuide -->|publish| CommunityPose
  PoseGuide --> MediaAsset
```

Không có FK từ `Photo` / `PersonalPose` sang server. `SavedEntry` không cấp ownership `PoseGuide`.
