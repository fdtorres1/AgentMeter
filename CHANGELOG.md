# Changelog

All notable changes to AgentMeter. Format follows [Keep a Changelog](https://keepachangelog.com);
versions follow semantic-ish `MAJOR.MINOR.PATCH`.

## [1.11.4] — 2026-09-22

### Fixed
- The menu bar panel now scrolls long provider lists while keeping Refresh,
  Usage Details, Settings, updates, Support, and Quit visible below the list.
  Its height follows the popup's display, and short lists remain compact.
- A translucent bottom fade and small down chevron indicate more providers
  below; the cue disappears when the list reaches the bottom.

## [1.11.3] — 2026-09-21

### Changed
- Agent skill (`agentmeter skill`) now explains multiple Codex accounts
  (`codex` vs `codex:<uuid>`, matching your own account by `accountEmail`),
  `planType`, and that `renewal` is billing information, not quota.

### Documentation
- New docs/CODEX_ACCOUNTS.md guide (multi-account setup, how accounts appear,
  renewal tracking, troubleshooting). README, docs/AGENT_INTERFACE.md (schema
  history, multi-account ids, refresh cadence, debugging), docs/RELEASING.md
  (actual local flow, artifact table), the agent skill, and AGENTS.md brought
  in line with 1.11.x.

## [1.11.2] — 2026-09-21

### Added
- Settings → Providers → Codex accounts now auto-discovers `~/.codex-*` homes
  that already have a Codex login and offers a one-click **Add** (label taken
  from the folder name), so accounts signed in from Terminal show up
  without retyping paths.

## [1.11.1] — 2026-09-21

### Fixed
- The "Copy login command" for extra Codex accounts now creates the home
  directory first (`mkdir -p … && CODEX_HOME=… codex login`); Codex refuses
  to start when `CODEX_HOME` does not exist yet. Paths with spaces are quoted.

## [1.11.0] — 2026-09-21

### Added
- **Multiple Codex accounts.** Add extra Codex homes in Settings → Providers
  (sign in with `CODEX_HOME=~/.codex-<label> codex login`); each account gets
  its own meter, menu bar entry (`CxW`, …), email and plan label, and snapshot
  entry (`codex:<id>`). AgentMeter never performs logins or reads tokens.
- **Live Codex data via the app-server protocol.** Codex usage now comes from
  `codex app-server` (`account/rateLimits/read`, `account/read`) — spawned for
  about a second, polled every 5 minutes — instead of only the last session
  log, which could be hours or days stale. Session logs remain the instant
  in-session update path and the offline fallback.
- **Subscription renewal tracking** for Codex accounts: record the renewal
  date and billing platform (ChatGPT / Apple / Google Play), see the expected
  next renewal as a distinct row (never mixed with usage windows), mark it
  confirmed, and get an optional reminder 1/3/7 days before.
- Snapshot schema (still v1, additive): `accountEmail`, `planType`, and
  `renewal { expectedAt, platform, confirmedAt }` per provider.
- `AGENTMETER_DEBUG=1` enables structural stderr tracing for development.

## [1.10.0] — 2026-09-21

### Added
- Agent skill: `agentmeter skill` prints a ready-to-install `SKILL.md`
  (canonical copy in docs/agent-skill/) that teaches Codex, Claude Code, and
  Cursor agents to check remaining quota before large tasks, interpret the
  snapshot, and never read credentials themselves.
- Settings → General → "Install Command-Line Tool…" symlinks the bundled CLI
  into `/usr/local/bin` (with the standard admin prompt when required) and
  shows whether `agentmeter` is already on your PATH.

### Fixed
- `agentmeter doctor` now prints balances with two decimals instead of raw
  floating-point values.

## [1.9.0] — 2026-07-28

### Added
- Agent & CLI access (opt-in, Settings → General): AgentMeter writes an
  atomic, schema-versioned `status.json` snapshot (usage numbers only, never
  credentials) to Application Support after each refresh.
- Bundled `agentmeter` CLI (`Contents/Helpers/agentmeter`, on PATH via
  Homebrew): `status [--json]`, `refresh [--wait N]`, and a redacted `doctor`
  report. The CLI is a thin read-only client — the app remains the only
  process that touches credentials or provider APIs.
- `agentmeter://refresh` and `agentmeter://details` URL actions.
- Usage Details window (⌘D from the dropdown): the same provider meters in a
  regular, resizable window — friendlier for screen sharing and
  computer-control agents.
- Schema and security model documented in docs/AGENT_INTERFACE.md.

## [1.8.0] — 2026-07-23

### Added
- VoiceOver support for the menu bar item: the rendered title now carries a
  spoken summary ("AgentMeter. Codex: 25% used. Cursor: 82% used, high
  usage…") in all display styles, including icon-only mode.
- Usage meters, balance rows, and provider sections are proper accessibility
  elements with spoken labels, values, reset times, and severity qualifiers
  ("high usage", "nearly used up", "low balance", "data is stale") that
  respect the used/remaining display setting.
- Severity is no longer color-only: meters and low balances show a small
  warning/critical symbol alongside the tinted bar and text.
- VoiceOver announcements for key actions: diagnostics copied, API key
  saved/removed, OpenRouter connected or failed.
- Copy Diagnostics now confirms visually with a checkmark.

### Changed
- Provider dashboard names and footer controls expose proper link/button
  semantics, tooltips, and accessibility labels.
- Disabled alert pickers explain that notifications must be enabled first.
- Low-balance tinting in the dropdown now follows the alert threshold setting
  instead of a hardcoded $5.

## [1.7.0] — 2026-07-23

### Added
- Key type detection: after saving or connecting an API key, Settings shows
  what kind of key it is (e.g. Venice Admin vs. Inference, OpenRouter
  management/limited/standard, Z.ai GLM Coding Plan vs. standard) with a
  plain-language summary written for non-technical users.
- An expandable "About this key" section under each saved credential explains
  what the key can do, confirms AgentMeter only reads usage/balance and can
  never spend, and links directly to the provider's key-management page.
- Least-privilege guidance: when a safer key type would work equally well
  (e.g. a Venice Inference key), AgentMeter says so instead of pushing users
  toward more powerful keys.

## [1.6.6] — 2026-07-23

### Fixed
- Venice Inference API keys now fall back to `/api_keys/rate_limits` for
  USD/DIEM balances when the Admin-only billing endpoint returns 401.
- Venice billing responses now decode the production lowercase, nullable, and
  string-encoded balance fields (not only the older uppercase test fixture).
- Venice Settings explain supported key types and the x402 wallet limitation.

## [1.6.5] — 2026-07-23

### Changed
- Z.ai credential setup is explicitly labeled as a GLM Coding Plan API key and
  explains that standard API billing/balance cannot be queried. The key field
  remains because Coding Plan monitoring itself authenticates with that key.

## [1.6.4] — 2026-07-23

### Fixed
- Z.ai no longer reports a valid standard API key as rejected when the account
  has no GLM Coding Plan. It now explains that quota monitoring is Coding
  Plan–only. Other API body errors are also reported accurately.

## [1.6.3] — 2026-07-23

### Fixed
- OpenRouter OAuth-provisioned keys now use the regular-key `/api/v1/key`
  endpoint, with account credits as optional enrichment. The previous
  implementation depended only on `/credits`, which OpenRouter documents as a
  management-key endpoint.
- OpenRouter PKCE verifier persists across app activation/relaunch during the
  browser callback; connection progress and failures are visible in Settings.
- OpenRouter Settings now offers manual API-key paste as a fallback.
- Fixed an extra parenthesis in the OpenRouter HTTP error message.

## [1.6.2] — 2026-07-23

### Changed
- Release tooling: notarization credentials now sourced from 1Password (op-sa) instead of machine-local paths. No user-facing changes.

## [1.6.1] — 2026-07-23

### Fixed
- App icon was distorted (non-square source stretched into the iconset); replaced with a correctly proportioned square icon.

## [1.6.0] — 2026-07-23

### Added
- Stale-data handling: when a refresh fails, the last-known meters stay visible
  (dimmed, with a "stale since" note) instead of being replaced by an error.
- Menu bar color states: provider entries tint yellow/red at the same
  thresholds as the meters; stale entries dim.
- Menu bar style picker: Full / Compact (worst only) / Icon only.
- Copy Diagnostics button (Settings → General): redacted troubleshooting
  report — never includes keys or tokens.
- About window with version, credits, and licenses.
- This changelog.

### Changed
- The menu bar title is now rendered as an image to support per-provider color.

## [1.5.0] — 2026-07-23

### Added
- Spanish localization; the app follows the macOS system language. All strings
  live in a String Catalog — community translations welcome.
- Homebrew tap: `brew install --cask fdtorres1/tap/agentmeter`.

## [1.4.0] — 2026-07-23

### Added
- Sparkle auto-updates with EdDSA-signed appcast served from the latest GitHub
  release. "Check for Updates…" now runs Sparkle's standard flow.

## [1.3.2] — 2026-07-23

### Changed
- Settings moved from the dropdown into a native tabbed window
  (General / Providers / Display / Alerts); the dropdown closes when opening it.
- Alert threshold labels follow the count-direction display setting.
- Provider monogram badges in Settings and the dropdown; unified footer styling.

## [1.3.0] — 2026-07-23

### Added
- Count direction display option ("% used" / "% left").
- Reset time display option (relative / exact date-time).
- Refresh on wake from sleep.
- Low-balance notifications for pay-as-you-go providers ($1/$5/$10).
- Menu bar options: per-provider visibility and compact mode.
- Click a provider's name to open its usage dashboard.

## [1.1.0] — 2026-07-22

### Added
- Five API-key providers: OpenRouter (OAuth PKCE or pasted key), DeepSeek,
  Kimi (Moonshot), Z.ai (coding-plan quota), Venice. Keys live in the macOS
  Keychain, masked in Settings, sent only to their own provider.
- Balance display for pay-as-you-go providers.
- Threshold notifications (opt-in, 70/80/90%, once per window).

## [1.0.0] — 2026-07-22

Initial release: menu bar meters for Codex/ChatGPT (5h + weekly), Cursor
(plan usage + billing cycle), Claude Code, and Gemini, with reset countdowns,
per-provider Auto/On/Off, launch at login, and zero telemetry. Signed and
notarized.
