# Secretary route load map (post desk-snapshot)

## Threads tab
- `SecretaryThreadListView`: `.task(isTabActive)` → `applyDeskSnapshot()` (reads `AppServices.secretaryDeskSnapshot` only).
- Pull-to-refresh → `refreshSecretaryDeskSnapshot(force: true)`.
- Row tap → `SecretaryWorkspaceView.openThread` → `getThread` (full) for social routing, then `.thread`.
- Recent Results mode only → `getThread` per session card.

## Inbound tab
- Mount: `applyDeskSnapshotInboxSeedIfAvailable()` then gated `load()`.
- `load()` → `listInboxItems(limit:800)` + trusted nodes + projection (skipped when snapshot/watermarks unchanged).
- Row tap (DM) → `openDirectMessageFromInbound` → metadata resolve → single `getThread(.directMessage)`.

## Direct message
- `SecretaryDirectMessageView.task` → `openOrCreateDirectMessageThread` + `getThread(hydrationMode: .directMessage)`.
- Federation pull gated on backoff/URL/scene; reload only when sync ran or local inbox delta.

## Profile tab
- `UnifyWorkspaceProfileShellView.task(isTabActive)` → `refreshSellerWorkspace()` only (skip if already hydrated).
- Desk snapshot refresh only via `requestSecretaryRefresh(.sellerWorkspaceChanged)` after publish/save.

## Route leave / return
- Switching to Inbound: no desk `manual` refresh (inbound view owns gated reload).
- App foreground / federation sync: `syncFederationInboxNow` → coalesced `requestSecretaryRefresh(.federationSync)`.
- Thread detail: `SecretaryThreadView` → full `getThread` + sync pass.
