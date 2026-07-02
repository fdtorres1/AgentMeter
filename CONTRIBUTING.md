# Contributing to AgentMeter

Thanks for your interest! PRs are welcome. For anything beyond a small fix,
please open an issue first so we can agree on the approach before you invest
time.

## Building and testing

```bash
swift build          # debug build
swift test           # unit tests (network-dependent tests are opt-in and skip by default)
scripts/bundle.sh    # produce AgentMeter.app in the repo root
```

Requirements: macOS 14+, Xcode command line tools (Swift 5.10+).

## Adding a provider

Each provider is one file in `Sources/AgentMeter/Providers/` implementing the
`UsageProvider` protocol:

1. `isDetected` must be cheap and prompt-free (file existence checks only —
   no Keychain reads, no network).
2. `fetch()` reads credentials fresh from the provider's own local storage,
   calls the provider's API, and maps the response to `UsageWindow`s
   (percent used + optional reset date).
3. Credentials must never be written to disk or sent anywhere except the
   provider's own API. This is the project's core promise.
4. Register the provider in `UsageStore.defaultProviders` and add unit tests
   for the response mapping (see `Tests/AgentMeterTests/` for examples).

## Ground rules

- Keep it small: this is a menu bar utility, not a dashboard suite.
- No analytics, no telemetry, no third-party dependencies without discussion.
- Issues marked `good first issue` are a fine place to start.

## Releases

Maintainer-only; see [docs/RELEASING.md](docs/RELEASING.md).
