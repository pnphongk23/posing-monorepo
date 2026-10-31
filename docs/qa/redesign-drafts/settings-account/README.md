# Settings / Account redesign drafts (build 17)

Draft Maestro flows for the cases in `docs/qa/test-cases/settings.md` and `account.md` whose
accessibility ids are not committed yet. They are NOT in `maestro/flows/`, so the traceability checker
ignores them, and nothing here has been run on a simulator.

- `runFlow` paths are written as they will read from `maestro/flows/` (e.g. `../subflows/launch.yaml`),
  so a draft can be moved there unchanged once Feature commits the ids it uses.
- Every id below is requested in the "Requests to Feature" section of its test-case doc. Ids that
  already exist in committed source are marked `exists` in the flow comments.
- Three drafts need harness pieces that do not exist yet and are called out in their headers: a
  signed-in launch subflow (credentials), a way to force the offline state, and the App Store URL
  constant behind Manage subscription.
- Not drafted on purpose (out of scope 1.1 (17), ideas kept in the docs): in-app delete confirmation and
  delete error (TC-ACC-016/017), the Settings Camera section (TC-SET-009/010/011), Forgot password
  (TC-ACC-029).
