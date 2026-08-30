---
work_item: 1
title: Close Firebase authority and SDK configuration
status: completed
priority: P2
effort: TBD
dependencies: []
decision_dependencies:
  - "[[DEC-006-remote-config-api-baseurl-policy|DEC-006]]"
  - "[[DEC-007-ios-sdk-integration-architecture|DEC-007]]"
---

# Work Item 1: Close Firebase authority and SDK configuration

## Tasks

- Confirm FEAT-010, DEC-006, DEC-007, and this Plan approvals before Cook.
- Confirm Firebase project, bundle configuration, external plist handling, and
  dSYM runbook inputs without committing credentials.
- Re-run sourcewalk/direct impact checks for App, AppConfig.SERVER_BASE_URL,
  PoseServiceLocator.baseUrl, and PoseServiceLocator.apiService.
- Record exact SDK versions supported by the current CocoaPods/Xcode toolchain;
  do not upgrade unrelated dependencies.

## Scope and affected files

gradle/libs.versions.toml, mobile/composeApp/build.gradle.kts,
mobile/iosApp/Podfile, Podfile.lock, project.yml, AppDelegate.swift,
Info.plist, Firebase resource/runbook placeholders. Do not touch
PosesScreen.kt or Navigation.kt.

## Success criteria

- Authority, SDK versions, package lane, public configuration, dSYM path, and
  conflict boundary are recorded without inventing approval.

## Risks

- Pod resolution can introduce unrelated lockfile churn; missing Firebase
  configuration can block runtime verification.

## Required evidence

ckh status/check output, impact evidence, approved dependency diff, and
credential/conflict audit.
