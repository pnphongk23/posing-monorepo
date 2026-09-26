---
schema_version: 1
title: Release Gitflow and Worktree Lifecycle
relationships:
  specs:
    - "[[web-railway-and-ios-testflight-build-and-release-guide]]"
  decisions: []
  plans: []
  reports: []
  rules: []
  features: []
  source_paths:
    - "AGENTS.md"
    - "CLAUDE.md"
    - "docs/README.md"
type: spec
status: active
---

# Release Gitflow and Worktree Lifecycle

## 1. Overview & Objective

This specification establishes the canonical Gitflow and dual-worktree operating model for the `ai-pose` repository. It defines clear boundaries between planning/design phases and execution/release phases to prevent incomplete features or experimental work from polluting release candidates or production baselines.

---

## 2. Worktree Lanes & Responsibilities

The repository organizes development across two primary lanes (worktrees):

| Worktree / Branch | Primary Role | Permitted Activities | Restrictions |
| --- | --- | --- | --- |
| **`backlog`** (`backlog` branch / worktree) | Planning & Specification | • Writing implementation plans (`plans/`)<br>• UI/UX designs and wireframes (`docs/design-reference/`, `prototype/`)<br>• Harness feature definitions (`docs/harness/features/`)<br>• Technical specs & architecture contracts (`docs/harness/specs/`) | **NO direct code cooking or release packaging.** Code is only cooked once a plan is finalized and shifted to baseline. |
| **`baseline`** (`main` / baseline lane) | Implementation & Release Verification | • Code implementation (`cook`)<br>• Running unit, integration, and UI tests (`test`)<br>• Verifying builds (Next.js, Express, native iOS)<br>• Packaging & submission (TestFlight, App Store, Railway deployment) | **NO unapproved exploratory architectural churn.** Follows approved plans from backlog. |

---

## 3. Release Lifecycle & Gitflow Protocol

When a milestone is reached and the application undergoes release review and submission:

```text
[backlog worktree]
  ├── plan, design, harness specs ────────┐ (Approved Plan)
  ▲                                       ▼
  │                              [baseline worktree: main]
  │                                       ├── cook, test, build
  │                                       ├── App Store submission / deployment
  │                                       ▼
  │                                [Release Approval]
  │                                       │
  │                                       ▼
  │                              Checkout: release/{version_name}
  │                                       │
  └──────── Merge release/{version_name} ◄┘
```

### Step 1: Pre-Release Verification & Approval
1. All automated tests and build checks pass (`npm run build`, `npm run backend:build`, iOS native builds).
2. The release build is submitted and verified (e.g. TestFlight or App Store review).
3. The release is formally approved for deployment.

### Step 2: Create Release Branch
From the verified commit on `main` (or baseline worktree):
```bash
git checkout -b release/{version_name}
```
*Example for version 1.0:*
```bash
git checkout -b release/1.0
```
Optional: create an annotated git tag:
```bash
git tag -a v{version_name} -m "Release {version_name}"
```

### Step 3: Back-Merge into `backlog`
To ensure that all release changes, final production tweaks, and submission metadata are incorporated into future planning:
1. Switch to the `backlog` worktree (or branch):
   ```bash
   git checkout backlog
   ```
2. Merge the release branch:
   ```bash
   git merge release/{version_name}
   ```
3. Resolve any documentation or roadmap conflicts, keeping release reality as the canonical truth.

### Step 4: Maintenance & Hotfixes
- Critical hotfixes for a deployed version branch from `release/{version_name}`.
- Once tested and approved, hotfix commits are cherry-picked or merged back into both `main` and `backlog`.

---

## 4. Agent Rules & Operating Directives

All AI agents and contributors must follow these operating constraints:
1. **Context Discipline**: Check your active working directory and git branch. If in `backlog`, restrict mutations to planning, design, and documentation.
2. **Release Traceability**: Never delete release branches (`release/*`). They serve as immutable snapshots of what was shipped to the App Store and production servers.
3. **Continuous Sync**: Always back-merge release branches into `backlog` immediately upon release approval to prevent divergence.
