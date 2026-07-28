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
- Manual installs: `ln -s /Applications/AgentMeter.app/Contents/Helpers/agentmeter /usr/local/bin/agentmeter`

```
agentmeter status [--json]
agentmeter refresh [--wait SECONDS]
agentmeter doctor
agentmeter --version
agentmeter --help
```

| Command | Description |
|---------|-------------|
| `status` | Print human-readable table (default) or raw JSON (`--json`) |
| `refresh` | Ask the running app to refresh; `--wait N` polls until `generatedAt` changes |
| `doctor` | Redacted environment and snapshot report |

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Usage error |
| 2 | No snapshot (app not writing — enable agent access) |
| 3 | AgentMeter not running (`refresh` only) |
| 4 | Refresh wait timed out |

`status` prints a staleness warning when `generatedAt` is older than 10 minutes.
