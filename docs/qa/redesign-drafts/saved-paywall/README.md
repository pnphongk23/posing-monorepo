# Redesign drafts — Saved + Paywall (build 17)

Cases live in [saved-bookmarks.md](../../test-cases/saved-bookmarks.md) and
[paywall-purchase.md](../../test-cases/paywall-purchase.md). These flows are **drafts**: they stay outside
`mobile/iosApp/maestro/flows/` because `check-traceability.sh` requires every file there to be git-tracked
*and* marked `automated: <file>` in the case doc, and a flow only earns that after it passes on a named
build. Nothing here has run yet — the QA lead has not named a build for the redesign.

## Coverage this round

| Screen | Cases | Automated (already in `maestro/flows`) | Draft flows here | Unit / XCTest | Pending (ids or data) |
|---|---|---|---|---|---|
| Saved | 13 | 1 (TC-SAV-001) | 6 (002, 003, 004, 009, 012, 013) | 1 (TC-SAV-008 skeleton decision) | 5 (005, 006 manual, 007, 010 ids, 011 data) |
| Paywall / purchase | 18 | 8 (001–006, 008, 009) | 5 (007, 012, 013, 015, 017) | 2 (TC-PAY-010 loading, 011 processing) | 3 (014 restore ids, 016 sign-in resume, 018 offering e2e) |

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
