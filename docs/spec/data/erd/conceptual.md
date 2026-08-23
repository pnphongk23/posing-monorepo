# ERD — Conceptual overlay

Quan hệ Try Pose và ranh giới mobile/server. [FEAT-008](../../../harness/features/FEAT-008-use-published-poses.md).

## Try Pose (in-memory)

```mermaid
erDiagram
    PREPARED_POSE_REFERENCE ||--o| POSE : "references poseId"
    PREPARED_POSE_REFERENCE ||--o| MEDIA_ASSET : "references mediaId (skeleton ready)"

    PREPARED_POSE_REFERENCE {
        string poseId
        string mediaId
        string skeletonLocator
        string name
    }
    POSE {
        string poseId PK
        string skeletonMediaId FK
    }
    MEDIA_ASSET {
        string mediaId PK
        string role
    }
```

`PreparedPoseReference.skeletonLocator` luôn local/data URI sau khi verify. Không
persist relaunch. Không còn `PoseReferenceKey.Personal|Community`.

## Ranh giới layer

```mermaid
flowchart LR
  subgraph mobile [Mobile local]
    Photo
    Pose
    PreparedPoseReference
  end
  subgraph server [Server]
    Pose
    MediaAsset
    Account
    SavedEntry
  end
  Pose -.->|download + verify skeleton| PreparedPoseReference
  Account -->|saves| SavedEntry
  SavedEntry --> Pose
  Pose --> MediaAsset
```

Không có FK bắt buộc từ `Photo` sang server. `SavedEntry` không cấp ownership
`Pose`. Catalogue công khai là view/DTO — không phải entity riêng.