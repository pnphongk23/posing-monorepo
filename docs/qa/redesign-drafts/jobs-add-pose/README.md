# Build 17 redesign — Jobs + Add pose flow drafts

Drafts for the cases in [extract-jobs.md](../../test-cases/extract-jobs.md) § "Build 17 redesign".
They stay here, **not** in `mobile/iosApp/maestro/flows/`, because every flow below uses ids that Feature
has not committed yet (the full list is in the doc's "Requests to Feature" section). Moving a draft into
`maestro/flows/` means: flip its doc row from `pending:` to `automated: <file>`, keep `tags: [<TC-ID>, …, e2e]`,
run it green on the lane-2 simulator, then commit both with an explicit pathspec.

Ids landed by Feature in 2b01b77 / 09ef76e are listed in the test-case doc; drafts below that only needed
those ids are runnable now (they stay here until a build with them is the named lane build).

Boards used: `/tmp/ds-261030/export-c/08-*` (Add pose: empty, form, dark, photo error, Pose preview) and
`09-*` (Jobs: Processing with badge + filters, Finished with Done/Failed rows, AX variant), plus
`FEEDBACK-261031.md` (F3 badge only, F4 one clean state icon, F5 snackbar at the bottom, F7 Add pose hidden
when `extractPoseEnabled` is off, F8 More menu).

| Case | Draft | Blocked on |
|---|---|---|
| TC-EXT-004 | `flows/TC-EXT-004-add-pose-empty-state.yaml` | `addPose.choosePhoto`, `addPose.empty.seeJobs` |
| TC-EXT-005 | `flows/TC-EXT-005-add-pose-form-validation.yaml` | `addPose.tags.addTag`, `addPose.tags.chip.<tag>`, `addPose.form.helper` |
| TC-EXT-006 | `flows/TC-EXT-006-add-pose-photo-error.yaml` | `addPose.error.title`, `addPose.error.message`, `addPose.changePhoto` + a fixture the server rejects |
| TC-EXT-007 | `flows/TC-EXT-007-pose-preview-publish.yaml` | **out of scope 1.1 (17)** (publish flow has no API); draft kept for later |
| TC-JOB-001 | `flows/TC-JOB-001-finished-view-pose.yaml` | build-17 copy of the committed flow (`Done · added to Poses`); replaces it when that build lands |
| TC-JOB-007 | `flows/TC-JOB-007-processing-filters.yaml` | `jobs.tab.processing.count`, `jobs.filter.queued`, `jobs.filter.processing` |
| TC-JOB-008 | `flows/TC-JOB-008-finished-filters-retry.yaml` | `jobs.filter.done`, `jobs.filter.failed` |
| TC-JOB-009 | `flows/TC-JOB-009-hide-job.yaml` | `jobs.row.remove.<jobId>` (landed, now the Hide swipe) + `jobs.footer.hint`, `jobs.snackbar` |
| TC-JOB-010 | `flows/TC-JOB-010-long-name-ax.yaml` | `jobRow.name.<jobId>`; needs a job with a 60+ character name |
| TC-JOB-012 | `flows/TC-JOB-012-empty-states.yaml` | action ids landed (`jobs.empty.viewFinished|goToProcessing|showAll`); title/body ids still missing |
| TC-JOB-013 | `flows/TC-JOB-013-offline-banner.yaml` | `jobs.offline.banner` landed; needs an unreachable API (dead base URL or stopped stub) |

Run one against the lane-2 simulator (credentials never leave the shell):

```
set -a; . mobile/iosApp/maestro/e2e.local.env; set +a
maestro --device <CF871F97 udid> test -e APP_ID=posing.camera.app \
  -e E2E_EMAIL="$E2E_EMAIL" -e E2E_PASSWORD="$E2E_PASSWORD" \
  docs/qa/redesign-drafts/jobs-add-pose/flows/TC-JOB-007-processing-filters.yaml
```

The drafts reuse the committed `ext-launch.yaml` / `ext-sign-in.yaml` subflows (owned by this lane) through
`../../../../mobile/iosApp/maestro/subflows/…`; on promotion that path becomes `../subflows/…`.

Real jobs: TC-EXT-007 and any Finished-tab case need jobs created by the production extractor. Do not spend
one until the QA lead approves — build 16 runs showed the provider failing on a stock photo.
