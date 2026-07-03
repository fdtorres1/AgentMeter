# AgentMeter — Agent Context

macOS menu bar app (SwiftUI, Swift Package, macOS 14+) showing AI coding usage
limits for Codex, Cursor, Claude Code, and Gemini. Public repo:
https://github.com/fdtorres1/AgentMeter

## Architecture

- One file per provider in `Sources/AgentMeter/Providers/`, each implementing
  the `UsageProvider` protocol (`id`, `displayName`, `shortCode`, `isDetected`,
  `fetch() -> ProviderUsage`). Registered in `UsageStore.defaultProviders`.
- `UsageStore` (@MainActor ObservableObject): per-provider `ProviderState`,
  refresh timer, and a `DispatchSource` file watcher on the newest Codex
  session file for instant updates after CLI activity.
- `SettingsStore`: per-provider visibility (`auto`/`on`/`off` in UserDefaults;
  `auto` = show only when `isDetected`) and refresh interval (30s/1m/5m).
- `MenuContent`: dropdown UI + inline settings panel. Menu bar title is built
  in `UsageStore.menuBarTitle`, e.g. `Cx 5% · Cu 20%` (worst window per
  provider).
- `UpdateChecker`: compares `CFBundleShortVersionString` against the latest
  GitHub release tag.

## Provider data sources (validated formats)

- **Codex**: no network. Parses newest `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`
  backwards for the last `rate_limits` snapshot (`primary` = 5h window,
  `secondary` = weekly; `used_percent`, `resets_at` epoch seconds, `plan_type`).
- **Cursor**: reads `cursorAuth/accessToken` from
  `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`
  (SQLite, read-only, queried in place — the DB is multi-GB, do not copy it).
  Cookie is `WorkosCursorSessionToken=<jwt-sub>::<token>` (percent-encoded);
  the `sub` claim MUST come from the JWT payload — the short `userId` from
  `~/.cursor/cli-config.json` only works on the legacy `/api/usage` endpoint,
  not `GET https://cursor.com/api/usage-summary`. Summary has
  `individualUsage.plan.{totalPercentUsed,autoPercentUsed,apiPercentUsed}`,
  with fallbacks to `individualUsage.overall` and `teamUsage.pooled`
  (used/limit cents) for team/enterprise accounts.
- **Claude**: OAuth creds from `~/.claude/.credentials.json`, falling back to
  Keychain item `Claude Code-credentials`. `expiresAt` is in **milliseconds**.
  Refresh: POST form-encoded to `https://platform.claude.com/v1/oauth/token`
  with client_id `9d1c250a-e61b-44d9-88ed-5944d1962f5e` (public). Usage:
  `GET https://api.anthropic.com/api/oauth/usage` with
  `anthropic-beta: oauth-2025-04-20` and a `claude-code/x.y.z` User-Agent;
  windows `five_hour`/`seven_day`/`seven_day_opus` with `utilization` percent
  and `resets_at` ISO8601. NOTE: the token endpoint rate-limits aggressively
  (HTTP 429 even for invalid tokens), so treat refresh failures gently.
- **Gemini**: OAuth creds from `~/.gemini/oauth_creds.json` (`expiry_date` in
  ms). Refresh via `oauth2.googleapis.com/token` with the Gemini CLI's public
  installed-app client (constants in `GeminiProvider`, split into string
  fragments only so GitHub secret scanning doesn't false-positive — Google
  documents installed-app secrets as non-confidential). Quota: POST
  `https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota` (body
  `{"project": id}` when `:loadCodeAssist` returns one); buckets have
  `modelId`, `remainingFraction` (0..1 remaining, invert for used), `resetTime`.

## Ground rules (project's core promise — do not violate)

- Credentials are read fresh from the other apps' own stores on each refresh,
  never written to disk, never logged, never sent anywhere except that
  provider's own API. Refreshed tokens live in memory only.
- `isDetected` must be cheap and prompt-free: file existence only. No Keychain
  reads (prompts), no network. (Claude's Keychain check uses
  `SecItemCopyMatching` without returning data, which does not prompt.)
- No analytics/telemetry, no third-party dependencies.
- Reading the desktop app containers (Claude.app cookies, Gemini.app auth blob)
  was considered and REJECTED: values are AES-encrypted via Keychain
  "Safe Storage" keys; decrypting them is fragile and trust-damaging. The CLI
  credential files are the intended source.

## Build / test / release

```bash
swift build                 # NOTE: run outside the tool sandbox; SwiftPM's own
                            # sandbox conflicts and errors with "sandbox_apply:
                            # Operation not permitted". Use full permissions.
swift test                  # 16 tests; live-network tests are opt-in via env
                            # (CURSOR_LIVE_TEST=1) and skip by default.
scripts/bundle.sh [--install]   # builds AgentMeter.app (ad-hoc signed by default)
scripts/release.sh          # Developer ID sign + notarize; needs SIGN_IDENTITY
                            # and notarization creds (see docs/RELEASING.md)
```

- CI: `.github/workflows/ci.yml` runs build+test on `macos-15` for push/PR.
- Release: `.github/workflows/release.yml` triggers on `v*` tags; needs the six
  signing secrets listed in `docs/RELEASING.md` (not yet added to the repo).
- A Developer ID cert exists in the local keychain:
  `Developer ID Application: Felix Torres (77Z6XS8JU8)`. Signed + hardened
  runtime builds verified locally; notarization not yet run (needs API key).

## Conventions

- Keep PR titles human-readable — the release workflow uses
  `generate_release_notes: true`, so they become the changelog.
- Public issue tracking only (no Discussions). Roadmap is pinned+locked issue #1.
- Author commits with a real identity; the repo's initial history was recreated
  once to strip a secret-scanner false positive, so avoid rewriting history.