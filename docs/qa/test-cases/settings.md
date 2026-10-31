# Settings (FEAT-015)

Build-17 redesign (per `/tmp/gap/GAP-AND-OWNERSHIP.md`, page 10): the Settings hub gains a **profile
card** (avatar initials + name + email → Account), **Library grouping**, an **Appearance segmented
control** and an **Active badge** on Premium; it loses the **Privacy group** (legal moves into About)
and never gains a Camera section. Today's screen is PARTIAL: no profile card, no Library grouping,
Appearance is three checkmark rows, no Active badge, no Camera rows, extra Privacy group, and it still
paints the old neo chrome. Cases marked `pending (ids …)` exist only in the boards/gap table; their
flows stay in `docs/qa/redesign-drafts/settings-account/`.

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-SET-001 | P0 | Clean install | 1. Launch. 2. Open Settings. 3. Tap About. 4. Close About | Settings opens (no dock, Back returns to Poses); About opens and closes back to Settings | automated: TC-SET-001-settings-about.yaml |
| TC-SET-002 | P1 | Camera permission denied | Tap Camera access row | iOS Settings opens; status badge reflects state | out of scope 1.1 (17): the Camera-access row is gone from the hub; camera permission is surfaced by the camera's own denied state (`camera-guide.md`) |
| TC-SET-003 | P1 | Any | Tap Terms of Use / Privacy Policy (in About after the redesign) | Each opens the real browser document | manual (destinations unit-covered by `SupportDestinationsTests.testLegalAndSupportDestinationsResolveToHTTPSURLs`) |
| TC-SET-004 | P2 | Any | Settings → HELP → Replay onboarding | Onboarding is presented again and dismissing it returns to Settings with the hub unchanged — no sign-out, no data loss | manual |
| TC-SET-005 | P0 | accounts flag on, signed in | Open Settings from the Poses header (gear) | Profile card on top shows avatar initials, display name and email with a chevron into Account; sections read LIBRARY (Saved, Premium) then APPEARANCE then HELP (Replay onboarding, About); no count text anywhere; Settings is pushed from the header, so it has Back and no dock | pending (ids: `settings.accountCard`, `settings.saved.row`, `settings.premium.row`, `settings.appearance.system`, `settings.appearance.light`, `settings.appearance.dark`, `settings.replayOnboarding`, `settings.about`, `settings.back`) |
| TC-SET-006 | P0 | accounts flag on, signed out | Open Settings | The profile card is replaced by a "Sign in to AI Pose" card (copy about keeping Saved poses and using Premium on every device) with a Sign in control; the Saved row reads "Sign in to view" and Premium reads "Not subscribed" — a signed-out user is never promised access | automated: TC-SET-006-settings-hub-signed-out.yaml |
| TC-SET-007 | P0 | Any appearance | 1. Settings → APPEARANCE → Light. 2. Kill and relaunch keeping data. 3. Open Settings | The chosen option is still chosen: the preference is stored, not per-session. Selecting an option changes the app immediately without leaving Settings | automated: TC-SET-007-appearance-persists.yaml |
| TC-SET-008 | P1 | Any appearance | Settings → APPEARANCE → System | The app follows the iPhone's light/dark setting instead of pinning one; the caption explains that System follows the iPhone and must not claim it while Light or Dark is chosen (board `10-settings-hub-dark` still shows it — copy defect) | automated: TC-SET-008-appearance-caption.yaml |
| TC-SET-009 | P1 | Camera reachable | Settings → CAMERA → Camera grid | — | **out of scope 1.1 (17)** (not built): the gap table keeps camera grid and guide-line colour inside the camera UI and records that haptics does not exist in the app at all, so this hub section is out of scope. Camera-side coverage belongs to `camera-guide.md`, not here |
| TC-SET-010 | P1 | Camera reachable | Settings → CAMERA → Haptics | — | **out of scope 1.1 (17)** (not built): no haptics model exists anywhere in the app (gap table) |
| TC-SET-011 | P1 | Camera reachable | Settings → CAMERA → Guide line colour | — | **out of scope 1.1 (17)** (not built): the guide colour stays a camera-side control (gap table) |
| TC-SET-012 | P1 | Any | Read the Premium row signed out, then signed in with a live entitlement | Signed out it reads "Not subscribed"; entitled it carries an "Active" badge; tapping opens the Premium/paywall surface and Back returns to Settings with the row unchanged | automated: TC-SET-012-premium-status-paywall.yaml |
| TC-SET-013 | P1 | Any | Settings → HELP → About | About is a sheet (Close or swipe down), not a push: it shows an "About" header with X, the app icon, name and version `x.y.z (build)`, and rows for Terms of Use, Privacy Policy and Open-source licences; the legal rows open the browser documents and licences opens in-app. **No "Contact support" row** — the board draws one but it contradicts the no-Support-row product fact | automated: TC-SET-013-about-sheet.yaml |
| TC-SET-014 | P2 | Any | Settings → Replay onboarding (board places it under HELP) | The onboarding is presented again over Settings and dismissing it returns to Settings with the hub unchanged | pending (ids: `settings.replayOnboarding`, `onboarding.close`) |
| TC-SET-015 | P1 | Settings open via Poses header | Press Back | Back returns to the Poses home with the dock visible again; Settings was pushed, so it has no dock of its own and no second back control | pending (ids: `settings.back`) |
| TC-SET-016 | P1 | Settings and About open, light and dark | Compare the cards with the rest of the app | Settings/About use the same direction-B chrome as Poses/Gallery/Saved — one soft elevation, no ink outline, no offset shadow — and in dark mode the card edge still reads against the background (≥3:1). Today both screens still paint neo chrome | manual/visual (tokens unit-covered by `APDesignTokensTests`; a flow cannot judge elevation) |
| TC-SET-017 | P1 | Signed in, account read fails or the device is offline | Open Settings and read the profile card | The F4 treatment applies to the one async element on this screen: instead of vanishing, the card degrades to a neutral, still-tappable row (it does not show a stale name/email as if it were fresh, and it does not break the rest of the hub). The remaining rows stay usable | pending (ids: `settings.accountCard`, `settings.accountCard.state` — a readable state so the assertion is not colour-based) |

## F4 state coverage on this screen

Settings cannot be empty (the board's evidence page says so) and has no loading state of its own: every
row is local. The only asynchronous element is the profile card, so this screen's F4 coverage is
TC-SET-017 (error/offline card) plus the Account screen's own states in `account.md`.

## Not built — do not re-add (gap table)

- **Camera section in the hub** (TC-SET-009/010/011): grid and guide colour stay in the camera UI,
  haptics has no model.
- **Privacy group in the hub**: legal rows move into About; the "Camera access" status row goes away.
- **In-app delete confirmation / delete error** (`10-board10/11`): overridden by the product fact that
  Delete account opens the web request form — see `account.md` TC-ACC-005.

## Re-baseline when build 17 lands (existing green flows)

- **TC-SET-001** — asserts the text `"Privacy"` and `"Replay onboarding guide"`; the Privacy group
  disappears and About becomes a header+X sheet with new rows. New flow: drop the Privacy assert,
  assert `about.version` / `about.terms` / `about.privacy`.
- **TC-SET-002, TC-SET-003, TC-SET-004** (manual rows) — their steps name rows that move: Camera access
  is gone, Terms/Privacy move inside About.
- **Every flow that enters Settings** (`TC-ACC-001/007/008/009/010`, `TC-SAV-001`, and this lane's
  `open-settings.yaml`) — `open-settings.yaml` uses `poses.more → poses.menu.settings`, while the board
  pushes Settings from the Poses header **gear** and F8 also keeps a Settings row in the More menu.
  Whichever ships, one path may stop existing: re-verify the subflow first, then the flows using it.
- **TC-ACC-008** — asserts `"Privacy"` is visible with accounts off; that text leaves the hub.

## Assumptions

- **A1 — hub order** LIBRARY → APPEARANCE → HELP with the profile card on top, per gap table page 10.
- **A2 — Appearance shape.** The gap table says the board is a segmented control and the app has three
  check rows. TC-SET-007/008 assert the *option ids and their state*, so they survive either shape;
  the segmented look is a visual check, not a case.
- **A3 — Camera access row** is not rebuilt; TC-SET-002 stays manual and camera permission is proven
  through the camera's own denied/blocked state.
- **A4 — Reduce Motion.** Boards require appearance switches and the About sheet to change without
  animation; motion is not assertable, so it stays a visual note.
- **A5 — "Contact support"** in the About board contradicts the no-Support-row fact; the case excludes it
  and it is flagged to the lead rather than tested.

## Harness notes (owner of the shared subflows)

- `subflows/launch.yaml` passes no `-AIPosePaywallEnabled`, so a flow starting there inherits the remote
  `paywall_enabled` value (OFF yesterday, ON now). Any future base-launch flow that presses the shutter
  becomes environment-dependent overnight. Proposal, deferred by GL and not implemented: pass
  `AIPosePaywallEnabled: "NO"` in `launch.yaml`; paywall cases keep their explicit flags through
  `launch-paywall.yaml` / `pay-launch.yaml`.

## Requests to Feature (build 17 ids — all unconfirmed)

Hub: `settings.accountCard`, `settings.saved.row`, `settings.signIn.card`, `settings.signIn.button`,
`settings.back`, `settings.premium.status` (`Active` / `Not subscribed`; the row id exists).
Appearance: `settings.appearance.system, settings.appearance.light, settings.appearance.dark` (exist) plus a **readable selected state** on each
option (accessibility value `Selected` / `Not selected`, or a distinct id suffix).
Help/About: `settings.replayOnboarding`, `settings.about`, `about.version`, `about.terms`,
`about.privacy`, `about.licences` (`about.close` exists).
Not needed any more: `settings.camera.*` (section cut) and `about.contact` (contradicts the product fact).
