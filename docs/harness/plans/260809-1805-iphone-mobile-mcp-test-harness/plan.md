---
title: iPhone Mobile MCP Test Harness
description: Establish a reproducible real-iPhone build, Mobile MCP automation, and evidence path for Camera verification.
status: pending
approval:
  status: pending
  required_by: Repository Maintainer
priority: P1
effort: L
branch: codex/iphone-mobile-mcp-test-harness
tags: [ios, iphone, testing, mobile-mcp, camera]
blockedBy: []
blocks:
  - 260809-1806-camera-source-of-truth-convergence
relationships:
  specs:
    - "[[technical-architecture]]"
    - "[[ui-ux-system]]"
  decisions: []
  plans: []
  reports: []
  rules: []
  features:
    - "[[FEAT-001-capture-a-photo-on-mobile|FEAT-001]]"
  source_paths:
    - docs/harness/plans/260809-1805-iphone-mobile-mcp-test-harness/design.md
    - docs/harness/plans/260809-1806-camera-source-of-truth-convergence/plan.md
    - .agents/skills/mobile-mcp-iphone-testing
    - mobile/composeApp/build.gradle.kts
    - mobile/iosApp/iosApp.xcodeproj/project.pbxproj
    - mobile/iosApp/iosApp/Info.plist
created: 2026-08-09T18:05:00+07:00
createdBy: Harness CLI
---

# iPhone Mobile MCP Test Harness

## Overview

Create the smallest repeatable path from a known iOS build to observable Camera
evidence on one explicitly selected physical iPhone. The path combines native
build/unit checks with Mobile MCP for device discovery, app lifecycle,
accessibility-first interaction, screenshots, recording, and crash inspection.

This is a technical-only Plan: it must not change product behavior. It may add
test/runbook/helper artifacts and accessibility identifiers required for
deterministic automation, but Camera behavior remains governed by FEAT-001 and
the linked specifications. See [design.md](./design.md).

Current grounding:

- **Verified:** the app is an iOS 15+ Kotlin/Compose Multiplatform target with
  bundle identifier `com.aipose.app`.
- **Verified:** `@mobilenext/mobile-mcp` 1.0.2 exposes local-device discovery,
  app lifecycle, accessibility, screenshot/recording, orientation, and crash
  tools; its official documentation supports real iOS devices.
- **Verified:** `ios` (`go-ios`) v1.0.188 and a WebDriverAgent checkout exist on
  this Mac.
- **Failed:** Mobile MCP is not registered in the current Codex MCP list.
- **Failed:** `ios list` returned no connected devices and Xcode reported only
  offline iPhones during planning; tunnel/WDA/device execution is unavailable.
- **Verified:** the repo-local skill
  `.agents/skills/mobile-mcp-iphone-testing` was created and mechanically
  validated to preserve setup, tool, safety, and evidence guidance.
- **Unresolved:** the Repository Maintainer must identify the test iPhone and
  confirm whether global Codex MCP configuration may be changed during Cook.

## Work Items

- [Work Item 1: Establish real iPhone and Mobile MCP preflight](./work-item-01-establish-real-iphone-and-mobile-mcp-preflight.md)
- [Work Item 2: Add reproducible build install and launch workflow](./work-item-02-add-reproducible-build-install-and-launch-workflow.md)
- [Work Item 3: Define Camera device scenarios and evidence contract](./work-item-03-define-camera-device-scenarios-and-evidence-contract.md)
- [Work Item 4: Execute and report the iPhone baseline](./work-item-04-execute-and-report-the-iphone-baseline.md)

## Coverage

| Technical objective | Work Items |
| --- | --- |
| T-01 Prove a selected real iPhone is discoverable and automatable | 1 |
| T-02 Produce a repeatable signed build/install/launch workflow | 2 |
| T-03 Define deterministic Camera scenarios and layered evidence | 3 |
| T-04 Execute a baseline and report pass/fail/blocker evidence | 4 |
| T-05 Keep device mutation, secrets, and paid cloud allocation controlled | 1, 2, 4 |

## Verification ledger

| Claim | Status | Evidence |
| --- | --- | --- |
| iOS bundle ID is `com.aipose.app` | Verified | `mobile/iosApp/iosApp.xcodeproj/project.pbxproj` |
| Deployment target is iOS 15 | Verified | `mobile/composeApp/build.gradle.kts`; Xcode project settings |
| Mobile MCP supports real iOS devices and required evidence tools | Verified | official README and current `src/server.ts` from release/source inspection |
| Codex currently has Mobile MCP enabled | Failed | `codex mcp list` on 2026-08-09 |
| A real iPhone is currently ready | Failed | `ios list` empty; `xcrun xctrace list devices` showed iPhones offline |
| Simulator can prove physical Camera capture | Verified false | app simulator bridge returns empty image data by design |
| Existing mobile tests are a clean prerequisite | Failed | REP-002 records unresolved `kotlinx.coroutines.test.runTest` compilation |

## Verification

- `python3 ~/.codex/skills/.system/skill-creator/scripts/quick_validate.py .agents/skills/mobile-mcp-iphone-testing`
- `./gradlew :composeApp:allTests :shared:iosSimulatorArm64Test`
- A documented signed device build (`xcodebuild` command finalized in Work Item 2).
- Mobile MCP calls: device list, app list/install/launch, element list,
  screenshots/recording, and crash-list delta on the selected real iPhone.
- `ckh workflow check 260809-1805-iphone-mobile-mcp-test-harness --workspace .`

Approval remains pending. Cook must not start until the failed device/MCP claims
are converted to verified prerequisites or explicitly scoped as setup tasks and
the Repository Maintainer approves the target device and mutation boundary.
