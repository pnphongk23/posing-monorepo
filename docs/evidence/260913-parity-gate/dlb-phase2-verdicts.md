# CYCLE 2 — FINAL RE-MEASURE (identity `613dbe859a692471f5469687e9dd584d139ce1c53b08fa41a10d343a8b65847f`)

Identity computed with the General Lead's canonical command and **matched exactly** before any scoring
(14 files staged, 0 untracked). Frozen component `db80563a…` unchanged; every `.xcscheme` byte-identical
to HEAD. R9-R13 present (`No poses match` ×2); R14 dead `emptyIcon` gone (0 repo hits).

BUILD: SUCCEEDED (35s, 0 `error:`), installed on the same rig. Main flow now exits **0** with 68 steps
COMPLETED and zero FAILED, producing 17 shots in `/tmp/f3-out/screenshots/`.

## Cycle-1 in-scope defects — both FIXED and verified

**Poses header (R8) — PASS.** Measured on the final build: header ink band `y=113..178`, **h=66 px**, single
row, `x=35..748` — versus the reference's `y=112..178`, h=67, `x=39..734`. It is now **one row** (cycle 1:
two rows, 158 px) and the title is **left-aligned at the margin** (cycle 1: centred, ink `x=345..435`,
centre 390 = frame centre). Opened and confirmed: no tablist, no Create Pose, no count; grid loaded; dock
with Poses active. The 4 px band-origin delta is the frame-border/stroke offset already decomposed.

**Search empty state (R9-R13) — PASS, all four rows flipped.** Opened the device and the settled capture:
title `No poses match "zzzz"` (embeds the query, curly quotes), copy `Try a different pose name.`,
**no action button**, and the results count **hidden at zero**. H6a/H6b/H6c/H6d all PASS (cycle 1: static
`No poses found`, concatenated copy, a `Clear search` button, a `0 poses` count). Chips and dock unchanged.

**Account signed-out (AC1 success tone) — PASS.** Newly reachable: the rig is unauthenticated so this IS the
default state (`SupportScreens.swift:84` renders `Sign out` only when `.signedIn`). Opened: success surface
`#B5E2B9`, **no glyph** (F3a), top-anchored leading-aligned inline card (F3b), `Signed out` + copy
`Sign in again to access your Saved poses.` verbatim from `account.js:24`, **no action on the card** (correct),
`Continue with Google` below. Measured success tone **7.03%** of frame vs the reference's **8.12%**.

## Harness defects found and fixed this cycle (mine, not product)

1. `extendedWaitUntil: visible: "No poses match"` never matched although the text was on screen — **Maestro
   full-matches the concatenated accessibility label, so a substring regex can never match**. Correct form
   `.*No poses match.*`. Without this I would have reported a false FAIL on a correct screen.
2. `04-search-no-match` had captured the **transient debounced loading state** (`Searching…`), not the
   no-match card. Added a wait for the settled state before the screenshot.
3. A stale `tapOn "Sign out"` failed on a **correct** screen — the account is already signed out here. Replaced
   with an assertion on the signed-out state, so the run proves the state instead of the tap.
4. (cycle 1) `[0-9]+ poses?` awaited a count AC2 deliberately removed.

## Final 1.5px border measurement — THIS build

| | card left border (780-wide normalisation) |
|---|---|
| REFERENCE `search-no-match.png` | **2 px** (`x=36..37`, pure `(0,0,0)`) |
| NATIVE final build `04-search-no-match.png` | **3 px** (`x=31..33`) |

The native figure is unchanged from cycle 1 at **3 px**, now re-measured on this build rather than reused;
the analytic 1.5 pt × 3 ÷ 1.5 = 3.0 px prediction is confirmed by measurement.


## CYCLE 2 FINAL — CAMERA / AC3-AC4 PASS (the previously uncovered surface)

Only 4 camera shots were obtainable; the flow then failed on a picker-card selector. Judged from opened
images on identity `613dbe85…`.

**camera-live — PASS.** No four-corner framing overlay (matches the reference, and `camera-viewport.css`
has 0 `framing|bracket|corner` rules). More/`⋮` sits lower-right **immediately above** the `Choose pose`
blue chip. Zoom `1x` centred at the viewport bottom; `#FBF6EF` shutter rail with a 2 pt top border,
thumbnail left / pink shutter centre / flip right. **No dock.** Excluded: the black camera-feed region
(simulator has no camera) and the empty thumbnail (fresh `clearState` — no captured photos).

**camera-tools — PASS.** Popup anchored **bottom-right, right-aligned with More and directly above it**;
measured width ~**263 pt** vs the required ~264 pt; fill `#121212`; 2 pt border; hard shadow; **no scrim,
no handle, no app-bar Close**; rows **Flash + Grid only** with no pose selected (row C10 holds).
Two LOW observations, both stated as measured-or-seen and not measured precisely:
  1. Flash default renders `Off` where the frozen reference shows `Auto` (`camera-live.html` fixture
     `#flash-value` = `Auto`). AC4 lists the cycle as `Off→Auto→On→Off` but does not pin the default, so
     I record the divergence and flag the ambiguity rather than call it a hard FAIL.
  2. The Grid switch reads as a very low-contrast white pill + white knob against the white row; the
     reference switch has a visible outline. Not measured to precision.

**camera-picker-open — FAIL (HIGH).** The sheet's panel does not paint `--nb-color-bg`. Measured in the
panel region: **reference `camera-picker-open.png` = `#FBF6EF` 51%** (+ `#FFFFFF` 42%); **native = 0%
`#FBF6EF`**, dominated by `#FFFFFF` 63% and **`#000000` 28%**. So the panel background is black where
`camera-guide.css:41-66` sets `background-color: var(--nb-color-bg)` = `#FBF6EF`.
Consequence, seen in the opened image: the title `Choose a pose` and every pose card label
(`Pose Compilation 13 - Block Side-Sit`, …) render **dark-on-black and are effectively illegible**.
Geometry is otherwise correct — the sheet is a bottom sheet over the still-visible camera, top corners
radius `22/22/0/0`, `42x4` handle present, title at left, **Close on the right with NO Back button**
(AC3 met), local search field with magnifier, and a 2-column staggered masonry. I did not pin the exact
line in `CameraFeature.swift` within budget.

**NOT VERIFIABLE — harness (raw error, rows not filled in):**
`camera-pose-overlay` and `camera-tools-pose` — the camera flow died at
`Tap on "Use .* as guide" → Element not found: Text matching regex: Use .* as guide` after
`04-pose-picker`, so no pose was ever applied and the pose-guide rows were never reached.
`camera-picker-loading` / `-no-match` / `-error`, and **R4/R5** (offline/no-match precedence) — never
driven: the camera flow does not type a picker query, and offline has no simulator toggle.
`gallery-filter-empty` — the flow ran green (exit 0) but `Today` is **populated** on this rig
(`#FBF6EF` 72.9%, tiles rendered), so the empty state was never reached; the shot is a populated
filtered grid and is not scoreable as the filter-empty reference.

Candidate (verified unmoved before scoring, 2026-09-14):
- full tracked diff `651c7eeed7d41e38dc99a587ec9d5ecf1e9c418f01e88f2c49d4611fdf10839b`
- code-only `mobile/**` `a3d8c8ed487f1f55fc6e8ab6430db05e032bd646c1e9f0b063fbc238c90829ed`
- 17 changed tracked files, 51 untracked (`git status -uall`)
- frozen component `AIPoseDesignSystem.swift` `db80563a45092ea2ad76610576f175610870e8cad1aa24444437eb9c24d0a960`

BUILD: SUCCEEDED — `xcodebuild -project iosApp.xcodeproj -scheme Dev -configuration Debug-Dev
-destination "platform=iOS Simulator,id=8A4AB36C-68D4-499E-B749-B56C9BC0B75A" -derivedDataPath /tmp/dd-dl-b build`
→ `** BUILD SUCCEEDED **`, exit 0, 1m48s, zero `error:` lines.

DEVICE: `DL-B-Parity-iPhone13` `8A4AB36C-68D4-499E-B749-B56C9BC0B75A` (iPhone 13, 390x844 pt, iOS 26.1).
Dedicated to this lane; `privacy grant camera|photos camerapose.app` applied before driving.

Post-F3 gate satisfied before any state-surface scoring: `FeatureStateView` declares exactly
`tone / title / message / actionTitle / action` — **no icon parameter** — and a repo grep for `icon:`
passed to `FeatureStateView(` returns **0**. The binary was built from this tree, not inherited.

## Screens

### POSES LIST — FAIL

Severity: **high** (top-level screen, AC2/parity header). Reference
`docs/prototype/screenshots/reference/poses-list.png`; actual
`/tmp/parity-out/<run>/screenshot-*.png` (1170x2532 @3x → normalised to 780x1688).

- checklist P2 PASS — **no** `My poses`/`Community` tablist, **no** Create Pose, **no** visible count.
  Verified visually: the app renders only `Poses` plus the 4 actions, and the grid loads 8+ real poses
  (`Pose Compilation 13 - Block Side-Sit`, `… 12 - Compact Curl`, `… 11 - Stair Knee Hug`, `… 10 - Bench
  Drape`, `… 04 - Knees Tucked`, `… 08 - Chair Knee Up`). The old `23 poses` count is gone.
- checklist P1 **FAIL** — title alignment and row structure, measured by ink-column profile:

  | | band | title ink | actions ink | rows |
  |---|---|---|---|---|
  | REFERENCE | `y=112..178` (h=**67** px) | x=**39**..146 (left-aligned) | x=392..734 | **one** row — title and actions share the band |
  | NATIVE | title `y=125..149`, actions `y=217..282` | x=345..435, centre **390 = frame centre** | x=467..748 | **two** rows; header span `y=125..282` = **158** px |

  So the app renders the title **centred in a system nav bar** (`.navigationTitle("Poses")` +
  `.navigationBarTitleDisplayMode(.inline)`, `PosesFeature.swift:341-342`) with the 4 actions on a
  **separate lower row**, while the prototype has a single row with the title **left-aligned**
  (`styles/components/nav-bar.css:69` `.nb-nav-bar--poses { text-align: left }`).
  Consequence: the header is ~45 pt taller and the grid starts at `y=298` instead of `y=212`.
- checklist P3 PASS — 4 header actions present (crown/search/bookmark/gear); measured widths
  reference 67 px vs native 66 px ≈ 33.5 vs 33 pt.
- checklist P6 PASS (geometry) — first pose card left border measured **4 px thick in both**
  (reference `x=36..39`, native `x=30..33`); see the border/inset note under EXCLUDED.

Root cause of the FAIL, stated precisely: `PosesFeature.swift:305-308` keeps a **two-row** header on
purpose, justified in its own comment by a width calculation that assumed the three category pills
(`My poses`/`Community`/…) were still present ("three category pills (297.7pt) plus four 32pt actions
(140pt) … 358pt available"). AC2 removed those pills, and the frozen reference proves a **single row**
fits at 390 pt. The comment is stale and the layout was never simplified after the tabs were removed.

### GALLERY (root) — FAIL

Severity: **high** (top-level tab; structural). Reference `gallery.png`; actual `/tmp/parity-out/screenshots/10-gallery.png`.

Measured by tile-run detection at two rows (780-wide normalisation):

| | y | tile runs | column width | internal gutter |
|---|---|---|---|---|
| REFERENCE | 440 and 500 | **2** — (36..381), (398..743) | ~345 px = 172.5 pt | **17 px ≈ 8 pt** |
| NATIVE | 411 and 471 | **3** — (30..268), (271..508), (511..749) | ~238 px = 119 pt | **~3 px ≈ 1.5 pt** |

- checklist G-grid **FAIL** — **3 columns where the prototype has 2**, and a ~1.5 pt gutter where the
  prototype has **8 pt** (`components/grid.css:105-108` `.nb-gallery-grid { column-count: 2; column-gap:
  var(--nb-space-sm) }`). Wrong column count is an always-a-FAIL row.
- checklist G-absence **FAIL** — the native renders visible **`TODAY` / `YESTERDAY`** section headings.
  The prototype renders no such text: `app.js:574` uses `dateLabel` only inside the item's
  `aria-label`, never as visible content, and the reference shows no headings.
- checklist G1 **FAIL** — the native filter row has **4** chips (`All`, `Today`, `7 days`, `30 days`);
  the prototype has **5**, the last being the custom-date chip (`Date`, relabelled `Jan 1` when active
  — `app.js:523`). **Absence defect.**
- PASS: title `Gallery` left-aligned, crown top-right, `All` chip active, dock present with **Gallery** active.

**Root cause is a spec-vs-prototype conflict, not guesswork — flagging for a scope ruling.**
`GalleryFeature.swift:561-563` reads "`SCR-002-01-GRD-002` fixes 3 columns with a 3dp gap" and sets
`columnCount = 3`. A Basic Design document mandates 3 columns; the frozen prototype CSS and its
rendered reference show 2. Precedence is **CSS > rendered PNG > prose/design doc**, so parity FAILs —
but the app author followed a written spec, so this needs a General-Lead ruling on which artifact is
the contract, exactly like F2. Cheapest check whether this is a regression from UI-CHANGE-260913 or
pre-existing: `git log -S columnCount -- mobile/iosApp/iosApp/Features/Gallery/GalleryFeature.swift`.

### SAVED LIST — NOT VERIFIABLE (no credentials) + one scrim FAIL

`/tmp/parity-out/screenshots/09-saved-list.png` is **not** the saved list: the app gates Saved behind
sign-in and the capture shows the **Sign in** sheet over a white screen (`saved.signIn`,
`PosesFeature.swift:1107-1108`). The populated reference `saved-list.png` is therefore unreachable —
see NOT VERIFIABLE below.

- checklist V6-scrim **FAIL** — measured scrim extent: **reference `sign-in-failure.png` covers
  y=4..1683 (essentially the full frame, 954 matching rows)**; the **native scrim covers only y=637..1184
  (91 matching rows)** — a middle band, not full-bleed. The modal overlay must cover the phone frame.
  Inference stated explicitly: the default sign-in prompt has no dedicated in-slice reference, but the
  scrim belongs to the shared `nb-modal-overlay`, whose full-bleed geometry is evidenced by
  `sign-in-failure.png` where the error state renders inside that same overlay.
- PASS: modal card styling — white surface, 2 pt border, hard shadow, title `Sign in`, copy
  `View your saved poses.`, pink `Continue with Google`, white `Not now`.

### SEARCH — blank state PASS on the rows checked

`/tmp/parity-out/screenshots/02-search-blank.png` vs `search-blank.png`.

- checklist H1 PASS — `Recent searches` heading + 3 chips `Dancing` / `Stretching` / `Warrior`.
- checklist H2 PASS — back control left; ink band measured `x=36..453` (reference) vs `x=30..453`
  (native) — the 6 px left delta is the same frame-border/stroke offset already decomposed.
- checklist H5 PASS — **dock present with NO active pill** (both items plain), matching the prototype's
  `initTabBar(null)` for search.
- Search field present with leading magnifier and `Search poses` placeholder.

### SEARCH no-match — FAIL (fully in scope: AC1 / report §3.5)

`/tmp/parity-out/screenshots/04-search-no-match.png` vs `search-no-match.png`. Both opened.

| # | Check | Prototype (reference) | Native | Verdict |
|---|---|---|---|---|
| H6a | state title | `No poses match "zzzz"` — dynamic, embeds the query | `No poses found` — static | **FAIL** |
| H6b | state copy | `Try a different pose name.` | `No poses match "zzzz". Try a different title or clear the search.` | **FAIL** |
| H6c | state action | **none** | a `Clear search` button | **FAIL** (extra control) |
| H6d | results count | **not rendered** | `0 poses` shown top-right of the results header | **FAIL** (extra text) |
| H6e | filter chips | `All poses` / `My poses` / `Community` | same three, `All poses` active | PASS |
| H6f | dock | present, **no** active pill (`initTabBar(null)`) | present, no active pill | PASS |

Additional observed defect: the native `Clear search` action's label collides with its own border — the
glyphs run into the right-hand stroke of the button (button spans roughly `x=78..322`, label to ~`x=307`
at the 924-wide display scale, with the final glyph overlapping the border). It reads as a button sized
without accounting for its label. Flagged as a probable layout defect; I did not measure it to the same
precision as the rows above.

## TOTAL

**TOTAL: 2/5 screens PASS** — `search-blank` PASS, `poses-list` FAIL (in scope, routed as R8),
`search-no-match` FAIL (in scope), `saved-list` NOT VERIFIABLE (no credentials), `gallery` NOT JUDGED for
its in-scope surfaces. The camera and gallery-empty flows had not finished when the candidate was
superseded. **m is short and that is the honest result** — I did not invent verdicts for screens I never
opened, and the gallery shortfall is attributed below rather than folded into DEFECTS.

## DEFECTS (in scope for UI-CHANGE-260913, severity order)

1. **HIGH — Poses header is two rows with a centred title.** `PosesFeature.swift:341-342`
   (`.navigationTitle` + `.navigationBarTitleDisplayMode(.inline)`) and `:305-308` (the stale two-row
   justification that still assumes the removed category pills). Prototype: one row, title left-aligned
   (`nav-bar.css:69-76`). Measured: header 67 px vs 158 px; title centre 390 = exact frame centre.
   **Routed by the General Lead as R8.**
2. **HIGH — Search no-match state is textually and structurally wrong.** Four rows above. The prototype's
   title embeds the query and offers **no action**; the native replaces the title with a static string,
   rewrites the copy, and adds a `Clear search` button plus a `0 poses` count. `PosesFeature.swift:1175`
   (`search.retry` identifier is bound to this state) and the search empty-state copy block `:73-96`.
3. **MEDIUM — `Clear search` action label collides with its own border.** Same screen;
   probable sizing defect.

## PRE-EXISTING DIVERGENCE (out of scope for UI-CHANGE-260913) — reported, NOT scored

The General Lead verified the decisive fact: `git diff HEAD -- .../Gallery/GalleryFeature.swift` contains
**zero** changes to `columnCount`, `GridItem`, `TODAY`, `YESTERDAY`, `GRD-002` or `GalleryTimeFilter`, and
the 4-case enum is unchanged. Report §3.7 line 190 carves gallery list geometry out of this change:
"The existing Gallery design remains the owner of list/detail/delete behavior; these changes standardize
state presentation rather than creating a new Gallery flow." These four are real, measured, and **not this
change's regressions**:

1. Gallery root renders **3 columns** vs the prototype's 2, with a ~1.5 pt gutter vs 8 pt (measured: 3 tile
   runs of ~119 pt vs 2 runs of ~172.5 pt with a 17 px gap).
2. Gallery renders visible `TODAY` / `YESTERDAY` section headings the prototype does not have
   (`app.js:574` keeps the date in `aria-label` only).
3. Gallery offers **4 filter chips** where the prototype offers 5 — no custom-date chip.
4. Sign-in modal **scrim is a middle band** (`y=637..1184`, 91 rows) not full-bleed (reference
   `y=4..1683`, 954 rows); report §3.8 says "the existing auth navigation is unchanged". This one was
   inference-based on my side (no in-slice reference for the default prompt), so reclassifying costs nothing.

Consequence for scope: gallery must be scored **only** on the empty / filter-empty state presentation
that this change actually touches — not on its list geometry or chip set, which would be scoring the wrong
thing. That is why gallery appears as NOT JUDGED above rather than FAIL.

## DOCUMENTATION FINDING (not a code fix)

**`SCR-002-01-GRD-002` contradicts the frozen prototype on column count.** The Basic Design artifact says
"**3 columns with a 3dp gap**"; `components/grid.css:105-108` says `column-count: 2` with
`column-gap: var(--nb-space-sm)` = **8pt**, and the rendered reference measures 2 columns with a ~8pt
gutter. Same shape as F2: the prototype CSS is the parity contract for this change, so the basic-design
number is the **stale artifact**. Recorded for a user decision — do not "fix" the app toward the stale
number in this cycle.

## EXCLUDED FROM VERDICT (declared, with measurements)

1. **1.5 px sub-pixel border artifact.** Prototype token `tokens.css:22` `--nb-border-width-thin: 1.5px`
   (authoritative, unchanged). **Reference rendered = 2 px** — measured by me on `search-no-match.png`,
   card left border `x=36..37` = `(0,0,0)`×2. **Native rendered = 3 px** — measured by me on
   `04-search-no-match.png`, card left border `x=31..33` (core 8, antialiased edges). This independently
   reproduces the General Lead's analytic 3.0 px rather than inheriting it. Same token, different
   rasteriser; the 1.5 pt value must not be changed. Declared, not scored.
2. **F2 carve-out — `gallery-detail-v2`** missing/deleted use the page's own placeholder geometry
   (`screens/gallery-detail-v2.html:126-140`), not the component tone. Machine-confirmed by
   `validate-reference-states.py`: `gallery-detail-v2-*` = **0.00%** `#FFF4F5`. Measured, not solicited.
3. **Prototype frame border (2 px) and stroke centring (~1 px).** The `.nb-phone` element screenshot
   includes the frame's own 2 px border (4 px at dsf2), and SwiftUI `.stroke()` centres a stroke while
   CSS `border` paints inside the box. Explains the consistent ~5-6 px left-edge offset (card left edge
   reference `x=36` vs native `x=30`/`x=31`). Border **thickness** matched exactly at 4 px for 2 pt cards.
4. **Status-bar clock/date**, the **system home indicator**, the **absent simulator camera feed**, and
   the browser **`:focus-visible` dashed ring** on `camera-tools.png` / `camera-picker-open.png`
   (iOS paints none; its absence is not a defect).
5. **Fixture-vs-real content** — the native gallery's gradient placeholder tiles vs the prototype's
   stock photographs, and the pose artwork itself. The frame is judged, not the artwork.

## NOT VERIFIABLE (each row, its class, and its named substitute)

**Class 1 — prototype-side missing (no reference can exist):**

| Row | Why | Substitute check |
|---|---|---|
| Gallery all-empty | `?state=empty` is a no-op (`app.js:543-552`); with `filter=all` the fixture set is never empty | Match the app screenshot against the code-locked strings `No photos yet` / `Capture a pose to start your gallery.` + an `Open Camera` action (`app.js:545-551`) |
| pose-detail-saved guest gate | no load-time state exists; `auth=guest` is read only inside `toggle.onclick` (`pose-detail-saved.js:42`) and navigates away | behaviour only: a guest save attempt must not mutate Saved |

**Class 2 — app-side undrivable (the reference EXISTS; state the reason it could not be used):**

| Row | Reference that exists | Why undrivable | Substitute check |
|---|---|---|---|
| Search offline | `search-offline.png` | no `.offline` producer in the app | view-model unit tests |
| Search refresh-error / warning | — | no `.warning` producer | view-model unit tests |
| Saved-list offline | `saved-list-offline-no-cache.png`, `saved-list-offline-stale.png` | no producer; and the rig is unauthenticated | view-model unit tests |
| Saved-list refresh-error | `saved-list-refresh-error.png` | no `.warning` producer | view-model unit tests |
| Saved-list load-more-error | **no reference** (interaction-only) and almost certainly no app producer | both | view-model unit tests |
| Signed-in Saved (all list states) | `saved-list.png` | `/api/me/saved` → **401** (measured); no credentials reachable, app gates behind sign-in | view-model unit tests; a seeded session would upgrade this to PASS/FAIL |
| **Pose-picker offline** | `camera-picker-offline.png` | **producer NOW EXISTS** (`NWPathMonitor`, `CameraFeature.swift:1321-1329`) but a simulator has no network toggle. Attempted, not forced | the producer + unit test. **Not** reachable via `setOfflineForTesting` (`:1385`) — that is a test seam, and using it for a screenshot would be the faking the ruling forbids |

## Procedure note — why this pass is pre-fix

This pass scores the pre-fix candidate. The General Lead has since re-opened it for R1-R8, which touch
`poses-list`, `gallery` empty/error states, `pose-detail-unavailable`, all `saved-list` states, and
`camera-picker-offline` / `-no-match`. **R8 is my Poses header finding, routed verbatim.** My FAILs on
those surfaces are independent corroboration, not final verdicts; a re-run on the post-fix binary is
required for: `poses-list`, `gallery` empty, `pose-detail-unavailable`, all `saved-list` states,
`camera-picker-offline`, `camera-picker-no-match`.

Also recorded as the General Lead's defect, not a product one: the code-only freeze identity
`a3d8c8ed…` was incomplete because `git diff HEAD` cannot see untracked files —
`mobile/iosApp/iosAppTests/Features/PosePickerViewModelTests.swift` is untracked and referenced **4×** in
`project.pbxproj` (I verified both). Corrected method `git add -A -- mobile/ && git diff --cached HEAD -- mobile/`
yields **`dfd1de200492e49ec93f6bf10e0c15d73516ead3afaad6aa30153677417cfd89`**. My no-movement check remains
valid for every screen scored, since all compared Swift sources are tracked.

## MEASUREMENT SETTLED — the 16pt vs 19pt content-inset delta (DL-A's question)

**Answer: it is NOT a real padding difference and must not be changed.** It is the `.nb-phone` frame
border artifact plus SwiftUI stroke centring — the same decomposition as the 6px card inset, and it
decides DL-A's `Pending-validation` flag in favour of leaving the padding alone.

Verified in the prototype CSS first, rather than trusting my earlier assumption:

- `components/phone-frame.css:2-8` — `.nb-phone { width: 390px; border: var(--nb-border-thick) }`, and
  `tokens.css:18` `--nb-border-thick` = `2px solid` → the frame carries its **own 2px border**, and the
  element screenshot includes it.
- `phone-frame.css:42-49` — `.nb-phone__content { padding: 0 var(--nb-space-md) }`, and
  `tokens.css:48` `--nb-space-md` = **16px** → the authoritative content inset is **16pt on both sides**.

Both measurements:

| | card border outer edge (780-wide normalisation) | composition |
|---|---|---|
| REFERENCE `poses-list.png` | **x=36** (2pt card border measured 4px thick, `x=36..39`) | frame border 2px × dsf2 = **4px** + content padding 16pt × dsf2 = **32px** → 4+32 = **36** ✓ |
| NATIVE (new build) | **x=30** (2pt card border 4px thick) | no frame border; 16pt = 32px, less 1pt of stroke centring (a 2pt `.stroke()` extends 1pt outside the frame edge, where CSS `border` paints inside the box) → 32−2 = **30** ✓ |

Total apparent delta = 6px = **3pt**, and it is fully accounted for: **2pt** from the prototype frame's
own border being inside the element screenshot, plus **~1pt** from stroke-centring. **Residual 0.**
The state card measures the same way: 1.5pt stroke → outer edge at 16 − 0.75 = 15.25pt ≈ **x=31**, measured 31.

The "19pt" figure comes from measuring the card's **inner** white start (`x=38` at the reference → 19pt)
and comparing it against an **outer** edge — an inner-edge-vs-outer-edge comparison across a 1.5–2pt border.
Same designed padding (16pt) on both sides; no R8 effect and no pre-existing divergence.

## Explicitly NOT scored as defects

- **Card left-inset 6 px delta** (reference `x=36` vs native `x=30` at 780-wide normalisation).
  Fully accounted for, not a product defect: the prototype's `.nb-phone` element carries its own 2px
  frame border, which the element-screenshot includes (2 px × dsf2 = **4 px** of pure offset), and
  SwiftUI `.stroke()` centres a 2 pt stroke on the frame edge (outer edge 16 − 1 = **15 pt**) while CSS
  `border` paints inside the box (outer edge exactly **16 pt**). Net residual = **1 pt**, inside the
  declared rasterisation/stroke-model exclusion. The border *thickness* itself matches exactly (4 px both).
