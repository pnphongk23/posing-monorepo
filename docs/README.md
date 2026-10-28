# posing documentation

## Project map

```text
ai-pose/
├── AGENTS.md
├── CLAUDE.md
├── README.md
├── mobile/
│   └── iosApp/
├── web/
│   ├── admin-ui/
│   └── services/pose-extract-server/
├── docs/
│   ├── harness/       (single source of truth: specs/, features/, plans/, reports/)
│   ├── prototype/
│   ├── app-store-publish/
│   ├── evidence/
│   └── design-reference/
├── plans/
├── scripts/
└── correlation/
```

## How to read this project

Start with the root `README.md` for repository lanes and common commands. Read
`docs/harness/specs/data-contract.md` for canonical entities, fields, business rules, and ERD;
`docs/harness/specs/api-contract.md` for OpenAPI, HTTP conventions, and API modules. Read
`docs/harness/specs/` for cross-feature technical summaries and
`docs/harness/features/` for observable product behavior and acceptance.

The root routers are intentionally thin: `AGENTS.md` gives the code-navigation
rule and `CLAUDE.md` repeats that router instruction for Claude-oriented entry;
`README.md` routes people to the project lanes and checks. Follow this order:
root `README.md` → the relevant Harness feature/spec → canonical data/API
contracts (`docs/harness/specs/data-contract.md`, `api-contract.md`) →
implementation evidence only when needed.

`docs/harness/workflows/` contains workflow contracts for authoring and
validation. It is not the product source of truth; product behavior belongs in
Harness Features and shared technical contracts live in `docs/harness/specs/`.

Frozen ignore list for bounded documentation work:
`mobile/`, `web/`, `docs/prototype/`, `features/`, `decisions/`, `plans/`,
`reports/`, `templates/`, and `workflows/`. Do not alter those paths unless a
task contract explicitly reopens them. Generated Harness index and graph
artifacts must be rebuilt through the CLI, never hand-edited.

## Release Gitflow & Worktree Lifecycle

The project adheres to a dual-worktree Gitflow strategy for development and releases:
- **`backlog` worktree (`backlog` branch)**: Planning, UX/UI designs, feature specifications, and architectural documentation.
- **`baseline` worktree (`main` / baseline lane)**: Implementation (`cook`), test execution, build verification, and release deployment.
- **Release procedure**: Once a release candidate is approved and published (e.g. submitted to App Store), create branch `release/{version_name}` (e.g. `release/1.0`), then merge `release/{version_name}` back into `backlog` to keep planning tracks synchronized with shipped reality.

Detailed contract: [Release Gitflow Specification](harness/specs/release-gitflow.md).
