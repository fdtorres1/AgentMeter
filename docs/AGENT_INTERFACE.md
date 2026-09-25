# AgentMeter Agent & CLI Interface

AgentMeter exposes a read-only local interface for scripts and coding agents. The menu bar app is the only process that reads credentials or calls provider APIs. The CLI reads a snapshot file and can poke the app via URL schemes.

## Security model

- **Opt-in**: snapshot writing is disabled by default (`Settings → General → Enable agent & CLI access`).
- **No credentials**: the snapshot contains usage percentages, reported API spend/token counts, balances, and redacted error strings only.
- **CLI is read-only**: `agentmeter` never imports Security/Keychain, never performs network I/O, and never reads provider credential files.
- **App is sole handler**: only the running AgentMeter app refreshes usage and writes `status.json`.

## Snapshot file

| Property | Value |
|----------|-------|
| Path | `~/Library/Application Support/AgentMeter/status.json` |
| Format | JSON, UTF-8 |
| Dates | ISO 8601 |
| Current schema | `schemaVersion: 1` |

The file is written atomically after each refresh completes (visible providers only). It is deleted when agent access is turned off.

### Schema v1

Top-level object:

| Field | Type | Description |
|-------|------|-------------|
| `schemaVersion` | `Int` | Always `1` for this schema |
| `generatedAt` | `String` (ISO 8601) | When the snapshot was written |
| `appVersion` | `String` | AgentMeter app version |
| `providers` | `[ProviderStatus]` | Visible providers, in display order |

`ProviderStatus`:

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | Provider id: `codex`, `cursor`, `claude`, `gemini`, `openrouter`, `deepseek`, `moonshot`, `zai`, `venice`. Extra Codex accounts are `codex:<uuid>` (stable per account for as long as it is configured). |
| `displayName` | `String` | Human label (extra Codex accounts: `Codex — <label>`) |
| `state` | `String` | `ready`, `stale`, `error`, or `loading` |
| `windows` | `[WindowStatus]` | Rate-limit windows |
| `balance` | `BalanceStatus?` | Pay-as-you-go balance, if any |
| `asOf` | `String?` (ISO 8601) | Provider-reported data timestamp |
| `staleSince` | `String?` (ISO 8601) | Present when `state` is `stale` |
| `error` | `String?` | Redacted error message for `error` / `stale` |
| `accountEmail` | `String?` | Signed-in account email — Codex accounts only (added in 1.11.0) |
| `planType` | `String?` | Plan / tier label as shown in the app's plan capsule (e.g. `Pro`, `Pro Lite`, `Ultra`, `Credits`, `Inference key`); present for any provider that reports one (added in 1.11.0) |
| `renewal` | `RenewalStatus?` | User-entered subscription renewal — billing information, NOT a usage window; do not use it for quota decisions (Codex accounts; added in 1.11.0) |
| `apiUsage` | `APIUsageStatus?` | Claude organization API usage report, when available; does not represent prepaid credits |

`APIUsageStatus` (Claude organization API report):

| Field | Type | Description |
|-------|------|-------------|
| `costUSD` | `Number` | Reported cost in USD, excluding Priority Tier costs |
| `inputTokens` | `Int` | Uncached input tokens; cache reads and cache creation are reported separately |
| `outputTokens` | `Int` | Output tokens |
| `cacheReadTokens` | `Int` | Cache-read input tokens |
| `cacheCreationTokens` | `Int` | Cache-creation input tokens |
| `periodStart` | `String` (ISO 8601) | Start of the current calendar month in UTC |
| `periodEnd` | `String` (ISO 8601) | End of the reported period; the report may lag actual usage |
| `currency` | `String` | `USD` |
| `prepaidCreditsStatus` | `String` | `unavailable`; no actual available credit amount is exposed |
| `costExcludesPriorityTier` | `Bool` | `true` for this report |

The report is organization-wide and covers the current UTC calendar month
through `periodEnd`. Token categories are separate: `inputTokens` excludes
cache-read and cache-creation tokens. API reporting may lag; `prepaidCreditsStatus`
does not imply a balance or remaining credit amount. The `claude-api`
`balance` field remains a spend-style compatibility value (`kind: "spent"`).

`RenewalStatus` (added in 1.11.0):

| Field | Type | Description |
|-------|------|-------------|
| `expectedAt` | `String` (ISO 8601) | Next expected renewal date |
| `platform` | `String` | Billing platform (`chatgpt`, `apple`, `google`, `other`) |
| `confirmedAt` | `String?` (ISO 8601) | When the user last confirmed the date on the billing platform |

`WindowStatus`:

| Field | Type | Description |
|-------|------|-------------|
| `label` | `String` | Window name (e.g. `5h`, `Weekly`) |
| `usedPercent` | `Number` | Used percent, 0–100 (always “used”, not “remaining”) |
| `resetsAt` | `String?` (ISO 8601) | Reset time, if known |

`BalanceStatus`:

| Field | Type | Description |
|-------|------|-------------|
| `amount` | `Number` | Balance or spend amount |
| `currency` | `String` | Symbol prefix (e.g. `$`, `¥`) |
| `kind` | `String` | `remaining` or `spent` |

### Example

```json
{
  "appVersion": "1.11.2",
  "generatedAt": "2026-09-21T07:30:00Z",
  "providers": [
    {
      "accountEmail": "you@example.com",
      "asOf": "2026-09-21T07:29:58Z",
      "displayName": "Codex",
      "id": "codex",
      "planType": "Pro",
      "state": "ready",
      "windows": [
        { "label": "5h limit", "resetsAt": "2026-09-21T10:00:00Z", "usedPercent": 42 },
        { "label": "Weekly limit", "resetsAt": "2026-09-28T05:12:00Z", "usedPercent": 17 }
      ]
    },
    {
      "accountEmail": "work@example.com",
      "asOf": "2026-09-21T07:29:59Z",
      "displayName": "Codex — work",
      "id": "codex:2F1A6C1E-8B3D-4E6F-9A0B-1C2D3E4F5A6B",
      "planType": "Pro Lite",
      "renewal": {
        "confirmedAt": "2026-09-01T14:00:00Z",
        "expectedAt": "2026-10-03T00:00:00Z",
        "platform": "apple"
      },
      "state": "ready",
      "windows": [
        { "label": "Weekly limit", "resetsAt": "2026-09-25T18:40:00Z", "usedPercent": 62 }
      ]
    },
    {
      "balance": { "amount": 8.06, "currency": "$", "kind": "remaining" },
      "displayName": "OpenRouter",
      "id": "openrouter",
      "planType": "Credits",
      "state": "ready",
      "windows": []
    },
    {
      "displayName": "Z.ai",
      "error": "Z.ai key is valid, but this account has no GLM Coding Plan",
      "id": "zai",
      "state": "error",
      "windows": []
    }
  ],
  "schemaVersion": 1
}
```

Notes for consumers:

- Window labels are localized to the app's UI language; match on `id` and
  window position/`resetsAt`, not on label text, if you need stability.
- `usedPercent` is always *used*; the app's "count down" display setting does
  not affect the snapshot.
- Codex `asOf` is the time of the last live app-server read (or the newest
  session-log event when the fallback is in use).

### Schema stability

Within `schemaVersion` 1, changes are **additive only** (new optional fields). Breaking renames or semantic changes require incrementing `schemaVersion`.

| App version | Schema change |
|-------------|---------------|
| 1.9.0 | Schema v1 introduced |
| 1.11.0 | Added optional `accountEmail`, `planType`, `renewal` on `ProviderStatus`; extra Codex accounts appear as `codex:<uuid>` providers |
| 1.12.0 | Added optional Claude API `apiUsage` report on `ProviderStatus` |

## URL schemes

Registered scheme: `agentmeter://`

| URL | Behavior |
|-----|----------|
| `agentmeter://openrouter?...` | OAuth callback (existing) |
| `agentmeter://refresh` | Triggers refresh when agent access is enabled |
| `agentmeter://details` | Opens the Usage Details window |

## CLI (`agentmeter`)

Bundled at `AgentMeter.app/Contents/Helpers/agentmeter` (in `Helpers/` because
`agentmeter` and `AgentMeter` would collide in `MacOS/` on case-insensitive
filesystems).

- Homebrew installs put it on your `PATH` automatically (cask `binary` stanza).
- Manual installs: use **Settings → General → Install Command-Line Tool…**, or
  `ln -s /Applications/AgentMeter.app/Contents/Helpers/agentmeter /usr/local/bin/agentmeter`

```
agentmeter status [--json]
agentmeter refresh [--wait SECONDS]
agentmeter doctor
agentmeter skill
agentmeter --version
agentmeter --help
```

| Command | Description |
|---------|-------------|
| `status` | Print human-readable table (default) or raw JSON (`--json`) |
| `refresh` | Ask the running app to refresh; `--wait N` polls until `generatedAt` changes |
| `doctor` | Redacted environment and snapshot report |
| `skill` | Print the agent skill markdown for Codex, Claude Code, or Cursor |

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Usage error |
| 2 | No snapshot (app not writing — enable agent access) |
| 3 | AgentMeter not running (`refresh` only) |
| 4 | Refresh wait timed out |

`status` prints a staleness warning when `generatedAt` is older than 10 minutes.

### Refresh cadence

The app refreshes every 30 s / 1 min / 5 min (user setting) and on wake, and
Codex updates instantly during CLI activity via a file watcher. Live Codex
app-server reads are capped at one per 5 minutes per account regardless of the
refresh interval; `agentmeter refresh` triggers a normal refresh, which reuses
the cached app-server reading if it is younger than 5 minutes. For Claude API,
explicit menu/CLI refresh bypasses the five-minute report cache. Automatic
polling retains caching; retries after reporting failures wait one minute.

### Debugging

`AGENTMETER_DEBUG=1` in the app's environment enables structural tracing to
stderr (refresh completion per provider, Codex app-server success/failure).
It never prints credentials. Note that launching the app binary directly from
a shell can leave the initial refresh incomplete; prefer
`open /Applications/AgentMeter.app` for real-world behavior and use the
snapshot/CLI to observe it.

## Agent skill

`agentmeter skill` prints the AgentMeter agent skill markdown to stdout (exit 0).
Install it into your coding agent's skill directory, for example:

```bash
mkdir -p ~/.codex/skills/agentmeter
agentmeter skill > ~/.codex/skills/agentmeter/SKILL.md

mkdir -p ~/.claude/skills/agentmeter
agentmeter skill > ~/.claude/skills/agentmeter/SKILL.md

mkdir -p ~/.cursor/skills/agentmeter
agentmeter skill > ~/.cursor/skills/agentmeter/SKILL.md
```

The canonical source in this repository is `docs/agent-skill/SKILL.md`; the CLI
embeds the same bytes at build time (a test enforces byte identity).

## Codex multi-account specifics

Extra Codex accounts are configured in Settings → Providers → Codex accounts
and monitored through separate `CODEX_HOME` directories. See
[CODEX_ACCOUNTS.md](CODEX_ACCOUNTS.md) for setup. From an agent's point of
view each account is an independent provider entry. To find *your own*
account's entry, compare `accountEmail` with `codex login status` (run with the
same `CODEX_HOME` you are executing under), or match the home you were started
with to the label the user chose.
