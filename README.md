# Unify AI

Unify is a privacy-first iOS application for discovery, private AI assistance, and direct coordination.

This public repository contains the application source, Swift packages, tests, and engineering documentation. Large local model weights, build products, and generated Xcode artifacts are intentionally excluded.

## Project focus

- Natural-language discovery and matching
- Private, on-device AI workflows
- Local model runtime integration
- Human-controlled communication and exchange flows
- Federation support for development and staging

## Local development

Open `AnumAPP/AnumAPP.xcodeproj` in Xcode on macOS. The `AnumCore` Swift package can be tested independently with Swift Package Manager.

The default federation endpoint and optional staging override are documented in `AnumAPP/DEBUG-STAGING-FEDERATION-SMOKE.md`.

Model weights, credentials, private user data, production secrets, and local build directories are intentionally not part of this public repository.
