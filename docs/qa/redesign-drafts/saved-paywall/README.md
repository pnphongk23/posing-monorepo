# Redesign drafts — Saved + Paywall (build 18)

Cases live in [saved-bookmarks.md](../../test-cases/saved-bookmarks.md) and
[paywall-purchase.md](../../test-cases/paywall-purchase.md). These flows are **drafts**: they stay outside
`mobile/iosApp/maestro/flows/` because `check-traceability.sh` requires every file there to be git-tracked
*and* marked `automated: <file>` in the case doc, and a flow only earns that after it passes on a named
build. Nothing here has run yet — the QA lead has not named a build for the redesign.

## Coverage this round

| Screen | Cases | Automated (already in `maestro/flows`) | Draft flows here | Unit / XCTest | Pending (ids or data) |
|---|---|---|---|---|---|
| Saved | 15 | 1 (TC-SAV-001) | 9 (002, 003, 004, 006, 009, 010, 012, 013, 014) | 2 (TC-SAV-008 skeleton, TC-SAV-015 undo failure) | 3 (005, 007, 011) |
| Paywall / purchase | 21 | 8 (001–006, 008, 009) | 5 (007, 012, 013, 015, 017) | 2 (TC-PAY-010 loading, 011 processing) | 6 (014 restore ids, 016 sign-in resume, 018 offering, 019 3.1.2 disclosure ids, 020 shutter-only claim, 021 identity line ids) |

MUST-COVER items for build 18 land in these rows: **Saved Undo** (TC-SAV-010), **Saved offline cached
mode** (TC-SAV-006), **Paywall 3.1.2 disclosures** (TC-PAY-019), **shutter-only claim** (TC-PAY-020),
and the F4 state component on both screens (TC-SAV-008/009/006 + TC-PAY-007/010/012).

## Re-baselining (cases written against the pre-redesign screen)

The gap table (`/tmp/gap/05-06.md` §06, `/tmp/gap/09-11.md` §11) makes several of these cases *different*
behaviour, not just different pixels. They were updated in the commit that promotes them that
promotes their flow, and their existing assertions re-checked:

| Case | What changes |
|---|---|
| TC-SAV-001, TC-SAV-004 | copy: gate text, empty-state action "Browse poses" (was "Browse Community") |
| TC-SAV-006, TC-SAV-010 | new behaviour: offline cached mode + per-row "Not saved offline"; unsave Undo (both MISSING today) |
| TC-SAV-009, TC-SAV-013 | error copy; AX3 unsave tile sizing |
| TC-PAY-001, TC-PAY-008 | presentation becomes a full-screen cover |
| TC-PAY-003, TC-PAY-009, TC-PAY-016 | signed-out paywall keeps the plans and offers one "Sign in to subscribe"; the options move into a sheet with the system Apple button |
| TC-PAY-004, TC-PAY-006, TC-PAY-018 | CTA is "Subscribe" (not "Continue with <plan>"); plan labels Yearly/Monthly + store saving badge |
| TC-PAY-007, TC-PAY-010 | offline/skeleton offer shape: "Price unavailable offline" rows, skeleton cards, disabled subscribe + helper copy |
| TC-PAY-012, TC-PAY-013, TC-PAY-014 | outcome is an error **card** with Try again; restore gains an inline retry and a failure state |
| TC-PAY-015, TC-PAY-017, TC-PAY-020 | legal labels "Terms of Use"/"Privacy Policy"; AX3-scrolled disclosure + dock inset; shutter-only benefit list |

Also re-baselined on the flow side (owned here): `mobile/iosApp/maestro/subflows/pay-buy-monthly.yaml`
asserts the label **"Continue with Monthly"**, which the redesign replaces with "Subscribe" — that
assertion must change with the CTA copy, or TC-PAY-004/005/006 break for a copy reason.

No Saved or Paywall case is out of scope for 1.1 (the out-of-scope list — publish flow, Gallery Star,
in-app delete confirm, Forgot password, camera Timer/Ratio/Scale/mirror — touches no case in these two
docs; password reset is named in the paywall doc only to keep it away from this surface).

Every case in those two docs is either `automated:`, a `draft:` file here, a unit test, or an explicit
pending row with the reason — no case is silently unowned.

## What the drafts assume

- **Shared subflows are used, never edited** (`launch*.yaml`, `open-settings.yaml`, `open-camera.yaml`,
  `open-first-pose.yaml`, `pay-launch.yaml`, `pay-sign-in.yaml`, `pay-buy-monthly.yaml`) — owned by worker
  26ab1fba. Paths are relative: `../../../../../mobile/iosApp/maestro/subflows/…`.
- **Ids**: only ids present in committed source are asserted (`saved.signIn`, `saved.browseCommunity`,
  `saved.back`, `saved.retry`, `saved.loading`, `poses.header.saved`, `poseDetail.saveButton`,
  `poseDetail.use`, `paywall.close`, `paywall.status`, `paywall.cta`, `paywall.plan.annual|monthly`,
  `paywall.signin.apple|google`, `signin.emailEntry`). Two drafts deliberately assert a **code-owned
  accessibility label** with a `TODO(<id>)` comment where the id is missing (`saved.retry.button`,
  `paywall.retry`, `paywall.unavailable`, `paywall.terms`, `paywall.privacy`, `paywall.restore`).
- **Purchases**: Test Store only, on the Debug-Dev build (`test_…` key), so `TC-PAY-012/013` tap the SDK's
  own "Test failed purchase" / "Cancel" — no money, no sandbox Apple ID. TC-PAY-017 runs on the Prod-config
  build and stops at the plan cards; on that build `paywall.cta` is never tapped.
- **Credentials** come from the gitignored `mobile/iosApp/maestro/e2e.local.env` via `-e` and every
  credential-backed draft carries the `e2e` tag. The demo account is never used.

## Run on 1.1 (18) — first run against the redesign

Build `/tmp/ai-pose-lane2-app-1.1/dev18/posing.app` (`1.1`/`18`, Debug-Dev @ `da7c019`), lane-2 `CF871F97`.
13 drafts promoted (commit `e12d6ec`); the full default suite ran once at the end: **65 flows, 48 PASS,
17 FAIL** — 8 of those are the camera reds owned by the camera seat (`camera-18-02`), 9 are mine.

| Flow | Result | Reason / evidence |
|---|---|---|
| TC-SAV-001 saved-signed-out | **PASS** | `screens/run-1.1-18/TC-SAV-001-saved-signed-out.png` |
| TC-SAV-002 saved-list-loaded | **PASS** | `…/TC-SAV-002-saved-list-loaded.png` |
| TC-SAV-012 back-to-settings | **PASS** | flow fixed first (it asserted the Poses menu instead of `settings.back`) — `…/TC-SAV-012-back-to-settings.png` |
| TC-SAV-013 ax3-dark | **PASS** | dark + `accessibility-extra-large` — `…/TC-SAV-013-ax3-dark.png` |
| TC-SAV-003 unsave-removes | **FAIL — app bug** | `BUG-SAVED-18-01`: the unsave tile does nothing, so the list never empties |
| TC-SAV-004 empty-browse | **FAIL — app bug** | same bug: its setup empties the list by unsaving, which cannot happen |
| TC-SAV-010 unsave-undo | **FAIL — app bug** | same bug: no snackbar, no Undo |
| TC-PAY-001 capture-gated | **PASS** | `…/TC-PAY-001-capture-gated.png` |
| TC-PAY-002 capture-ungated | **PASS** | `…/TC-PAY-002-capture-ungated.png` |
| TC-PAY-004 purchase-annual-entitles | **PASS** | Test Store buy, "Premium access confirmed", shutter ungated — `…/TC-PAY-004-purchase-annual-entitles.png` |
| TC-PAY-006 second-account-no-carryover | **PASS** | `…/TC-PAY-006-second-account-no-carryover.png` |
| TC-PAY-008 close-paywall | **PASS** | `…/TC-PAY-008-close-paywall.png` |
| TC-PAY-013 purchase-cancelled | **PASS** | cancelled banner shown, no access granted — `…/TC-PAY-013-purchase-cancelled.png` |
| TC-PAY-015 legal-links | **PASS** | Terms + Privacy open the real documents — `…/TC-PAY-015-legal-links.png` |
| TC-PAY-003 paywall-signin-prompt | **FAIL — app bug** | `BUG-PAY-18-01`: the signed-out CTA is enabled but opens no sheet |
| TC-PAY-005 signout-regates-capture | **FAIL — app bug** | same bug: after sign-out the sign-in sheet never appears |
| TC-PAY-009 signin-apple-first | **FAIL — app bug** | same bug: the options live in the sheet that never opens |
| TC-PAY-012 purchase-failed | **FAIL — app bug** | `BUG-PAY-18-02`: a failed Test Store purchase shows no banner at all |
| TC-PAY-017 ax3-dark | **FAIL — flow defect** | at AX3 the email-sheet text entry did not land; the app correctly validated it ("Enter your password") and the flow stopped there. Same case passes at light/large. |

The screenshots above are the durable evidence: the run's `/tmp` artefacts (per-flow shot dump, suite log,
probe flows) and the raw Maestro debug dirs were lost when the machine rebooted and `/tmp` was wiped. Nothing
needed to reproduce a result lived only there — the failing ids and reasons are quoted in this table and in
the two bug notes.

Deliberately demoted back to drafts after running (no producer on this build, so they cannot be green
instead of wrong): **TC-SAV-006** and **TC-SAV-014** (the `-AIPoseSavedOfflineFixture` seam did not render
the offline board — the fixture applies only once the list is already `.loaded`), **TC-SAV-009** (a dead
`-AIPoseAPIBaseURL` relaunch no longer forces the error state: the saved collection is served from the local
store). Reasons recorded in each file header.

**Fixed and waiting for dev19:** `BUG-SAVED-18-01` is fixed in `0cb55d1` (the unsave tile is a sibling of the
open-pose link). `TC-SAV-010`, `TC-SAV-003`, `TC-SAV-004` and `TC-SAV-014` are held until that build is
installed — and note the side effect of the fix: `poses.first-card` / `poses.card.<id>` now mark the link
(thumbnail + copy), not the whole row, so the unsave tile is pressed by `"Remove from saved"`, never by a row
coordinate.

**Order dependency learned:** TC-PAY-012/013/017 need an *unentitled* account, and account A becomes
entitled as soon as TC-PAY-004 buys. They now sign in as account B (the TC-PAY-006 injection) instead of
depending on where they sit in the suite.

## Run on 1.1 (17) — Saved/Paywall regression, all green

Build: `/tmp/ai-pose-lane2-app-1.1/dev17/posing.app` (Debug-Dev, `1.1` build `17`), built from `a03d03a`;
lane-2 `CF871F97`, install-only, `run.sh` per flow. 9/9 PASS, screenshots in
`screens/run-1.1-17/` (one per flow, final screen):

| Flow | Result | Screenshot |
|---|---|---|
| TC-SAV-001 saved-signed-out | PASS | `screens/run-1.1-17/TC-SAV-001-saved-signed-out.png` |
| TC-PAY-001 capture-gated | PASS | `…/TC-PAY-001-capture-gated.png` |
| TC-PAY-002 capture-ungated | PASS | `…/TC-PAY-002-capture-ungated.png` |
| TC-PAY-003 paywall-signin-prompt | PASS | `…/TC-PAY-003-paywall-signin-prompt.png` |
| TC-PAY-004 purchase-annual-entitles (Test Store) | PASS | `…/TC-PAY-004-purchase-annual-entitles.png` |
| TC-PAY-005 signout-regates-capture | PASS | `…/TC-PAY-005-signout-regates-capture.png` |
| TC-PAY-006 second-account-no-carryover | PASS (2nd attempt) | `…/TC-PAY-006-second-account-no-carryover.png` |
| TC-PAY-008 close-paywall | PASS | `…/TC-PAY-008-close-paywall.png` |
| TC-PAY-009 signin-apple-first | PASS | `…/TC-PAY-009-signin-apple-first.png` |

Notes, so the next run does not re-learn them:

- **TC-PAY-006's first attempt died at B's sign-in** with `Failed to connect to /127.0.0.1:7001` — the
  Maestro iOS driver dropped, no assertion failed and there was no app crash report. Rerunning the same
  flow immediately passed end to end, so it is harness flake, not a product or flow defect. If it recurs,
  restart the run rather than editing the flow.
- TC-PAY-004 is the only flow that *buys* anything: it does so through the RevenueCat **Test Store**
  dialog on the Dev-Debug key. It leaves the E2E account entitled, which is what TC-PAY-005 then regates —
  so 004/005/006 must run in that order in the same session.
- Build 17 confirms the Settings rebuild at runtime: `settings.premium.row` lives in the new Library group
  and still opens the paywall, which is what TC-PAY-004/005/006 use as their entitlement probe.

## Disk hygiene on lane 2 (CF871F97) — run this before and after every Maestro batch

The lane-2 simulator accumulates XCTest attachments and has already filled the disk once. Before starting a
run and again after every batch:

```bash
# lane 2 ONLY — never another simulator
find ~/Library/Developer/CoreSimulator/Devices/CF871F97-1789-4490-B3E3-0B5EFA39F23F/data/Containers/Data/InternalDaemon/*/Attachments \
  -type f -mmin +10 -delete
rm -rf ~/Library/Developer/CoreSimulator/Devices/CF871F97-1789-4490-B3E3-0B5EFA39F23F/data/Library/Caches/com.apple.containermanagerd/Dead/*
find "$TMPDIR" -maxdepth 1 -name 'maestro_xctestrunner_*' -mmin +10 -exec rm -rf {} + 2>/dev/null
ls -d /tmp/dd-* 2>/dev/null      # unused derived-data dirs: remove the ones no build is using
df -h /    # require >= 3 GiB free before AND after a batch; under that, stop and tell the QA lead
```

One Maestro batch per integration commit, and artefacts that must survive a reboot stay outside `/tmp`
(committed under `screens/`, or the ledger folder) — a reboot wiped `/tmp` once already.

`run.sh` cannot do this for us: its `cleanup_dead_containers` deliberately skips `CF871F97*`, and it does not
touch XCTest attachments at all, so both commands are manual on this lane. Never `simctl erase`. Keep bulky
screenshots/logs under `/tmp/qa-*`; the evidence that matters is committed under `screens/`.

## Build 1.1 (17) scope: regression only (historical — the redesign is in 18)

`/tmp/ai-pose-lane2-app-1.1/dev17/posing.app` is built from `a03d03a`. Verified with
`git merge-base --is-ancestor <sha> a03d03a`:

| Commit | In build 17? | Consequence |
|---|---|---|
| `f73748f` Settings hub + Account rebuild | **yes** | `settings.saved.row`, `settings.back`, `settings.accountCard` exist |
| `0632361` per-field email validation | **yes** | email sign-in ids unchanged; `signin.google` is gone (nothing in this suite used it) |
| `18a13f8` support screens split | **yes** | paywall/settings ids survived the file split |
| `bf1db8c` F4 state component | **no** | state panels still the old chrome |
| `1925f5c` saved undo + offline rows, `6eab7c9` undo scoping | **no** | TC-SAV-006/010/014 have no producer in this build |
| paywall redesign (`paywall.benefit|offline|notice|signin.sheet|signin.close`) | **no** | all paywall redesign drafts stay drafts |

So the build-17 job here is **regression of the nine existing flows** on the new build
(`TC-SAV-001`, `TC-PAY-001/002/003/004/005/006/008/009` — all 20 accessibility ids they use are present at
`a03d03a`). Every redesign flow in this directory stays a draft until the **1.1 (18)** app lands after the
00:30 integration; the promotion table below is then executed against that build instead, with the ids
re-verified in committed source at that sha.

## Promotion plan (re-verified at every build; currently targeting 1.1 (18))

Ids verified against committed source at `a03d03a` (not the dirty worktree). Promoted into
`maestro/flows/` with the run, and the matching doc row flipped to `automated: <file>`:

| Case | Flow | Note |
|---|---|---|
| TC-SAV-002 | `TC-SAV-002-saved-list-loaded.yaml` | save from detail → listed; needs `E2E_EMAIL` |
| TC-SAV-003 | `TC-SAV-003-unsave-removes.yaml` | row unsave → empty after reload |
| TC-SAV-004 | `TC-SAV-004-empty-browse.yaml` | empty state + Browse poses; needs an account with nothing saved |
| TC-SAV-009 | `TC-SAV-009-load-error-retry.yaml` | error panel + Try again; uses the Debug `-AIPoseAPIBaseURL` relaunch seam |
| TC-SAV-012 | `TC-SAV-012-back-to-settings.yaml` | Settings → Saved → Back → Settings (`settings.saved.row`) |
| TC-SAV-006 | `TC-SAV-006-offline-banner-rows.yaml` | offline board via the DEBUG `-AIPoseSavedOfflineFixture 2` seam (`subflows/saved-launch-offline.yaml`) |
| TC-SAV-010 | `TC-SAV-010-unsave-undo.yaml` | server-confirmed unsave → "Removed <pose>" + Undo restores at its previous index (snackbar read by text) |
| TC-SAV-014 | `TC-SAV-014-no-unsave-offline.yaml` | same seam with 0 cached rows: no unsave offered |
| TC-SAV-013 | `TC-SAV-013-ax3-dark.yaml` | AX3 + dark; runner sets device state and restores it |
| TC-PAY-012 | `TC-PAY-012-purchase-failed.yaml` | Test Store "Test failed purchase" |
| TC-PAY-013 | `TC-PAY-013-purchase-cancelled.yaml` | Test Store "Cancel" |
| TC-PAY-015 | `TC-PAY-015-legal-links.yaml` | legal links from the paywall |
| TC-PAY-017 | `TC-PAY-017-ax3-dark.yaml` | AX3 + dark with plans loaded (signed in, nothing bought) |

Saved undo + offline landed in `1925f5c`/`6eab7c9` (**not** in build 17, so 18). Stays a draft: **TC-PAY-007** (plans-unavailable/offline has no deterministic producer on a Test Store build).

Paywall redesign ids (`paywall.benefit`, `paywall.offline`, `paywall.notice`, `paywall.signin.sheet`,
`paywall.signin.close`) are **pending commit** — the drafts that would use them (TC-PAY-007/009/016/020) stay
drafts until they are in committed source and verified there, per the QA lead.

## How to run a draft (after the QA lead names a build)

```bash
set -a; . mobile/iosApp/maestro/e2e.local.env; set +a
maestro --device <CF871F97 udid> test -e APP_ID=<bundle id of the named build> \
  -e E2E_EMAIL="$E2E_EMAIL" -e E2E_PASSWORD="$E2E_PASSWORD" \
  docs/qa/redesign-drafts/saved-paywall/flows/TC-SAV-012-back-to-settings.yaml
```

Device state some drafts need (restore afterwards — `appearance light`, `content_size large`):
`TC-SAV-013` and `TC-PAY-017` expect dark + `accessibility-extra-large`; `TC-SAV-009` needs the Debug build
for its `-AIPoseAPIBaseURL` relaunch.

Promotion to `maestro/flows/` = move the file, flip its row from `draft:` to `automated: <file>`, run
`./check-traceability.sh`, and commit only after it passes on the named build.

## Screens

`docs/qa/redesign-drafts/saved-paywall/screens/` receives the evidence screenshots the drafts take
(TC-PAY-017 writes one; add the rest when the runs happen).
