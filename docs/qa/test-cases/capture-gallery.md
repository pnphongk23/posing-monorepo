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
| TC-GAL-002 | P0 | Device camera, capture allowed | Capture a photo, then open Gallery | The new photo is the first cell under today's date header, exactly once, and the grid is 3 columns | manual (device: checklist §9) |
| TC-GAL-003 | P1 | Two or more photos | Open the newest photo, swipe forward and back | Each swipe shows the next/previous photo full frame; the header reads **"Photo"** (the screen's name) and the date/time/size live in the caption block under the frame; no "n of N" line; page dots only when there is more than one photo | manual (device: checklist §10; unit: GalleryFeatureTests `testGalleryDetailVoiceOverLabelsCarryNoCount`, `testGalleryDetailPresentationUsesTheBoardV3Contract`, `testGalleryDetailCaptionJoinsDayTimeAndSize`) |
| TC-GAL-004 | P1 | Photo open | Tap Share, then dismiss the system sheet | The tray action shows "Preparing…" while a temporary copy is made, the system share sheet opens with that copy, and dismissing returns to the same photo with the tray usable | manual (device: checklist §10; unit: `testGallerySharePreparationCopiesIntoSystemTemporaryDirectory`, `testGallerySharePreparationReportsMissingSource`) |
| TC-GAL-005 | P1 | At least one photo | Open a photo → Delete → confirm "Delete photo" | The dialog closes, the viewer dismisses, the photo is gone from the grid and its file is removed from disk (no orphan, no ghost row after a relaunch) | manual (device: checklist §10; unit: `testGalleryDeleteSuccessRemovesThePhotoAndRaisesNoToast`) |
| TC-GAL-006 | P1 | Photos spread over more than a week | Tap each filter chip: All, Today, 7 days, 30 days | The grid narrows to the window and is re-bucketed by day; chips show which window is active; no count text appears anywhere | manual (device: checklist §9; unit: `testGalleryDateSectionsRespectTodayTimeFilter`, `testGalleryDateSectionsGroupByDayNewestFirstWithoutLoss`) |
| TC-GAL-007 | P1 | Photo open, Photos access denied | Tap Save | A snackbar above the action tray reports the outcome honestly (saved, or the Photos-permission message); the photo stays open and the tray stays usable | manual (device: checklist §10) |
| TC-GAL-008 | P0 | Photos in the gallery | Inspect the layout on a phone and at a large text size | Exactly one layout: a 3-column grid with 12 pt gaps and 8 pt thumbnail corners. No list mode, no dense grid, no layout toggle anywhere on the screen, and it never reflows to 1 or 2 columns | unit: GalleryFeatureTests (`testGalleryGridPaintsThreeColumns`, `testGalleryGridUsesTheThreeColumnTokenLayout`, `testGalleryGridNeverReflowsForDynamicType`); device visual: checklist §9 |
| TC-GAL-009 | P1 | Photos on several days | Read the section headers above the rows | One header per day above its rows; the label is relative for recent days ("Today", "Yesterday") and "MMM d" otherwise; the header carries the date only — no "n photos" count next to it or next to the title | manual (device: checklist §9; unit: `testGallerySectionLabelsCarryNoCountText`, `testGalleryDateHeaderPaintsTheDateOnly`) |
| TC-GAL-010 | P0 | Clean install, no photos | 1. Open Gallery (All filter). 2. Tap "Today". 3. Tap "All" | All with no photos → the empty panel offers "Open Camera". A time window with no photos → the filter-empty panel ("No photos in this filter", "Try another filter.") with **no** camera action, and the chips stay tappable so All gets back to the camera action | pending — draft: docs/qa/redesign-drafts/gallery-camera/TC-GAL-010-filter-empty-state.yaml (ids committed; ready to promote once a build is named) |
| TC-GAL-011 | P1 | Photo open | 1. Tap Delete → Cancel. 2. Tap Delete → tap the scrim. 3. Tap the "…" options menu → Delete photo | Cancel and a scrim tap both keep the photo and close the dialog; the options-menu Delete opens the same centred dialog with the same copy | manual (device: checklist §10; unit: `testGalleryDeleteConfirmationFollowsTheBoardCopy`, `testDeleteDialogPaintsTheDestructiveActionAboveTheCancel`) |
| TC-GAL-012 | P1 | Remote `extractPoseEnabled` on / off | Read the Gallery header in both states | The header carries the large title and **only** Add pose; Add pose disappears when the remote flag is off (no dead control) and the title stays | unit: GalleryFeatureTests (`testGalleryHeaderOffersOnlyAddPose`, `testGalleryAddPoseIsHiddenByTheRemoteFlag`, `testGalleryHeaderPaintsOnlyTheFlagGatedAddPose`); flag-off end-to-end: TC-EXT-003-extract-flag-off.yaml |
| TC-GAL-013 | P1 | Photo open | Tap Back in the detail header | The viewer closes and the grid is where it was (same scroll, same photo still first); the dock is usable | manual (device: checklist §10) |
| TC-GAL-014 | P1 | A photo whose file is gone from disk | Look at its cell, then open it | The cell shows the failed-photo glyph + "Retry" instead of an empty tile and VoiceOver reads "Couldn't load this photo, …, Retry"; opening it shows the in-frame failure panel ("Couldn't load this photo" / "The photo is missing from this device.") with Retry, which stays reachable at accessibility text sizes | unit: GalleryFeatureTests (`testGalleryCellTapsRetryOnlyWhenThePhotoFailed`, `testGalleryDetailFailurePanelKeepsRetryAtAccessibilitySizes`); device: checklist §10 |
| TC-GAL-015 | P1 | Photo open, delete fails (store error) | Delete and confirm | The failure does not throw the grid away: the photos stay, a snackbar rises above the dock/tray explaining the failure, and it self-dismisses | unit: `testGalleryDeleteFailureKeepsTheGridAndRaisesAToast`; device visual: checklist §10 |
| TC-GAL-016 | P1 | Photos in the gallery, Accessibility text size | Set a large text size (AX3) and reopen Gallery, then open a photo | The grid stays 3-up (cells are photos, not text), the filter chips stack one per row full width, the date headers scale, and the detail tray + delete dialog stay reachable without clipping | unit: GalleryFeatureTests (`testGalleryFilterBarStacksOnlyAtAccessibilitySizes`, `testGalleryFilterChipsStackFullWidthAtAccessibilitySizes`, `testGalleryDetailHeaderReservesSpaceForTheOptionsControl`); device visual: checklist §9–§10 |
| TC-GAL-017 | P1 | Gallery in a failing state (store cannot open) | Open Gallery | One shared state panel under the header ("Couldn't load gallery" + the store's reason + "Try again"), chips stay interactive, and Retry re-runs the load | unit: GalleryFeatureTests (`testGalleryStatePresentationPicksOneSharedStatePerState`, `testGalleryStatePanelsCarryTheQaActionIdentifier`, `testGalleryStatePanelsDrawTheSeventyTwoPointAccentCircle`, `testGalleryLoadFailureSurfacesError`) |
| TC-GAL-018 | P1 | Remote `extractPoseEnabled` on (Add pose visible), device offline | Open Gallery with no network, then repeat with the remote flag off | The offline notice is **honest and scoped**: it appears only because **Add pose** needs a connection — banner title "You're offline. Add pose needs a connection." and message "Your photos are on this device and still open normally." (`gallery.offline.banner`, above the filter chips). The grid is **not** replaced or emptied, every cached photo still opens, and with the flag off (no Add pose action) the banner **never** appears | unit: GalleryFeatureTests (`testGalleryOfflineBannerOnlyAppearsForANetworkBoundAction`, `testGalleryOfflineCopyDoesNotClaimLocalPhotosFail`, `testGalleryStatePresentationNeverReportsOffline`, `testGalleryOfflineBannerPaintsTheWarningSurface`); device visual: checklist §9 — no flow: reachability cannot be forced from Maestro (Requests 7) |
| TC-GAL-019 | P1 | One photo open | Read the block under the framed photo | A caption block (`gallery.detail.caption`, one combined VoiceOver element) that shows the photo's name on its own line, then one meta line "Today · 11:08 · 1.2 MB" — day label relative (Today/Yesterday, else a short date), local time, and the real file size. An unnamed capture drops the name line (the header already says "Photo") and a missing file drops the size instead of inventing one. No photo count anywhere | unit: GalleryFeatureTests (`testGalleryDetailCaptionNamesOnlyNamedPhotos`, `testGalleryDetailCaptionJoinsDayTimeAndSize`, `testGalleryDetailCaptionOmitsAnUnknownSize`, `testGalleryDetailCaptionSizesAreHumanReadable`, `testGalleryDetailCaptionReadsTheRealFileSize`, `testGalleryDetailCaptionRendersNameAboveTheMetaLine`); device visual: checklist §10 — no flow: needs photos in the database (Requests 1) |
| TC-GAL-021 | P1 | Photo open, Add pose available | Tap **Add pose** in the photo-detail tray | The tray (Share · Save · **Add pose** · Delete) opens the Add pose entry from the open photo; without an Add pose destination the tray hides that action instead of shipping a dead control. The publish flow itself is out of scope for 1.1 (TC-EXT-*) | unit: GalleryFeatureTests (`testGalleryDetailTrayCarriesShareSaveAddPoseAndDelete`, `testGalleryDetailTrayHidesAddPoseWithoutADestination`, `testGalleryDetailTrayKeepsTheExistingIdentifiers`); device visual: checklist §10 |
| TC-GAL-020 | P1 | Photos in the gallery | Look for a Star action in the detail caption and a Starred filter chip | **Cut for 1.1** — no model field, no DB column, no service call: the caption draws no star and the filter row has no Starred chip (All / Today / 7 days / 30 days only). Kept as the acceptance target if it is ever built | out of scope 1.1 (cut, no ids; do not delete the idea) |

Notes for triage:
- **TC-GAL-006 replaced the old "favourites" case.** The redesign removed favourites: `GalleryTimeFilter` is
  All / Today / 7 days / 30 days and `GalleryItem` carries no favourite flag, so a favourite-filter case cannot exist
  any more. The id is kept and now covers the time filters. `docs/qa/test-cases/README.md` (lead-owned) needs the row
  relabelled.
- The old "TC-GAL-003 shows `Photo n of N`" expectation is gone on purpose: F3 removed the count line, so the flow
  equivalent (if one is ever written) must assert the *date*, not a number. Page dots replace the counter.

## F4 state coverage for the Gallery (loading / empty / error / offline)
| State | Where it is proven |
|---|---|
| loading | unit: `APLoadingStateView` + `testGalleryStatePresentationPicksOneSharedStatePerState` (`gallery.loading` is the panel id, too transient to assert in a flow) |
| empty (no photos) | TC-GAL-001 (flow) |
| empty (filter window) | TC-GAL-010 (draft flow) |
| error | TC-GAL-017 (unit: panel/action ids, store failure copy) |
| offline (scoped to the network-bound Add pose action) | TC-GAL-018 (unit policy + copy tests; device visual) |
| cell failed (per-photo) | TC-GAL-014 (unit + device) |
| detail failed (per-photo) | TC-GAL-014 (unit + device) |
| detail tray without an Add pose destination | TC-GAL-021 (unit) |

## Re-baseline when the build lands (existing cases whose expected outcome may change)
- **TC-GAL-001** and **TC-GAL-010** — the app keeps the filter chip row visible on every state and the filter-empty
  panel has **no** action; the board hides the chips on empty/error and gives the filter-empty state a "Show all photos"
  action. If either lands, both cases change (and TC-GAL-010's flow gains a tap on that action).
- **TC-GAL-003** and **TC-GAL-013** — **re-baselined at `4ac4ddc`**: the detail header now reads "Photo" (the screen's
  name) and the date/time/size moved into the caption block, so the old "header shows the photo's date" expectation is
  retired. Any device note written against the pre-`4ac4ddc` build is stale on this point.
- **TC-GAL-006** — the shipped filter set is All / Today / 7 days / 30 days (boards show All / This week / **Starred**).
  Stable unless Starred is built, which is out of scope 1.1.
- **TC-GAL-014** — the app replaces the whole frame with the failure panel + Retry, while the board keeps the tray muted;
  if the failed-photo presentation changes, this case's expected changes with it.

## Out of scope for 1.1 (no flows; kept as acceptance targets)
- TC-GAL-020 Star action + Starred filter — **cut** (no model, no DB column, no service call). The tray ships
  Share · Save · Add pose · Delete and the caption draws no star.
- The **Add pose publish** flow behind the tray action (no publish API) — the tray action itself ships and is TC-GAL-021.

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
