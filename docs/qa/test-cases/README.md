# QA test cases — native iOS app

Columns: ID, priority, preconditions, steps, expected, automation. Automation is `automated: <flow file>` (one flow per case under `mobile/iosApp/maestro/flows/`, file name starts with the case ID), `manual`, or `pending: <reason>`. `mobile/iosApp/maestro/check-traceability.sh` enforces the mapping.

Scope is realistic user flows and common edge cases. Rare timing races are out of scope (unit tests own them).

Remote-config switches change what a run sees: `account_feature` (Saved/Account rows), `paywall_enabled` (capture gating). Each case states which state it needs. The Simulator has no camera: capture itself is manual or device-only.

Purchase E2E blockers: [purchase-e2e-blockers](../purchase-e2e-blockers.md).

Files: [browse-search](browse-search.md) · [pose-detail](pose-detail.md) · [camera-guide](camera-guide.md) · [capture-gallery](capture-gallery.md) · [saved-bookmarks](saved-bookmarks.md) · [account](account.md) · [paywall-purchase](paywall-purchase.md) · [settings](settings.md). Run instructions: [maestro README](../../../mobile/iosApp/maestro/README.md).
