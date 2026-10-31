# Settings / Account redesign drafts (1.1 build 18)

Draft Maestro flows for the cases in `docs/qa/test-cases/settings.md` and `account.md`. They are NOT in
`maestro/flows/`, so the traceability checker ignores them and no other worker's run can pick them up.
Nothing here has been run on a simulator yet.

- `runFlow` paths are written as they will read from `maestro/flows/` (e.g. `../subflows/launch.yaml`),
  so a draft moves there unchanged.
- Ids are now committed (`f73748f`, `13afc3a`) for every draft below; what is missing is the **1.1 (18)
  build** to run them against and, for a few, credentials or a deterministic hook.
- Three drafts need harness pieces that do not exist yet, called out in their headers: a signed-in launch
  subflow (credentials), a way to force the offline state, and the App Store URL constant behind Manage
  subscription.

## What is still here (5 drafts)

- `TC-SET-017` — the hub profile card when the account read fails (needs a signed-in session plus a
  failing read).
- `TC-ACC-012` — Account F4 error state and its retry (same dependency).
- `TC-ACC-013` — Account offline: cached identity, Delete disabled with its reason (no supported way to
  reach a cached-offline state yet).
- `TC-ACC-024` — the submit control cannot be double-fired (no deterministic in-flight hook: the button
  label only flips for the length of a real request).
- `TC-ACC-028` — Manage subscription opens the App Store page; it renders only with a live entitlement
  (`showsManageSubscription`), so it needs an entitled account, and the exact URL needs a unit test.

Promoted and no longer drafted (green on 1.1 (18), rows now `automated:`): `TC-SET-001`, `TC-SET-005`,
`TC-SET-006`, `TC-SET-007`, `TC-SET-008`, `TC-SET-012`, `TC-SET-013`, `TC-ACC-008`, `TC-ACC-014`,
`TC-ACC-021`, `TC-ACC-022`, `TC-ACC-023`.

## Not drafted on purpose (out of scope 1.1 (18), ideas kept in the docs)

In-app delete confirmation and delete error (TC-ACC-016/017), the Settings Camera section
(TC-SET-009/010/011 — no haptics model, grid and guide colour stay in the camera UI), Forgot password
(TC-ACC-029).

## Promotion plan (when the 1.1 (18) build is named)

1. Sanity-check the shared subflows first (`launch`, `launch-accounts-on`, `launch-accounts-off`,
   `open-settings`, `relaunch-keep-state`) — everything else depends on them.
2. Move each draft into `maestro/flows/` under its own basename and flip its row in
   `docs/qa/test-cases/{settings,account}.md` from "pending (re-baselined flow drafted…)" to
   `automated: <file>`; `./check-traceability.sh` fails until both sides agree.
3. Run the suite. A red is either a flow defect (fix, rerun once) or an app bug (write a bug note; never
   edit app source).
4. Commit only flows that are green, with the matching docs rows in the same pathspec.
