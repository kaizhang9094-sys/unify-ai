# DEBUG staging federation smoke (optional override only)

**Default:** Debug and Release both use production:

`https://unify-federation-server-production.up.railway.app`

Do **not** commit LAN IPs, `trycloudflare.com`, or tunnel URLs in the Xcode scheme. The shared `AnumAPP` scheme must not set `UNIFY_DEBUG_FEDERATION_BASE_URL` by default.

## Optional Debug-only override

To point a local Debug build at a staging server temporarily:

1. Xcode → Scheme → Run → Environment Variables
2. Add `UNIFY_DEBUG_FEDERATION_BASE_URL` = `https://your-staging-host.example.com` (HTTPS only for device testing)
3. Launch and confirm log:

```
[ExchangeBootstrap] federationBaseURL=https://your-staging-host.example.com source=debugEnvironment
```

When unset, expect:

```
[ExchangeBootstrap] federationBaseURL=https://unify-federation-server-production.up.railway.app source=productionDefault
```

## Clear persisted override

If a prior smoke test stored a URL in UserDefaults:

```swift
ExchangeBootstrap.setDebugFederationBaseURLOverride(nil)
```

Local/LAN/tunnel hosts in UserDefaults are auto-cleared on launch.

## Local server rehearsal (developer machine only)

Run federation-server locally, then set the Debug env override to your staging HTTPS URL for the duration of the test. Do not commit that URL to the repo or scheme.

All Exchange HTTP clients resolve via `ExchangeBootstrap.resolvedFederationBaseURL()`.
