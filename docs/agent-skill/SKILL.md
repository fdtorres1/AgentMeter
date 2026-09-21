---
name: agentmeter
description: Check remaining AI coding usage limits and API balances (Codex, Cursor, Claude Code, Gemini, OpenRouter, DeepSeek, Kimi, Z.ai, Venice) through the local AgentMeter menu bar app before starting large or long-running tasks. Use when planning work that will consume significant model quota, when choosing between providers, when a rate-limit or quota error occurs, or when the user asks how much usage they have left.
---

# AgentMeter usage check

AgentMeter is a macOS menu bar app that tracks AI coding usage limits. It
exposes a read-only snapshot through the `agentmeter` CLI. Use it to avoid
starting work you cannot finish within the user's remaining quota.

## When to use

- Before a large task: multi-file refactors, long agentic loops, batch jobs,
  anything likely to run for many turns.
- When a provider returns a rate-limit or quota error.
- When the user asks about their usage, limits, balance, or reset times.
- When deciding which provider or model to route work to.

Check once per task, not once per step. The app refreshes itself.

## Command

```bash
agentmeter status --json
```

If `agentmeter` is not on PATH, try these in order:

```bash
/opt/homebrew/bin/agentmeter
/usr/local/bin/agentmeter
/Applications/AgentMeter.app/Contents/Helpers/agentmeter
```

Exit codes:

| Code | Meaning | What to do |
|------|---------|------------|
| 0 | Success | Read the JSON. |
| 2 | No snapshot | Tell the user to turn on Settings → General → "Enable agent & CLI access" in AgentMeter, then retry. |
| 3 | App not running (`refresh` only) | Ask the user to launch AgentMeter. |
| 127 / not found | CLI not installed | Suggest `brew install --cask fdtorres1/tap/agentmeter` or the Settings → General "Install Command-Line Tool" button. |

If the snapshot is unavailable, say so and proceed with the task as normal.
Never work around a missing snapshot by reading `~/.codex`, `~/.claude`,
Cursor's local database, OAuth credential files, or the Keychain, and never
call provider APIs yourself. The snapshot is the only sanctioned source.

## Reading the output

Top-level fields: `schemaVersion` (1), `generatedAt` (ISO 8601), `appVersion`,
`providers[]`.

Each provider:

- `id`, `displayName`
- `state`: `ready`, `stale` (last known data; a fetch recently failed),
  `error`, or `loading`
- `windows[]`: rate-limit windows with `label`, `usedPercent` (0–100, always
  *used*, never remaining), and `resetsAt` (ISO 8601, optional)
- `balance` (pay-as-you-go providers): `amount`, `currency` symbol, and
  `kind` — `remaining` means money left, `spent` means money used
- `asOf`, `staleSince`, `error` (redacted message) where applicable
- `accountEmail` and `planType` (Codex): which signed-in account and plan the
  entry belongs to
- `renewal` (optional): the user's subscription *billing* renewal date. This is
  not a usage window — never treat it as quota, and do not mention it unless
  the user asks about billing.

Multiple Codex accounts: the user may monitor several Codex subscriptions.
The default account has `id` `codex`; extra accounts have ids like
`codex:<uuid>` and display names like `Codex — work`, each with its own
`accountEmail`. If you are running as Codex, find your own entry by matching
`accountEmail` against `codex login status` (run with the same `CODEX_HOME`
you were started with); when unsure, report the most constrained Codex
account and say which email it is.

Freshness: if `generatedAt` is more than 10 minutes old, run
`agentmeter refresh --wait 15` once, then read the snapshot again. Do not
refresh more than once per task.

## Decision guidance

- Any window with `usedPercent` ≥ 85: warn the user before starting, quote the
  `resetsAt` time, and suggest waiting or using a provider with more headroom.
- 60–85: proceed, but mention the headroom and prefer smaller, committable
  steps so partial progress survives a limit.
- `balance.kind == "remaining"` below about 2 currency units: warn the user.
- `stale` or `error` states: mention that the number may be outdated; do not
  treat it as zero or as unlimited.

Report in one line before proceeding, for example:
"Codex weekly 55% used (resets Aug 4), Cursor 8% used, OpenRouter $1.13 left —
fine to proceed, but OpenRouter is nearly empty."

## Do not

- Do not modify `status.json` or anything under
  `~/Library/Application Support/AgentMeter/`.
- Do not read credentials or call provider APIs to get usage yourself.
- Do not nag: one check per task is enough.
