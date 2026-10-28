# QA test cases — native iOS app

One file per feature area. Columns: ID, priority (P0 release blocker / P1 common / P2 edge), preconditions, steps, expected, automation (`maestro:<flow>` under `mobile/iosApp/maestro/flows/`, `manual`, or `pending` = feature not landed or no seam yet).

Scope is realistic user flows and common edge cases. Rare timing races are out of scope (unit tests own them).

Remote-config switches change what a run sees: `account_feature` (Saved/Account rows), `paywall_enabled` (capture gating). Each case states which state it needs. The Simulator has no camera: capture itself is manual or device-only.

Files: [browse-search](browse-search.md) · [pose-detail](pose-detail.md) · [camera-guide](camera-guide.md) · [capture-gallery](capture-gallery.md) · [saved-bookmarks](saved-bookmarks.md) · [account](account.md) · [paywall-purchase](paywall-purchase.md) · [settings](settings.md). Run instructions: [maestro README](../../../mobile/iosApp/maestro/README.md).
