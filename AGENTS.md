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

## Build / test

```bash
swift build                 # NOTE: run outside the tool sandbox; SwiftPM's own
                            # sandbox conflicts and errors with "sandbox_apply:
                            # Operation not permitted". Use full permissions.
swift test                  # live-network tests are opt-in via env
                            # (CURSOR_LIVE_TEST=1) and skip by default.
scripts/bundle.sh [--install]   # builds AgentMeter.app (ad-hoc signed by default)
```

- CI (`.github/workflows/ci.yml`) runs build+test on `macos-15` for push/PR.
- `.github/workflows/release.yml` is manual-dispatch only; releases are cut
  LOCALLY (see runbook below), so its signing secrets are not configured.

## Release runbook (the actual, tested end-to-end flow)

Releases are cut locally. This is the exact sequence run each time — reproduce
it faithfully. Full detail in [docs/RELEASING.md](docs/RELEASING.md).

Credentials (do NOT prompt for them):
- Signing identity: `Developer ID Application: Felix Torres (77Z6XS8JU8)`
  (login keychain) — pass as `SIGN_IDENTITY`.
- Notarization (App Store Connect API key, key-id, issuer): stored in 1Password,
  fetched automatically by `release.sh` via `op-sa` (vault Sage-Openclaw, item
  "AgentMeter Notarization (App Store Connect API)"; the `.p8` is stored
  base64 in field `private key b64`). No env vars needed.
- Sparkle EdDSA signing key: login keychain item "Private key for signing
  Sparkle updates"; backed up in 1Password (vault Sage-Openclaw, item
  "AgentMeter Sparkle EdDSA Private Key").

Steps (bump `X.Y.Z`, keep `CHANGELOG.md` updated first):
1. `git add -A && git commit && git push` on `main`.
2. Run `SIGN_IDENTITY="Developer ID Application: Felix Torres (77Z6XS8JU8)" \
   AGENTMETER_VERSION=X.Y.Z scripts/release.sh`. It pulls notarization creds
   from op-sa, builds, signs (inside-out incl. Sparkle framework), notarizes +
   waits, staples, zips, and writes a signed `appcast.xml`.
3. `git tag vX.Y.Z && git push origin vX.Y.Z`.
4. `gh release create vX.Y.Z AgentMeter.zip appcast.xml --title "AgentMeter X.Y.Z" --notes ...`
   — BOTH assets; the app's SUFeedURL is `releases/latest/download/appcast.xml`.
5. Bump the Homebrew cask in the separate repo `fdtorres1/homebrew-tap`
   (`/tmp/homebrew-tap` clone): update `version` + `sha256`
   (`shasum -a 256 AgentMeter.zip`), commit, push.
6. Install locally to verify (`cp -R AgentMeter.app /Applications/`), tick the
   roadmap (issue #1), close the milestone.

Gotchas:
- `generate_appcast` (in `release.sh`) may trigger a macOS Keychain prompt for
  the Sparkle key if the Sparkle tool binary changed (e.g. after an SPM
  re-resolve). Approve with "Always Allow" — it blocks the release until then.
- `appcast.xml` is gitignored (build artifact); it lives only as a release asset.
- `.build/`, `*.app/`, `HANDOFF.md` are gitignored.

## Conventions

- Keep PR titles human-readable — the release workflow uses
  `generate_release_notes: true`, so they become the changelog.
- Public issue tracking only (no Discussions). Roadmap is pinned+locked issue #1.
- Author commits with a real identity; the repo's initial history was recreated
  once to strip a secret-scanner false positive, so avoid rewriting history.