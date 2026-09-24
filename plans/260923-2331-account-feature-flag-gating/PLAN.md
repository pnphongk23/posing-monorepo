# PLAN — Account feature-flag gating (iOS)

Mission: `ACCOUNT-FLAG-260923` · Workspace `wks_2e69547344ec0a0b` · General Lead: Chu Du
Baseline: `HEAD=d6b5c10` + 56 pre-existing dirty files (unrelated email/password-auth work).
Pre-mutation snapshot of every flag-touched file: `/tmp/account-flag-baseline/` (`BASELINE.sha`).

## Goal

One Remote-Config-driven kill switch hides the account feature and its dependents on iOS:
Account settings, Saved poses, the account sign-in prompt, and the pose-detail save affordance.

## Frozen contract (v1 — implementers must not change names/semantics)

- RC key `account_enabled`; read with `configValue(forKey:).stringValue` (never `.boolValue`).
- `RemoteConfigService.accountEnabledKey: String`
- `RemoteConfigService.parseBoolean(raw: String?) -> Bool?` — `"true"/"1"/"yes"` → true,
  `"false"/"0"/"no"` → false (case-insensitive), anything else/nil → nil.
- `RemoteConfigService.resolveAccountEnabled(cachedRaw: String?, fetchedRaw: String?) -> Bool`
  — fetched wins, then cache, else default `true`.
- `RemoteConfigService.applyAccountEnabled(_ enabled: Bool)` → `AppConfig.shared.applyAccountFeatureEnabled`.
- `AppConfig.isAccountFeatureEnabled: Bool` (lock-protected, default `true`);
  `func applyAccountFeatureEnabled(_ enabled: Bool)`; DEBUG-only `-AIPoseAccountEnabled true|false`
  launch-argument override, compiled out of Release (mirrors `debugBaseURLOverride`).
- `AppDelegate.resolveEndpointThenShowRoot()`: read the key from the already-activated cache before
  first paint, apply it; in the `fetchAndActivate` callback apply the fetched value and rebuild the
  root when the flag value changed (reuse the existing latch/rebuild path).

## Decisions

- **D1 — default `true` (opt-out).** [C1] A missing/unparseable/failed Remote Config read must not
  silently remove account surfaces; hiding is an explicit console action. Preserves current
  behaviour for dev/CI/offline (no Firebase).
- **D2 — explicit string parse.** [C1] `configValue(...).boolValue` returns `false` for a missing
  key, which would make "absent" indistinguishable from "disabled". This is the main correctness trap.
- **D3 — gated surfaces.** [C2] (a) `SettingsScreen` Account group: the **Account row** and the
  **Saved poses row** only — when the flag is off the whole group (and its "Account" header)
  disappears; (b) `PosesScreen.posesHeader` "Open Saved poses" icon; (c) `PoseDetailScreen` "Save
  pose/Saved" button + `toggleBookmark()` early return; (d) `SavedPosesScreen` defensive guard so a
  stale route cannot mount account UI or the sign-in prompt. The header gear (Settings) and crown
  (Premium) stay in both states.
- **D4 — Premium/paywall stays visible and keeps its own purchase sign-in prompt.** [C2] The
  mission enumerates account, Saved poses, SignIn prompt, Account settings; premium/purchase is not
  enumerated. **D4 overrides D3 for the Premium row**: it is never gated. When the flag is off it is
  rendered in its own `settingsGroup(title: "Premium")` so the surviving row never sits under a
  lying "Account" header. Residual risk recorded (tapping Premium can still surface a sign-in prompt).
- **D5 — account session machinery untouched** (`SessionScopeCoordinator`, `AccountSessionModel`,
  `SignIn.swift`): no UI surface, no prompt of its own. [C1]

## Non-goals

Web/Android parity; changing Firebase console values; account deletion/auth logic; premium gating;
a new `docs/harness` DEC entry; commit/push (worktree already carries unrelated changes).

## Acceptance evidence

1. `xcodebuild test -workspace iosApp.xcworkspace -scheme Dev -destination
   'platform=iOS Simulator,id=4C1D6E55-2C31-4BD7-9881-F86F21CC53C8' -only-testing:iosAppTests`
   green, including new `RemoteConfigServiceTests` parse/resolve cases and `AppConfigTests`
   default+apply cases.
2. `scripts/maestro/account-flag-hidden.yaml` with the flag off: no "Open Account", no
   "Open Saved poses" row/icon, no "Save pose" button; Settings shows a "Premium" group and its
   Privacy/Help groups are still present; the poses-header crown and gear are still present.
3. Flag-on control run: same flow assertions inverted (Account + Saved poses rows present, Premium
   inside the "Account" group, no separate "Premium" group).

## Risks

- Dirty worktree: candidate identity is per-file against `/tmp/account-flag-baseline/`.
- SwiftUI reads the flag at view-build time; a mid-session flip depends on the AppDelegate root
  rebuild (documented, accepted).
- Maestro iOS launch-argument support unverified → fallback: `xcrun simctl launch
  --terminate-running-process camerapose.app -AIPoseAccountEnabled false` then a flow without
  `launchApp`.

## Review record

- Candidate v1 frozen by Lead; 9/9 sha256 re-verified against the handback before launch.
- Reviewer `af5fa02c` ([Khổng Minh], `agy/gemini-3.8-flash-high`, read-only, lens correctness/evidence),
  blind first pass on the raw diff + artifacts. **VERDICT: CLEAR.** Cycle 1 of 2 used.
- NIT 1 (AppDelegate DEBUG override keeps `accountFeatureChanged == false`): intentional — the launch
  override wins over Remote Config; compiled out of Release. Accepted, no action.
- NIT 2 (`AccountScreen` has no internal `EmptyView` guard like `SavedPosesScreen`): verified there is
  exactly one construction site (`SupportScreens.swift:335`) and it sits inside the flag condition;
  no deep link or URL route exists. Accepted as recorded; no mutation, so candidate v1 stands.
- Reviewer uncertainty: (a) the `isSuccess == false` fetch path was not exercised over a real
  network failure — `Pending-validation`; (b) a mid-session root swap resets navigation stacks and
  dismisses modals — pre-existing behaviour of the endpoint-swap path, now also reachable from a
  flag change.

## Topology

General Lead (Chu Du) owns the outcome and the plan. Review scoring: S=3, I=3, U=2 → R=8 → one
read-only Reviewer, lens correctness/evidence. I<4 and U<4 → no PREPLAN branch, no Planning Lead.
One Worker executes the coupled config+UI packet; no per-Worker review.
