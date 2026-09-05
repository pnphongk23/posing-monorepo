---
schema_version: 1
type: feature
id: FEAT-015
title: Manage App Settings and Preferences
status: draft
created: 2026-09-05
relationships:
  specs:
    - "[[product-delivery-roadmap|Product Delivery Roadmap]]"
    - "[[product-feature-inventory]]"
    - "[[technical-architecture|Technical Architecture]]"
    - "[[ui-ux-system|UI/UX System]]"
  decisions: []
  plans: []
  reports: []
  rules: []
  features:
    - "[[FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases|FEAT-011]]"
    - "[[FEAT-012-restore-pose-and-camera-settings-across-relaunch|FEAT-012]]"
    - "[[FEAT-013-saved-poses-albums-account-backed|FEAT-013]]"
    - "[[FEAT-014-manage-account-and-session|FEAT-014]]"
  source_paths:
    - docs/harness/features/FEAT-011-integrate-revenuecat-paid-access-and-in-app-purchases.md
    - docs/harness/features/FEAT-012-restore-pose-and-camera-settings-across-relaunch.md
    - docs/harness/features/FEAT-013-saved-poses-albums-account-backed.md
    - docs/harness/features/FEAT-014-manage-account-and-session.md
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
    - mobile/composeApp/build.gradle.kts
    - mobile/shared/src/commonMain/kotlin/com/aipose/data/DatabaseProvider.kt
    - mobile/shared/src/commonMain/sqldelight/com/aipose/Pose.sq
    - mobile/shared/build.gradle.kts
---

# FEAT-015: Manage App Settings and Preferences

## Introduction

**Purpose:** Give a guest or signed-in user one predictable Settings surface for
app-level controls, privacy and permissions, help/about, and links to existing
Account, Saved, and Premium surfaces without duplicating their behavior.

**In scope:** A grouped Settings surface that is available without an authenticated
session; Account, Saved, and Premium rows route to their owning Features; privacy
rows show camera-access status with an iOS Settings shortcut; legal, support,
feedback, and About destinations use the Product Authority-approved URLs and content;
About is a fixed in-app surface. v1 ships no mutable non-camera preferences
(`PA-015-02`).

**Out of scope:** Camera settings or camera snapshot persistence; Camera remains the
only owner of camera controls under [FEAT-012](FEAT-012-restore-pose-and-camera-settings-across-relaunch.md).
Saved/Unsave/Albums behavior, Account/session/sign-out behavior, Premium purchase or
subscription behavior, account deletion, data export, gallery deletion, analytics
controls, notification preferences, language selection, custom appearance themes,
and Android parity are not redefined here.

**Evidence summary:** **Observed:** FEAT-012 owns eight persisted camera settings;
FEAT-013 owns Saved and keeps Albums future/out-of-scope; FEAT-014 owns Account and
session lifecycle; the mobile app is Compose Multiplatform with Voyager tabs and
nested screens in `App.kt`/`Navigation.kt`; the existing `ExternalActions` seam
supports host-injected Terms/Privacy documents on iOS; `PaywallScreen` consumes a
`PurchaseGateway` and owns Premium outcomes; SQLDelight is the current shared
persistence boundary; and the common test source set uses deterministic Kotlin
tests, fakes, coroutines, MockEngine, and iOS simulator SQLDelight tests. The
prototype lane handed back a visual Settings candidate. **Inferred:** Settings
should be a thin commonMain screen/state owner for app-wide presentation and
cross-feature callbacks, with Account, Saved, Premium, auth, permissions, legal,
support, and persistence behavior supplied through explicit seams. **Failed:** the
bounded mobile navigation search found no production Account or Settings route;
bounded searches found no user-facing auth/session, support, feedback, or About
implementation; there is no Android source set or Android target in the current
Gradle files; and no Settings preference store exists. The visual handoff is not
evidence of a production route, and the Camera settings popover/`CameraController`
permission seam is Camera evidence, not a Settings permission contract. These gaps
cannot be treated as shipped capabilities. **Resolved (Product Authority,
2026-09-05):** six canonical decisions `PA-015-01`…`PA-015-06` are closed; see
the Product Authority decision matrix below. Repository evidence still shows no
production Account or Settings route in `App.kt`/`Navigation.kt`; resolved
authority does not claim those routes exist today.

The separate Settings artifact is an interactive visual handoff. Product Authority
resolved `PA-015-01`…`PA-015-06` on 2026-09-05; per-file SHA-256 and candidate
identity are recorded in the Plan verification ledger. The handoff does not
establish a production route in `App.kt`/`Navigation.kt`. Neither this draft
Feature nor its Plan constitutes formal approval, Cook authorization, or
`READY_FOR_WORK`.

## Business Understanding

### Actors

| Actor | Type | Goal | Responsibility |
| --- | --- | --- | --- |
| Guest or signed-in user | User | Find and understand app controls | Open Settings, inspect status, choose an available action |
| Account/session authority | External system | Preserve the correct authenticated context | Report valid, signed-out, or invalid session state to Account-owned flows |
| Platform permission and legal system | External system | Enforce device permissions and expose approved legal destinations | Return permission state and open platform or legal controls |
| Subscription authority | External system | Report Premium access when the billing Feature is available | Own purchase, restore, and subscription outcomes |
| Product Authority | Business role | Recorded resolved Settings boundary (`PA-015-01`…`PA-015-06`, 2026-09-05) | Feature approval remains a separate gate |

### User needs

- Users need one recognizable place to find app-wide controls without searching
  through Camera, Account, or Gallery surfaces.
- Users need to distinguish app-level Settings from Camera-only controls.
- Users need to understand permission, legal, support, and account destinations before
  taking an action that may leave the app.
- Signed-out users need Settings without seeing stale account identity or protected
  Saved state.

### Preconditions

- The app can render a Settings surface for a guest or a signed-in user.
- An owner destination exists, or the system can show a truthful unavailable/retryable
  state instead of a dead link.
- Resolved legal/support URLs and camera-access row are configured per
  `PA-015-03`, `PA-015-04`, and `PA-015-06`.
- v1 shows no mutable non-camera preferences (`PA-015-02`).

### Navigation and state contract

- **Entry:** Product Authority resolved `PA-015-01` (2026-09-05): push
  `SettingsScreen` from Account via the Voyager `Screen` stack with Back to
  Account. Current `App.kt`/`Navigation.kt` evidence shows no Account or Settings
  route yet; this is the approved target, not an existing production route.
- **Back:** one Back action pops the Settings screen or returns from an external
  destination without changing owner state. Re-entry refreshes session, permission,
  and destination availability; it must not duplicate a list load or stack two
  Settings screens. Async reads that complete after a session-generation change
  must be discarded (stale-result rejection).
- **Session:** the surface is renderable for Guest, SignedIn, Unknown/Loading, and
  Expired/Invalid states. Settings may show only a neutral loading or signed-out
  state until FEAT-014 supplies the authoritative session snapshot; it must not
  cache or synthesize identity.
- **Rows:** every row is either a Settings-owned static surface row or a callback
  to exactly one owner or external destination. v1 has no mutable preference rows
  (`PA-015-02`). A previously configured destination that fails at runtime exposes
  a recoverable error and Back path rather than a dead link.
- **Refresh:** after returning from platform settings, legal/support content, or an
  owner flow, the state layer re-reads the relevant provider. A stale status is not
  reported as a successful change.

### Trigger

The user chooses Settings from Account. Product Authority resolved `PA-015-01`
(2026-09-05): Voyager push from Account with Back to Account. Repository evidence
still shows no Account or Settings route in `App.kt`/`Navigation.kt`; the Account
prototype is visual reference only.

### Main flow

1. **Actor:** The user opens Settings. **System:** The system presents grouped
   Account/access, Privacy/permissions, and Help/about sections for the resolved
   v1 row set (`PA-015-01`…`PA-015-06`); no mutable preference controls.
2. **Actor:** The user selects an Account, Saved, or Premium destination. **System:**
   The system hands off to the owning Feature with its existing session or billing
   gate and does not reproduce that Feature's behavior.
3. **Actor:** The user selects a permission or legal destination. **System:** The
   system shows the current state and opens the approved platform/legal destination;
   returning to Settings refreshes the visible state when possible.
4. **Actor:** The user selects Help, feedback, or About. **System:** The system
   presents the approved content or external destination with a clear return path.
5. **Actor:** The user inspects About or external legal/support rows. **System:** The
  system presents the approved About surface or opens the configured external
  destination with a clear return path. v1 has no mutable non-camera preferences
  (`PA-015-02`); persistence store is deferred.

### Alternative flows

- **A1 — Signed-out account action.** Source step: 2. Condition: the user selects
  an Account or Saved action without a valid session. Behavior: show the existing
  sign-in requirement or signed-out Account state; do not expose stale identity or
  Saved data. Ends with: the user remains in a safe signed-out context.
- **A2 — Permission was denied.** Source step: 3. Condition: the platform reports
  denied or restricted access. Behavior: show the status and offer the platform
  settings path when supported. Ends with: the user can return and re-check status.
- **A3 — Owner destination unavailable.** Source step: 2 or 4. Condition: the
  destination is not configured or not available. Behavior: show a truthful,
  recoverable unavailable state and preserve the Settings route. Ends with: no
  false completion claim.
- **A4 — Deferred preference change (post-v1).** Not in v1 (`PA-015-02`). If a
  future preference is approved, apply device scope without implying account sync.

### Exception flows

- **E1 — Session becomes invalid.** Source step: 2. Failure: Account-owned action
  receives an invalid or expired session. Handling: defer to FEAT-014 recovery or
  clear/gate the protected context. Prohibited: showing another account's identity
  or Saved data.
- **E2 — Platform/legal action cannot open.** Source step: 3 or 4. Failure: no
  configured URL or platform destination is available. Handling: show a retryable
  explanation and retain a usable back path. Prohibited: blank navigation or a claim
  that the action succeeded.
- **E3 — Preference persistence fails.** **Deferred (post-v1).** Not applicable in
  v1 because `PA-015-02` excludes mutable preferences and `SettingsPreferenceStore`.

### Postconditions

- **Success:** The user reaches the selected owner destination or sees the truthful
  current state/content for the selected Settings row.
- **Isolation:** Settings never changes Camera settings, Saved semantics, Account
  session semantics, or Premium purchase state by duplicating them.
- **Failure:** The user can return to Settings; no stale account data or unverified
  success is exposed.

## Requirements

- **FR-001:** Settings shall be reachable from Account via Voyager push with Back to
  Account (`PA-015-01`, resolved 2026-09-05). Repository evidence shows no
  production route yet; implementation adds the approved seam when Cook starts.
- **FR-002:** Settings shall group rows by user intent and shall not display a row
  for an unsupported capability.
- **FR-003:** Account and session actions shall route to FEAT-014; Settings shall
  not redefine identity, sign-out, refresh, expiry, or account isolation behavior.
- **FR-004:** Saved actions shall route to FEAT-013; Settings shall not redefine
  Save, Unsave, Saved list, Try Pose, or Albums behavior.
- **FR-005:** Premium actions shall route to the approved FEAT-011 billing/paywall
  behavior when available; Settings shall not claim purchase, restore, or entitlement
  outcomes on its own.
- **FR-006:** Settings shall show permission/legal status and open only configured
  platform or legal destinations, with a recoverable unavailable state otherwise.
- **FR-007:** Settings shall provide Help, feedback, and About with the approved
  destinations: Support `https://forms.gle/sample-aipose-feedback` (`PA-015-03`);
  Terms `https://aipose.app/terms` and Privacy `https://aipose.app/privacy`
  (`PA-015-04`); About as a fixed in-app surface (product requirement, not a
  seventh authority decision).
- **FR-008:** Camera settings shall not appear in Settings. Facing, flash, grid,
  guide visibility, opacity, line color, overlay position/scale, and zoom remain
  Camera-owned under FEAT-012 and are changed only from the current Camera surface.
- **FR-009:** v1 shall expose no mutable non-camera preferences (`PA-015-02`,
  resolved 2026-09-05). Any future preference requires an approved default, scope,
  and failure behavior before implementation.
- **FR-010:** Settings shall expose meaningful labels and values to assistive
  technology, preserve minimum touch targets, support Dynamic Type and contrast,
  and avoid relying on color or motion alone to communicate state.
- **BR-001:** A Settings row must have one owning Feature or Spec; Settings may route
  to an owner but must not create a second contract for that behavior.
- **BR-002:** A signed-out or invalid-session state must never render stale protected
  identity, Saved data, or account-scoped success.
- **BR-003:** No Settings control may imply account sync, Android parity, notification
  support, language support, custom themes, deletion, export, or analytics controls
  until those capabilities receive their own approved boundary.
- **NFR-001:** Every unavailable, loading, or failed destination shall retain a
  recoverable back path and shall not leave the user at a dead end.

## Acceptance

- [ ] Guest and signed-in users can open Settings from the approved app entry point.
- [ ] Settings renders grouped Account/access, Privacy/permissions, and Help/about
  sections without a blank or dead-end state.
- [ ] Settings contains no Camera settings; changing Camera settings remains
  possible only through the existing Camera surface and FEAT-012 semantics are not
  redefined.
- [ ] Account and Saved rows preserve the owning FEAT-014 and FEAT-013 session/gating
  behavior, including safe signed-out and invalid-session states.
- [ ] Premium navigation preserves the owning FEAT-011 billing/paywall behavior and
  does not report an entitlement locally.
- [ ] Permission/legal rows show truthful status, open the configured destination,
  and recover when the destination is unavailable.
- [ ] Help/About rows use the approved destinations; Support opens
  `https://forms.gle/sample-aipose-feedback`; Terms and Privacy are separate rows
  with external-link behavior.
- [ ] v1 has no mutable non-camera preference rows or persistence store
  (`PA-015-02`).
- [ ] Settings remains usable with assistive technology, larger text, high contrast,
  reduced motion, and keyboard/focus navigation where supported.
- [ ] Product Authority resolved `PA-015-01`…`PA-015-06` on 2026-09-05 (see matrix
  below). This checklist does not constitute formal Feature approval.
- [ ] The implementation has a commonMain state/port contract with deterministic
  fakes; navigation, owner callbacks, session gating, permission/legal/support
  destination outcomes, and recoverable Back behavior are covered by automated
  tests or an explicitly recorded platform/manual gap. **v1 excludes** persistence,
  write/relaunch, and persistence-failure tests (`PA-015-02`); those are deferred
  post-v1 only if a future preference is approved.
- [ ] The handed-back Settings visual design preserves the FEAT-014, FEAT-013, and
  FEAT-011 ownership boundaries and introduces no Camera or preference behavior;
  visual presentation is not treated as a production route or Product Authority
  decision.

**Scenario: guest opens Settings**

Given a guest without a valid Account session
When the guest opens Settings
Then Settings shows app-level, privacy/legal, and help/about actions without stale
identity or protected Saved content, and account actions use the existing sign-in gate.

**Scenario: Camera settings remain Camera-owned**

Given the user opens Settings and the Camera surface
When the user looks for grid, flash, guide, opacity, line color, overlay transform,
or zoom controls
Then those controls are absent from Settings and remain available only in Camera;
no Settings action changes the FEAT-012 camera snapshot.

**Scenario: invalid session from Settings**

Given Account A opens a protected destination from Settings and the session becomes
invalid
When the owner flow reports expiry or 401
Then FEAT-014 recovery or gating runs, Account A data is not shown as valid, and no
other account is substituted.

**Scenario: unavailable external destination**

Given a legal, support, or platform destination is not configured
When the user selects its Settings row
Then the system shows a truthful recoverable state and preserves a working return path.

## Relationships

- FEAT-014 owns Account identity, session, sign-out, expiry recovery, and account
  isolation; FEAT-015 only links to those behaviors.
- FEAT-013 owns Saved/Unsave/Saved list/Try Pose and the future Albums boundary;
  FEAT-015 only links to Saved.
- FEAT-012 owns all camera settings and relaunch persistence; FEAT-015 explicitly
  excludes Camera settings.
- FEAT-011 owns Premium access, billing, restore, and paywall outcomes when approved;
  FEAT-015 only links to that surface.
- UI and accessibility guidance comes from [[ui-ux-system|UI/UX System]] and the
  Axiom UX/HIG audit used during discovery.
- Product sequencing belongs to [[product-delivery-roadmap|Product Delivery Roadmap]];
  this draft does not authorize production implementation. The FEAT-015 Plan is the
  implementation-and-test plan, remains pending the Feature and Repository Maintainer
  approval gates, and consumes the separate visual handoff only as a reference.

### Implementation evidence contract

| Boundary | Current evidence | Required production evidence | Required test evidence |
| --- | --- | --- | --- |
| Compose/navigation | `App.kt` mounts `TabNavigator` with Poses/Gallery/Camera tabs only; `Navigation.kt` owns nested Voyager screens; no Settings/Account route today | Settings `Screen`, one approved entry callback after `PA-015-01`, exactly-once Back/pop, re-entry refresh, and session-generation stale-result rejection | reducer/navigation tests plus supported Compose UI navigation tests when runner verified |
| Account/Saved/Premium | FEAT-013/014/011 define ownership; current commonMain has no Account route; `PaywallScreen` owns billing UI | typed owner callbacks returning `Opened`/`NotConfigured`/`Failed`; no copied identity, Saved, purchase, restore, or entitlement state | guest/signed-in/expired owner-gate tests and Premium handoff tests |
| Permissions/external actions | `CameraController` exposes camera permission/app settings; `ExternalActions` exposes Terms/Privacy with iOS Info.plist lookup | Settings-specific permission reader and host action ports return `Opened`/`NotConfigured`/`Failed`; camera access status plus iOS Settings shortcut (`PA-015-06`); no `SettingsContract.kt` in repository yet (planned) | fake status matrix, unavailable/retry tests, iOS host smoke; Android gap explicit |
| Persistence | SQLDelight/`DatabaseProvider` is the shared persistence boundary; `Pose.sq` is pose-only | v1: no Settings preference store (`PA-015-02`) | **None in v1**; post-v1 tests only if a preference is approved later |
| Accessibility/quality | UI system requires labels, targets, explicit loading/empty/failure; repository has no complete dynamic-type/VoiceOver audit | semantics, target-size, focus/order, larger-text, contrast, reduced-motion, localization, and responsive evidence | automated semantics where supported plus iOS device/manual matrix; no Android claim without a target |

### Product Authority decision matrix

Sole canonical Product Authority record for FEAT-015. Plan and Work Items reference
this matrix and must not restate decision rows.

| ID | Label | Status | Authority | Date | Resolved answer |
| --- | --- | --- | --- | --- | --- |
| `PA-015-01` | Production entry point | Closed | Product Authority | 2026-09-05 | Push `SettingsScreen` from Account via Voyager `Screen` stack; Back returns to Account. Repository evidence: `App.kt`/`Navigation.kt` have no Account/Settings route today. |
| `PA-015-02` | First non-camera preference set and persistence scope | Closed | Product Authority | 2026-09-05 | No mutable preferences or persistence store in v1; omit `SettingsPreferenceStore` and SQLDelight Settings tables. |
| `PA-015-03` | Support destination | Closed | Product Authority | 2026-09-05 | Support & feedback opens `https://forms.gle/sample-aipose-feedback` in an external browser. |
| `PA-015-04` | Legal destinations | Closed | Product Authority | 2026-09-05 | Terms of Service `https://aipose.app/terms`; Privacy Policy `https://aipose.app/privacy`; two separate rows with external-link behavior. |
| `PA-015-05` | Platform-parity commitment | Closed | Product Authority | 2026-09-05 | iOS-first implementation; Android parity deferred until an Android target/actual/test runner exists. |
| `PA-015-06` | Permission-row ownership/scope | Closed | Product Authority | 2026-09-05 | Settings shows camera access status with green Allowed badge and iOS Settings shortcut; Grid, Timer, Flash, and Pose Overlay remain Camera-owned under FEAT-012. |

### Prototype handoff ledger

Three prototype file SHA-256 values are recorded read-only in the Plan prototype
ledger (`plan.md` → Verification ledger → Prototype SHA-256 ledger), reconciled
2026-09-05 in Work Item 3. **Candidate identity:**
`b59cca2a291c8557469970f955e81c5448c73f4476c94f46d9a55ec5d62430b3` (see Plan
ledger). Work Item 1 authority and route/prototype-boundary reconciliation is
complete. This planning lane owns only the five-file Markdown write-set (Feature,
Plan, three Work Items); prototype paths are verification references, not owned
edits. Feature remains `draft`; no formal approval here.
