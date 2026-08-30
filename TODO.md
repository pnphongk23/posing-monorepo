# Admin Community Poses CRUD — Execution TODO

- [x] Scout lại các file liên quan (store, routes, proxy, page, tests)
- [x] Impact analysis (symbols mới: LOW risk — additive)
- [ ] CommunityStore: thêm `updatePose`, `deletePose`
- [ ] communityStore.test.ts: test update/delete
- [ ] adminCommunityRoutes.ts: GET /:id, PATCH /:id, DELETE /:id
- [ ] adminCommunityRoutes.test.ts: test routes mới
- [ ] Next proxy: `api/admin/community/poses/[id]/route.js` (GET/PATCH/DELETE)
- [ ] Admin UI `community/page.js`: error state list + read/edit/delete UX
- [ ] Chạy backend tests