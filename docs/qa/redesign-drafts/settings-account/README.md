# Settings / Account redesign drafts (1.1 build 17)

Draft Maestro flows for the cases in `docs/qa/test-cases/settings.md` and `account.md`. They are NOT in
`maestro/flows/`, so the traceability checker ignores them and no other worker's run can pick them up.
Nothing here has been run on a simulator yet.

- `runFlow` paths are written as they will read from `maestro/flows/` (e.g. `../subflows/launch.yaml`),
  so a draft moves there unchanged.
- Ids are now committed (`f73748f`, `13afc3a`) for every draft below; what is missing is the **1.1 (17)
  build** to run them against and, for a few, credentials or a deterministic hook.
- Three drafts need harness pieces that do not exist yet, called out in their headers: a signed-in launch
  subflow (credentials), a way to force the offline state, and the App Store URL constant behind Manage
  subscription.

## Two kinds of draft

1. **Re-baselines of cases that already have a committed flow** — `TC-SET-001-settings-about`,
   `TC-ACC-008-accounts-off`. The committed versions still assert the pre-redesign Privacy group, which no
   longer exists on 1.1 (17); these copies replace them as soon as they pass on that build.
2. **Flows for new cases** — `TC-SET-006/007/008/012/013`, `TC-ACC-021`.

Signed-in or undeterministic cases stay drafts for now: `TC-SET-005`, `TC-SET-017`,
`TC-ACC-012/013/014/024/028`.

## Not drafted on purpose (out of scope 1.1 (17), ideas kept in the docs)

In-app delete confirmation and delete error (TC-ACC-016/017), the Settings Camera section
(TC-SET-009/010/011 — no haptics model, grid and guide colour stay in the camera UI), Forgot password
(TC-ACC-029).

## Promotion plan (when the 1.1 (17) build is named)

1. Sanity-check the shared subflows first (`launch`, `launch-accounts-on`, `launch-accounts-off`,
   `open-settings`, `relaunch-keep-state`) — everything else depends on them.
2. Move each draft into `maestro/flows/` under its own basename and flip its row in
   `docs/qa/test-cases/{settings,account}.md` from "pending (re-baselined flow drafted…)" to
   `automated: <file>`; `./check-traceability.sh` fails until both sides agree.
3. Run the suite. A red is either a flow defect (fix, rerun once) or an app bug (write a bug note; never
   edit app source).
4. Commit only flows that are green, with the matching docs rows in the same pathspec.
