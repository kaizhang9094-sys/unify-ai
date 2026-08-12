---
name: Second-half UI projection parity TODO
overview: "Read-only backlog: minimal future tests so cached second-half UI reads (`getThread` / `InboxItem`) stay aligned with persisted `ExchangeSecondHalfAgencySnapshot` where the façade hydrates agency, plus projection-string hygiene for user-facing secretary cards—without changing production yet."
todos:
  - id: hydration-happy-facade
    content: "Add facade integration test: persisted ExchangeSecondHalfRecord.agency + role alignment → getThread secondHalfDisplay.agencyAssessment hydrated"
    status: pending
  - id: hydration-role-miss-facade
    content: "Add facade integration test: role/raw mismatch vs saved agency role → hydration skipped; document expected absence"
    status: pending
  - id: secretary-no-debug-strings-unit
    content: "Extend SecretaryProjectionEngineTests + fixture helper: hydrated DisplayModel strings exclude trace/debug/internal tokens"
    status: pending
isProject: false
---



