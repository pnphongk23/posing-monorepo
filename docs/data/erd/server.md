# ERD — Server Physical Graph

Source: `web/services/pose-extract-server/src/db/schema.sql`

```mermaid
erDiagram
    API_KEYS ||--o{ REQUEST_LOGS : "request_logs.key_id (nullable, ON DELETE SET NULL)"
    API_KEYS {
        text id PK
        text name
        text api_key
        text status
        integer requests_today
        datetime created_at
        datetime last_used_at
    }
    REQUEST_LOGS {
        integer id PK
        text key_id FK
        datetime timestamp
        integer processing_time_ms
        integer success
        text error_code
    }
    COMMUNITY_POSES {
        text id PK
        text name
        text image_path
        text thumbnail_path
        text tags
        text difficulty
        text description
        text body_parts
        text status
        datetime uploaded_at
        integer download_count
    }
    EXTRACTION_JOBS {
        text id PK
        text status
        text source_image_base64
        text source_mime_type
        text result_image_base64
        text result_mime_type
        text error_code
        text error_message
        integer attempts
        integer max_attempts
        datetime locked_at
        text lock_token
        datetime created_at
        datetime updated_at
    }
```

`API_KEYS` → `REQUEST_LOGS` là FK duy nhất trong schema server.  
`COMMUNITY_POSES` và `EXTRACTION_JOBS` không có FK vật lý nào kết nối với nhau — xem [conceptual.md](conceptual.md).  
Bảng `schema_bootstrap` bị bỏ qua: operational only, không phải product entity.
