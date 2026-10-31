# Extract pose (Add pose + consent) and Jobs (FEAT-015 / FEAT-016)

Cases for the Add pose flow (`Features/Jobs/AddPoseScreen.swift`), the consent step in front of the
first upload, and the Jobs screen (`Features/Jobs/JobsScreen.swift`) with its More-menu badge.
Matrix context and existing unit/server coverage: [release-matrix-4-flows](../release-matrix-4-flows.md) §2 and §4.

Consent copy (final, product owner 2026-10-31) — asserted verbatim, no vendor name:
"To extract the pose, your photo is sent to a third-party AI service. The pose created from it is saved privately to your account until you delete it."

Business rule: the sheet is asked **once per signed-in account**, before the first upload. The ack is
stored per account in UserDefaults, so `launchApp clearState: true` clears it and the sheet reappears on
the next run (that is how these flows re-run on the same account). Cancel records no answer, so the next
submit asks again; after Allow the same account is never asked again. The sheet is a SwiftUI `.sheet`, so
swiping it down is a Cancel too.
Consent ids (frozen by Feature S1): `addPose.consent.message`, `addPose.consent.allowButton` ("Allow"),
`addPose.consent.cancelButton` ("Cancel"). Trigger: `addPose.submitButton` with a valid form and no
recorded ack. No consent-specific launch arg; the sheet needs `-AIPoseExtractPoseEnabled true` plus the
accounts flag.

Run model (QA lead, 2026-10-31): TC-EXT-001, TC-EXT-002 and TC-JOB-001 run against **production** with the
two test accounts only — account A (`E2E_EMAIL`) and account B (`E2E_EMAIL_B`). A third account
(`tester003`) is reserved for the Apple review demo and must stay clean: no flow, doc example or env file
uses it. Credentials come only from a `chmod 600` file outside the repo
(`/tmp/ai-pose-e2e.env`, `E2E_EMAIL` / `E2E_PASSWORD` / `E2E_EMAIL_B` / `E2E_PASSWORD_B`), passed to maestro
with `-e`; the file is never read into a report, printed or committed, and no credential appears in a flow.
The flows also need a real photo pushed into the simulator library
(`xcrun simctl addmedia <udid> /tmp/<photo>.jpg`, kept outside the repo). Flows fail fast when the
credentials are missing. **Budget: at most 2 real extraction jobs per full run (AI cost)**: TC-EXT-002
and TC-JOB-001 cost one job each, and the jobs are removed after the run. TC-JOB-002/003/004/005/006
have no reproducible Maestro state, so they stay with the unit suites that already assert them.

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-EXT-001 | P0 | Accounts on (launch arg), signed in, extraction on, consent ack cleared by the clean launch (`clearState: true`) | 1. Launch signed in. 2. Poses header + (Add pose). 3. Pick a photo, enter a name and one tag. 4. Tap Extract Pose. 5. Read the consent sheet, tap Cancel. 6. Tap Extract Pose again. 7. Open More > Jobs (both tabs) | Consent sheet appears before the first upload with exactly the final copy and no vendor name. Cancel closes it and leaves the user on the Add pose form with the draft intact (photo, name, tags) and no processing screen. Nothing is uploaded and no job is created: the Jobs Processing and Finish tabs contain no row with this draft's name. Because Cancel records no answer, step 6 asks for consent again instead of uploading (a cancel costs no AI job) | pending: Pending-validation — flow drafted (`extract-jobs-drafts/flows/TC-EXT-001-consent-cancel.yaml`); needs a build with S1 consent and the E2E account |
| TC-EXT-002 | P0 | Accounts on, signed in, extraction on, consent ack cleared by the clean launch (`clearState: true`) | 1. Launch signed in. 2. Add pose, pick a photo, name, one tag. 3. Tap Extract Pose. 4. Tap Allow. 5. Open More > Jobs | Allow sends the upload once (the form becomes the processing surface without a second tap) and exactly one new row appears in Jobs > Processing with the pose name. The answer is remembered per account: the sheet does not come back on the next submit for this account (asserted by Feature's ack unit test — a second submit would cost a second real job) | pending: Pending-validation — flow drafted (`extract-jobs-drafts/flows/TC-EXT-002-consent-allow.yaml`); needs a build with S1 consent and the E2E account |
| TC-EXT-003 | P0 | Launch arg `-AIPoseExtractPoseEnabled false` (extraction kill switch off), accounts on | 1. Launch with the switch off. 2. Inspect the Poses header. 3. Open More. 4. Tap the Jobs row. 5. Open the Gallery tab | No Add pose control in the Poses header (no `poses.add-pose`) and none in the Gallery header (no `gallery.add-pose`). The More menu Jobs row is present but disabled, so tapping it never leaves the Poses home screen (no `jobs.tab.processing`). The Add pose screen is unreachable, so the form can never issue a submit or retry request, and the Jobs screen with its Add pose empty-state action is unreachable too. With the switch on the same controls are visible, which is what makes this assertion falsifiable | pending: Pending-validation — flow drafted (`extract-jobs-drafts/flows/TC-EXT-003-extract-flag-off.yaml`, no backend needed); moves to `automated:` once it passes on the simulator |
| TC-JOB-001 | P0 | Signed in, extraction on, a real photo available, consent ack cleared by the clean launch | 1. Add pose with a photo, name and tag; allow the consent sheet. 2. Wait for the job to succeed. 3. Open Jobs (Finish tab) and tap the row action View pose. 4. Open Saved. 5. Search the catalogue for the pose name | The ready row sits in Finish with the label "<name>, Ready, View pose" and its own action element `jobRow.viewPose.<jobId>` (the row is `.contain`, the button is not swallowed by the row summary). Tapping it opens the PRIVATE pose detail of the created pose: "Try this pose" is visible and works (`poseDetail.use`) while there is no Save control (`poseDetail.saveButton` absent), because the pose is private. The pose is materialised with `status: local`, so it appears neither in Saved nor in Community search (search for the name shows the no-match panel). One real job, shared with nothing else in the run | pending: Pending-validation — flow drafted (`extract-jobs-drafts/flows/TC-JOB-001-finished-view-pose.yaml`, taps `jobRow.viewPose..*`); needs a build with S1 consent + the `JobRowView` `.contain` change, the E2E account and a working extraction pipeline |
| TC-JOB-002 | P0 | Signed in, one queued job and one processing job | 1. Open More > Jobs. 2. Read the Processing tab. 3. Let the screen poll once | Both in-progress rows are listed on Processing with "Queued" and "Processing", the Processing tab carries the count 2, and polling starts on appear so a status change shows up without a manual refresh; a row that finishes leaves Processing | unit: Features/JobsServiceTests.swift (testRefreshSplitsInProgressAndFinished, testJobMovingFromProcessingToSucceededMovesToFinished) — no Maestro state can seed queued+processing jobs |
| TC-JOB-003 | P0 | Signed in, one failed job that carries an error message | 1. Open More > Jobs. 2. Tap the Finish tab. 3. Tap Retry on the failed row | The failed row is in Finish with "Failed", the job's error message and a Retry action; Retry sends exactly one POST /api/me/extract-jobs/<jobId>/retry and the row returns to Processing as "Queued". With extraction off no Retry control is drawn | unit: Features/JobsServiceTests.swift (testDecodeFailedJobStatusWithError, testWatchJobTerminatesOnFailed) + src/routes/myExtractJobsRoutes.test.ts — a failed job cannot be seeded from the UI |
| TC-JOB-004 | P1 | Signed in, extraction on, the account has no jobs | 1. Open More > Jobs | "No jobs yet", "Pose extraction jobs will appear here when you submit a pose." and an Add pose action that opens the Add pose flow and closes Jobs; with extraction off the action is not offered | unit: Features/JobsScreenModelTests.swift (testJobsScreenEmptyStateWhenStubHasNoRows) — the test account gains jobs as soon as TC-EXT-002/TC-JOB-001 run |
| TC-JOB-005 | P1 | Signed in with jobs loaded, then the API becomes unreachable | 1. Load Jobs online. 2. Let one poll fail. 3. Reconnect | Cached rows stay on screen, the banner "You're offline — statuses update when you're back online." appears at the top of the list (as the whole panel when no rows are cached) and clears on the next successful poll | unit: Features/JobsServiceTests.swift (testOfflineNetworkErrorPreservesCachedJobsAndSetsOffline) — the simulator cannot drop the network per app |
| TC-JOB-006 | P2 | Signed in, two processing jobs; then none; then signed out | 1. Open More and read the Jobs row. 2. Finish the jobs, reopen More. 3. Sign out, reopen More | With two running jobs the Jobs row shows one badge with the number 2 and the accessibility label "Jobs, 2 active"; no other More row carries a count. With no running jobs the badge is hidden and the label is plain "Jobs". Signed out the badge is hidden even if the last count was not zero | unit: DesignSystem/APShellTests.swift (testMoreMenuRowsCarryNoSubtitleCounts) — needs a seeded running count |

## How these cases are driven deterministically

Checked in code, 2026-10-31:

- **Sign-in:** email sign-in is a plain API call, `POST /api/auth/email/signin` (`Core/Network/APIClient.swift:107-121`),
  and the pair it returns is stored in the Keychain through `SessionBoundary.saveCredentials`. So a
  flow signs in with the run-time `${E2E_EMAIL}` / `${E2E_PASSWORD}` on the Account screen
  (`poses.more` → `poses.menu.settings` → `settings.account.row` → `signin.emailEntry` →
  `signin.email` / `signin.password` / `signin.submit`) and every later step is a normal signed-in
  session. Google/Apple sign-in are not needed.
- **Photo:** `PhotoLibraryPicker` is a `PHPickerViewController` (`Features/Jobs/PhotoLibraryPicker.swift`),
  so the flow needs one image in the simulator library. `xcrun simctl addmedia <udid> /tmp/qa-pose.jpg`
  adds it once per simulator; the picker sheet is UIKit, so its first cell is addressed by position.
  Nothing is committed: the image lives under `/tmp`.
- **`-AIPoseAPIBaseURL <url>` is honoured** (Debug only, `Core/Network/AppConfig.swift:22-27`;
  `EndpointPolicy.validate` accepts any `http`/`https` URL with a host, so `http://127.0.0.1:<port>`
  works, and every service reads it through `ServiceLocator.makeAPIClient`). It does **not** cover the
  Firestore config fetch, which is why the feature switches are set with launch args.
- **No launch arg seeds jobs.** `-AIPosePagingFixture` only parks the catalogue footer; there is no
  fixture for the Jobs list, no way to make a job fail, and no way to start with a non-zero running
  count. That is why TC-JOB-002..006 stay with the unit suites.
- **No stub server is in the repo** (`docs/qa/purchase-e2e-blockers.md` blocker 4). A throwaway stub
  would still be the only way to *count* uploads; the drafted flows prove "no job row appeared"
  (TC-EXT-001) and "one job row per submit" (TC-EXT-002) instead.

## Requests to Feature

1. Consent ids (frozen by S1): `addPose.consent.message` on the copy, `addPose.consent.allowButton` /
   `addPose.consent.cancelButton` on the buttons — the two consent flows need them in a built binary.
   A container id (`addPose.consent.sheet`) would let a flow assert the sheet is gone without matching
   the copy.
2. Optional, to automate the count-sensitive half of TC-EXT-002 and the cut Jobs cases: a
   seeded-jobs fixture arg mirroring `-AIPosePagingFixture`, e.g.
   `-AIPoseJobsFixture queued,processing,succeeded,failed`, plus (if uploads must be counted) an
   in-repo stub server on a fixed port started by `run.sh`.
3. `JobRowView` accessibility (change written by Feature, not yet built): the row is `.contain` and the
   actions are separate elements, `jobRow.retry.<jobId>` / `jobRow.viewPose.<jobId>` (suffixed, matched
   by regex in the flow), while the row summary keeps the label "<name>, <status>[, <action>]" and no id.
   The Maestro run is the real proof of tapability — a unit test can pin the modifier, not that a tap on
   the id reaches the button.
