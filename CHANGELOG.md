# Changelog

All notable changes to AgentMeter. Format follows [Keep a Changelog](https://keepachangelog.com);
versions follow semantic-ish `MAJOR.MINOR.PATCH`.

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
