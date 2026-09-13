# PLAN — UI-CHANGE-260913 → native iOS sync

Owner: General Lead (Chu Du, `77c1eaa7-40fa-42e7-9e6a-0b3fe7fd9886`), workspace `wks_2e69547344ec0a0b`.
Source of truth: `docs/prototype` at HEAD (`1221622`) + `plans/reports/ui-change-report-260913.md`.
Baseline: `mobile/iosApp` at HEAD (`3a4be1c`, clean tree).

## Intent
Make the native SwiftUI app (`mobile/iosApp`) match the updated prototype/design contract, and prove it
with the mandatory parity gate: `ios-ui-parity-verification` + `maestro-ios-simulator-testing` → PASS.

## Scope (write-set)
- `mobile/iosApp/iosApp/**`, `mobile/iosApp/iosAppTests/**` — implementation.
- `scripts/**`, `docs/prototype/screenshots/reference/**`, `docs/evidence/**` — verification harness/evidence.

## Non-goals
- No web/, backend, API-contract, DB-schema, RevenueCat/Firebase, or release/TestFlight change.
- No Android parity. No new design inventing: `frame-ratio` row in `CameraMorePopup` stays **unresolved**
  (report §3.2 explicit boundary) — do not invent it.
- `pose-guide.html` is now a compatibility redirect; the native guide-picker route is replaced by the
  camera-local pose-picker sheet, not kept as a pushed screen.

## Frozen contract (General Lead, non-negotiable)
`Core/DesignSystem/AIPoseDesignSystem.swift` — `FeatureStateView` gains
`FeatureStateTone { empty, error, loading, offline, success, warning }` and a `tone` parameter; action
becomes `actionTitle: String?` + `action: (() -> Void)?`.
Tone surfaces from `styles/components/empty-state.css`: error `#FFF4F5`; offline+warning `#FED766`
(warning surface); success `#B5E2B9`; loading = white surface with gray copy; empty = white surface.
Structure (map tokens **by value**, not by name — see `tokens.css`): white `#FFFFFF` surface, **1.5pt**
black `#000000` border (`--nb-border-thin` = `--nb-border-width-thin` = 1.5px), radius **10**
(`--nb-radius-medium`), padding **16** (`--nb-space-md`, NOT `AIPoseSpacing.md`=12), gap **8**
(`--nb-space-sm`), bottom margin 8, leading column, title (heading-3) + copy (max 42ch) + optional
action, NO shadow. Copy colour = `#121212` (`--nb-color-dark`); `.loading` container colour is
`#6B7280` (`--nb-color-gray`) while its title stays `#121212`.

**F3 structural ruling (verified against `empty-state.js` + `reference/poses-list-empty.png`).** The
prototype renderer creates only: an optional preserved visual, a `<strong>` title, a `<p>` copy, and an
optional action — **there is no icon**. The component is an **inline, leading-aligned card** at the top
of its content area; it is never a full-screen centred stack (`empty-state.css` sets no centring and no
full height; only `gallery-detail-v2` supplies `data-empty-state-visual`). Therefore:
- `icon` becomes **optional with default `nil`** and MUST be nil on every surface where the prototype
  supplies no `data-empty-state-visual`. A rendered glyph is a divergence on all of them.
- No `.frame(maxWidth:maxHeight: .infinity)` centring inside the component; that is a screen-level
  decision, not a component one.
- Title is **18px bold** (`--nb-type-heading-3-size`), not Swift `.title2` (~22pt); copy is 14px.
- Known cross-render artifact to EXCLUDE: Chrome paints a 1.5px border as 1px, so the 780x1688
  reference shows a ~2 device-px border while the native 1.5pt at 3x normalises to ~3. Declare it
  with both measurements; it is not a defect and not a reason to change the 1.5pt value.
a11y from `scripts/empty-state.js`: `error` → role alert / live assertive; all others → status / polite;
element combined (aria-atomic true).

## Acceptance
- AC1 `FeatureStateView` exposes the 6 tones above and is adopted for every empty/loading/error/offline/
  success/warning surface listed in report §3.5–§3.8 (Search, Pose Detail, Gallery ×3, Saved list,
  pose-detail-saved, account signed-out success, sign-in failure).
  **F2 carve-out (verified by General Lead + DL-B):** `gallery-detail-v2` missing/deleted photo is
  EXEMPT from the tone surfaces. `screens/gallery-detail-v2.html:126-140` re-declares `.empty-photo`
  inline with its own layout (absolute inset 0, grid place-items center, padding 24) and that page uses
  its own local token set (`--ink-muted`, `--surface-muted`, `--surface`) — measured reference shows
  ~48% `#EEE9E1` and **0%** `#FFF4F5`. Per the parity skill's precedence (CSS > rendered PNG > prose),
  report §3.7's "use the shared error state" is a **prototype self-contradiction**; the shared element is
  reused with `preserveVisual`/placeholder geometry and **no** error tone. Native already preserves
  geometry via `GalleryFeature.swift:471-473` — do not add a tone here.
  **Corollary:** judge a warning tone by *magnitude*, never presence — `--nb-color-accent-yellow` and
  `--nb-color-warning-surface` are the same `#FED766`, so every reference carries ~0.2-1% of it.
- AC2 Poses list: single `Poses` title; no `My poses`/`Community` tablist, no `Create Pose`, no visible
  count; two-column staggered published collection; empty state has no personal Create CTA.
- AC3 Camera: no static four-corner framing overlay; More/Camera Tools at lower-right immediately above
  `Choose pose`; `Choose pose` opens a camera-local pose-picker bottom sheet (taller, app-bar Close,
  **no Back**, title `Choose a pose`, local title search, two-column staggered cards, loading/no-match/
  error/offline/clear-search states) that returns to Camera without a pushed route.
- AC4 Camera Tools is an anchored popup (bottom-right, `transform-origin` bottom-right, no scrim/handle/
  app-bar Close), dismiss by outside tap / Escape / local Back with focus returning to More; rows: Flash
  `Off→Auto→On→Off`, Grid toggle, Pose guide show/hide, Opacity 10–100%, Line color Black/White, Clear pose.
- AC5 `xcodebuild -scheme Dev -configuration Debug-Dev` **BUILD SUCCEEDED** and the unit-test suite green
  (or every changed expectation updated with justification).
- AC6 Parity gate: per-screen PASS/FAIL verdicts from real screenshots against regenerated prototype
  references at 390x844pt, with the exact build/device/artifact paths. No global "looks fine".

## Topology (Lead Delegation Gate)
Gate → **delegated path**: ≥2 independent domains, ≥2 lanes each, harness writes are disjoint from app
writes. No Planning Lead: the contract is derived from committed prototype CSS/JS, not open.
- DL-A `Domain Lead · Native UI Sync` → implements the frozen component, then 2 Workers:
  `Lính · Triệu Vân` (Camera surface), `Lính · Quan Vũ` (Poses/Search/Saved/Detail/Gallery/Support).
- DL-B `Domain Lead · Parity Verification` → regenerates references, extends the Maestro flow, runs the
  gate after DL-A hands back. Writes only `scripts/**` + reference shots + evidence.
- General Lead: contract, convergence, freeze candidate, then 2 independent reviewers
  (S≈5, I≈3, U≈3 → R≈11 → 2 lenses: correctness/evidence + architecture/risk).

## Scope boundary — pre-existing divergences (ruled cycle 1, do NOT fix here)
The parity gate reported four gallery/auth divergences that are **real but pre-existing and outside this
change set**. Ruling: report them, do not fix them. Evidence for each:
- **Gallery 3-column grid vs the prototype's 2** (`GalleryFeature.swift` `columnCount = 3` vs
  `components/grid.css:105-108`), **visible `TODAY`/`YESTERDAY` headings** vs the prototype keeping the
  date only in `aria-label` (`app.js:574`), and **4 filter chips vs 5** (no custom-date chip):
  `git diff HEAD -- Gallery/GalleryFeature.swift` contains **zero** changes to `columnCount`, `GridItem`,
  `TODAY`, `YESTERDAY`, `GRD-002` or `GalleryTimeFilter`; the 4-case enum is verbatim at HEAD.
- **Report line 190 is explicit:** "The existing Gallery design remains the owner of list/detail/delete
  behavior; these changes standardize state presentation rather than creating a new Gallery flow."
  So gallery list geometry and chip set are carved out by the report itself.
- **Sign-in scrim not full-bleed** — report 3.8 says "the existing auth navigation is unchanged", and the
  gate itself flags this one as inference-based with no in-slice reference. Not scored.
- **Documentation conflict to surface, not resolve by code:** `SCR-002-01-GRD-002` specifies "3 columns
  with a 3dp gap" while `grid.css:105-108` specifies 2 columns with an 8pt gap. Same shape as F2. The
  prototype CSS remains the parity contract for anything this change touches; the basic-design number is
  the stale artifact. Reported to the user as a divergence, not fixed in this cycle.
A shortfall in TOTAL PASS caused by these is **not** a failed verification — they are recorded as
`PRE-EXISTING DIVERGENCE (out of scope)` in their own section, never as PASS and never as this change's
defect.

## Candidate identity — method (corrected after review cycle 1)
`git diff HEAD -- <path>` **under-reports a candidate: it cannot see untracked files.** Cycle 1's BLOCKER was
mine, not the code's: `PosePickerViewModelTests.swift` was untracked while `project.pbxproj` referenced it
4x, so the recorded code-only hash omitted a file the build requires and a clean checkout would not
compile. Corrected method for every future freeze/commit:

    git add -A -- mobile/            # stage code incl. untracked
    git diff --cached HEAD -- mobile/ | shasum -a 256

Stage rather than hash the working tree, and re-derive the identity after ANY mutation.

## Review cycle 1 (max 2) — frozen identity superseded, candidate re-opened
| Lens | Verdict | Outcome |
|---|---|---|
| architecture/risk | CHANGES_REQUIRED | 5 REQUIRED + 1 NIT; all re-verified by me against code and prototype before routing |
| correctness/evidence | CHANGES_REQUIRED | 1 BLOCKER (the freeze flaw above) + 1 NIT (none required); AC1–AC5 and all token values verified independently by value |

Fixes routed to DL-A as R1–R7: R1 Gallery root top-aligned frame; R2 `PoseDetailView` unavailable path;
R3 `SavedPosesScreen` non-list states; R4 picker tone precedence inverted vs `guide-picker.js:140-149`;
R5 offline must not REPLACE a populated grid (prototype shows a notice above it); R6 **no retry on
`.offline`** — the prototype's offline card has no action, so a retry would create a new parity failure;
reset to `.idle` on dismissal instead; R7 stop the `NWPathMonitor` running from `init` for the camera's
whole lifetime.

## Review cycle 2 — canonical identity (one content, one hash)
Cycle 1 exposed that each lane had derived its own digest for the same tree (`a3d8c8ed`, `dfd1de20`,
`c9211dac`), which is not one immutable identity. Canonicalized to:

    git add -A -- mobile/ && git diff --cached HEAD -- mobile/ | shasum -a 256
    -> 2d62e1374817ca4300b0700250e53caa445b34925fd1fbd5d40800046ca29cec

13 files: 8 production (`project.pbxproj`, `AIPoseDesignSystem`, `AppFeatureRoot`, `CameraFeature`,
`GalleryFeature`, `PosesFeature`, `SignIn`, `SupportScreens`) + 4 tests + the new
`PosePickerViewModelTests.swift` recorded as `A` (added), which resolves cycle 1's BLOCKER structurally.
Frozen component `AIPoseDesignSystem.swift` unchanged at `db80563a...`; every `.xcscheme` byte-identical
to HEAD (`git diff HEAD` and `git diff --cached HEAD` over `xcshareddata/` both empty).
Out-of-scope guard verified: the staged diff contains **no** change to `columnCount`, `GridItem`,
`TODAY`, `YESTERDAY`, `GRD-002` or the `GalleryTimeFilter` cases.

## Review cycle 2 — outcome and the R9–R13 delta
- **architecture/risk: CLEAR.** R1–R8 verified in code; the R8 header rebuild keeps
  `.accessibilityAddTraits(.isHeader)` for VoiceOver, tab-root needs no back button, and pushed
destinations keep their own system/custom headers; monitor lifecycle verified (`guard pathMonitor == nil`
prevents duplicates, serial queue survives `cancel()`, `prepareForDismissal()` calls `stopMonitoring()`).
- **correctness/evidence: CLEAR.** Cycle-1 BLOCKER confirmed resolved from its own inspection
  (`PosePickerViewModelTests.swift` staged as `A`, `git ls-files --others` empty) and confirmed by a
  clean `xcodebuild … build` → `** BUILD SUCCEEDED **`. Q2 evidence preservation verified:
  `AIPoseDesignSystem.swift` byte-identical at `db80563a…` with all six token values exact to
  `tokens.css` (1.5 / 10 / 16 / 8 / 18 / 14), AC2 removals still complete after the header rebuild, F2
  carve-out intact, and `stateTone` precedence now mirroring `guide-picker.js:130-149`.
- **The parity gate then found NEW in-scope defects on a surface that had been NOT JUDGED:** the Search
  empty state. I verified all of them against `app.js:836-851` and by opening
  `reference/search-no-match.png`. Routed as **R9–R13**: title must embed the query; copy must be the
  short prototype string (`Try a different pose name.`) and not a title+instruction concatenation; the
  card must have **no action** when a query is present (the `Clear search` button is an extra control,
  and the prototype passes `null`) while keeping the search field's own clear affordance; the results
  count must be **hidden at zero** (`searchResultsCount.hidden = filtered.length === 0`); the label/ border
  collision resolves when the action is removed.
- **Cycle budget:** R9–R13 is one file, `I≈2`, `U≈1`, verified against unambiguous prototype source, so
  per review-scoring §1 the Lead verifies the delta rather than opening a third review cycle. The
  cycle-2 CLEAR remains valid for the R2/R3 regions of that file; I will confirm the delta touches only
  the search copy/rendering region.

## Round 3 — camera surface verified for the first time (R15–R17)
The parity gate's first camera pass (the flow had produced **zero** shots) returned **6/7 PASS** and found a
**HIGH** defect on the AC3 centrepiece:
- **camera-picker-open FAIL (HIGH).** Panel painted black instead of cream: native **0% `#FBF6EF`** vs reference
  **51%**; title and every card label dark-on-black and illegible. **Root cause (found by the General Lead,
  independently converged on by DL-B):** in `PosePickerSheet.panel` the two `.background` modifiers are
  inverted — chained `.background` puts the later one BEHIND, so the full-size black
  `AIPoseColor.border` shape (offset `y: -shadow`) composites **in front of** the cream
  `AIPoseColor.background` fill and paints the whole panel black. The prototype's `box-shadow: 0 -4px 0`
  must render behind the panel. Routed as **R15**.
- **R16 (LOW):** Flash defaults to `Off`; `camera-live.html:87` ships `Auto`.
- **R17 (LOW):** Grid switch contrast; match the prototype `.nb-switch` rules.
- Verified PASS: camera-live (no framing overlay, More above Choose pose, no dock), camera-tools (anchored
  ~263pt vs 264pt, no scrim/handle/Close, Flash+Grid only with no pose).
- **Still open for AC6:** `gallery-detail-unavailable`, `pose-detail-unavailable`, `sign-in-failure` are
  **NOT JUDGED**; the camera flow types no picker query so R4/R5 are code-verified only; and
  `gallery-filter-empty` was not reached because `Today` is populated on the rig.

## Round 4 — R15-R17 verified fixed; final identity and honest coverage
Identity **`6bdac9e9…`** (14 files). `** BUILD SUCCEEDED **` + 238/0. R15 (panel layer order), R16 (Flash default
`Auto`) and R17 (Grid switch rebuilt from `toggle.css`/`tokens.css`) all verified fixed by measurement and
eyes: panel cream `#FBF6EF` **0% → 19%**, black **28% → 3%** (residual = the required thin shadow), title
and card labels legible dark-on-cream. **camera-picker-open PASS.**
**Opened-and-passing:** poses-list, search-blank, search-no-match, account-signed-out, camera-live,
camera-tools, camera-picker-open, camera-tools-pose. Provenance split across builds and stated per row;
the total is **not** coverage.
**Two General-Lead source verifications — one overturned.**
1. **"Picker search field not addressable" is SUBSTANTIATED as a product/a11y defect. My code-based rebuttal was WRONG.**
   I argued from source that `accessibilityIdentifier("posePicker.search")` sits on the `TextField` itself
   (`CameraFeature.swift:1596`), that no ancestor merges children, and that `search.field`
   (`PosesFeature.swift:811`) resolves elsewhere. DL-B then produced a live
   `maestro hierarchy --compact --no-reinstall-driver` dump on `6bdac9e9` with the sheet open: it exposes
   `resource-id=posePicker.grid`, the card labels, the scroll bar and status bar — and **no element
   matching "search" at all** (no `posePicker.search`, no `Search poses`, no TextField), while those
   **siblings in the same sheet are exposed normally**. That is decisive: not a driver limit, not an
   ancestor merge — the field specifically is absent. My `search.field` counterexample was invalid
   because it is a different TextField in a different (non-sheet) presentation context.
   **Lesson: code inspection can show an identifier is correctly declared; only a runtime dump shows
   whether it is exposed.** Recorded as an open MEDIUM defect (report/AC3 feature "local title search"
   unreachable by VoiceOver and by automation). Routed as **R18**.
2. **R2's top anchor genuinely covers the unavailable branch.** The `.frame(…, alignment: .top)` at
   `PosesFeature.swift:624` encloses the `VStack` holding **both** `if isUnavailable { unavailableState }
   else { detailContent }`. Visual verdict still absent (state undrivable, `:602`).

**R19 — suspected second product defect from the same evidence chain.** Two independent flow revisions
still produce **byte-identical** `05-camera-pose-overlay.png` and `06-camera-tools-pose.png`
(md5 `8abf0a7e…`): the `id: camera.tools` dismiss step reports COMPLETED but does not clear the popup.
AC4 requires dismissal by outside tap / Escape / local Back with focus returning to More, so "reports
COMPLETED but stays open" may be a real AC4 defect. Routed for runtime investigation.

## Final AC4 confirmation — handover from the verification lane (Lead will run this)
DL-B's measurement budget is spent and it stopped without transferring its result by assumption. The fix is
present in source (`toggleCameraTools()` at `CameraFeature.swift:138`, wired at `:594-595`) but its AE
confirmation was taken on `f4b21335` while the tree was still being written, so it is **one identity stale**.
**Exact sequence required (the post-install XCUITest driver flake is real - it hit three consecutive runs):**

    xcrun simctl install <UDID> <app>
    xcrun simctl shutdown <UDID> && xcrun simctl boot <UDID>
    xcrun simctl bootstatus <UDID> -b
    xcrun simctl privacy <UDID> grant camera camerapose.app   # and photos
    ~/.maestro/bin/maestro test scripts/maestro/ui-parity-camera.yaml --device <UDID> --test-output-dir <dir>

Running `install` → `maestro` directly dies at the second tap (`Tap on "Open Camera"` not found) after
`clearState` and the optional `Continue` succeed. That is the documented driver flake, **not** a product
defect - reboot and re-run, do not go looking for a cause in the app.
**The proof is the conjunction of two relations, not either alone:**
- `md5(02-camera-tools.png) != md5(03-camera-tools-dismissed.png)`
- `AE(01-camera.png, 03-camera-tools-dismissed.png) == 0`  (dismissal restores the base state pixel-for-pixel)
**Baselines:** BROKEN on `6bdac9e9` — `02` and `03` both `b645fc4274034651614a4d54d4d11475` (byte-identical).
FIXED on `f4b21335` — four distinct md5s `fa259115ad1ce693b3bc599f2e10ebc6`, `8f6ee78f697c135984d126b44c0b9c46`,
`4dd77f762d7542d8edf18556d115796a`, `6c521e23740e0b9e7153f14de1a6f40c`.
**Flow fix before running:** delete the extra `tapOn: id: camera.tools` between the `Use .* pose` tap and
`takeScreenshot: 05-camera-pose-overlay` - with dismissal working that tap REOPENS the popup and the
`05`/`06` labels end up swapped. Do not relabel by inference; open `06` to settle it.
**Disclosure:** this run is Lead-run on DL-B's harness, device (`8A4AB36C`) and comparison method - it is
**not** a second independent lane, and the report must say so.
**Honesty guards for the final report:** `9/9 PASS` was measured on `6bdac9e9` and is now several
identities behind - label it "not re-measured on the committed identity". `camera-tools-pose` was scored
against the AC4 row contract, **not** its reference PNG.

## Checks
`node --check` on changed JS harness · `xcodebuild ... build` (gate: `** BUILD SUCCEEDED **`) ·
`xcodebuild test` · `scripts/prototype-reference-shots.mjs` · `maestro test scripts/maestro/ui-parity.yaml --device <UDID>` ·
`scripts/compare-prototype-screenshot.sh` + `scripts/measure-ui-parity.py` + eyes-on region checklist.

## AC6 evidence rules (added after Phase 1 exposed two measurement defects)
- **A reference must be positively identified, not merely distinct.** Byte-count, file size and
  hash-distinctness prove nothing about *which state* was captured. Two references were byte-identical
  no-ops (`?state=empty` on gallery, `auth=guest` on pose-detail-saved) and passed the first check.
  Every reference used as a baseline must name the positive observable that identifies its state
  (expected title/copy text present, expected control present/absent).
- **Two distinct NOT VERIFIABLE classes, each with a named substitute check:**
  1. *Prototype-side missing* — the state exists in prototype **code** but is not renderable, so no
     reference can exist. Case: all-empty gallery (`app.js:545-551` defines `No photos yet` /
     `Capture a pose to start your gallery.` / `Open Camera`; unreachable because `filter=all` fixtures
     are never empty and emptying fixtures would edit the frozen prototype). Substitute check: the
     app's screenshot must match the **code-derived** title/copy/action strings, cited by line.
  2. *App-side undrivable* — the prototype reference EXISTS but the app cannot be forced into the
     state. Cases: offline, refresh-error, load-more-error. Substitute check: unit tests on the view
     model.
  Neither class may be reported as PASS (AC6: a PASS requires looking at compared images) and neither
  may be silently dropped.
- **OPERATIONAL HARD LIMIT — max 8 inline images per request.** Exceeding it returns `400
  too_many_images` and kills the run; it already killed L-B1 mid-flight when a packet told it to open
  47 references. Operating cap for this mission is **6 images per request**. No instruction may say
  "open every screenshot": evidence review is either programmatic or split across many requests. This
  binds the freeze reviewers explicitly — an evidence lens must not batch-open the reference set.
- **Evidence standard (upgraded from positive-state-identification, which it subsumes).** State
  identity is asserted **at capture time in code**, not by reading PNGs: each reference declares
  `expectText` / `expectVisible` / `expectAbsent` derived from the prototype's own source, asserted
  against the live page *before* the screenshot, with failures collected and a non-zero exit, so a
  wrong or missing state fails the capture run instead of passing silently. Provenance per manifest row
  is `confirmed-by: dom-asserted | measured | opened | UNCONFIRMED`. This is strictly stronger than a
  human or model reading the image and is immune to the image cap. Tone hexes are asserted separately
  with a magnitude threshold, because `--nb-color-accent-yellow` == `--nb-color-warning-surface`
  (`#FED766`) puts ~0.2-1% of that hex in every reference.
- **F3d `42ch` is not universally observable.** On `poses-list-empty` the card interior is ~351pt,
  narrower than the ~370pt cap, so the cap cannot show itself there. A NIT/OBSERVABLE rule: assert the
  cap only on a reference whose copy is long enough to reach it; otherwise mark it NOT OBSERVABLE. It
  must never produce a false FAIL.
- **Typography authority.** `tokens.css:100-104` gives title **18px** (`--nb-type-heading-3-size`) and
  copy **14px** (`--nb-type-body-size` = `--nb-font-size-base`). Rendered *ink* extents measure smaller
  (~16pt title ink, ~13pt copy ink on the pose-empty card) because ink is not the em size. Reviewers
  compare against the token values, never against an ink measurement.
