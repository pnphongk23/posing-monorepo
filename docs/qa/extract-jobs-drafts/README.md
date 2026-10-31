# Extract pose / Jobs — flow drafts (not yet run)

Unvalidated drafts for the cases in [extract-jobs.md](../test-cases/extract-jobs.md). They live here,
**not** in `mobile/iosApp/maestro/flows/`, because a flow may only enter that directory once it has
passed on the simulator (and because an untracked flow there fails `check-traceability.sh` for every
other lane).

| Case | Draft | Blocked on |
|---|---|---|
| TC-EXT-001 | `flows/TC-EXT-001-consent-cancel.yaml` | sim GO + build with S1 consent (no upload, so no AI cost) |
| TC-EXT-002 | `flows/TC-EXT-002-consent-allow.yaml` | sim GO + S1 build + E2E account — **1 real extraction job** |
| TC-EXT-003 | `flows/TC-EXT-003-extract-flag-off.yaml` | sim GO only (no backend, no AI cost) |
| TC-JOB-001 | `flows/TC-JOB-001-finished-view-pose.yaml` | sim GO + S1 build + E2E account — **1 real extraction job** |

Budget: at most 2 real extraction jobs per full run (AI cost), which is exactly TC-EXT-002 +
TC-JOB-001, one job each. Both start with the consent sheet (the clean launch clears the per-account
ack), so neither needs a shared job and each stays 1 case = 1 flow. The "asked once per account" half
of TC-EXT-002 is not re-tested here — a second submit would cost a second job; it belongs to Feature's
ack unit test.

Every flow here except TC-EXT-003 is tagged `e2e` in its header, and `mobile/iosApp/maestro/run.sh`
excludes `e2e` flows unless `E2E_EMAIL` is exported (`--exclude-tags=e2e`), so the default suite stays
green without credentials. Move the tag along with the flow.

Subflows: `ext-launch.yaml` (extraction + accounts on, clean container), `ext-sign-in.yaml`
(`${E2E_EMAIL}`/`${E2E_PASSWORD}`), `ext-add-pose-form.yaml` (photo from the simulator library,
name/tags), `ext-consent-allow.yaml`.

Credentials are never in this repo. The QA lead supplies `mobile/iosApp/maestro/e2e.local.env`
(gitignored, `chmod 600`, `KEY=VALUE` lines: `E2E_EMAIL`, `E2E_PASSWORD`, `E2E_EMAIL_B`,
`E2E_PASSWORD_B`); source it in the shell and pass the values with `-e`, so they never land in a
command line you print or in a commit. Readiness check without printing anything:
`[ -n "$E2E_PASSWORD" ]`. Only accounts A (`E2E_EMAIL`) and B (`E2E_EMAIL_B`) are used —
the App Review demo account (`tester.posing.003`) is reserved and must stay clean
(no jobs, no purchases), so no flow, doc example or env file may point at it:

```
set -a; . mobile/iosApp/maestro/e2e.local.env; set +a
maestro --device <UDID> test -e APP_ID=posing.camera.app \
  -e E2E_EMAIL="$E2E_EMAIL" -e E2E_PASSWORD="$E2E_PASSWORD" \
  docs/qa/extract-jobs-drafts/flows/TC-JOB-001-finished-view-pose.yaml
```

The photo must be in the simulator library first: `xcrun simctl addmedia <UDID> /tmp/qa-pose.jpg`
(the picker is a system `PHPickerViewController`, so the first cell is tapped by position).

Cleanup after a run (keeps the QA account's list tidy, no extra AI cost): Jobs > Finish > swipe the
row > Remove. Moving a draft into `maestro/flows/` requires flipping its row in `extract-jobs.md` from
`pending:` to `automated: <file>` in the same commit, or `check-traceability.sh` fails.
