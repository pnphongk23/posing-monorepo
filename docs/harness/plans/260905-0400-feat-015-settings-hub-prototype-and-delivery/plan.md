---
title: FEAT-015 Settings production implementation and test plan
description: "Implementation-ready production code and test plan for FEAT-015; Product Authority resolved PA-015-01..06 on 2026-09-05; Feature/Plan approval gates remain pending."
status: pending
approval:
  status: pending
  required_by: Repository Maintainer
priority: P2
effort: M
branch: backlog
tags:
  - feat-015
  - settings
  - mobile
  - implementation-plan
  - testing
blockedBy: []
blocks: []
relationships:
  specs:
    - "[[product-delivery-roadmap|Product Delivery Roadmap]]"
    - "[[product-feature-inventory]]"
    - "[[ui-ux-system|UI/UX System]]"
    - "[[technical-architecture|Technical Architecture]]"
  decisions: []
  plans: []
  reports: []
  rules: []
  features:
    - "[[FEAT-015-manage-app-settings-and-preferences|FEAT-015]]"
  source_paths:
    - docs/harness/features/FEAT-015-manage-app-settings-and-preferences.md
    - docs/harness/features/FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases.md
    - docs/harness/features/FEAT-012-restore-pose-and-camera-settings-across-relaunch.md
    - docs/harness/features/FEAT-013-saved-poses-albums-account-backed.md
    - docs/harness/features/FEAT-014-manage-account-and-session.md
    - docs/harness/specs/product-delivery-roadmap.md
    - docs/harness/specs/product-feature-inventory.md
    - docs/harness/specs/ui-ux-system.md
    - docs/harness/specs/technical-architecture.md
    - docs/prototype/screens/settings.html
    - docs/prototype/styles/settings.css
    - docs/prototype/scripts/settings.js
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/App.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/Navigation.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/camera/CameraContract.kt
    - mobile/composeApp/src/iosMain/kotlin/com/aipose/camera/CameraContract.ios.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/platform/ExternalActions.kt
    - mobile/composeApp/src/iosMain/kotlin/com/aipose/platform/ExternalActions.ios.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/purchases/Paywall.kt
    - mobile/composeApp/src/commonMain/kotlin/com/aipose/purchases/PurchaseCore.kt
    - mobile/composeApp/src/commonTest/kotlin/com/aipose/navigation/MainDockTest.kt
    - mobile/composeApp/src/commonTest/kotlin/com/aipose/navigation/ListStateOwnershipContractTest.kt
    - mobile/composeApp/src/commonTest/kotlin/com/aipose/purchases/PaywallTest.kt
    - mobile/composeApp/src/commonTest/kotlin/com/aipose/camera/CameraCoordinatorTest.kt
    - mobile/composeApp/build.gradle.kts
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/DatabaseProvider.kt
    - mobile/shared/src/commonMain/sqldelight/com/aipose/Pose.sq
    - mobile/shared/build.gradle.kts
created: 2026-09-05T04:00:00+07:00
createdBy: Harness CLI
---

# FEAT-015 Settings production implementation and test plan

## Overview

This Plan turns FEAT-015 into an implementation-ready contract for the mobile
code and test lanes. It is not application code and does not authorize Cook or
production changes while FEAT-015 is `draft`, this Plan is `pending`, and
Repository Maintainer approval is still pending. Product Authority resolved
`PA-015-01`…`PA-015-06` on 2026-09-05 (see Feature canonical record). The Plan
owns only its three Work Items, and the FEAT-015 Feature document during this
planning turn. Future implementation Work Items name production touchpoints, but this
lane does not edit mobile source, owner surfaces, prototype files, README files,
or generated artifacts.

The separate Settings visual handoff is a reference for information architecture
and visual intent. It is not a production route, auth contract, permission
contract, persistence decision, or Product Authority approval.

## Authority and decision boundary

- FEAT-015 remains `status: draft`; this Plan remains `status: pending` with
  `approval.status: pending`.
- No Feature/Plan approval, Cook, `READY_FOR_WORK`, or production implementation
  is claimed.
- **Canonical authority record:** [[FEAT-015-manage-app-settings-and-preferences|FEAT-015]]
  Feature → Product Authority decision matrix; this Plan consumes that record and
  does not restate decision rows.

`PA-015-06` excludes Grid, Timer, Flash, and Pose Overlay from Settings; those
remain FEAT-012 Camera-owned. About is a fixed product/prototype requirement, not
an additional Product Authority decision ID.

### Implementation notes (derived from resolved PA-015-01..06, 2026-09-05)

These notes translate closed Product Authority answers into Cook guidance. They are
not open decisions.

| ID | v1 implementation note | Repository constraint |
| --- | --- | --- |
| `PA-015-01` | Push `SettingsScreen` from Account via Voyager; Back to Account | `App.kt`/`Navigation.kt` have no Account/Settings route today |
| `PA-015-02` | Static surface only; no mutable preference rows; omit `SettingsPreferenceStore` and SQLDelight Settings tables | No v1 persistence/write/relaunch tests |
| `PA-015-03` | Support row opens `https://forms.gle/sample-aipose-feedback` externally | Host reports `Opened`/`Failed`; no invented URL |
| `PA-015-04` | Separate Terms (`https://aipose.app/terms`) and Privacy (`https://aipose.app/privacy`) external-link rows | Reuse typed `LegalDocument`/host seam; no raw URL in common UI |
| `PA-015-05` | iOS actual first; label Android deferred until target/runner exists | Do not claim Android compile/runtime evidence |
| `PA-015-06` | Camera access status row plus iOS Settings shortcut via Settings-specific ports | Do not use `CameraController` for capture config; Grid/Timer/Flash/Pose Overlay stay Camera-owned |

About is a fixed product/prototype surface, not an additional Product Authority ID.

## Product behavior and user flows

### Surface contract

Settings is a grouped, scrollable surface available to Guest and SignedIn users.
It owns presentation state for the resolved v1 row set only. It does not own
Account identity/session, Saved collection, Premium billing, Camera settings,
mutable preferences, or external destination content. Every visible row has one
owner and one explicit action seam.

The v1 surface (`PA-015-01`…`PA-015-06`, closed 2026-09-05) comprises:

1. **Account/access:** Account and Saved handoffs; signed-out users see the
   existing FEAT-014 sign-in-required/signed-out behavior rather than stale
   identity or protected Saved data.
2. **Premium:** one handoff to FEAT-011's owner/paywall surface. Settings never
   reads or writes entitlement state as its own authority.
3. **Privacy/permissions:** camera access status (`PA-015-06`) with iOS Settings
   shortcut via Settings-specific ports; capture configuration stays Camera-owned.
4. **Legal/support/about:** Support, separate Terms and Privacy external links, and
   fixed About surface per resolved URLs/content (`PA-015-03`, `PA-015-04`).
5. **Preferences:** none in v1 (`PA-015-02`); static surface aside from
   session/permission/destination refresh semantics.

### Route boundary (current repository)

Bounded `srcwalk discover 'Settings,Account' --as symbol --scope
mobile/composeApp/src/commonMain/kotlin/com/aipose` found no production
`Account` route/symbol and no `Settings` screen/route. `App.kt:59-74` mounts
only `PosesTab`, `GalleryTab`, and `CameraTab` through `TabNavigator`.
`Navigation.kt:173-355` nests Voyager `Screen`s under list roots only; there is
no Settings or Account `Screen` registration today. Camera UI copy such as
"Camera Settings" and "Open Settings" in `CameraScreen.kt` is Camera-owned
permission UI, not a FEAT-015 route.

**Approved target (`PA-015-01`, 2026-09-05):** push `SettingsScreen` as a Voyager
`Screen` from Account with Back to Account. Repository evidence: bounded
`srcwalk discover` found no production Account/Settings route; `App.kt:59-74`
mounts only tab roots; `Navigation.kt:173-355` has no Settings/Account
registration today. Implementation must not claim an existing route.

### Entry and Back flow

1. The Account host pushes Settings via Voyager after Cook starts (`PA-015-01`).
   Repository evidence shows no production route yet.
2. Settings renders a loading/neutral state while session, permission, or
   destination providers are read, then renders only rows supported by the
   returned state.
3. Back pops Settings exactly once. It never signs out, changes a preference, or
   mutates an owner feature. If Settings was opened from an owner screen, that
   screen remains the return destination.
4. Returning from an owner or external destination re-reads the affected
   provider. A changed permission/status is reflected; a failed refresh keeps the
   last truthful value and exposes retry/error state.

### Account, Saved, and Premium flow

- **Account:** invoke the FEAT-014 owner callback. Do not duplicate identity,
  provider, sign-out, expiry, refresh, or account-isolation logic.
- **Saved:** invoke the FEAT-013 owner callback with the current authenticated
  context supplied by FEAT-014. Do not query or cache Saved rows inside Settings.
- **Premium:** invoke the FEAT-011 owner/paywall callback. The existing
  `PurchaseGateway`/`PaywallScreen` remains the authority for offering, purchase,
  restore, and entitlement outcomes.
- **Guest:** Settings remains browseable, but protected owner actions use the
  existing signed-out gate. Settings shows no stale Account identity, Saved data,
  or account-scoped success.
- **Expired/invalid session:** FEAT-014 owns refresh/clear/gating. Settings keeps
  a safe Back path and never substitutes another account or treats a protected
  error as an empty success.

### Privacy, permissions, Help/About, and legal flow

- The state layer consumes a Settings-specific permission/status provider for
  camera access (`PA-015-06`), not the Camera-only `CameraController` port for
  capture configuration. Status values: `Loading`, `Granted`, `Denied`,
  `Restricted/Unavailable`, or `Error`.
- Selecting a permission action invokes a platform action and returns to Settings;
  the row refreshes on re-entry. If the platform action cannot open, show a
  retryable message and preserve Back.
- Terms/Privacy use host-injected actions mapped to `https://aipose.app/terms` and
  `https://aipose.app/privacy` (`PA-015-04`). The existing iOS `Info.plist` seam is
  integration evidence, not a substitute for the resolved URLs in product copy.
- Help opens Support at `https://forms.gle/sample-aipose-feedback` (`PA-015-03`).
  Terms and Privacy are separate external-link rows (`PA-015-04`). About is a
  fixed in-app surface (product requirement). Configured destinations that fail
  return `Failed(retryable)` with Back preserved.

### Preference flow (v1)

v1 has no mutable preferences (`PA-015-02`). Omit `SettingsPreferenceStore`,
`Settings.sq`, and preference write/relaunch failure semantics from v1 acceptance.
**Deferred (post-v1, only if a future preference is approved):** optional
`SettingsPreferenceStore` with SQLDelight table and single-flight write ordering.

## Current architecture evidence

These are repository-grounded facts for the implementation lane, not authority
decisions:

| Area | Observed evidence | Planning consequence |
| --- | --- | --- |
| UI/navigation | `App.kt:32-78` mounts `TabNavigator` with three tabs; `Navigation.kt:219-355` nested Voyager screens | Add Settings `Screen` push from Account (`PA-015-01`); preserve exactly-once pop |
| State style | `GalleryViewModel.kt:13-39` and `PosesScreen.kt:148-183` use plain Kotlin classes with `MutableStateFlow`/`StateFlow`; there is no common ViewModel framework | Prefer a small injected `SettingsController`/state reducer rather than introducing a new lifecycle framework |
| Ownership | FEAT-011/013/014 define Premium, Saved, and Account/session boundaries, but bounded commonMain search found no production Account/Settings/auth route | Depend on typed callbacks/ports; do not create shadow owner state or claim current routes |
| Premium | `Paywall.kt:60-160` consumes `PurchaseGateway`, exposes explicit loading/no-offering/purchase-failure/restore states, and calls host-injected legal actions; `PurchaseCore.kt:65-83` defines the gateway contract | Settings calls the Premium owner; it must not reproduce these states or read entitlement directly |
| Camera permissions | `CameraContract.kt:39-54` and `CameraContract.ios.kt:15-64` expose camera permission and `openAppSettings()`; iOS uses `UIApplicationOpenSettingsURLString` | Keep this port Camera-only. A Settings permission bridge must be separate and authority-scoped |
| External/legal | `ExternalActions.kt:3-9` defines Terms/Privacy and share; iOS reads Info.plist keys in `ExternalActions.ios.kt:9-19` | Extend only through a separately tested Settings host/platform seam; do not invent URLs |
| Persistence | `mobile/shared/build.gradle.kts:13-42` configures SQLDelight and iOS drivers; `DatabaseProvider.kt:3-14` caches one database; `Pose.sq:2-21` is pose-only | Add a versioned Settings table/repository only if a preference is approved; never reuse Camera snapshot tables or Pose ownership fields |
| Tests | `PaywallTest.kt` covers gateway decisions; `MainDockTest.kt` checks stable tags; `ListStateOwnershipContractTest.kt` uses deterministic SQLDelight/MockEngine fixtures; `CameraCoordinatorTest.kt` uses fakes for permission/error state machines | Use the same fake/contract style for Settings; add UI tooling only with an actual supported runner |
| Platform | `composeApp/build.gradle.kts:12-15` and `shared/build.gradle.kts:8-11` declare iOS targets only; the architecture/UI specs call Android parity unresolved | Common code may be prepared, but Android compile/runtime/accessibility evidence is not claimable in this Plan |

## Production code plan

### Proposed common contracts and state

Create a small `com.aipose.settings` package in `commonMain` (planned files;
not present and not edited in this planning lane):

- `SettingsContract.kt`: stable row IDs, `SettingsSessionState` (`Guest`,
  `SignedIn`, `Loading`, `Expired`), `SettingsPermissionState`, destination
  availability, and typed callbacks/ports. Avoid route strings and avoid a
  Settings-owned Account/Premium model. Concrete planned signatures:

```kotlin
// Planned commonMain contract (not present in repository)

enum class SettingsRowId {
    Account,
    Saved,
    Premium,
    CameraAccess,
    TermsOfService,
    PrivacyPolicy,
    Support,
    About,
}

sealed interface SettingsSessionState {
    data object Loading : SettingsSessionState
    data object Guest : SettingsSessionState
    data class SignedIn(val accountSummary: AccountSummaryDisplay) : SettingsSessionState
    data object Expired : SettingsSessionState
}

data class AccountSummaryDisplay(val label: String, val providerLabel: String? = null)

enum class PermissionStatus { Granted, Denied, Restricted }

sealed interface SettingsPermissionState {
    data object Loading : SettingsPermissionState
    data class Ready(val status: PermissionStatus) : SettingsPermissionState
    data class Unavailable(val reason: String) : SettingsPermissionState
    data class Failed(val retryable: Boolean) : SettingsPermissionState
}

sealed interface SettingsDestinationResult {
    data object Opened : SettingsDestinationResult
    data object NotConfigured : SettingsDestinationResult
    data class Failed(val message: String, val retryable: Boolean) : SettingsDestinationResult
}

interface SettingsSessionProvider {
  /** Monotonic generation; increments on sign-in, sign-out, expiry, or account switch. */
    val generation: Long
    suspend fun readSession(): SettingsSessionState
}

interface SettingsOwnerNavigator {
    suspend fun openAccount(): SettingsDestinationResult
    suspend fun openSaved(): SettingsDestinationResult
    suspend fun openPremium(): SettingsDestinationResult
}

interface SettingsPermissionReader {
    suspend fun read(permissionId: String): SettingsPermissionState
}

interface SettingsPlatformActions {
    suspend fun openPlatformSettings(): SettingsDestinationResult
    suspend fun openLegalDocument(document: LegalDocument): SettingsDestinationResult
    suspend fun openSupport(): SettingsDestinationResult
}

// Deferred post-v1 only if a future preference is approved (not in v1 contract):
// interface SettingsPreferenceStore { ... }
```

- `SettingsController.kt`: a plain class exposing `StateFlow<SettingsUiState>`;
  inject session, owner navigation, platform actions, and permission reader only
  in v1. Make actions idempotent. **Session-generation stale-result rejection:**
  capture `sessionGeneration` at the start of each async read; if
  `SettingsSessionProvider.generation` changes before completion, discard the stale
  result. **Re-entry refresh:** on screen resume and after any owner/platform
  return, re-read the affected provider and update row state; Back remains available.
  Do not inject or simulate preference persistence in v1.
- `SettingsScreen.kt`: a Voyager-compatible Compose screen that collects state,
  renders grouped rows, dispatches actions, and exposes `onBack`. Keep the screen
  free of SQLDelight, auth SDK, RevenueCat, and Camera concrete dependencies.

Recommended state shape:

```text
SettingsUiState(
  phase = Loading | Ready | Refreshing | Error,
  session = Guest | SignedIn(accountSummary) | Loading | Expired,
  sections = ordered list of SettingsSection(rows),
  rowStates = Loading | Ready(value/status) | Unavailable(reason) | Failed(retryable),
  message = UiMessage?
)
```

Remove `pendingPreference` from v1 state; add only if a post-v1 preference is approved.

`accountSummary` is an opaque owner-provided display model, not a new auth
contract. For Guest/Expired it is absent. The reducer must preserve a last
truthful status during refresh and clear protected values when the session moves
to Guest/Expired.

### Impact map and ownership interfaces

| File/module | Change when implementation starts | Owner and constraint |
| --- | --- | --- |
| `.../settings/SettingsContract.kt` (new) | Typed row/state/port contracts for resolved v1 matrix | FEAT-015 presentation contract; no v1 `SettingsPreferenceStore` |
| `.../settings/SettingsController.kt` (new) | Implement reducer, refresh, idempotent actions, error mapping | No auth, billing, Camera, or SQLDelight concrete dependency |
| `.../settings/SettingsScreen.kt` (new) | Compose grouped rows, headings, semantics, targets, Back | Use `AiPoseColors`, `Spacing`, `AiPoseTypography`, and existing pressable component conventions |
| `mobile/composeApp/src/commonMain/kotlin/com/aipose/navigation/Navigation.kt` | Add Settings `Screen` push from Account (`PA-015-01`) | Voyager owns stack/back; no duplicate owner screens |
| `mobile/composeApp/src/commonMain/kotlin/com/aipose/App.kt` | Inject resolved entry/ports at app root | Preserve `previousNonCameraTab` and current tab behavior |
| `mobile/composeApp/src/commonMain/kotlin/com/aipose/platform/ExternalActions.kt` | Settings platform actions for legal/support/camera-access shortcut | Keep existing `LegalDocument` behavior compatible |
| `mobile/composeApp/src/iosMain/kotlin/com/aipose/platform/ExternalActions.ios.kt` | iOS actuals for resolved URLs and platform settings | Test open failure/retry paths |
| FEAT-014 owner integration | Session snapshot and Account callback | Integration waits for FEAT-014 runtime contract |
| FEAT-013 owner integration | Saved callback with valid session context | Settings never reads Saved tables |
| FEAT-011 owner integration | Premium/paywall callback | Settings never claims entitlement |
| `mobile/shared/.../Settings.sq` (deferred) | **Not in v1** (`PA-015-02`) | Add only after a future approved preference |
| `mobile/composeApp/src/commonTest/.../settings/*Test.kt` (new) | Add reducer/contract/fake tests | Deterministic fakes; no native services or wall clock |

### Integration points

- **Auth/session:** inject a read-only `SettingsSessionProvider` from FEAT-014.
  Settings can clear its protected presentation on `Expired`, but it cannot
  refresh tokens, sign out, or choose a replacement account.
- **Persistence:** **v1 omitted** (`PA-015-02`). Do not inject `SettingsPreferenceStore`
  or add Settings SQLDelight tables in v1 Cook. Deferred design note: versioned
  table in `shared` only after a future approved preference.
- **Permissions:** inject `SettingsPermissionReader` and `SettingsPlatformActions` for
  camera access status and iOS Settings shortcut (`PA-015-06`). Do not call
  `CameraController` from Settings for capture configuration.
- **Legal/support:** inject typed actions including `openSupport()`, Terms, Privacy,
  and platform settings (`PA-015-03`, `PA-015-04`, `PA-015-06`). Host reports
  `Opened`, `NotConfigured`, or `Failed(retryable)`.
- **Owners:** callbacks should be recorded by fakes and return a result that lets
  Settings decide whether to keep, refresh, or show an unavailable message. No
  owner behavior is copied into Settings.

### Loading, empty, and failure behavior

| Condition | UI behavior | Test evidence |
| --- | --- | --- |
| Initial provider read | Loading indicator/semantics, no false row values, Back remains available | state transition from `Loading` to `Ready`/`Failed` |
| No approved rows | Explicit empty/informational state with Back; no placeholder controls | empty-state reducer/UI test |
| Guest/Expired | Signed-out context; protected rows gate through owner; no stale identity/Saved | session transition and leakage tests |
| Permission denied/restricted | Truthful status, approved settings action if supported, retry/Back | fake permission matrix and platform result tests |
| Destination missing | Omit unapproved row, or `Unavailable` for a previously configured capability | configuration matrix test |
| Destination open fails | Retryable message, preserve Settings stack and Back | action failure test |
| Owner returns invalid session | Delegate FEAT-014 recovery/gating; clear protected Settings state | auth integration fake test |

Preference write/corruption rows are **deferred** (`PA-015-02`); not v1 acceptance gates.

## Ordered implementation, rollout, and risk

1. **Contract freeze (complete for authority):** row matrix, entry, session snapshot,
   permission scope, and resolved legal/support URLs are frozen from
   `PA-015-01`…`PA-015-06` (2026-09-05).
2. **Common state layer:** contracts, reducer/controller, deterministic fakes, and
   unit tests for session, row, permission, and destination transitions only (no
   preference store tests in v1).
3. **Compose surface:** `SettingsScreen`, semantics/test tags, loading/empty/failure
   states, exactly-once Back, and Voyager push from Account (`PA-015-01`); update
   `App.kt`/`Navigation.kt` at that seam.
4. **Owner/platform integration:** FEAT-014/013/011 callbacks plus resolved
   legal/support/permission iOS actuals (`PA-015-03`…`PA-015-06`). Android remains
   deferred (`PA-015-05`).
5. **Verification and rollout:** common unit tests, supported Compose UI tests when
   runner exists, iOS simulator/manual checks, requirement matrix. Monitor navigation,
   external-action, and session-leakage signals. No v1 preference persistence rollout.

Primary risks are unowned Account/auth runtime, accidental account-state leakage,
external-action failures, and claiming Android parity without a target. Permission
scope is resolved (`PA-015-06`) but must stay separate from Camera capture config.
Legal/support URLs are resolved (`PA-015-03`, `PA-015-04`) and must use typed host
actions, not hard-coded common UI strings.

## Work Items

- [Work Item 1: Freeze FEAT-015 behavior contracts and owner seams](./work-item-01-reconcile-feat-015-authority-and-prototype-boundary.md) — **`status: completed`** (authority reconciliation and route/prototype-boundary evidence; not formal approval, Cook, or `READY_FOR_WORK`)
- [Work Item 2: Implement Settings common state, UI, and navigation seam](./work-item-02-verify-settings-prototype-handoff-and-traceability.md) — `status: pending`
- [Work Item 3: Integrate platform/persistence contracts and quality-test matrix](./work-item-03-validate-plan-and-prepare-review-handback.md) — `status: pending` (prototype-hash ledger reconciliation **complete**; production integration remains future Cook)

The Work Items describe future production implementation and tests; none assigns
prototype creation, editing, building, or ownership to this Plan.

## Requirement-to-code/test coverage

| Requirement | Production evidence | Test evidence and acceptance |
| --- | --- | --- |
| FR-001 entry for Guest/SignedIn | `SettingsScreen`, Account push in `Navigation.kt`/`App.kt` (`PA-015-01`), `SettingsSessionState` | navigation push/pop test; Guest/SignedIn/Loading/Expired matrix |
| FR-002 grouped rows/no unsupported capability | section/row model matching resolved v1 matrix | state snapshot tests; UI semantics/headings test |
| FR-003 Account/session ownership | FEAT-014 session/Account callback adapter | owner callback invocation, signed-out gate, expired/401 recovery, stale identity clearance |
| FR-004 Saved ownership | FEAT-013 Saved callback with session context | callback receives current valid context; Guest cannot expose Saved; Settings performs no Saved DB query |
| FR-005 Premium ownership | FEAT-011 callback to `PaywallScreen`/gateway owner | handoff test; no local entitlement assertion; existing `PaywallTest` remains green |
| FR-006 permission/legal status | `SettingsPermissionReader`, typed platform action, `ExternalActions` actual | status matrix, not-configured/open-failure/retry, return-refresh, legal URL validation; iOS host smoke |
| FR-007 Help/feedback/About | typed content/action ports for Support, Terms, Privacy, About (`PA-015-03`, `PA-015-04`) | configured URL/open-failure/retry tests; About in-app surface test |
| FR-008 Camera exclusion | no Camera concrete dependency in `settings` package | static dependency review; camera config rows absent |
| FR-009 approved preferences | **v1: none** (`PA-015-02`) | negative test: no preference control or store in v1; deferred store tests post-v1 only |
| FR-010 accessibility | semantics, content descriptions, role, focus order, target sizes, Dynamic Type-safe layout | automated semantics where supported; 44dp minimum-target audit; larger text/contrast/reduced-motion/keyboard checks |
| BR-001 single owner | typed owner/action matrix and no duplicated feature state | architecture review plus fake callback ownership assertions |
| BR-002 no stale protected state | session transition clears or gates protected row data | Account A → Guest/Account B fixture, expiry, sign-out, and process-reentry tests |
| BR-003 no invented capabilities | resolved v1 row catalog (`PA-015-01`…`PA-015-06`) | negative row tests for Camera config, notifications, language, themes, export, deletion, analytics, preference controls |
| NFR-001 recoverable failure | state model preserves Back and retry on all unavailable/error branches | reducer/UI failure matrix and deterministic repeated-action tests |

## Test-quality plan

### Deterministic unit and state tests

Add common tests around a pure reducer/controller and injected fakes:

- `FakeSettingsSessionProvider`: Guest, SignedIn(Account A), Expired, and delayed
  or failed reads; assert protected values clear on context change.
- `FakeSettingsOwnerNavigator`: records Account/Saved/Premium calls and returns
  opened/unavailable/invalid-session outcomes; assert exactly one call per action.
- `FakeSettingsPermissionReader` and `FakeSettingsPlatformActions`: camera access,
  `openSupport()`, legal document open, denied/restricted, open failure, retry,
  return-refresh (`PA-015-03`…`PA-015-06`); never use Camera's concrete controller
  for capture config.
- Reducer properties: Back always available; no false success; rows deterministic
  for resolved v1 matrix; Guest/Expired cannot expose account-scoped values.

**v1 excludes** `FakeSettingsPreferenceStore` and preference write/relaunch tests
(`PA-015-02`).

### Navigation and UI tests

**UI-test acceptance boundary:** common unit/state tests with deterministic fakes
are required in `commonTest` for every reducer branch listed above. Compose UI
navigation/semantics tests are an acceptance gate only after a supported Compose
UI test runner/dependency is verified for the declared target; until then label
the gap `Unresolved`, record the missing runner explicitly, and rely on the manual
iOS VoiceOver/keyboard matrix for navigation/accessibility evidence. Do not report
UI automation as passing without that runner.

When the runner exists, assert:

- Settings entry once, one Back/pop, owner callback routing, scrollable grouped
  sections, loading/empty/error semantics, retry, and return-refresh.
- Stable test tags/content descriptions for Settings root, Back, section
  headings, Account/Saved/Premium rows, camera-access/legal/support/About rows.
  No v1 preference control tags.
- Test narrow/large widths, landscape where supported, larger text/Dynamic Type,
  focus order, keyboard activation where supported, minimum 44 dp touch targets,
  color-independent state, and reduced-motion behavior. A manual iOS VoiceOver /
  keyboard matrix is required while automated accessibility tooling is absent.

### Integration and platform tests

- **No v1 Settings SQLDelight/persistence tests** (`PA-015-02`).
- Test that Settings never reads Camera snapshot state; FEAT-012 tests unchanged.
- Exercise owner adapters with FEAT-014/013/011 test doubles; include invalid
  session, sign-out, Premium no-offering/purchase-cancelled, and owner unavailable
  branches. Do not require production auth or RevenueCat network calls in unit
  tests.
- iOS host tests/manual smoke cover resolved legal/support URLs, platform settings
  return, and lifecycle re-entry. Android evidence remains deferred (`PA-015-05`).

### Localization, responsive, and failure matrix

- Keep all user-facing strings centralized in the approved localization mechanism;
  current repository evidence does not establish a localization module, so record
  the integration choice before adding translated copy. Test long labels, missing
  translation fallback, plural/formatting if applicable, and RTL only if the
  selected platform contract supports them.
- Use deterministic fixtures for Account A/B, Guest, permission statuses,
  destination configuration, and Premium snapshots. No preference-value fixtures in v1.
- Quality gates before implementation handback: common unit tests; supported UI
  tests; iOS simulator integration tests; compile for each declared target;
  accessibility/large-text/focus evidence; requirement matrix with no missing
  rows; and a changed-file check proving this Plan lane edited only the
  five-file Markdown write-set (Feature, Plan, three Work Items) and did not
  edit prototype, owner, README, mobile, or generated files during planning.
  Known repository graph/index failures remain external evidence and are not
  silently repaired.

## Triệu Vân review findings resolution

| # | Finding | Resolution across owned docs | Testable check |
| --- | --- | --- | --- |
| 1 | Six Product Authority decisions need one canonical ID/label set | Sole six-row matrix in Feature; Plan/WIs reference Feature only | Feature matrix has six Closed IDs; Plan/WIs have no duplicated decision rows |
| 2 | Resolved authority must replace pre-resolution recommendation wording | Implementation notes table derived from closed answers | No "must decide", "conditional only", or "not approved yet" for PA-015-01..06 |
| 3 | Plan must state prototype hashes without stale doc self-hash drift | Verification ledger lists three prototype `sha256sum` values only | Re-run `sha256sum` on prototype paths (**reconciled 2026-09-05, WI-03**) |
| 4 | Route boundary states no current route; push is approved target | `Route boundary` cites `App.kt`/`Navigation.kt` and `PA-015-01` | `srcwalk discover` absence + navigation citations |
| 5 | `SettingsContract.kt` needs concrete types | Planned contract block; `SettingsPreferenceStore` deferred post-v1 | Contract compile review in WI-01 (**WI-01 completed**) |
| 6 | `Opened`/`NotConfigured`/`Failed` explicit | `SettingsDestinationResult` in contract | Fake platform/owner matrix |
| 7 | Re-entry refresh and session-generation stale-result rejection | `SettingsController` rules | Fake delayed session read test |
| 8 | v1 excludes persistence; UI-test runner gap explicit | No v1 preference store/tests; Compose UI gap labeled deferred | No preference write/relaunch v1 gate |

## Verification ledger

| Claim | Status | Evidence or next verification | Caveat |
| --- | --- | --- | --- |
| Feature is draft and Plan is pending | Verified from latest workflow state | `ckh workflow status FEAT-015` and prior Plan status result | No approval/readiness claim |
| Current navigation uses Voyager tabs/nested Screens | Verified | `App.kt:32-78`, `Navigation.kt:153-355` | Structural evidence, not runtime proof |
| Current state/test conventions support StateFlow and deterministic fakes | Verified | `GalleryViewModel.kt:13-39`, `PaywallTest.kt`, `CameraCoordinatorTest.kt:21-164` | No Settings implementation exists yet |
| Production Account/Settings/auth route exists | Failed / Unresolved | Bounded `srcwalk discover` found no commonMain Account/Settings/auth route | Absence is not authority to invent one |
| Android target/parity exists | Failed / Unresolved | `composeApp/build.gradle.kts:12-15`, `shared/build.gradle.kts:8-11`; architecture/UI specs mark Android unresolved | Do not claim Android evidence |
| SQLDelight is the current shared persistence boundary | Verified | `shared/build.gradle.kts:13-42`, `DatabaseProvider.kt`, `Pose.sq` | No Settings table in v1 (`PA-015-02`) |
| Product Authority scope | Closed 2026-09-05 | Sole decision matrix in Feature; Plan references Feature and implementation notes only | Feature/Plan approval still pending |
| Work Item 1 execution | Completed 2026-09-05 | Authority reconciliation, route boundary, prototype-boundary contract freeze in owned docs | Not formal approval, Cook, or `READY_FOR_WORK` |
| Work Item 3 hash ledger reconciliation | Completed 2026-09-05 | Prototype ledger reconciled to verified `sha256sum`; candidate identity recorded | WI-03 remains `pending` for future Cook integration |
| Prototype link | Verified | [Settings prototype](../../../prototype/screens/settings.html) | Visual reference only |
| Prototype file SHA-256 (read-only ledger) | Reconciled 2026-09-05 (WI-03) | Three hashes below match verified current `sha256sum`; prototype paths not edited | Recompute after prototype edits only |
| Prototype candidate identity | Verified | SHA-256 of ordered ledger hashes (html, css, js): `b59cca2a291c8557469970f955e81c5448c73f4476c94f46d9a55ec5d62430b3` | Derived from read-only prototype ledger |
| Five-file Markdown write-set | Verified scoped | Only five owned Markdown paths modified in this lane: Feature FEAT-015, `plan.md`, and Work Items 1–3 | Unrelated dirty work preserved |

### Prototype SHA-256 ledger (in-repo)

Recompute with `sha256sum` on the three prototype paths after any prototype edit.
This planning lane records prototype hashes read-only; doc hashes are not
embedded in owned Markdown to avoid self-hash drift. Prototype-hash ledger
reconciliation completed in Work Item 3 (2026-09-05); prototype bytes were not
edited.

| File | SHA-256 |
| --- | --- |
| `docs/prototype/screens/settings.html` | `53b5425ff011d7bf3bd6fd561fb429d53265bdc0939835a73fb9170f63a72aa1` |
| `docs/prototype/styles/settings.css` | `dc64735f40cd9ebf24e30230ff3a83b295a9f4780e424164b1b31147889ca9e2` |
| `docs/prototype/scripts/settings.js` | `45e336657aa3638b1dddf083b4f06d4f4e54098441243d72aa0850427db5243c` |

**Prototype candidate identity:** `b59cca2a291c8557469970f955e81c5448c73f4476c94f46d9a55ec5d62430b3`
(SHA-256 of the three ledger hashes above, one per line, html → css → js order.)

## Risks and integration blockers

- Account/session runtime is proposed by FEAT-014 but not implemented in current
  mobile source; Settings must consume an owner adapter, not invent auth behavior.
- Saved and Premium owner surfaces are not production routes yet; end-to-end
  acceptance waits on owning Features' runtime contracts.
- Android parity and Compose UI automation remain deferred quality gates
  (`PA-015-05`); label gaps explicitly, do not claim evidence.
- Post-v1 preference persistence remains out of scope until a future preference is
  approved; v1 must not add `SettingsPreferenceStore` or SQLDelight Settings tables
  (`PA-015-02`).

## Minimal visual handoff

Interactive Settings prototype paths are read-only verification references for
this planning lane. Visual traceability: prototype link, reconciled three-file
SHA-256 ledger, and candidate identity above. Owned edits are limited to the
five-file Markdown write-set (Feature, Plan, Work Items 1–3). Feature remains
`draft`; Plan/WIs remain `pending`; no Cook, approval, or `READY_FOR_WORK` claim.
