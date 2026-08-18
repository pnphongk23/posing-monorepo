---
schema_version: 1
type: spec
title: Harness Global Entity Relationship Diagram
status: draft
relationships:
  specs:
    - "[[model-entity-catalogue]]"
    - "[[technical-architecture]]"
    - "[[api-catalogue]]"
  decisions: []
  plans: []
  reports:
    - "[[REP-004-backend-feature-and-model-entity-scout|REP-004]]"
  rules: []
  features:
    - "[[FEAT-001-capture-a-photo-on-mobile|FEAT-001]]"
    - "[[FEAT-002-manage-a-local-photo-gallery|FEAT-002]]"
    - "[[FEAT-003-browse-and-search-published-poses|FEAT-003]]"
    - "[[FEAT-004-extract-reusable-pose-images|FEAT-004]]"
    - "[[FEAT-005-manage-a-pose-guide|FEAT-005]]"
    - "[[FEAT-006-publish-a-pose|FEAT-006]]"
    - "[[FEAT-007-operate-pose-content-from-admin-web|FEAT-007]]"
    - "[[FEAT-008-use-published-poses|FEAT-008]]"
  source_paths:
    - mobile/shared/src/commonMain/sqldelight/com/aipose/Photo.sq
    - mobile/shared/src/commonMain/sqldelight/com/aipose/Pose.sq
    - web/services/pose-extract-server/src/db/schema.sql
---

# Global ERD — stub

> **Nguồn sự thật đã chuyển sang [`docs/spec/data/erd/`](../../spec/data/erd/).**

Tài liệu này được giữ lại để duy trì harness wikilinks. ERD diagrams không còn ở đây.

<a id="mobile-local-physical-graph"></a>
<a id="server-physical-graph"></a>
<a id="conceptual-feature-overlay"></a>
<a id="unresolved-cross-feature-links"></a>

| Tài nguyên | Đường dẫn |
|---|---|
| Server physical graph | [`docs/spec/data/erd/server.md`](../../spec/data/erd/server.md) |
| Mobile local physical graph | [`docs/spec/data/erd/mobile.md`](../../spec/data/erd/mobile.md) |
| Conceptual overlay | [`docs/spec/data/erd/conceptual.md`](../../spec/data/erd/conceptual.md) |
