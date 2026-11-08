# Capture and gallery (FEAT-001/002)

Redesign reference: F10 (grid only: one 3-column grid, header keeps only Add pose, no counts), F3 (no count text),
F4 (one shared state panel), F5 (bottom snackbar), F1/F2 (one-row detail header with the shared back control).
Source: `GalleryFeature.swift`. The device-only half of this table is mirrored in
`docs/qa/camera-device-checklist.md` §9 (grid) and §10 (photo detail).

A capture needs a real camera, so the Simulator can only show the *empty* and *filter-empty* gallery. Everything that
needs photos in the database is marked `manual (device)` and is walked through in the device checklist; the pure
mapping/geometry/copy behind those screens is asserted in `GalleryFeatureTests.swift` (see the `unit:` rows).

| ID | Pri | Preconditions | Steps | Expected | Automation |
|---|---|---|---|---|---|
| TC-GAL-001 | P0 | Clean install, no photos | 1. Launch. 2. Tap Gallery. 3. Tap the camera shortcut in the empty panel | An empty panel with one action ("Open Camera"); tapping it opens the camera | automated: TC-GAL-001-empty-gallery.yaml |
| TC-GAL-002 | P0 | Device camera, capture allowed | Capture a photo, then open Gallery | The new photo is the first cell under today's date header, exactly once, and the grid is 3 columns | manual (device: checklist §11) |
| TC-GAL-003 | P1 | Two or more photos | Open the newest photo, swipe forward and back | Each swipe shows the next/previous photo full frame; the header reads **"Photo"** (the screen's name) and the date/time/size live in the caption block under the frame; no "n of N" line; page dots only when there is more than one photo | manual (device: checklist §12; unit: GalleryFeatureTests `testGalleryDetailVoiceOverLabelsCarryNoCount`, `testGalleryDetailPresentationUsesTheBoardV3Contract`, `testGalleryDetailCaptionJoinsDayTimeAndSize`) |
| TC-GAL-004 | P1 | Photo open | Tap Share, then dismiss the system sheet | The tray action shows "Preparing…" while a temporary copy is made, the system share sheet opens with that copy, and dismissing returns to the same photo with the tray usable | manual (device: checklist §12; unit: `testGallerySharePreparationCopiesIntoSystemTemporaryDirectory`, `testGallerySharePreparationReportsMissingSource`) |
| TC-GAL-005 | P1 | At least one photo | Open a photo → Delete → confirm "Delete photo" | The dialog closes, the viewer dismisses, the photo is gone from the grid and its file is removed from disk (no orphan, no ghost row after a relaunch) | manual (device: checklist §12; unit: `testGalleryDeleteSuccessRemovesThePhotoAndRaisesNoToast`) |
| TC-GAL-006 | P1 | Photos in the gallery, at least one starred | Tap each filter chip: All, Starred only | The chip set is All / Starred only (the time windows were replaced in design-sync `70d38cfe`). All shows every photo; Starred only narrows to the starred ones and is re-bucketed by day; chips show which filter is active; no count text appears anywhere | manual (device: checklist §11; unit: `testGalleryDateSectionsRespectTodayTimeFilter` (legacy name: it stars today's items and filters `.starred`), `testGalleryDateSectionsGroupByDayNewestFirstWithoutLoss`) |
| TC-GAL-007 | P1 | Photo open, Photos access denied | Tap Save | A snackbar above the action tray reports the outcome honestly (saved, or the Photos-permission message); the photo stays open and the tray stays usable | manual (device: checklist §12) |
| TC-GAL-008 | P0 | Photos in the gallery | Inspect the layout on a phone and at a large text size | Exactly one layout: a 3-column grid with 12 pt gaps and 8 pt thumbnail corners. No list mode, no dense grid, no layout toggle anywhere on the screen, and it never reflows to 1 or 2 columns | unit: GalleryFeatureTests (`testGalleryGridPaintsThreeColumns`, `testGalleryGridUsesTheThreeColumnTokenLayout`, `testGalleryGridNeverReflowsForDynamicType`); device visual: checklist §11 |
| TC-GAL-009 | P1 | Photos on several days | Read the section headers above the rows | One header per day above its rows; the label is relative for recent days ("Today", "Yesterday") and "MMM d" otherwise; the header carries the date only — no "n photos" count next to it or next to the title | manual (device: checklist §11; unit: `testGallerySectionLabelsCarryNoCountText`, `testGalleryDateHeaderPaintsTheDateOnly`) |
| TC-GAL-010 | P0 | Clean install, no photos | 1. Open Gallery (All filter). 2. Tap "Starred only". 3. Tap "Show all photos". 4. Tap "Starred only", then "All" | The chip row is **All / Starred only** — design-sync `70d38cfe` replaced the time windows, so there is no Today/7 days/30 days chip. All with no photos → the empty panel offers "Open Camera" (`gallery.empty.openCamera`, button `gallery.empty.openCameraButton`). Starred with nothing starred → the filter-empty panel ("No starred photos" / "Tap the star on a photo to find it here.") with **no** camera action and one "Show all photos" action (`gallery.empty.showAllPhotos`) that flips the filter back to All; the chips stay tappable, so All is the other way back | automated: TC-GAL-010-filter-empty-state.yaml |
| TC-GAL-011 | P1 | Photo open | 1. Tap Delete → Cancel. 2. Tap Delete → tap the scrim. 3. Tap the "…" options menu → Delete photo | Cancel and a scrim tap both keep the photo and close the dialog; the options-menu Delete opens the same centred dialog with the same copy | manual (device: checklist §12; unit: `testGalleryDeleteConfirmationFollowsTheBoardCopy`, `testDeleteDialogPaintsTheDestructiveActionAboveTheCancel`) |
| TC-GAL-012 | P1 | Remote `extractPoseEnabled` on / off | Read the Gallery header in both states | The header carries the large title and **only** Add pose; Add pose disappears when the remote flag is off (no dead control) and the title stays | unit: GalleryFeatureTests (`testGalleryHeaderOffersOnlyAddPose`, `testGalleryAddPoseIsHiddenByTheRemoteFlag`, `testGalleryHeaderPaintsOnlyTheFlagGatedAddPose`); flag-off end-to-end: TC-EXT-003-extract-flag-off.yaml |
| TC-GAL-013 | P1 | Photo open | Tap Back in the detail header | The viewer closes and the grid is where it was (same scroll, same photo still first); the dock is usable | manual (device: checklist §12) |
| TC-GAL-014 | P1 | A photo whose file is gone from disk | Look at its cell, then open it | The cell shows the failed-photo glyph + "Retry" instead of an empty tile and VoiceOver reads "Couldn't load this photo, …, Retry"; opening it shows the in-frame failure panel ("Couldn't load this photo" / "The photo is missing from this device.") with Retry, which stays reachable at accessibility text sizes | unit: GalleryFeatureTests (`testGalleryCellTapsRetryOnlyWhenThePhotoFailed`, `testGalleryDetailFailurePanelKeepsRetryAtAccessibilitySizes`); device: checklist §12 |
| TC-GAL-015 | P1 | Photo open, delete fails (store error) | Delete and confirm | The failure does not throw the grid away: the photos stay, a snackbar rises above the dock/tray explaining the failure, and it self-dismisses | unit: `testGalleryDeleteFailureKeepsTheGridAndRaisesAToast`; device visual: checklist §12 |
| TC-GAL-016 | P1 | Photos in the gallery, Accessibility text size | Set a large text size (AX3) and reopen Gallery, then open a photo | The grid stays 3-up (cells are photos, not text), the filter chips stack one per row full width, the date headers scale, and the detail tray + delete dialog stay reachable without clipping | unit: GalleryFeatureTests (`testGalleryFilterBarStacksOnlyAtAccessibilitySizes`, `testGalleryFilterChipsStackFullWidthAtAccessibilitySizes`, `testGalleryDetailHeaderReservesSpaceForTheOptionsControl`); device visual: checklist §11–§12 |
| TC-GAL-017 | P1 | Gallery in a failing state (store cannot open) | Open Gallery | One shared state panel under the header ("Couldn't load gallery" + the store's reason + "Try again"), chips stay interactive, and Retry re-runs the load | unit: GalleryFeatureTests (`testGalleryStatePresentationPicksOneSharedStatePerState`, `testGalleryStatePanelsCarryTheQaActionIdentifier`, `testGalleryStatePanelsDrawTheSeventyTwoPointAccentCircle`, `testGalleryLoadFailureSurfacesError`) |
| TC-GAL-018 | P1 | Remote `extractPoseEnabled` on (Add pose visible), device offline | Open Gallery with no network, then repeat with the remote flag off | The offline notice is **honest and scoped**: it appears only because **Add pose** needs a connection — banner title "You're offline. Add pose needs a connection." and message "Your photos are on this device and still open normally." (`gallery.offline.banner`, above the filter chips). The grid is **not** replaced or emptied, every cached photo still opens, and with the flag off (no Add pose action) the banner **never** appears | unit: GalleryFeatureTests (`testGalleryOfflineBannerOnlyAppearsForANetworkBoundAction`, `testGalleryOfflineCopyDoesNotClaimLocalPhotosFail`, `testGalleryStatePresentationNeverReportsOffline`, `testGalleryOfflineBannerPaintsTheWarningSurface`); device visual: checklist §11 — no flow: reachability cannot be forced from Maestro (Requests 7) |
| TC-GAL-019 | P1 | One photo open | Read the block under the framed photo | A caption block (`gallery.detail.caption`, one combined VoiceOver element) that shows the photo's name on its own line, then one meta line "Today · 11:08 · 1.2 MB" — day label relative (Today/Yesterday, else a short date), local time, and the real file size. An unnamed capture drops the name line (the header already says "Photo") and a missing file drops the size instead of inventing one. No photo count anywhere | unit: GalleryFeatureTests (`testGalleryDetailCaptionNamesOnlyNamedPhotos`, `testGalleryDetailCaptionJoinsDayTimeAndSize`, `testGalleryDetailCaptionOmitsAnUnknownSize`, `testGalleryDetailCaptionSizesAreHumanReadable`, `testGalleryDetailCaptionReadsTheRealFileSize`, `testGalleryDetailCaptionRendersNameAboveTheMetaLine`); device visual: checklist §12 — no flow: needs photos in the database (Requests 1) |
| TC-GAL-021 | P1 | Photo open, Add pose available | Tap **Add pose** in the photo-detail tray | The tray (Share · Save · **Add pose** · Delete) opens the Add pose entry from the open photo; without an Add pose destination the tray hides that action instead of shipping a dead control. The publish flow itself is out of scope for 1.1 (TC-EXT-*) | unit: GalleryFeatureTests (`testGalleryDetailTrayCarriesShareSaveAddPoseAndDelete`, `testGalleryDetailTrayHidesAddPoseWithoutADestination`, `testGalleryDetailTrayKeepsTheExistingIdentifiers`); device visual: checklist §12 |
| TC-GAL-022 | P1 | Signed in, `extractPoseEnabled` on | Gallery tab → tap **Add pose (+)** in the header | The **Add pose form** opens directly (`addPose.title` + `addPose.photoPicker`) and **no** sign-in prompt is shown (`signin.emailEntry` / `signin.apple` absent) — a signed-in user is never asked to sign in again | automated: TC-GAL-022-gallery-add-pose-signed-in.yaml |
| TC-GAL-023 | P1 | Signed in, at least one photo in the gallery | Open a photo → tap **Add pose** in the detail tray | The **Add pose form** opens directly from the photo and **no** sign-in prompt appears — the tray entry behaves exactly like the header one | pending — draft: …/TC-GAL-023-photo-detail-add-pose-signed-in.yaml (**seed/device-dependent**: the form needs a gallery photo and the app has no gallery seed — on the Simulator a capture fixture is required, otherwise this is device-only) |
| TC-GAL-024 | P1 | Signed out, `extractPoseEnabled` on | Gallery tab → tap **Add pose (+)** | Signed out the prompt is correct: a sign-in affordance appears (`signin.emailEntry` / `signin.apple`) and the Add pose form does **not** (`addPose.photoPicker` absent). This is the counterpart that must keep working once camera-18-06 is fixed | pending — draft: …/TC-GAL-024-gallery-add-pose-signed-out.yaml (held for dev19; credential-free) — bug context: camera-18-06 |
| TC-GAL-020 | P1 | Photos in the gallery | Look for a Star action on the open photo and a Starred filter chip | **Shipped in design-sync `70d38cfe`** (it was cut, then built): the open photo carries Star (`gallery.detail.star`) and the filter row carries a Starred chip (`gallery.filter.starred`). Star is stored on the device only (`GalleryStarStore`, UserDefaults key `gallery.starredPhotoIDs`) — there is no model field, DB column or service call, so the star does not follow the account across devices | no flow: needs a real photo in the gallery (device: checklist §12; unit: `testGalleryDateSectionsRespectTodayTimeFilter`) |

Notes for triage:
- **TC-GAL-006 replaced the old "favourites" case.** `GalleryTimeFilter` is now All / Starred only (design-sync
  `70d38cfe` swapped the time windows for the starred filter; `GalleryItem` still carries no favourite flag, the star
  lives in `GalleryStarStore` on the device). The id is kept and covers the filters.
- **Filter history, so older notes can be read correctly:** the set was All / Today / 7 days / 30 days until
  `70d38cfe`. Any note that mentions a Today / 7 days / 30 days chip, `gallery.filter.today` or `gallery.filter.week`
  is pre-design-sync and stale.
- The old "TC-GAL-003 shows `Photo n of N`" expectation is gone on purpose: F3 removed the count line, so the flow
  equivalent (if one is ever written) must assert the *date*, not a number. Page dots replace the counter.

## F4 state coverage for the Gallery (loading / empty / error / offline)
| State | Where it is proven |
|---|---|
| loading | unit: `APLoadingStateView` + `testGalleryStatePresentationPicksOneSharedStatePerState` (`gallery.loading` is the panel id, too transient to assert in a flow) |
| empty (no photos) | TC-GAL-001 (flow) |
| empty (filter: starred, nothing starred) | TC-GAL-010 (flow) |
| error | TC-GAL-017 (unit: panel/action ids, store failure copy) |
| offline (scoped to the network-bound Add pose action) | TC-GAL-018 (unit policy + copy tests; device visual) |
| cell failed (per-photo) | TC-GAL-014 (unit + device) |
| detail failed (per-photo) | TC-GAL-014 (unit + device) |
| detail tray without an Add pose destination | TC-GAL-021 (unit) |

## Re-baseline when the build lands (existing cases whose expected outcome may change)
- **TC-GAL-001** and **TC-GAL-010** — **landed, re-baselined for design-sync `70d38cfe`**: the app keeps the filter chip
  row visible on every state (board hides it), and the filter-empty state *did* gain a "Show all photos" action
  (`gallery.empty.showAllPhotos`). TC-GAL-010's flow now taps that action as one way out, and taps the All chip as the
  other. The old expectation ("the filter-empty panel has no action") is retired.
- **Filter-empty copy** — it is now "No starred photos" / "Tap the star on a photo to find it here.", not "No photos in
  this filter" / "Try another filter.". Any note quoting the old copy is pre-`70d38cfe`.
- **TC-GAL-003** and **TC-GAL-013** — **re-baselined at `4ac4ddc`**: the detail header now reads "Photo" (the screen's
  name) and the date/time/size moved into the caption block, so the old "header shows the photo's date" expectation is
  retired. Any device note written against the pre-`4ac4ddc` build is stale on this point.
- **TC-GAL-006** — the shipped filter set is All / **Starred only** since `70d38cfe` (it was All / Today / 7 days /
  30 days). The board's "This week" is not built and the time windows are gone, so a time-window case cannot exist any
  more.
- **TC-GAL-014** — the app replaces the whole frame with the failure panel + Retry, while the board keeps the tray muted;
  if the failed-photo presentation changes, this case's expected changes with it.

## Out of scope for 1.1 (no flows; kept as acceptance targets)
- TC-GAL-020 Star action + Starred filter — **no longer cut**: both shipped in design-sync `70d38cfe`. It stays
  flow-less only because it needs a real photo (Requests 1).
- The **Add pose publish** flow behind the tray action (no publish API) — the tray action itself ships and is TC-GAL-021.
- TC-GAL-022/023/024 stay **drafts** until dev19: they cover the user-found defect camera-18-06 (Gallery → Add pose asked a
  signed-in user to sign in) for both entry points and both states.

## Requests to Feature (via the QA lead)
1. A Debug-only gallery fixture launch argument (for example `-AIPoseGalleryFixture 12` with a spread of
   `createdAt` days) would make the grid, the long grid, the filters and the whole photo detail automatable on the
   Simulator. Today a photo only exists after a real capture, so §TC-GAL-002…007/009/011/013 are device-only.
2. `gallery.grid` (grid container) and a per-cell identifier (`gallery.cell.<index>` or the photo id). Cells carry a
   VoiceOver label only, so a flow can neither assert "the grid is drawn" nor tap a specific photo.
3. `gallery.detail.media` on the pager page (it carries the label "Photo" but no id) — the only way to prove the
   viewer is showing the photo rather than a placeholder.
4. `gallery.toast` on the photo-detail snackbar (share / save / delete failures go through the shared `.apSnackbar`,
   which adds no identifier), so "the failure rides a snackbar above the tray" is assertable.
5. Identifiers on the options-menu items (`gallery.detail.options.delete`), so the second path to the delete dialog is
   tappable without matching the "Delete photo" text that also exists on the tray and in the dialog.
6. `dock.gallery` — the dock tab has a label but no identifier (already logged as `TODO(QA-261029-ID)`).
7. Landed at `4ac4ddc`: `gallery.offline.banner`, `gallery.detail.caption`, `gallery.detail.addPose` (and the tray keeps
   `gallery.detail.share/save/delete`; the empty/error ids are unchanged). Still needed for TC-GAL-018 to be a flow: a
   Debug seam that forces the offline reading (the real one is `NWPathMonitor`, which Maestro cannot drive), e.g.
   `-AIPoseForceOffline YES` on the Gallery's reachability model.
8. The caption is one combined accessibility element, so a flow could assert it by id — but it still needs a photo in the
   database (request 1). If the caption ever splits into a name line and a meta line as separate elements, give them
   their own ids (`gallery.detail.caption.title` / `.meta`) instead of matching a formatted date string.
9. If the filter-empty state gains the board's "Show all photos" action, it needs `gallery.empty.filter.showAll` (and
   TC-GAL-010 gets a second path).
