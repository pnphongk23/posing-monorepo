# ERD — Mobile local

Ảnh chụp và pose cá nhân trên thiết bị. [FEAT-001](../../../harness/features/FEAT-001-capture-a-photo-on-mobile.md), [FEAT-002](../../../harness/features/FEAT-002-manage-a-local-photo-gallery.md). Không FK tới server.

```mermaid
erDiagram
    PERSONAL_POSE ||--o{ PHOTO : "optional pose at capture"

    PERSONAL_POSE {
        integer id PK
        text name
        text imagePath
        text thumbnailPath
        text originalImagePath
        text createdAt
        integer isMine
        integer likes
    }
    PHOTO {
        integer id PK
        text imagePath
        integer poseId FK
        text poseName
        text createdAt
        integer isFavorite
    }
```

`Photo.poseId` → `PersonalPose.id` optional, ON DELETE SET NULL.
