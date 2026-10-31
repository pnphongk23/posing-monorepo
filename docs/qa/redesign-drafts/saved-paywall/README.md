# Redesign drafts — Saved + Paywall (build 17)

Cases live in [saved-bookmarks.md](../../test-cases/saved-bookmarks.md) and
[paywall-purchase.md](../../test-cases/paywall-purchase.md). These flows are **drafts**: they stay outside
`mobile/iosApp/maestro/flows/` because `check-traceability.sh` requires every file there to be git-tracked
*and* marked `automated: <file>` in the case doc, and a flow only earns that after it passes on a named
build. Nothing here has run yet — the QA lead has not named a build for the redesign.

## Coverage this round

| Screen | Cases | Automated (already in `maestro/flows`) | Draft flows here | Unit / XCTest | Pending (ids or data) |
|---|---|---|---|---|---|
| Saved | 13 | 1 (TC-SAV-001) | 6 (002, 003, 004, 009, 012, 013) | 1 (TC-SAV-008 skeleton decision) | 5 (005, 006 offline ids, 007 isolation, 010 undo ids, 011 data) |
| Paywall / purchase | 21 | 8 (001–006, 008, 009) | 5 (007, 012, 013, 015, 017) | 2 (TC-PAY-010 loading, 011 processing) | 6 (014 restore ids, 016 sign-in resume, 018 offering, 019 3.1.2 disclosure ids, 020 shutter-only claim, 021 identity line ids) |

MUST-COVER items for build 17 land in these rows: **Saved Undo** (TC-SAV-010), **Saved offline cached
mode** (TC-SAV-006), **Paywall 3.1.2 disclosures** (TC-PAY-019), **shutter-only claim** (TC-PAY-020),
and the F4 state component on both screens (TC-SAV-008/009/006 + TC-PAY-007/010/012).

## Re-baselining (cases written against the pre-redesign screen)

The gap table (`/tmp/gap/05-06.md` §06, `/tmp/gap/09-11.md` §11) makes several of these cases *different*
behaviour, not just different pixels. When build 17 lands, these must be updated in the same commit that
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

## Build 1.1 (17) scope: regression only — redesign waits for 1.1 (18)

`/tmp/ai-pose-lane2-app-1.1/dev17/posing.app` is built from `a03d03a`. Verified with
`git merge-base --is-ancestor <sha> a03d03a`:

| Commit | In build 17? | Consequence |
|---|---|---|
| `f73748f` Settings hub + Account rebuild | **yes** | `settings.saved.row`, `settings.back`, `settings.accountCard` exist |
| `0632361` per-field email validation | **yes** | email sign-in ids unchanged; `signin.google` is gone (nothing in this suite used it) |
| `18a13f8` support screens split | **yes** | paywall/settings ids survived the file split |
| `bf1db8c` F4 state component | **no** | state panels still the old chrome |
| `1925f5c` saved undo + offline rows, `6eab7c9` undo scoping | **no** | TC-SAV-006/010 have no producer in this build |
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
| TC-SAV-013 | `TC-SAV-013-ax3-dark.yaml` | AX3 + dark; runner sets device state and restores it |
| TC-PAY-012 | `TC-PAY-012-purchase-failed.yaml` | Test Store "Test failed purchase" |
| TC-PAY-013 | `TC-PAY-013-purchase-cancelled.yaml` | Test Store "Cancel" |
| TC-PAY-015 | `TC-PAY-015-legal-links.yaml` | legal links from the paywall |
| TC-PAY-017 | `TC-PAY-017-ax3-dark.yaml` | AX3 + dark with plans loaded (signed in, nothing bought) |

Stays a draft: **TC-PAY-007** (plans-unavailable/offline has no deterministic producer on a Test Store build).

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
