---
work_item: 2
title: Add reproducible build install and launch workflow
status: pending
priority: P1
effort: M
dependencies:
  - 1
decision_dependencies: []
---

# Work Item 2: Add reproducible build install and launch workflow

**Kind:** technical

## Tasks

- Define exact Gradle/CocoaPods/Xcode commands for a clean-enough signed device
  build without deleting user build state.
- Produce the real-device artifact format accepted by the verified Mobile MCP
  release (`.ipa` if installing through MCP) or document the exact Xcode-installed
  development build identity.
- Add the smallest repo-owned helper/runbook needed to build, locate, install,
  launch, terminate, and relaunch `com.aipose.app` reproducibly.
- Capture build metadata (commit/diff state, configuration, bundle ID, version)
  and protect signing credentials from logs and committed artifacts.
- Gate installation on device identity and user authorization; do not uninstall
  or erase app data by default.

## Scope and affected files

- `mobile/composeApp/build.gradle.kts`
- `mobile/iosApp/Podfile`, `mobile/iosApp/iosApp.xcodeproj/project.pbxproj`, and
  `mobile/iosApp/iosApp/Info.plist` only when required for reproducibility.
- A focused script under `scripts/` or a testing runbook under `docs/`; avoid a
  new framework when documented commands suffice.

## Success criteria

- A fresh invocation creates or identifies one signed build, installs it on the
  selected iPhone, launches the expected bundle, terminates, and relaunches it.
- The workflow fails fast on ambiguous device/artifact/build configuration.
- No signing secret, raw UDID, or generated app/IPA is committed.

## Risks

- Dirty working-tree and generated build deletions already exist; preserve user
  changes and never use destructive cleanup as an implicit prerequisite.
- Xcode signing can succeed locally but remain non-reproducible on another Mac;
  separate documented inputs from machine-local credentials.

## Required evidence

- Exact build command and exit status, artifact identity/checksum, redacted
  install/launch/terminate/relaunch results, and bundle ID assertion.
- `git status --short` before and after proving no unrelated source mutation.
