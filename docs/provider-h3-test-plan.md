# Provider H3 test plan (no device)

Canonical coverage: `ExchangeOffer.serviceAreas[].spatial` (declared service area, not device GPS).

## A. Swift local tests (isolated target)

The full `AnumCoreTests` target may not compile due to unrelated broken files. Use the isolated target:

```bash
cd ~/Desktop/Anum/AnumCore
swift test --filter ProviderH3MetadataTests
```

Covers:

- `ExchangeProviderServiceCoverageTests` — builder, Codable, SQLite, publish payload, retrieval builder, remote ingest, overlap, privacy
- `ExchangeProviderH3RetrievalHarnessTests` — ingest preserves `serviceAreas`, overlap near Aurora

## B. Server unit tests

```bash
cd ~/Projects/unify-federation/federation-server
npm run test:service-areas-h3    # H3 normalization only
npm run test:provider-h3         # normalization + publish/search round-trip
```

## C. Local publish/search smoke (HTTP)

Against a running federation server (local or Railway):

```bash
cd ~/Projects/unify-federation/federation-server
FEDERATION_BASE_URL=http://127.0.0.1:3000 npm run smoke:provider-h3
# or staging:
# FEDERATION_BASE_URL=https://your-railway-host npm run smoke:provider-h3
```

## D–E. Retrieval / discovery

- **D:** `ExchangeProviderH3RetrievalHarnessTests` (Swift, no server)
- **E:** Optional full discovery via app UI or future mock-directory test; named-place requester H3 may be absent until geocoder UI exists. Use `currentDevice` test coordinate near Aurora for overlap experiments.

## Privacy checks (all layers)

- `regionTags` must not contain 15-char lowercase hex H3 cells
- `lexicalText` / UI copy must not embed `h3Cells`
