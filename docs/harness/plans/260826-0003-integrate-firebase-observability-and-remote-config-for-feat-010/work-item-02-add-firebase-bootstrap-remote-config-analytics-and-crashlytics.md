---
work_item: 2
title: Add Firebase bootstrap, Remote Config, Analytics, and Crashlytics
status: completed
priority: P2
effort: TBD
dependencies:
  - 1
decision_dependencies:
  - "[[DEC-006-remote-config-api-baseurl-policy|DEC-006]]"
  - "[[DEC-007-ios-sdk-integration-architecture|DEC-007]]"
---

# Work Item 2: Add Firebase bootstrap, Remote Config, Analytics, and Crashlytics

## Tasks

- Initialize Firebase best-effort and apply DEC-006's source default, activated
  cache, bounded fetch/activate, validation, and fallback sequence.
- Apply one valid endpoint consistently to AppConfig.SERVER_BASE_URL and
  PoseServiceLocator.baseUrl before lazy/eager API-backed state is created.
- Add sanitized Analytics events for app start, endpoint source, and bounded
  lifecycle/configuration outcomes; exclude pose/camera/payment payloads.
- Add Crashlytics breadcrumbs/non-fatal mapping and document dSYM handling
  without blocking app launch or local verification.
- Add fakes/tests for endpoint fallback, event catalog, sensitive-value
  exclusion, and Firebase unavailable behavior.

## Scope and affected files

App.kt, AppConfig.kt, PoseServiceLocator.kt, new common/iOS config and
observability bridges/tests, approved Gradle/CocoaPods/resource wiring. Do not
touch PosesScreen.kt or Navigation.kt.

## Success criteria

- api_baseurl is defined once and every resolution outcome leaves both endpoint
  holders equal before first API use.
- Firebase failure/missing configuration enters a truthful operational state
  without blocking app launch.
- Analytics and Crashlytics are sanitized, bounded, and testable without live
  Firebase.

## Risks

- Eager communitySearchRepository and default coordinator construction can
  bypass a nominal App callback; the startup gate must own root composition.
- Duplicate Firebase initialization or wrong dSYM target can silently reduce
  observability.

## Required evidence

Fallback matrix tests, API construction-order proof, sanitized event catalog,
target/build-phase inspection, and no-credential diff.
