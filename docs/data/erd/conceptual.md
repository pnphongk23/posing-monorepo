# ERD — Conceptual Overlay

Các link conceptual và unresolved giữa các entity. **Không có FK vật lý** cho các quan hệ này.

## Mobile conceptual types

```mermaid
erDiagram
    POSE_REFERENCE_KEY ||--|| PERSONAL_POSE : "Personal(id) variant"
    POSE_REFERENCE_KEY ||--|| COMMUNITY_POSE : "Community(id) variant"
    POSE_REFERENCE_KEY ||--o| PREPARED_POSE_REFERENCE : "embedded as .key"
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

## Unresolved cross-feature links (cardinality TBD)

```mermaid
flowchart LR
    CP["CommunityPose"]
    EJ["ExtractionJob"]
    MA["MediaAsset (TBD)"]
    ACC["Account (TBD)"]
    SE["SavedEntry (TBD)"]
    PG["PoseGuide (TBD)"]

    CP -. "TBD — route tạo cả hai nhưng không lưu FK" .- EJ
    EJ -. "TBD — result chỉ có base64; không có asset table" .- MA
    CP -. "TBD — image_path là URL string, không FK tới asset table" .- MA
    ACC -. "TBD — chưa có schema/auth" .- SE
    SE -. "TBD" .- CP
    CP -. "TBD — aggregate chưa implement" .- PG
```

## Bảng unresolved links

| Link | Trạng thái hiện tại |
|---|---|
| `CommunityPose` → `ExtractionJob` | Route POST tạo cả hai nhưng không lưu FK |
| `ExtractionJob` → MediaAsset | Không có asset table; result là base64 trong job |
| `CommunityPose` → render asset | `image_path` là URL string; readiness/upload chưa proven |
| `Account` → `SavedEntry` → `CommunityPose` | Không tìm thấy schema, API, hoặc auth |
| `PoseGuide` aggregate | Không có dedicated implementation |
