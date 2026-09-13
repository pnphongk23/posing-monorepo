# DL-B — AC6 region checklist (derived from the frozen prototype CSS before any comparison)

Derived by the Domain Lead from `docs/prototype/styles/**` at HEAD `3a4be1c`, **before** looking at
any simulator screenshot. Each row is a measurable fact with a cited source. Work these rows in
order and quote a number per row; a row that cannot be measured is recorded as NOT VERIFIABLE, not
as a PASS.

## Frozen measurements (from `styles/tokens.css`)

- colours: bg `#FBF6EF`, border `#000000`, white `#FFFFFF`, dark `#121212`, gray `#6B7280`,
  error surface `#FFF4F5`, warning surface `#FED766`, success surface `#B5E2B9`,
  accent pink `#E89CAE`, accent blue `#7FBBE6`, accent yellow `#FED766`, accent green `#B5E2B9`
- borders: thick `2px`, thin `1.5px`, hairline `1px` (all solid `#000`)
- shadows: hard offset, **0 blur** — small `1.5px 1.5px 0`, default `3px 3px 0`, large `5px 5px 0`
- radii: phone `40px`, large `14px`, medium `10px`, small `6px`
- spacing: 2xs `2`, xs `4`, sm `8`, compact `12`, md `16`, lg `24`, xl `32`; touch min `44`
- type: navigation title = `--nb-font-size-xl` weight bold, leading 1.10; heading-3 `18px` bold 1.10

## Shared state surface (`styles/components/empty-state.css`) — applies to every state screen

| # | Check | Expected | Verdict |
|---|---|---|---|
| S1 | surface fill | white `#FFFFFF` **except** the tone overrides in S2 | |
| S2 | tone fill | error `#FFF4F5`; offline **and** warning `#FED766`; success `#B5E2B9`; loading `#FFFFFF` with gray `#6B7280` body copy and dark title. **Scoped out for `gallery-detail-v2` — see finding F2.** | |
| S3 | border | `1.5px` solid `#000000` on all four edges | |
| S4 | radius | `10px` | |
| S5 | padding / gap | padding `16px`; internal column gap `8px` | |
| S6 | layout | leading (left) column, `align-items: flex-start` — title, copy, optional action in that order | |
| S7 | title type | `18px`, bold, leading 1.10 | |
| S8 | copy measure | body size, `max-width: 42ch` | |
| S9 | action button | present only when the prototype renders one; intrinsic width (`width:auto`), never stretched | |
| S10 | absence | no shadow on the state surface (the CSS sets no `box-shadow`) | |

### F3 — the state surface's SHAPE is a SCORED requirement (not an exclusion)

F3 is scored: if the app violates it, that is a FAIL. Three independent sources:
`docs/prototype/scripts/empty-state.js:70-85` (the `render()` builder emits only
preserved-visual → `<strong>` title → `<p>` copy → action — **there is no icon parameter**);
`styles/components/empty-state.css` (no icon rule, no centring, no full height); and
`reference/poses-list-empty.png` (opened: top-anchored card, no glyph, left-aligned title and copy).

| # | Check | Expected | Verdict |
|---|---|---|---|
| F3a | icon | **absent** — no glyph at all | |
| F3b | placement | top-anchored, leading-aligned, full-width **inline card** — never a full-screen centred stack | |
| F3c | title | `18px` bold (`--nb-type-heading-3-size`) | |
| F3d | copy | `14px` at `1.55` leading, left-aligned, capped at the measured `42ch` (~370pt) | |

#### F3 numeric baseline — measured by me on `reference/poses-list-empty.png` (780x1688, dsf2)

Pixel bands inside the card interior (`x 39..741`, `y 215..419`), printed from raw pixel values:

| Element | Ink band (device px) | Ink height | Width |
|---|---|---|---|
| title `No poses yet` | `y=253..284` | **32 px = 16 pt** | 214 px = 107 pt |
| copy line 1 `New poses will appear here when` | `y=313..338` | **26 px = 13 pt** | 426 px = 213 pt |
| copy line 2 `they're available.` | `y=355..380` | **26 px = 13 pt** | 214 px = 107 pt |

Derived facts to compare the app against:

- **copy leading = 42 px = 21 pt** line-top to line-top (`313 → 355`) ⇒ ~1.5 line height at 14px. A 14px/1.55 CSS line box is 21.7px = 43.4 px; measured 42 px.
- card top border `y=212` → title ink `y=253` = 41 px = 20.5 pt ⇒ consistent with the `16px` padding plus the line box (row S5).
- title ink 16 pt tall for `No poses yet` (cap `N` + descenders `p`/`y`) is consistent with an **18px** font (row F3c).

⚠️ **INK EXTENT IS NOT FONT SIZE — do not compare these numbers against a font size.** The bands above
are measured *ink* extents (the painted pixels of the glyphs), not em sizes. The authority for the
font sizes is `tokens.css:100-104`: heading-3 = **18px** (bold, leading 1.10) and body =
**14px** (leading 1.55). Scoring native 18pt against a reference "16pt ink" figure would produce a
false FAIL. Use the ink band only to check *relative* agreement (title clearly larger than copy,
copy lines on a consistent rhythm) and take absolute sizes from the token file. (Raised by the
General Lead; recorded here so the trap is not repeated in Phase 2 or by a reviewer.)

⚠️ **F3d's `42ch` cap is NOT observable on this reference.** The card interior is 351 pt wide while `42ch` at 14px is ~370 pt, so the copy wraps at the card edge first — the cap never binds here. Do **not** FAIL the app for an unobservable cap. The checkable form of F3d on this screen is: copy is left-aligned, wraps inside the card, and sits on a ~21 pt line rhythm. Assert the cap only on a reference whose copy is long enough to reach it; otherwise the row is `NOT OBSERVABLE`, never a FAIL.

#### F3 rendered confirmations (opened, not inferred)

- `poses-list-empty.png` — no glyph; top-anchored full-width inline card directly under the header; left-aligned bold title + 2-line left-aligned copy; white surface, `2px` border, radius `10`; dock present with **Poses** active.
- `saved-list-offline-no-cache.png` — no glyph; warning surface `#FED766`; top-anchored inline card; title `Saved poses aren't available offline` + copy `Reconnect to load your saved collection.` + a **`Try again` action at intrinsic width (not stretched)** (row S9); pushed screen so **no dock**; status-bar glyphs are the `▰▮▰` placeholders (already excluded).

Affected screens (every consumer of the component): poses-list (empty/error/loading/refresh-error/
deleted), search (blank/no-match/error/loading/offline), saved-list (loading/empty/error/offline/
refresh-error/load-more-error), account signed-out, sign-in failure, gallery filter-empty,
pose-detail unavailable, and every camera pose-picker state.

⚠️ **Sequencing risk (General Lead's warning):** the app's state surfaces visibly change SHAPE when
DL-A lands F3 (glyph removed, no longer vertically centred). Any app-side shot taken before the F3
binary must **not** be scored against a reference — that would FAIL a surface that has not been
implemented yet. Confirm the build under test is post-F3 before issuing any state-surface verdict.

## Poses list (`screens/poses-list.html` + `styles/components/grid.css:288-299`)

| # | Check | Expected | Verdict |
|---|---|---|---|
| P1 | title | exactly one `Poses`, left-aligned (`nav-bar.css:69` `.nb-nav-bar--poses`), navigation-title size | |
| P2 | absence | **no** `My poses` / `Community` tablist, **no** `Create Pose` action, **no** visible pose count | |
| P3 | header actions | crown (Premium), search, bookmark (Saved), gear (Settings) — 4 controls, right side | |
| P4 | grid | masonry `column-count: 2`, `column-gap: 8px`, staggered (cards in the two columns do not share a baseline) | |
| P5 | dock | present, `Poses` item active (blue `#7FBBE6` pill + `1.5px` border) | |
| P6 | card | hard shadow, `2px` border, radius per card CSS; count cards in the first row and compare with the reference | |

## Camera (`screens/camera-live.html`, `styles/components/camera-viewport.css`)

| # | Check | Expected | Verdict |
|---|---|---|---|
| C1 | framing brackets | **absent** — no `framing`/`bracket`/corner rule survives in `camera-viewport.css` (grep: 0 hits) | |
| C2 | More / Camera tools | `44x44`, `right:16`, `bottom:68` (`:479-491`) — i.e. lower-right, directly above Choose pose; NOT top-right | |
| C3 | Choose pose | `44x44`, `right:16`, `bottom:16` (`:462-474`), immediately below More | |
| C4 | close button | top-left compact action, `44x44` touch target, `32x32` white surface, radius 10, `2px` border, `1.5px` hard shadow (`AIPoseComponents` mirror) | |
| C5 | zoom | horizontally centred, `bottom:16`, `36x36` circle | |
| C6 | shutter bar | `#FBF6EF` rail, `2px` top border only, thumbnail left, shutter centred, flip right | |
| C7 | dock | **absent** on camera | |
| C8 | camera tools popup | `right:16`, `bottom:120` (`:572-590`), width `264`, padding `8`, fill `#121212`, `2px` border, radius `10`, hard shadow `3px 3px 0`, `transform-origin: bottom right` | |
| C9 | popup chrome | **no** scrim, **no** handle, **no** app-bar Close inside the popup | |
| C10 | popup rows (no pose) | Flash + Grid **only** — the `[data-pose-tools]` divider + section are `hidden` (`app.js:290-294,339-344`) | |
| C11 | popup rows (pose selected) | adds Pose guide (Shown/Hidden), Opacity 10–100% default 50%, Line color Black(selected)/White, Clear pose | |

## Camera pose picker sheet (`camera-live.html?guide-picker=open`, `styles/components/camera-guide.css`)

| # | Check | Expected | Verdict |
|---|---|---|---|
| K1 | presentation | bottom sheet over the still-visible camera; `44px` top inset, backdrop `rgba(18,18,18,0.48)` | |
| K2 | panel | height `min(82%, 700px)` (min `420`), radius `22px 22px 0 0`, `2px` border on top+sides only, **no** bottom border, `box-shadow: 0 -4px 0 #000` | |
| K3 | app bar | title `Choose a pose` + a `44x44` **Close** on the right; **no Back button** | |
| K4 | handle | `42x4` dark bar, radius `2`, centred, `16px` below | |
| K5 | search | local search field with leading magnifier; clear button revealed only with text | |
| K6 | grid | 2-column staggered masonry, same visual language as Poses | |
| K7 | back-stack | returning to Camera leaves **no** pushed picker route (Camera is the parent) | |

## Search (`screens/search.html`)

| # | Check | Expected | Verdict |
|---|---|---|---|
| H1 | blank state | `Recent searches` heading + 3 chips (Dancing / Stretching / Warrior); no state surface | |
| H2 | nav | back control left, centred title `Search` | |
| H3 | results header | kicker `YOUR MATCHES`, heading `Results`, count right | |
| H4 | filters | 3 pills `All poses` / `My poses` / `Community`, active one selected | |
| H5 | dock | visible **with no active pill** (`reference/search-blank.png` shows both dock icons plain) | |
| H6 | states | loading / error+retry / empty / offline all render the shared surface with the correct tone (S1–S10) | |

## Gallery (`screens/gallery.html`, `gallery-detail.html`, `gallery-detail-v2.html`)

| # | Check | Expected | Verdict |
|---|---|---|---|
| G1 | filters | 5 chips `All` / `Today` / `7 days` / `30 days` / `Date`, only one active at a time. App side confirmed present: `GalleryFeature.swift:403-405` + `:253-258`, chip label is `Text(title)` at `AIPoseComponents.swift:9` | |
| G2 | empty (all) | shared empty surface, title `No photos yet`, copy `Capture a pose to start your gallery.`, **plus an `Open Camera` action** (`app.js:547-551`). **NO PROTOTYPE COUNTERPART** — see the no-counterpart table below; app-side only, so no reference image can exist | |
| G3 | empty (filter) | shared empty surface, title `No photos in this filter`, copy `Try another filter.`, **no action** (`app.js:547-551` passes `null` when the filter is not `all`). Reference: `gallery-filter-empty.png` | |
| G4 | detail unavailable | shared error surface + `Return to gallery` action, detail content and actions hidden | |
| G5 | detail-v2 missing/deleted | state rendered **inside** the preserved media placeholder (`preserveVisual: true`), centred, page fill `#EEE9E1` — **not** the `#FFF4F5` component tone, and with no component border/radius. Measured: `#EEE9E1` = 48.0% of the frame vs 0% in the ready state | |

## Saved / auth (`screens/saved-list.html`, `pose-detail-saved.html`, `account.html`, `sign-in-prompt.html`)

| # | Check | Expected | Verdict |
|---|---|---|---|
| V1 | saved loading | shared loading surface, `Loading saved poses` | |
| V2 | saved error | error tone + `Try again` | |
| V3 | saved offline | offline tone `#FED766`, `Saved poses aren’t available offline` + `Try again` | |
| V4 | saved empty | empty surface, `No saved poses yet` + `Browse Community` | |
| V5 | saved refresh-error | **warning** tone `#FED766`, `Couldn’t refresh` + `Retry` | |
| V6 | pose-detail-saved mutation error | error tone surface | |
| V7 | account signed-out | success tone `#B5E2B9`, `Signed out`; name becomes `Signed out`, provider `No active session`, Saved shortcut hidden | |
| V8 | sign-in failure | error tone `#FFF4F5` inside the modal, `Sign-in failed` + `Try again`, modal still open | |

## Rig conditions measured before Phase 2 (probed 2026-09-14, read-only)

These were measured, not assumed, because they decide which rows can even be attempted.

| Probe | Result | Consequence for the gate |
|---|---|---|
| `GET /api/community/poses?limit=2` | **HTTP 200**, real payload (`poseId`, `name`, `skeletonUrl` on R2) | Poses/Search/Camera-picker **content** states are achievable — the catalogue really loads |
| `GET /api/health` | HTTP 200 `{"status":"ok"}` | server up |
| `GET /api/me/saved` | **HTTP 401 UNAUTHORIZED** | the rig is **unauthenticated** → signed-in Saved states are not drivable |
| `GET /api/account/me` | **HTTP 401 UNAUTHORIZED** | account **signed-in** state not drivable; the signed-out state (the AC1 success tone) IS drivable |

Consequence: `saved-list-empty` (needs signed-in with zero saved) and every signed-in Saved content
state move to class 2 **on measurement**, not on assumption. Do not plan a signed-in Saved shot.

**Build invocation — `-project` is correct, do NOT use `-workspace`.** All dependencies (Firebase,
RevenueCat, GRDB, Kingfisher) are Swift Package Manager packages declared in `project.yml` with
exact-version pins. The `Podfile`, `iosApp.xcworkspace` and `Pods/` are **vestigial from the retired
KMP lane** (`pod 'composeApp', :path => '../composeApp'` — that target no longer exists). Building the
workspace would pull in a stale Pods project referencing a deleted pod. Phase 2 uses:
`xcodebuild -project iosApp.xcodeproj -scheme Dev -configuration Debug-Dev -destination "platform=iOS Simulator,id=8A4AB36C-68D4-499E-B749-B56C9BC0B75A" -derivedDataPath /tmp/dd-dl-b build`

## Exclusions — decided now, before comparing (never a FAIL)

1. Status-bar clock (prototype hard-codes `9:41`, the simulator shows real time) and its icon set
   (the prototype's account/saved screens use `▰▮▰` glyph placeholders).
2. The system home indicator.
3. The absent simulator camera feed — judge camera **chrome** only.
4. Browser-vs-platform font rasterisation and 1–2px safe-area shifts.
5. Fixture-vs-real content: prototype stick-figure SVGs vs real pose artwork; the prototype's
   fixture query is not production data.
6. The iOS on-screen keyboard itself (prototypes do not model it); the *anchoring* of floating
   chrome with the keyboard up is still checked.
7. The iOS first-run keyboard onboarding overlay (dismissed once per device).

## Reference-side artifacts — measured, must not be scored as product defects

These are in the **reference** images by construction. Excluded for the same reason as the
status-bar clock: a browser artifact with no iOS counterpart.

1. **Browser focus ring.** `scripts/modal.js:29-32` and `scripts/guide-picker.js:161-165` move focus
   to the first control / the Close button when the popup or sheet opens, so `camera-tools.png` and
   `camera-picker-open.png` carry a **dashed blue `:focus-visible` outline** around the Flash row
   and the picker Close button respectively. iOS does not paint a focus ring for programmatic
   focus. If the simulator shot lacks it, that is **not** a defect. Verified absent from
   `camera-live.png`, so it is genuinely the focus move and not a page style.
2. **`#FED766` false positive.** `--nb-color-warning-surface` and `--nb-color-accent-yellow` are the
   *same hex*. Every reference therefore shows ~0.18–0.96% `#FED766` from the Poses crown button
   and the Search chips even when no warning state is on screen. Judge a warning tone by magnitude
   (10–15% of the frame), never by mere presence.
3. **1.5px border rasterisation.** Prototype value: `tokens.css:22`
   `--nb-border-width-thin: 1.5px`. **Independently re-measured by me** on
   `reference/poses-list-empty.png` (780x1688, dsf2), printing raw pixel values:
   left border `x=36,37` pure `(0,0,0)` = **2 device px**; right border `x=742,743` = **2 device px**;
   top border rows `y=212,213` = **2 device px**; bottom rows `y=420,421` = **2 device px**.
   Card box therefore `x=36..743`, `y=212..421`. The General Lead's 2px figure is confirmed and
   my first scanline attempt (which suggested 4px) was misreading the vertical border line and the
   rounded-corner arcs — the raw-pixel print settled it.
   Native expectation: a true 1.5pt on a 3x capture (1170x2532) = 4.5 device px, normalised to the
   780-wide comparison pane = **3.0 px** — **analytic only; I must MEASURE it in Phase 2 rather than
   inherit it.** Exclusion entry: reference **2 px** vs native **~3 px** at the same card edge after
   normalisation — same token, different rasteriser. Do not change the 1.5pt value.

## Findings raised while validating the references (for the General Lead; not mine to fix)

**F1 — prototype tone contract holds, with one exception.** Measured `#FFF4F5` on
`poses-list-error`, `search-error`, `saved-list-error`, `camera-picker-error`,
`pose-detail-unavailable`, `pose-detail-saved-error`, `gallery-detail-unavailable` and
`sign-in-failure` (9.7–14.5% of frame); `#B5E2B9` on `account-signed-out` and `poses-list-deleted`
(8.1%); `#FED766` on the warning/offline set (5.9–15.1%). The PLAN §Frozen-contract tone list is
faithful to the prototype everywhere except F2.

**F2 — `gallery-detail-v2` error state does not use the component tone.**
`screens/gallery-detail-v2.html:126-140` re-declares `.empty-photo` with its own `display: grid`,
`padding: 24px`, `text-align: center` and the page's `--surface` fill. The rendered references
confirm it: `gallery-detail-v2-missing.png` and `-deleted.png` fill 48.0% of the frame with
`#EEE9E1` and contain **0% `#FFF4F5`**. On this one screen the prototype's rendered result
contradicts both the shared component and the PLAN prose. Precedence is CSS > rendered PNG > prose,
so the **prototype's** rendering is the contract here and row `S2` must not be scored against this
screen. The contradiction itself is a documentation finding.

## No prototype counterpart / undrivable — two classes, two substitute checks, never a PASS

The General Lead split what I had collapsed into one ruling. Both classes are reported as
`NOT VERIFIABLE` with the class named, and neither may be dropped from the report.

### Class 1 — prototype-side missing (state exists in prototype CODE, is not renderable)

No reference can ever exist. Substitute check: the app screenshot must match the **code-derived**
strings, cited by line. This is a checkable contract, not a shrug.

| State | Why not renderable | Substitute check (code-derived) |
|---|---|---|
| Gallery, all-empty | `?state=empty` is a no-op — `app.js:543-552` derives emptiness from `visibleCount === 0` and never reads `getPrototypeState()`; with `filter=all` the fixture set is never empty. Measured: byte-identical to `gallery.html` (AE = 0) | Title `No photos yet`; copy `Capture a pose to start your gallery.`; **an `Open Camera` action present** — per `app.js:545-551`. The app currently passes no `actionTitle`/`action` (`GalleryFeature.swift:420`) |
| pose-detail-saved, guest save gate | `auth=guest` is read only inside `toggle.onclick` (`pose-detail-saved.js:42`) — no load-time visual (AE = 0); the branch navigates to `sign-in-prompt.html?intent=save`, an unchanged out-of-slice surface | Only that a guest save attempt does not mutate Saved (behaviour, not pixels) |

### Class 2 — app-side undrivable (the reference EXISTS; the app cannot be forced into the state)

The asymmetry matters: here I *have* a reference and must state why I could not use it. Substitute
check: unit tests on the view model.

Confirmed class 2:

| State | Reference that exists | Substitute check |
|---|---|---|
| Saved list, offline | `saved-list-offline-no-cache.png`, `saved-list-offline-stale.png` | view-model unit tests |
| Saved list, refresh-error | `saved-list-refresh-error.png` | view-model unit tests |
| Saved list, load-more-error | **no reference (interaction-only) and almost certainly no app producer** — record as both | view-model unit tests |
| Search, offline | `search-offline.png` | view-model unit tests |
| Poses list, refresh-error | `poses-list-refresh-error.png` | view-model unit tests |

**In-scope with drivability to be ATTEMPTED — never pre-classified, never pre-PASSed.** Prototype URL
reachability does NOT imply app drivability; that inference is the same error shape as the withdrawn
gallery finding. Attempt each in Phase 2; if the app reaches the state it becomes a normal row, and
only if it cannot does it move to class 2 **at that point**, with the reason recorded.

| State | Why drivability is in doubt |
|---|---|
| `saved-list-empty` | needs a signed-in account with zero saved poses |
| `poses-list-empty` | needs an empty published catalogue |
| `poses-list-loading`, `search-loading`, `saved-list-loading`, `camera-picker-loading` | transient; may not be catchable mid-flight |
| `camera-picker-no-match` | genuinely drivable — type a nonsense query |

### Out of scope by ruling — no producer exists (documented boundary, not a defect)

DL-A established that the app has **no offline/warning producer at all**: `Loadable` is
`idle, loading, loaded, empty, failed(String)`, and `.offline`/`.warning` exist only because the
frozen component declares them. The General Lead ruled these out of scope as a documented boundary
(report §6: native production behaviour "remain[s] unresolved unless separately implemented and
verified"). Consequence for the report: no app-side offline shot is expected for any class-2 offline
row, and its absence is **not** a coverage failure. State that explicitly rather than silently
omitting it.

## Withdrawn findings (corrected record)

- **WITHDRAWN: "Gallery filter/empty has no UI path in the app."** False.
  `GalleryFeature.swift:403-405` already renders `NeoFilterChip` for every `GalleryTimeFilter`, and
  `:436` already distinguishes the filter-empty message from the all-empty message. The General Lead
  caught this; I had forwarded L-B1's claim without reading the code myself. The real, narrower gap
  is only that the all-empty state passes no `actionTitle`/`action` (`GalleryFeature.swift:420`).

## Reference-integrity standard — hash-distinctness is NOT sufficient

The first reference set passed every mechanical check — 48 files, all 780x1688, flows
`check-syntax` green, no `point:` taps — and was still **wrong**: two of the 48 were byte-identical
duplicates of another state. File count and file size cannot detect a wrong state; only opening or
hashing them can.

`scripts/prototype-reference-shots.mjs` now self-checks distinctness and exits non-zero on a
duplicate pair. **That guard is necessary but not sufficient**: a distinct file can still be the
wrong state (a distinct-but-wrong reference is worse than a missing one, because it produces a
confident wrong FAIL against a correct app). So every reference used as a baseline must also carry a
**positive state identification** in `dlb-reference-manifest.md`: the observable that proves *which*
state it shows — the expected title/copy text present, and the expected control present or absent,
each with the source line.

Worked example of the required standard, validated by opening the PNG:
`gallery-filter-empty.png` — title `No photos in this filter` present; copy `Try another filter.`
present; **no action button** (correct: the `Open Camera` action is all-empty only); 5th chip
relabelled `Jan 1` and active while `All` is inactive (`app.js:523`); state surface in-grid spanning
both masonry columns with the 16pt grid inset (`empty-state.css:88` `column-span: all`), bordered and
radius 10. All four General-Lead acceptance points hold.

## Reference-integrity defects and how the baseline is now proven

### The standard

Hash-distinctness alone is NOT sufficient — a distinct file can still be the wrong state, and a
distinct-but-wrong reference is worse than a missing one because it yields a confident wrong FAIL
against a correct app. Every reference therefore carries a **machine-checked positive state
identification**: `scripts/prototype-reference-shots.mjs` declares per-state
`expectText` / `expectVisible` / `expectAbsent` / `expectEmptyText` derived from the prototype's own
code, asserts them against the live page **before** each screenshot, collects **every** failure and
exits non-zero. A wrong or missing state now fails the capture run instead of passing silently.
**116 assertions across the 47 states.** `scripts/validate-reference-states.py` asserts the tone hexes
with a magnitude threshold (present ≥3%, absent <2% — required because `warning-surface` and
`accent-yellow` are the same `#FED766`); **29 tone assertions green**.

`dlb-reference-manifest.md` records per reference: `expected-visible`, `expected-controls`
(PRESENT and ABSENT), `source` (prototype file:line) and `confirmed-by` — `dom-asserted` (49),
`measured` (28, percentage quoted), `opened` (0), `UNCONFIRMED` (0). Checked by reading the rows: the
`opened`/`UNCONFIRMED` hits in that file are prose in the legend and the copy string "This photo can't
be opened.", not provenance values.

### The four wrong-state references this caught (all fixed, all verified)

The first delivery passed every mechanical check — 48 files, all 780x1688, flows `check-syntax`
green, no `point:` taps, hash-distinctness guard — and was still wrong four times:

| # | Reference | Defect | How it was caught |
|---|---|---|---|
| 1 | `gallery-empty.png` | byte-identical to `gallery.png`; `?state=empty` is a no-op (`app.js:543-552`) | md5 + AE = 0 |
| 2 | `pose-detail-saved-guest.png` | byte-identical to `pose-detail-saved.png`; `auth=guest` has no load-time visual (`pose-detail-saved.js:42`) | md5 + AE = 0 |
| 3 | `search-results-community.png` | **hash-distinct but the WRONG STATE** — `q=Warrior&source=community` matches nothing (`fixtures.js:174,202`), so it rendered the *no-match* surface. Replaced with `q=Dancing&source=community` | capture-time `expectText` assertion |
| 4 | `camera-live.png`, `poses-list.png` | stale — the committed captures still showed the pre-AC2/AC3 design | AE 1.00% / 43.58% vs fresh capture |

Defect #3 is the important one: exactly the failure mode a hash guard cannot see, and it was caught
by a DOM assertion — not by a hash, and not by eye.

Also fixed: the missing `gallery-filter-empty.png` (added from
`gallery.html?filter=custom&date=2000-01-01`), and `gallery-detail-unavailable`, where absence could
not be proven by visibility because `card.css` re-displays the hidden shells — handled with an
`expectEmptyText` assertion on the nav action buttons instead of a weakened check.

### Verified: HEAD's committed references were stale (eye-confirmed)

`git show HEAD:...reference/poses-list.png` shows the **pre-AC2 design**: a `My poses` / `Community`
tablist, a `+` Create Pose action, and a visible **`23 poses` count** — every one of which AC2 requires
removed. The current reference correctly shows a single left-aligned `Poses`, no tabs, no Create Pose,
no count, staggered 2-col masonry, dock with Poses active. This independently vindicates the parity
skill's rule that committed screenshots must never be trusted; the AC6 baseline is the regenerated set.

### Tested and REJECTED: remote-imagery nondeterminism is NOT a factor

I hypothesised that `camera-live.png`/`gallery.png` embed remote Unsplash imagery (`fixtures.js` has 5
`images.unsplash.com` URLs; `camera-live.html` has 2) and would therefore be byte-unstable — which
would have justified excluding the camera-feed region from comparison. **I tested it and the hypothesis
is false:** capturing `camera-live`, `gallery` and `poses-list` twice in **two independent chromium
launches** gives **AE = 0** for all three. The references are byte-reproducible, so pixel diffs against
them are meaningful and **no remote-imagery exclusion is warranted**. Recorded because I nearly wrote
that exclusion into this file without measuring it — the camera-feed exclusion stands only for the
*simulator's absent feed*, which is a different reason.

## Always a FAIL

Wrong or missing control · wrong colour · flat card where the prototype has a hard shadow (or the
reverse) · wrong column count · extra text the prototype does not have · a screen presented as a
sheet when the prototype is full-screen (or the reverse) · dock present where the prototype omits
it, or absent where it shows it · a state surface that does not render at all.
