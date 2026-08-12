# Unify AI

Unify is a privacy-first iOS application for discovery, private AI assistance, and direct coordination.

This public repository contains the application source, Swift packages, tests, and engineering documentation. Large local model weights, build products, and generated Xcode artifacts are intentionally excluded. Obtain model assets separately and place them in the locations documented by the project before building a full local-model configuration.

## Project focus

- Natural-language discovery and matching
- Private, on-device AI workflows
- Local model runtime integration
- Human-controlled communication and exchange flows
- Federation support for development and staging

## Local development

Open `AnumAPP/AnumAPP.xcodeproj` in Xcode on macOS. The `AnumCore` Swift package can be tested independently with Swift Package Manager.

The default federation endpoint and optional staging override are documented in `AnumAPP/DEBUG-STAGING-FEDERATION-SMOKE.md`.

## Public-release note

This repository is an engineering portfolio snapshot. Do not commit model weights, credentials, private user data, production secrets, or local build directories.
