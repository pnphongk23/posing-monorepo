# Settings (FEAT-015)

Build-17 redesign: the Settings hub is pushed from the Poses header gear, carries no dock, and is
grouped LIBRARY → CAMERA → APPEARANCE → HELP with the account card on top. Cases below marked
`pending (ids …)` describe behaviour that exists only in the boards today; their flows stay in
`docs/qa/redesign-drafts/settings-account/` until Feature commits the ids.

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-SET-001 | P0 | Clean install | 1. Launch. 2. Open Settings. 3. Tap About. 4. Close About | Settings opens (no dock, Back returns to Poses); About sheet opens with its close control; after closing, Settings is back | automated: TC-SET-001-settings-about.yaml |
| TC-SET-002 | P1 | Camera permission denied | Tap Camera access row | iOS Settings opens; status badge reflects state | manual — build 17 boards have no Camera-access row; relocates the case if the row is gone (see assumption A3) |
| TC-SET-003 | P1 | Any | Tap Terms / Privacy | Opens in browser | manual (unit: `SupportDestinationsTests`) |
| TC-SET-004 | P2 | Any | Replay onboarding | Onboarding is shown again and closes back to Settings | manual |
| TC-SET-005 | P0 | accounts flag on, signed in | 1. Poses → More → Settings | Account card on top shows avatar initials, display name and email, with a chevron to Account; sections appear in the order LIBRARY (Saved, Premium), CAMERA (Camera grid, Haptics, Guide line colour), APPEARANCE, HELP (Replay onboarding, About); no count text anywhere | pending (ids: `settings.accountCard`, `settings.saved.row`, `settings.premium.row`, `settings.camera.grid`, `settings.camera.haptics`, `settings.camera.guideColour`, `settings.appearance.system\|light\|dark`, `settings.replayOnboarding`, `settings.about`) |
| TC-SET-006 | P0 | accounts flag on, signed out | Open Settings | The account card is replaced by a sign-in card with copy about keeping Saved poses and Premium across devices, and a Sign in control; Saved row says "Sign in to view"; Premium row says "Not subscribed" — neither promises access to a signed-out user | pending (ids: `settings.signIn.card`, `settings.signIn.button`, `settings.saved.row`, `settings.premium.row`) |
| TC-SET-007 | P0 | App installed, any appearance | 1. Settings → APPEARANCE → Light. 2. Kill and relaunch (keep data). 3. Open Settings | The chosen option stays chosen after the relaunch (the preference is a stored user setting, not a per-session toggle) | pending (ids: `settings.appearance.light` + a readable selected state, e.g. accessibility value `Selected`; scheme mapping is unit-covered by `APShellTests.testChosenAppearanceResolvesTheSchemeItNames`) |
| TC-SET-008 | P1 | Any appearance | Settings → APPEARANCE → System | The app follows the iPhone's light/dark setting instead of pinning one; the caption under the control explains that System follows the iPhone (and must not claim it while Light or Dark is chosen) | unit: `APShellTests.testChosenAppearanceResolvesTheSchemeItNames` (flow blocked on the same selected-state id as TC-SET-007; caption copy is a visual check) |
| TC-SET-009 | P1 | Camera reachable | 1. Settings → CAMERA → turn Camera grid off (default on). 2. Back to Poses → open the camera | The grid overlay is gone in the camera; the setting survives leaving Settings and a relaunch with data kept | pending (ids: `settings.camera.grid`, camera-side `camera.grid` for the cross-screen assertion) |
| TC-SET-010 | P1 | Camera reachable | 1. Settings → CAMERA → Haptics toggle. 2. Open the camera and capture | The toggle persists like the grid setting; capture feedback follows it (haptics cannot be asserted on a simulator, so only the persisted switch and the unaffected capture path are in scope) | pending (ids: `settings.camera.haptics`) |
| TC-SET-011 | P1 | Camera reachable | 1. Settings → CAMERA → Guide line colour (shows the current value). 2. Pick another colour. 3. Open the camera with a pose guide drawn | The chosen colour is applied to the pose guide outline; the row keeps showing the chosen value after leaving Settings | pending (ids: `settings.camera.guideColour`, `settings.camera.guideColour.<value>`, camera-side guide colour state) |
| TC-SET-012 | P1 | Any | Read the Premium row, signed out and signed in | Signed out it reads "Not subscribed"; with a live entitlement it carries an "Active" badge; tapping either opens the Premium/paywall surface and Back returns to Settings with the row unchanged | pending (ids: `settings.premium.row`, `settings.premium.status`; paywall side already has `paywall.close`) |
| TC-SET-013 | P1 | Any | Settings → HELP → About | The About sheet is a sheet (Close or swipe down), not a push; it shows the app icon, name, version line `x.y.z (build)`, and rows for Terms of Use, Privacy Policy, Open-source licences and Contact support; the legal rows open the browser documents and licences opens in-app | pending (ids: `about.version`, `about.terms`, `about.privacy`, `about.licences`, `about.contact`; legal destinations are unit-covered by `SupportDestinationsTests.testLegalAndSupportDestinationsResolveToHTTPSURLs`) |
| TC-SET-014 | P2 | Any | Settings → HELP → Replay onboarding | The onboarding is presented again over Settings and dismissing it returns to Settings with the hub unchanged — no sign-out, no data loss | pending (ids: `settings.replayOnboarding`, `onboarding.close`) |
| TC-SET-015 | P1 | Settings open via Poses → More | Press Back | Back returns to the Poses home with the More menu closed and the dock visible again; Settings was pushed, so it had no dock of its own and no second back control | pending (ids: `settings.back`; the sheet round-trip is already covered by TC-SET-001) |

## Assumptions (boards + feedback only — Feature's gap table was not forwarded)

- **A1 — hub shape.** LIBRARY/CAMERA/APPEARANCE/HELP order and the account card come from
  `10-settings-hub-signed-in/out/dark/ax3`. If Feature ships a different order the row assertions move,
  the cases do not.
- **A2 — the legal group left Settings.** Boards keep no Privacy group in the hub; Terms of Use and
  Privacy Policy appear inside the About sheet. TC-SET-003 therefore tests the About rows, and
  TC-SET-001's old "Privacy is visible" claim is now only valid while the pre-redesign build is the
  installed one.
- **A3 — Camera access row.** No board shows the "Camera access" status row that 1.2 had. TC-SET-002
  assumes it either disappears (camera permission is then only surfaced by the camera's own denied
  state, covered in `camera-guide.md`) or moves into the camera section — needs a Feature answer.
- **A4 — theme caption.** `10-settings-hub-dark` still reads "System follows your iPhone setting."
  while Dark is selected; treated as a copy defect, not a behaviour.
- **A5 — Reduce Motion.** The evidence board requires appearance switches and the About sheet to
  change without animation under Reduce Motion; no simulator assertion exists for motion, so this is
  a visual check only.

## Harness notes (owner of the shared subflows)

- `subflows/launch.yaml` passes no `-AIPosePaywallEnabled`, so a flow that starts there inherits the
  remote `paywall_enabled` value. Yesterday it was OFF and now it is ON: any *future* base-launch flow
  that presses the shutter becomes environment-dependent overnight. Proposal (GL deferred it, not done):
  pass `AIPosePaywallEnabled: "NO"` in `launch.yaml` so base launches are hermetic; paywall cases keep
  their explicit flags through `launch-paywall.yaml` / `pay-launch.yaml`.

## Requests to Feature (build 17 ids — all unconfirmed)

Hub and account card: `settings.accountCard`, `settings.saved.row`, `settings.signIn.card`,
`settings.signIn.button`, `settings.back`, `settings.title`.
Camera section: `settings.camera.grid`, `settings.camera.haptics`, `settings.camera.guideColour`,
`settings.camera.guideColour.<value>`.
Appearance: `settings.appearance.system|light|dark` (exist) plus a **readable selected state** on each
option — either an accessibility value (`Selected` / `Not selected`) or a distinct id suffix — because
Maestro cannot read the `.isSelected` trait that TC-SET-007/008 need.
Help: `settings.replayOnboarding`, `settings.about`, `settings.premium.status`
(`Active` / `Not subscribed` — the row id already exists).
About sheet: `about.version`, `about.terms`, `about.privacy`, `about.licences`, `about.contact`
(`about.close` exists).
Camera side for the cross-screen cases: an id or accessibility value that reports the camera grid /
guide-colour state so TC-SET-009/011 can assert the effect, not just the toggle.
