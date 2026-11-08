# qa-stale-ids — two flows pointed at ids the design sync removed

Goal: TC-GAL-010 and TC-SET-013 still referenced ids that no longer exist on `main` @ `9886cb34`
(design sync `70d38cfe`). Branch `qa/b23-prep`. Owner `9a1c304`, 2026-11-08.

## What was stale, and what the code actually ships

| Flow | Stale reference | Reality on `main` 9886cb34 |
|---|---|---|
| TC-GAL-010 | `gallery.filter.today`, `gallery.filter.week` | `GalleryFeature.swift:119-131` — `GalleryTimeFilter` is `all` + `starred` only, so the ids that exist are `gallery.filter.all` / `gallery.filter.starred`. |
| TC-GAL-010 | "filter-empty panel has no action" | It has one: `GalleryStateCopy.showAllPhotosButtonIdentifier` = `gallery.empty.showAllPhotos` (`GalleryFeature.swift:156, 415, 851-855`), wired to `model.timeFilter = .all` (`:792`). The doc had predicted this change ("if either lands, both cases change"). |
| TC-SET-013 | `assertNotVisible: about.contact` | No such id was ever built — `SettingsScreen.swift:589` says the row is deliberately not built, and `grep` for `about.*` finds only `version/terms/privacy/licences/close/title`. |

Cross-check: all 13 ids the two flows now assert exist in the app source; `check-traceability.sh`
is green (69 flows).

## Fix

- `TC-GAL-010`: taps `gallery.filter.starred`, then proves **both** ways back — the panel action
  `gallery.empty.showAllPhotos` and the `gallery.filter.all` chip — and still asserts the camera
  action never appears in the filter-empty state.
- `TC-SET-013`: the "no Contact support row" guard is now by **label** (`"Contact support"`), because
  the id cannot exist. A negative assertion on a non-existent id passes without testing anything.
- Docs re-baselined (`capture-gallery.md`, `settings.md`): filter set All / Starred only, the
  filter-empty copy ("No starred photos" / "Tap the star on a photo to find it here."), the show-all
  action, and TC-GAL-006 / TC-GAL-020 retired from the "cut for 1.1" wording since the starred
  filter and the Star action shipped.

## Verification — actually run, not just parsed

Dev build of `main` @ `9886cb34` (build 25) on simulator `7CC9393C-88FC-4AE6-88D3-AC68A2E266B7`
(`xcodebuild -scheme Dev -derivedDataPath /tmp/dd-shared build` → **BUILD SUCCEEDED**,
`simctl install` → installed `CFBundleVersion = 25`).

| Case | Result | Evidence |
|---|---|---|
| TC-GAL-010 | **PASS** (19/19 steps `COMPLETED`) | `reports/TC-GAL-010-filter-empty-state.png` |
| TC-SET-013 | **PASS** (12/12 steps `COMPLETED`, incl. `Assert that "Contact support" is not visible`) | `reports/TC-SET-013-about-sheet.png` |

Both runs: `maestro/run.sh <udid> flows/<file>` with `SHOTS_DIR` outside the repo (one Maestro run at
a time; nothing else was running on `7CC9393C`).

## Notes for the next lane

- `gallery.empty.filter` copy and the show-all action are the contract now; a note quoting
  "No photos in this filter" / "Try another filter." is pre-`70d38cfe`.
- `GalleryStatePresentation.kind` carries a stale comment ("the filter-empty state stays actionless")
  that contradicts its own `emptyFilter` branch. Source change, out of scope for a QA-id goal — left
  alone deliberately.
- The gallery doc's "Requests to Feature" still asks for `gallery.grid` / per-cell ids; TC-GAL-002…
  007/009/011/013 stay device-only until a Debug gallery fixture exists.
