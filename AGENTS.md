# AgentMeter — Agent Context

macOS menu bar app (SwiftUI, Swift Package, macOS 14+) showing AI coding usage
limits for Codex (multiple accounts), Cursor, Claude Code, Gemini, Claude API reporting, and
pay-as-you-go balances for OpenRouter, DeepSeek, Kimi, Z.ai, and Venice.
Public repo: https://github.com/fdtorres1/AgentMeter. Current release line:
1.12.x (see CHANGELOG.md). Test suite: 164 tests (`swift test`).

**If `HANDOFF.md` exists in the repo root, read it first.** It is the
gitignored, machine-local session handoff (current state, pending work,
announcement drafts, environment specifics) and complements this file.

## Architecture

- One file per provider in `Sources/AgentMeter/Providers/`, each implementing
  the `UsageProvider` protocol (`id`, `displayName`, `shortCode`, `isDetected`,
  `fetch() -> ProviderUsage`, optional `assessCredential()`,
  `credentialHelpText`, `apiKeyPlaceholder`, `dashboardURL`). Built by
  `UsageStore.defaultProviders(extraAccounts:)` — the list is DYNAMIC: extra
  Codex accounts (`CodexProvider(accountConfig:)`, id `codex:<uuid>`) are
  inserted after the primary `codex`, and `UsageStore.rebuildProviders()` runs
  when `SettingsStore.codexExtraAccounts` changes.
- `UsageStore` (@MainActor ObservableObject): per-provider `ProviderState`
  (`loading`/`ready`/`stale`/`error`), refresh timer, `DispatchSource` file
  watcher on the newest Codex session file, wake/credential-change observers,
  menu bar title/entries + spoken `menuBarAccessibilityDescription`, and the
  post-refresh `StatusSnapshotWriter` call.
- `SettingsStore` (UserDefaults): per-provider visibility (`auto`/`on`/`off`;
  `auto` = show only when `isDetected`), refresh interval (30s/1m/5m),
  notifications + thresholds, count direction, reset-time style, menu bar
  style (full/compact/icon), `agentAccessEnabled`, `codexExtraAccounts`
  (`[CodexAccountConfig]`, JSON), `subscriptionRenewals`
  (`[providerID: SubscriptionRenewal]`, JSON).
- UI: `MenuContent` (dropdown with a display-bounded scrolling provider list
  and a fixed footer; short lists shrink to their content; provider sections live in
  `ProviderUsageSections.swift` and are shared with `UsageDetailsView`, the
  ⌘D / `agentmeter://details` window), `SettingsWindow` (native tabbed
  Settings: General / Providers / Display / Alerts; includes
  `CodexAccountsSection` with auto-discovery of `~/.codex-*` homes and
  `CodexSubscriptionSettings`), `AboutWindow`. Menu bar title is a rendered
  `NSImage` (`MenuBarTitleRenderer`) with an `accessibilityDescription`.
- Cross-cutting: `CredentialAssessment` (key-type detection + plain-language
  explainers), `UsageMeterSeverity` (shared 60/85% thresholds, symbols,
  spoken qualifiers), `NotificationManager` (`ThresholdTracker`,
  `RenewalTracker`), `SubscriptionRenewal` (anniversary math; billing dates
  are NEVER merged with usage windows), `ErrorRedaction`, `Diagnostics`,
  `DebugLog` (`AGENTMETER_DEBUG=1` stderr tracing; never credentials).
- Agent/CLI interface (v1.9.0): opt-in `status.json` snapshot in Application
  Support written by `StatusSnapshotWriter` after each refresh; shared schema
  lives in the `AgentMeterStatusKit` library target; `agentmeter-cli` is a
  read-only executable product installed as `Contents/Helpers/agentmeter`.
  GOTCHA: the product MUST stay named `agentmeter-cli` and ship in `Helpers/`
  — "agentmeter" and "AgentMeter" clobber each other on case-insensitive APFS
  (both in `.build/release/` and in `Contents/MacOS/`). Schema doc:
  docs/AGENT_INTERFACE.md (additive changes only within schemaVersion 1).
  `agentmeter skill` prints `docs/agent-skill/SKILL.md`, embedded as
  `AgentSkill.markdown` — a test enforces byte identity, so edit the .md and
  regenerate the Swift constant together (see Conventions).

## Provider data sources (validated formats)

- **Codex** (v1.11.0+): primary source is the Codex CLI app-server protocol.
  `CodexAppServerClient` spawns `codex app-server` (resolved from
  /opt/homebrew/bin, /usr/local/bin, ~/.local/bin, PATH, then `zsh -lc`),
  speaks newline-delimited JSON-RPC over stdio: `initialize` (clientInfo) →
  `initialized` notification → `account/read` (`{account:{email,planType}}`
  or `account:null`) → `account/rateLimits/read` (`rateLimits.primary/
  secondary{usedPercent,windowDurationMins,resetsAt(epoch s)}`, `credits`,
  `planType`; error "authentication required" when signed out). Pipelining
  all four lines up front is fine; skip lines without our ids. ~1 s round
  trip; process is terminated afterwards — never persistent. Polled at most
  every 5 min per account (`CodexAppServerClient.pollInterval`), cached in
  `CodexAccountCache`. Extra accounts = `CodexAccountConfig` entries in
  `SettingsStore.codexExtraAccounts`, each with its own `CODEX_HOME`; the
  user signs in via `mkdir -p <home> && CODEX_HOME=<home> codex login` (Codex refuses a nonexistent CODEX_HOME) — AgentMeter never logs
  in or reads auth.json. The protocol has NO account-switch method;
  `~/.codex/accounts.json` is written by the Codex desktop app only.
  FALLBACK (primary account only): parse newest
  `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` backwards for the last
  `rate_limits` snapshot (`primary`/`secondary`, `used_percent`, `resets_at`,
  `plan_type`); also preferred when its timestamp is newer than the cache.
  `agentmeter` tracing: `AGENTMETER_DEBUG=1` (DebugLog) prints structural
  info to stderr — NOTE: when launched directly from a shell (not via `open`)
  the initial refresh may not complete; test with `open`.
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
- **Claude API** (`claude-api`, v1.12.0): separate from subscription Claude.
  Keychain API key must have organization reporting access. Read-only GET
  `/v1/organizations/cost_report` and `/v1/organizations/usage_report/messages`
  return organization-wide UTC monthly spend and token categories. Costs are
  decimal-string cents; convert to USD. Daily report end is next UTC midnight
  to include today's partial bucket. Paginate both reports. Cache for five
  minutes (60-second failure cooldown), keyed by credential digest and month;
  explicit menu/CLI refresh bypasses successful cached reports. Concurrent
  refreshes share a request; failed refreshes cannot reuse an old cached success.
  Actual coverage `periodEnd` comes from returned bucket ends, capped at fetch
  time, using the older of cost and token coverage. API `asOf` is last checked;
  do not claim the current day is reported just because a fetch succeeded.
  do not log keys or response bodies. No public prepaid-credit endpoint:
  explicitly unavailable plus billing link, never an estimated balance.
  `ProviderUsage.apiUsage` holds the detail; `.spent` balance supports menu
  summaries and old CLI readers. Key changes clear state and ignore old fetches.
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
   (`shasum -a 256 AgentMeter.zip`), commit, push. The cask has a `binary`
   stanza for `Contents/Helpers/agentmeter` (added in 1.9.0) — keep it.
6. Install locally to verify (`cp -R AgentMeter.app /Applications/`), tick the
   roadmap (issue #1), close the milestone.

Gotchas:
- `generate_appcast` (in `release.sh`) may trigger a macOS Keychain prompt for
  the Sparkle key if the Sparkle tool binary changed (e.g. after an SPM
  re-resolve). Approve with "Always Allow" — it blocks the release until then.
- `appcast.xml` is gitignored (build artifact); it lives only as a release asset.
- `.build/`, `*.app/`, `HANDOFF.md` are gitignored. `AgentMeter.zip` IS
  tracked (historical); `release.sh` overwrites it — run
  `git checkout -- AgentMeter.zip` before committing unrelated work.
- `/tmp/homebrew-tap` may be gone between sessions; reclone
  `https://github.com/fdtorres1/homebrew-tap` before bumping the cask.
- Running the app binary directly from a shell (for `AGENTMETER_DEBUG`) can
  leave the initial refresh incomplete; verify behavior with `open`.

## Conventions

- Keep PR titles human-readable — the release workflow uses
  `generate_release_notes: true`, so they become the changelog.
- Public issue tracking only (no Discussions). Roadmap is pinned+locked issue #1.
- Author commits with a real identity; the repo's initial history was recreated
  once to strip a secret-scanner false positive, so avoid rewriting history.
- Localization: every user-facing string goes through `L()` and gets en + es
  entries in `Sources/AgentMeter/Resources/Localizable.xcstrings`; then run
  `xcrun xcstringstool compile Sources/AgentMeter/Resources/Localizable.xcstrings
  --output-directory Sources/AgentMeter/Resources` (bundle.sh does this too).
  CLI output and docs are English-only.
- Agent skill: `docs/agent-skill/SKILL.md` is canonical; after editing it,
  regenerate `Sources/AgentMeterStatusKit/AgentSkill.swift` so the raw-string
  constant is byte-identical (`AgentSkillTests` fails otherwise).
- Snapshot schema (`AgentMeterStatusKit`): additive optional fields only
  within `schemaVersion` 1; update docs/AGENT_INTERFACE.md tables and the
  fixture test in the same change.
- Accessibility: every new meter/row is one accessibility element with a
  label + value; severity is never color-only (`UsageMeterSeverity`); state
  changes post `AccessibilityNotification.Announcement`.
- Delegation pattern that has worked: spec bounded implementation tasks to a
  subagent, then review every diff, run the suite, and live-test against the
  installed app before releasing. Subagents sometimes create a stray branch
  at HEAD — `git checkout main` carries the working tree back.
