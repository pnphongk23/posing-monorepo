# Search prototype design notes

## Research signal

The new search prototype was informed by a focused Mobbin review of iOS
search screens and related flows:

- [Gojek search](https://mobbin.com/screens/2405dc59-f53d-43b9-9715-cfaa81ddee0e): search history, category shortcuts, and trending entry points reduce the blank state.
- [Airbnb destination search](https://mobbin.com/screens/74bd15ab-2ebd-447b-aea4-68ce596c2140): a prominent query field is paired with structured follow-up choices instead of asking users to type everything.
- [Spotify search](https://mobbin.com/screens/6b1d14a0-c708-4790-a626-491401c6e2b7): browse categories make discovery useful before a query exists.
- [Airbnb map results](https://mobbin.com/screens/24072f6f-71d3-47f1-92e3-3b63bf4b1b43): results keep the primary content visible while refinement controls stay close to the result set.
- [Klook flight results](https://mobbin.com/screens/23a02d70-c862-4d0a-b680-1e1fb3dd9ad3): comparison-oriented results expose filters and next actions without hiding the current selection.

These references were used for interaction patterns, not visual copying. The
prototype does not use the previous search screen as a design reference.

## Adopted pattern

Search is a push destination from the pose library. It opens in a focused
discovery state:

1. A single large search field accepts title queries and is the only primary
   action on the screen.
2. Recent searches provide one-tap return paths without adding a second
   browsing system.
3. Once the user has a query, discovery is replaced by a focused result state
   with source filters and a count.

The screen deliberately omits source cards, suggested-title sections, and
marketing copy. They do not help the core job enough to earn space before a
query exists; source choice appears only when it can refine visible results.

## Navigation and states

- Back returns to `poses-list.html` and preserves the normal browser/hardware
  Back behavior.
- Opening a pose pushes its detail screen; search query and source are kept in
  the URL so the initiating context can be restored.
- Clear removes only the query. A selected source remains selected.
- `ready` shows discovery, `q`/`source` shows results, `loading` shows an
  in-context progress state, `error` preserves the query with retry,
  `offline` shows the last confirmed list with a freshness note, and `empty`
  explains the missing match with a recovery action.
- Results remain in the existing scroll container so long content does not
  cover the bottom navigation dock.
