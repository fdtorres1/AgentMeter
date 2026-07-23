# Changelog

All notable changes to AgentMeter. Format follows [Keep a Changelog](https://keepachangelog.com);
versions follow semantic-ish `MAJOR.MINOR.PATCH`.

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
