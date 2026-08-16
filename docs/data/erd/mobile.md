# ERD — Mobile Local Physical Graph

Source: `mobile/shared/src/commonMain/sqldelight/com/aipose/Photo.sq`, `Pose.sq`

```mermaid
erDiagram
    POSE ||--o{ PHOTO : "Photo.poseId (nullable, ON DELETE SET NULL)"
    POSE {
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

`Photo.poseId` → `Pose.id` là FK duy nhất trong mobile schema.  
Không có FK từ mobile tables tới server tables.
