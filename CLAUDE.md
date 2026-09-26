# CLAUDE.md — Project Rules

> ⚠️ **CODE NAVIGATION: USE `srcwalk` FIRST.**
> Read `.agents/skills/srcwalk/SKILL.md` + `GUIDE.md`, run `srcwalk guide`, and prefer
> `srcwalk` (map/find/callers/flow) over raw reads or broad grep for code-structure work.
> Use raw reads/grep only for pure text/path matching.
> Documentation map: [docs/README.md](docs/README.md).
Ưu tiên test quality, feauture code, nghiệp vụ thực tế, thay vì tập trung vào pass các quy trình workflow

## Release Gitflow & Worktree Lanes

- **`backlog` worktree (`backlog` branch)**: Dành riêng cho tạo plan, design, phân tích yêu cầu, đặc tả harness specs/features.
- **`baseline` worktree (`main` / baseline lane)**: Dành riêng cho triển khai code (`cook`), chạy kiểm thử (`test`), verify build thực tế.
- **Quy trình Release**:
  1. Sau khi duyệt release: tạo nhánh `release/{version_name}` (ví dụ: `release/1.0`).
  2. Sau đó merge nhánh `release/{version_name}` ngược lại vào `backlog` để đồng bộ baseline mới nhất cho planning tiếp theo.
- Chi tiết xem tại: [`docs/harness/specs/release-gitflow.md`](docs/harness/specs/release-gitflow.md).
