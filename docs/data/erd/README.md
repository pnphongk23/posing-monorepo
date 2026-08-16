# ERD

Tài liệu entity relationship diagrams cho ai-pose.

| File | Nội dung |
|---|---|
| [`server.md`](server.md) | Server physical graph (SQLite tables và FK thực sự) |
| [`mobile.md`](mobile.md) | Mobile local physical graph (SQLDelight tables) |
| [`conceptual.md`](conceptual.md) | Conceptual overlay và unresolved links |

**Quy ước:**
- Edge liền: FK vật lý có trong schema
- Edge đứt / TBD: conceptual link hoặc link chưa có implementation

Semantics của từng field: xem [`../entities/`](../entities/).
