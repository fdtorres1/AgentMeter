# AgentMeter Agent & CLI Interface

AgentMeter exposes a read-only local interface for scripts and coding agents. The menu bar app is the only process that reads credentials or calls provider APIs. The CLI reads a snapshot file and can poke the app via URL schemes.

## Security model

- **Opt-in**: snapshot writing is disabled by default (`Settings → General → Enable agent & CLI access`).
- **No credentials**: the snapshot contains usage percentages, balances, and redacted error strings only.
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
| `id` | `String` | Provider id (e.g. `codex`, `cursor`) |
| `displayName` | `String` | Human label |
| `state` | `String` | `ready`, `stale`, `error`, or `loading` |
| `windows` | `[WindowStatus]` | Rate-limit windows |
| `balance` | `BalanceStatus?` | Pay-as-you-go balance, if any |
| `asOf` | `String?` (ISO 8601) | Provider-reported data timestamp |
| `staleSince` | `String?` (ISO 8601) | Present when `state` is `stale` |
| `error` | `String?` | Redacted error message for `error` / `stale` |
| `accountEmail` | `String?` | Signed-in account email (Codex; added in 1.11.0) |
| `planType` | `String?` | Plan display name (Codex; added in 1.11.0) |
| `renewal` | `RenewalStatus?` | User-tracked subscription renewal (Codex; added in 1.11.0) |

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
  "appVersion": "1.0",
  "generatedAt": "2026-07-28T20:15:00Z",
  "providers": [
    {
      "asOf": "2026-07-28T20:14:55Z",
      "displayName": "Codex",
      "id": "codex",
      "state": "ready",
      "windows": [
        {
          "label": "5h",
          "resetsAt": "2026-07-28T22:00:00Z",
          "usedPercent": 42
        },
        {
          "label": "Weekly",
          "resetsAt": "2026-08-04T00:00:00Z",
          "usedPercent": 17
        }
      ]
    },
    {
      "balance": {
        "amount": 12.5,
        "currency": "$",
        "kind": "remaining"
      },
      "displayName": "OpenRouter",
      "id": "openrouter",
      "state": "ready",
      "windows": []
    }
  ],
  "schemaVersion": 1
}
```

### Schema stability

Within `schemaVersion` 1, changes are **additive only** (new optional fields). Breaking renames or semantic changes require incrementing `schemaVersion`.

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
embeds the same bytes at build time.
