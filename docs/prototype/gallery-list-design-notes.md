# Gallery list design notes

## Product intent

The user comes here to review captured pose-match photos, find a photo by
recency or pose, and open one item for its next action with as little scanning
friction as possible.

The flow starts from the Gallery tab or the latest-photo affordance in Camera
and hands off to `gallery-detail-v2.html` when a photo is opened. This is a
personal history/library task, not a social discovery feed.

## Reference study

- **Platform:** iOS
- **Source:** Mobbin
- **Research date:** 2026-09-10
- **Access note:** The free account was used, so the study sampled distinct
  filter branches and a small set of detailed anchors instead of opening every
  result.

### Filter matrix

The same Mobbin library changes materially when the filter family changes. The
counts below were visible during this study and are useful as a research
coverage record, not as permanent product data.

| Content type and filters | Showing | What this branch contributed |
| --- | ---: | --- |
| Screens → `Browse & Discover` | 4,995 screens | Broad browse/feed structures: search, category rails, cards, and bottom navigation. |
| Screens → `Browse & Discover` + Categories → `Photo & Video` | 318 screens | Media-heavy browse: editorial modules, mixed tiles, and photo-first feeds. |
| Above + UI Elements → `Gallery` | 78 screens | Direct gallery patterns: masonry, fixed grids, collection tiles, and creator strips. |
| Screens → `Browse & Discover` + Categories → `Social Networking` + UI Elements → `Gallery` | 60 screens | Instagram-style equal grids and social-media gallery density. |
| Screens → `Bookmarks & Collections` | 2,533 screens | Saved/library management, favorites, edit/reorder, and collection-level actions. |
| Above + Categories → `Photo & Video` | 221 screens | Personal media libraries, memories, projects, and saved boards. |
| Flows → `Switching View` | 485 flows | List/map or view transitions that preserve context and selection. |
| Flows → `Filtering & Sorting` | 1,839 flows | Full-screen filter task, applied state, and sticky result action. |
| Flows → `Saving to Collection` | 945 flows | Item action → short sheet → create/select collection → confirmation. |

Collection URLs:

- [Browse & Discover](https://mobbin.com/search/apps/ios?content_type=screens&sort=popularity&filter=screenPatterns.Browse+%26+Discover)
- [Browse & Discover × Photo & Video × Gallery](https://mobbin.com/search/apps/ios?content_type=screens&sort=popularity&filter=screenPatterns.Browse+%26+Discover_appCategories.Photo+%26+Video_screenElements.Gallery)
- [Browse & Discover × Social Networking × Gallery](https://mobbin.com/search/apps/ios?content_type=screens&sort=popularity&filter=screenPatterns.Browse+%26+Discover_appCategories.Social+Networking_screenElements.Gallery)
- [Bookmarks & Collections × Photo & Video](https://mobbin.com/search/apps/ios?content_type=screens&sort=popularity&filter=screenPatterns.Bookmarks+%26+Collections_appCategories.Photo+%26+Video)
- [Switching View flows](https://mobbin.com/search/apps/ios?content_type=flows&sort=popularity&filter=flowActions.Switching+View)
- [Filtering & Sorting flows](https://mobbin.com/search/apps/ios?content_type=flows&sort=popularity&filter=flowActions.Filtering+%26+Sorting)
- [Saving to Collection flows](https://mobbin.com/search/apps/ios?content_type=flows&sort=popularity&filter=flowActions.Saving+to+Collection)

### Detailed anchors

| Reference | Observed pattern | Relevance to Gallery |
| --- | --- | --- |
| [Unfold](https://mobbin.com/screens/3b35da75-d5c0-4d09-b275-807565fe2185) | Horizontal content chips (`Reel`, `Story`, `Post`), a featured visual, and a secondary tools grid. | Shows how a media surface can keep global modes compact and put content first. |
| [Pinterest Browse](https://mobbin.com/screens/fb6f66bf-5705-4933-b0d4-5522c783c677) | `Browse/Watch` tabs, two-column masonry with mixed aspect ratios, item overflow, and bottom navigation. | Strong visual scan pattern when image ratio is meaningful. |
| [Cosmos Home](https://mobbin.com/screens/186e9df3-db3c-48a9-8e05-82315d7b63d7) | `Featured/Following` tabs and a dark, immersive two-column masonry. | Useful contrast: dense media browsing can be immersive, but that is not automatically right for a personal history. |
| [Instagram Search](https://mobbin.com/screens/f88c75a0-70b6-4755-bc51-0f9c4ebd08ef) | Search field above an equal three-column grid; media badges identify special items. | Best reference for predictable, fast visual scanning. |
| [Lemon8 Home](https://mobbin.com/screens/894274f3-fd6e-44b2-af34-a1e0aab26a7f) | Editorial hero, `Editor's Picks`, and hashtag rows with chevrons. | A meaningful outlier: discovery/editorial hierarchy, not a history list. |
| [Picsart Creators](https://mobbin.com/screens/d952dd3e-6231-414a-94d6-3039afaa3953) | Repeated list rows with identity, `Follow`, and a horizontal strip of thumbnails. | Shows a compact list when the row's metadata and action matter more than one large image. |
| [Cosmos Media Library](https://mobbin.com/screens/b5a53d73-3302-4c4a-ba5a-5dec6fe5a873) | `Your Library`, search and add actions, filter chips (`All elements`, `Images`, `Videos`, `Links`), two-column tiles, and `Elements/Clusters`. | Closest structural reference for a personal media library with global filters. |
| [CapCut Projects](https://mobbin.com/screens/0faea8ac-1eb1-40d2-bb07-76e7ae9f8809) | Large `New project` CTA followed by rows with thumbnail, timestamp, file size, duration, and overflow menu. | Strong list-mode reference for metadata-rich personal content. |
| [Lapse Memories](https://mobbin.com/screens/ec30b588-bd9e-4443-b69a-4e79363fb06a) | `Snaps/Albums/Tagged`, a date rail, grouped memories, item counts, and a hold-to-view action. | Supports grouping a personal history by time without turning it into a social feed. |
| [Airbnb Wishlists](https://mobbin.com/screens/f07129eb-51e2-4036-9085-514580621de3) | Named collection tiles with cover images, saved counts, and an `Edit` action. | Useful if posing later adds albums; too much structure for the current capture history. |

### Flow anchors

- [Airbnb — Switching to map view](https://mobbin.com/flows/11dcbf0c-d2a0-4f3c-833b-cc0b0a50477d) shows a five-screen transition from list to map, a selected item card, another selection, and a final map state. The important transferable behavior is that the view changes while the user's context remains intact.
- [Airbnb — Filtering search results](https://mobbin.com/flows/9404b847-12ad-45f5-98c5-a1637ae16254) shows a full-screen Filters task with segmented options, a price histogram/range, `Clear all`, and a sticky `Show …` result action.
- [Airbnb — Saving a listing to a new wishlist](https://mobbin.com/flows/fa29583e-d768-42ad-a028-4037b322bdfe) shows a detail action opening a short bottom sheet, text entry for a new collection, keyboard state, and an inline confirmation with `Change`.

## Observed patterns

- Gallery surfaces keep the media collection as the dominant content. Search,
  mode, and filter controls stay in a compact top rail or become contextual.
- There are two legitimate density modes: equal tiles for rapid recognition,
  and rows when metadata, status, or per-item actions are important.
- Masonry is visually expressive but makes chronology and comparison harder.
  Fixed grids are easier to scan and keep item positions predictable.
- Personal libraries benefit from time or collection grouping. Lapse uses time;
  Airbnb uses named collections; Cosmos uses type chips and clusters.
- Per-item actions are usually contextual (`…`, heart, or row overflow). They
  should not compete with the primary tap target.
- View switching should preserve the same data, filter state, and approximate
  scroll position. It is a presentation change, not a new destination.
- Full-screen filters work when there are enough dimensions to configure. A
  small gallery should use a short sheet or inline chips instead of recreating
  Airbnb's long form.

## Meaningful variations

| Variation | Seen in | Implication for posing |
| --- | --- | --- |
| Equal three-column grid vs. variable two-column masonry | Instagram vs. Pinterest/Cosmos | Use predictable equal tiles for comparison; reserve masonry for a deliberate visual-first mode. |
| Editorial hero/feed vs. personal library | Lemon8/YouTube/Unfold vs. Cosmos/CapCut/Lapse | Gallery should start with the user's captured items, not a hero or recommendation module. |
| Date grouping vs. named collections | Lapse vs. Airbnb | Current data already has `today` and `yesterday`; compact date filters are the lowest-complexity retrieval aid. |
| Global type chips vs. per-item overflow | Cosmos vs. CapCut/Pinterest | Keep filters global and stable; expose destructive/share actions only from the item menu or detail. |
| Short view toggle vs. full filter task | Airbnb Switching View vs. Airbnb Filtering | List/grid needs a compact toggle; only promote filters to a sheet when there are real dimensions to set. |

## Reference → Pattern → Principle → Product-specific implementation

| Reference | Pattern | Principle | posing implementation |
| --- | --- | --- | --- |
| Cosmos Media Library, Lapse Memories | A personal collection has type/date context before the tiles. | Retrieval is faster when the collection explains what is being shown. | Keep `Today` and `Yesterday` sections, show a count per section when useful, and expose a compact `All / With match / Pending` filter only if those states exist in product data. |
| Instagram Search, Pinterest Browse | Grid density is tuned to the scanning task. | Predictable positions support comparison; variable ratios support visual discovery. | Make a two-column staggered grid the only browse mode for captured photos. Keep each tile's full photo tappable, avoid adding text over the image, and keep date headers out of repeated content. |
| CapCut Projects, Picsart Creators | Rows reserve space for thumbnail + metadata + one action. | List mode is valuable when the user needs to identify or manage an item, not just recognize it. | Do not add list mode until metadata-heavy management becomes a validated use case. |
| Airbnb Switching View | The presentation changes without losing context. | A view toggle should not reset the user's work. | Not adopted: Gallery has one visual mode, so there is no presentation state to preserve. Back still returns to the same Gallery filter context. |
| Airbnb Filtering | A multi-dimensional filter is a short task with a clear result action. | The user should know what changed and how many results remain. | Start with inline chips. If filtering grows, use a bottom sheet with `Clear all`, selected-state summary, and `Apply`/result count; do not hide the current gallery unnecessarily. |
| Airbnb Saving to Collection | Item action opens a short subordinate sheet and confirms inline. | Secondary organization should preserve the initiating item. | Do not add albums in the first gallery version. If albums become a requirement, use a sheet and return to the same photo/detail state after create/select. |

## Flow model

```text
  Gallery tab / Camera latest-photo affordance
    → Gallery (ready)
        ├─ apply filter → updating → filtered content / empty recovery
        ├─ tap photo → Gallery photo detail → Back → Gallery context restored
        ├─ item overflow → short action sheet → share/delete result
        └─ local capture pending → processing item → ready / failed retry
```

Required lifecycle states:

  - **Loading:** keep the Gallery title and controls stable; use photo-sized
    skeletons so the staggered layout does not jump.
  - **Ready:** staggered grid with an explicit active date filter; dates do not need repeated headers on every screenful.
- **Updating:** preserve the existing collection while filter results refresh;
  do not replace the whole screen with a spinner.
- **Empty:** explain whether there are no captures or no filter matches. Offer
  `Capture a pose` for the first case and `Clear filters` for the second.
- **Error:** keep the last confirmed list when possible and provide `Retry`.
- **Offline:** show cached photos with a small freshness/offline note; local
  captures should remain available if that is the product contract.
- **Pending/failed capture:** a placeholder or processing row must identify the
  state and expose retry/recovery rather than looking like a broken image.
- **Detail interruption:** Back from detail or an action sheet returns to the
  initiating Gallery position; destructive deletion requires confirmation and a
  recoverable success message where the product supports undo.

  ## Adopt

  - Date-aware retrieval through compact filters (`Today`, `Yesterday`, then older buckets).
  - Staggered two-column grid as the only Gallery presentation mode.
    - Compact top controls: title and a filter affordance whose selected state is
      always visible.
  - Full-photo tap target; contextual overflow for secondary actions.
  - State-preserving transitions and inline loading/error/empty recovery.

  ## Scaling the date filter

  For a collection spanning many dates, keep the chip row semantic rather than
  turning it into a date navigator:

  - Keep a short set of fixed buckets such as `All`, `Today`, `7 days`, and `30 days`.
  - Add one `Date` chip that opens a short bottom-sheet date or date-range picker.
  - When a custom range is active, replace the label with the selected range and
    keep a clear affordance in the same sheet.
  - Do not render one chip per day. Horizontal scrolling is acceptable for a few
    stable filters, not for 100 dynamic dates.

  ## Avoid

  - Editorial hero, recommendations, or social engagement chrome in a private
    capture history.
  - Masonry without a clear filter/context when the collection spans many dates.
  - Permanent `Delete`, `Share`, and other destructive controls on every card.
- Named collections/albums until the product has a real organization use case.
- A full-screen filter flow for only one or two filter dimensions.

## Current prototype baseline

This is code evidence from the existing static prototype, not a Mobbin finding:

  - `screens/gallery.html` defines the Gallery destination and exposes only the
    compact date filters; Gallery does not expose a view toggle because the product
    decision is grid-only.
  - `scripts/app.js` renders date-aware fixtures, applies the active date filter,
    alternates tall/square/wide media ratios, supports placeholders, and routes
    each item to `gallery-detail-v2.html`.

## Open questions

- Is Gallery local-only, synced, or a mixture? This determines offline behavior,
  retention, and loading/error copy.
- What are the real item states: captured, extracting, matched, failed, deleted,
  or unavailable? Filter chips should only represent states the backend can
  guarantee.
- Is the primary Gallery action opening detail, retrying extraction, trying the
  pose again, sharing, or deleting? Mobbin can show patterns but cannot answer
  this product priority.
  - Should older date sections collapse once the collection grows? Keep the
    staggered grid until chronology or collection size creates a concrete need for
    another presentation.
- Do we need search in Gallery, or is date/filter navigation sufficient for the
  expected collection size?
