# Extract pose (Add pose + consent) and Jobs (FEAT-015 / FEAT-016)

Cases for the Add pose flow (`Features/Jobs/AddPoseScreen.swift`), the consent step in front of the
first upload, and the Jobs screen (`Features/Jobs/JobsScreen.swift`) with its More-menu badge.
Matrix context and existing unit/server coverage: [release-matrix-4-flows](../release-matrix-4-flows.md) §2 and §4.

Consent copy (final, product owner 2026-10-31; re-issued 2026-10-31 with a new closing clause) — asserted
verbatim, no vendor name:
"To extract the pose, your photo is sent to a third-party AI service. The pose created from it is saved privately to your account until you delete your account."

The flows assert `addPose.consent.message` with the distinctive closing substring
(`saved privately to your account until you delete your account`), not the whole sentence, so a copy edit
to the opening clause cannot break them while the promise itself is still pinned.

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
two test accounts only — account A (`E2E_EMAIL`) and account B (`E2E_EMAIL_B`). The App Review demo
account (`tester.posing.003`) is reserved and must stay clean: no flow, doc example or env file uses it.
Credentials come only from a `chmod 600` file outside the repo
(`mobile/iosApp/maestro/e2e.local.env`, `E2E_EMAIL` / `E2E_PASSWORD` / `E2E_EMAIL_B` / `E2E_PASSWORD_B`),
passed to maestro with `-e`; the file is gitignored and `chmod 600`, and is never read into a report,
printed or committed, and no credential appears in a flow.

Credential-dependent flows carry the extra `e2e` tag (`tags: [TC-EXT-001, p0, e2e]`), and `run.sh` honours
it: with no `E2E_EMAIL` in the environment it passes `--exclude-tags=e2e`, so the default
`./run.sh <udid>` stays green without credentials; with `set -a; . e2e.local.env; set +a` exported it
forwards `-e E2E_EMAIL/E2E_PASSWORD` (and B) and the `e2e` flows run. TC-EXT-003 carries no `e2e` tag —
it needs no backend and runs in the default suite.
The flows also need a real photo pushed into the simulator library
(`xcrun simctl addmedia <udid> /tmp/<photo>.jpg`, kept outside the repo). Flows fail fast when the
credentials are missing. **Budget: at most 2 real extraction jobs per full run (AI cost)**: TC-EXT-002
and TC-JOB-001 cost one job each, and the jobs are removed after the run. TC-JOB-002/003/004/005/006
have no reproducible Maestro state, so they stay with the unit suites that already assert them.

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-EXT-001 | P0 | Accounts on (launch arg), signed in, extraction on, consent ack cleared by the clean launch (`clearState: true`) | 1. Launch signed in. 2. Poses header + (Add pose). 3. Pick a photo, enter a name and one tag. 4. Tap Extract Pose. 5. Read the consent sheet, tap Cancel. 6. Tap Extract Pose again. 7. Open More > Jobs (both tabs) | Consent sheet appears before the first upload with the final copy (asserted through `addPose.consent.message` on the closing clause `saved privately to your account until you delete your account`) and no vendor name. Cancel closes it and leaves the user on the Add pose form with the draft intact (photo, name, tags) and no processing screen. Nothing is uploaded and no job is created: the Jobs Processing and Finish tabs contain no row with this draft's name. Because Cancel records no answer, step 6 asks for consent again instead of uploading (a cancel costs no AI job) | automated: TC-EXT-001-consent-cancel.yaml |
| TC-EXT-002 | P0 | Accounts on, signed in, extraction on, consent ack cleared by the clean launch (`clearState: true`) | 1. Launch signed in. 2. Add pose, pick a photo, name, one tag. 3. Tap Extract Pose. 4. Tap Allow. 5. Done, then More > Jobs > Finish | Allow sends the upload once (the form becomes the processing surface without a second tap, and the consent sheet does not come back) and exactly one new row appears in Jobs with the pose name. The extraction pipeline is fast enough that the row lands in Finish rather than Processing, so the flow asserts it there; the answer being remembered for the account is asserted by Feature's ack unit test, because a second submit would cost a second real job | automated: TC-EXT-002-consent-allow.yaml |
| TC-EXT-003 | P0 | Launch arg `-AIPoseExtractPoseEnabled false` (extraction kill switch off), accounts on | 1. Launch with the switch off. 2. Inspect the Poses header. 3. Open More. 4. Tap the Jobs row. 5. Open the Gallery tab | No Add pose control in the Poses header (no `poses.add-pose`) and none in the Gallery header (no `gallery.add-pose`). The More menu Jobs row is present but disabled, so tapping it never leaves the Poses home screen (no `jobs.tab.processing`). The Add pose screen is unreachable, so the form can never issue a submit or retry request, and the Jobs screen with its Add pose empty-state action is unreachable too. With the switch on the same controls are visible, which is what makes this assertion falsifiable | automated: TC-EXT-003-extract-flag-off.yaml |
| TC-JOB-001 | P0 | Signed in, extraction on, a real photo available, consent ack cleared by the clean launch | 1. Add pose with a photo, name and tag; allow the consent sheet. 2. Wait for the job to succeed. 3. Open Jobs (Finish tab) and tap the row action View pose. 4. Open Saved. 5. Search the catalogue for the pose name | The ready row sits in Finish with the label "<name>, Ready, View pose" and its own action element `jobRow.viewPose.<jobId>` (the row is `.contain`, the button is not swallowed by the row summary). Tapping it opens the PRIVATE pose detail of the created pose: "Try this pose" is visible and works (`poseDetail.use`) while there is no Save control (`poseDetail.saveButton` absent), because the pose is private. The pose is materialised with `status: local`, so it appears neither in Saved nor in Community search (search for the name shows the no-match panel). One real job, shared with nothing else in the run | automated: TC-JOB-001-finished-view-pose.yaml |
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

## Build 17 redesign — Jobs and Add pose (cases pending confirmed ids)

Boards: `/tmp/ds-261030/export-c/08-*` (Add pose) and `09-*` (Jobs); owner feedback
`FEEDBACK-261031.md`. The redesign changes the shape of both surfaces, so these cases are written now
and their flows stay in `docs/qa/redesign-drafts/jobs-add-pose/` until Feature confirms the ids listed
under [Requests to Feature](#requests-to-feature).

Redesign deltas the existing rows above must be re-read against (they were written for 1.2 (16), the build
before this release):

- Add pose is a **three-step** flow: empty state ("Turn a photo into a pose" → Choose a photo) → form
  (Name, **tag chips + Add tag**, Description with a **200** counter, pinned **Add pose** CTA + Done) →
  **Pose preview** (skeleton over the photo, Name, tag chips, **Publish pose** + Done). The comma-separated
  tags text field and the 500-character description counter are gone.
- Add pose error state is a card above the form ("Couldn't read this photo" + reason) with a
  "Choose another photo" action and a disabled CTA plus a "Choose another photo to continue." helper line.
- Jobs segments read "Processing <badge>" / "Finished" (count only as a badge), and each tab has its own
  filter chips: **All / Queued / Processing** and **All / Done / Failed**.
- Job rows show a status line instead of a status word: "Done · added to Poses" (with a chevron that opens
  the private pose), "Failed · <server message>" (with a Retry action), "Processing"/"Queued" with a striped
  progress bar for the in-progress rows.

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-EXT-004 | P0 | Signed in, extraction on, this account has no job in progress | 1. Poses header + (Add pose). 2. Read the empty state. 3. Tap Choose a photo | The empty state explains the flow in one sentence ("Choose a photo. We find the pose, then you name and publish it."), offers one primary Choose a photo action, states that Back returns to Poses, and offers "See your jobs". Choose a photo opens the system photo picker; cancelling the picker returns to the same empty state with nothing changed | pending: needs `addPose.choosePhoto` and `addPose.empty.seeJobs` |
| TC-EXT-005 | P0 | Photo chosen, form on screen | 1. Read the CTA state with no name and no tag. 2. Type a name only. 3. Add one tag chip. 4. Type a 200+ character description | The pinned Add pose CTA is disabled and the helper line says what is missing until the form is valid; it enables only with a photo, a non-empty name and at least one tag. The description counter tracks the limit and refuses input beyond 200 characters instead of silently truncating the saved pose | pending: needs `addPose.tags.addTag`, `addPose.tags.chip.<tag>`, `addPose.description.counter`, `addPose.form.helper`, and a stable `addPose.submitButton` disabled state |
| TC-EXT-006 | P1 | Form filled, the server rejects the photo (413 / unreadable) | 1. Tap Add pose with a photo the server rejects. 2. Read the error card. 3. Tap Choose another photo | One error card above the form names the problem and the reason ("It's larger than 20 MB (error 413)") without a raw status code alone; the name, tags and description the user typed are kept; the CTA is disabled with "Choose another photo to continue." and Choose another photo reopens the picker | pending: needs `addPose.error.title` / `addPose.error.message` / `addPose.changePhoto` (the card currently only has `addPose.errorView`) |
| TC-EXT-007 | P0 | **out of scope 1.1 (17)** — the publish flow has no API yet. A job has been submitted and the skeleton came back | 1. Wait for the Pose preview step. 2. Read Name and tag chips. 3. Tap Publish pose. 4. Repeat with Done instead of Publish | Preview shows the photo with the detected skeleton, the name and the tag chips the user entered, and one primary Publish pose action. Publish pose creates the pose ("Done · added to Poses" in Jobs) exactly once; Done leaves the preview without publishing, and the job stays visible in Jobs so nothing is lost silently | pending: needs `addPose.preview.publishButton`, `addPose.preview.name`, `addPose.preview.tags` |
| TC-JOB-007 | P0 | Signed in, one queued and one processing job | 1. Open Jobs. 2. Read the segmented control. 3. Tap Queued, then Processing, then All | The segmented pill reads "Processing <badge>" / "Finished" with the count only as a badge (F3), the Processing filters are All / Queued / Processing and narrow the list to exactly that group, and the in-progress rows show an indeterminate bar (Processing) or an hourglass (Queued) with no action button | pending: ids landed in 2b01b77 (`jobs.tab.processing.count` with label "<N> running", `jobs.filter.all|queued|processing`); draft ready |
| TC-JOB-008 | P0 | Signed in, one done job and one failed job | 1. Open Jobs > Finished. 2. Tap Done. 3. Tap Failed. 4. Tap Retry on the failed row | The Finished filters read All / Done / Failed; Done rows read "✓ Done · added to Poses" with a chevron that opens the private pose, Failed rows read "Failed · <server reason>" with a plain accent Retry; each filter isolates its group and Retry re-queues exactly that job once, moving it back to Processing as Queued | pending: ids landed in 2b01b77 (`jobs.filter.done|failed`, `jobRow.retry.<jobId>`); the Done row label is "<name>, Done · added to Poses, View pose" |
| TC-JOB-009 | P1 | Signed in, a finished job | 1. Open Jobs > Finished. 2. Swipe the row left and tap **Hide** (eye.slash). 3. Tap the chevron of another Done row | Hide drops the row with **no confirmation dialog** (board 09-05) and without deleting the pose it produced: a Done row still opens its pose through the chevron. The swipe action keeps the id `jobs.row.remove.<jobId>`, the footer explains once that hiding only removes the row from the list, and a failed hide is reported in the bottom snackbar (F5), never a mid-screen alert | pending: `jobs.row.remove.<jobId>` exists (2b01b77); the footer hint and snackbar still need ids (`jobs.footer.hint`, `jobs.snackbar`) |
| TC-JOB-010 | P1 | Long pose name (60+ characters), Accessibility text size | 1. Open Jobs with a long-named job in Processing and Finished. 2. Repeat at AX3 | Names wrap instead of being truncated to "QA consent a…" at default size, the status line stays readable, the segments stay tappable (stacking vertically is fine) and Retry/chevron stay reachable without horizontal scrolling | pending: `jobRow.name.<jobId>` landed in 2b01b77; needs a job whose name is 60+ characters |
| TC-JOB-011 | P1 | superseded by TC-JOB-013 (same state, gap-table copy) — kept for traceability | 1. Load Jobs online. 2. Let one poll fail. 3. Recover | Cached rows stay, an offline banner sits above the list with the recovery copy, and it clears on the next successful poll; the segments and filters keep working on the cached rows | pending: needs `jobs.offline.banner` |
| TC-JOB-012 | P0 | Signed in with (a) no jobs at all, (b) no finished jobs, (c) a filter that matches nothing | 1. Open Jobs with no jobs. 2. With only in-progress jobs, open Finished. 3. With finished jobs, pick a filter with no match | Three **distinct** empty states, not one generic one: empty Processing explains that jobs appear after an upload and offers Add pose; empty Finished explains that results land here and offers to go back to Processing; an empty filter says nothing matches and offers Show all. Each keeps the tabs and filters on screen so the user can leave the state without going Back | pending: actions landed in 2b01b77 (`jobs.empty.viewFinished`, `jobs.empty.goToProcessing`, `jobs.empty.showAll`); the title/body per state still need ids (`jobs.empty.title`, `jobs.empty.body`) |
| TC-JOB-013 | P1 | Signed in, cached rows, then the API becomes unreachable | 1. Load Jobs online. 2. Let a poll fail. 3. Recover | Cached rows stay on screen, the offline banner sits above the list with the recovery copy, in-progress rows additionally say they are waiting for the connection, and both the banner and the per-row state clear on the next successful poll; tabs and filters keep working on the cached rows | pending: banner landed in 2b01b77 (`jobs.offline.banner`, copy "You're offline. Progress resumes when you reconnect."); the per-row waiting state is asserted through `jobRow.name.<jobId>` (label "…, Queued · waiting for connection") |
| TC-JOB-014 | P2 | Signed in; slow or failing job list | 1. Open Jobs on a slow network. 2. Open Jobs when the list request fails | The loading state uses skeleton rows matching the real row geometry (tabs and filters as placeholders too, not live content); a failed list shows the single F4 state (72 pt accent circle, title, body) with a Try again action that re-requests once and recovers | pending: needs `jobs.loading.skeleton` and `jobs.error.retry` |

## Run log (lane-2 CF871F97, run on 1.2 (16), account A)

Run 2026-10-31 19:0x, one flow at a time, photo `xcrun simctl addmedia` + `/tmp/qa-pose.jpg`:

- TC-EXT-003 **PASS** (12 steps, no backend needed).
- TC-EXT-001 **PASS** (consent copy on the closing clause, Cancel, draft kept, sheet asked again, no job row in Processing or Finish).
- TC-EXT-002 **PASS** (Allow → processing surface → one row named after the draft in Finish). Caveat: the production extractor returned **Failed** for this fixture photo, so no *succeeded* job existed afterwards.
- TC-JOB-001 **PASS** (2026-10-31 19:57, one approved real job, provider auth fixed): Add pose → consent Allow →
  job succeeded → Jobs > Finish row "QA finished pose, Ready, View pose" → `jobRow.viewPose.<jobId>` → PRIVATE pose
  detail with `poseDetail.use` visible and `poseDetail.saveButton` absent → the pose is absent from Saved and from
  Community search. Two caveats recorded for Feature: `addPose.viewJobsButton` returns to the Poses home instead of
  opening Jobs (reproduced twice), so the flow uses Done + the More menu; and the job id could not be captured
  (`maestro hierarchy` hung, nothing logged), the row was identified by its pose name.

Harness notes learned in this run (they cost two red runs): `hideKeyboard` fails on this form (no standard
dismiss action) and scrolling is not a substitute for the keyboard-avoidance shift — fill **tags before the
name** so the layout shift happens once, then pin each field's value with an `assertVisible` on the field id;
Maestro's `text` matches the element's whole accessibility text, so partial phrases need `'.*…*'`;
`addPose.viewJobsButton` returned to the Poses home instead of opening Jobs in this build (unconfirmed: could
be a stale-coordinate tap rather than a navigation bug) — the flow uses Done + the More menu instead.

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

## Requests to Feature (1.1 (17) redesign ids)

**Landed in 2b01b77 / 09ef76e:** `jobs.tab.processing`, `jobs.tab.finish`, `jobs.tab.processing.count`
(label "<N> running"), `jobs.filter.all|queued|processing|done|failed`, `jobs.offline.banner`,
`jobs.empty.viewFinished`, `jobs.empty.goToProcessing`, `jobs.empty.showAll`, `jobRow.name.<jobId>`,
`jobRow.retry.<jobId>`, `jobRow.viewPose.<jobId>`, `jobs.row.remove.<jobId>` (now the Hide swipe action).

**Still missing (cases stay pending):** `jobs.footer.hint` (the Hide explanation), `jobs.snackbar`
(hide failure, F5), `jobs.empty.title` / `jobs.empty.body` (per segment/filter copy),
`jobs.loading.skeleton`, `jobs.error.retry`. Jobs:
Add pose: `addPose.choosePhoto`, `addPose.empty.seeJobs`, `addPose.changePhoto`, `addPose.error.title`,
`addPose.error.message`, `addPose.form.helper`, `addPose.description.counter`, `addPose.tags.addTag`,
`addPose.tags.chip.<tag>`, `addPose.preview.publishButton`, `addPose.preview.name`,
`addPose.preview.tags`. Keep the frozen consent ids (`addPose.consent.message/allowButton/cancelButton`).

Open questions for the boards: the design shows a **20 MB** photo limit while the app copy says 10 MB;
the design's Done rows read "added to Poses" while 1.2 (16) reached the pose through the Jobs row — confirm
the chevron opens the same private pose detail. No consent sheet appears in the 08 boards, so the frozen
copy/ids are assumed unchanged.
