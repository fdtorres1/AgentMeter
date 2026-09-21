# Codex: multiple accounts and renewal dates

AgentMeter can monitor several ChatGPT/Codex subscriptions side by side —
for example a personal account, a work account, and an older one — each with
its own meter, menu bar entry, and (optionally) a tracked billing renewal
date. This guide explains how it works and how to set it up.

## How AgentMeter reads Codex usage

Since 1.11.0, AgentMeter gets Codex numbers from your own Codex CLI rather
than from session logs alone. Every five minutes per account it launches
`codex app-server` for about a second, asks two questions over Codex's
documented JSON-RPC protocol (`account/read` for the signed-in email and plan,
`account/rateLimits/read` for the limit windows), and quits the process.

What this means for trust:

- **AgentMeter never touches your tokens.** Codex reads its own credentials,
  refreshes them, and talks to OpenAI. AgentMeter only sees the answer.
- **AgentMeter never signs you in.** You run `codex login` yourself, in
  Terminal, for each account.
- **No background processes.** The helper runs for roughly a second and exits.
- **Offline fallback.** For the default account, the newest session log is
  still parsed when the app-server is unavailable, and it keeps updates
  instant while you are actively using the CLI.

Requirements: the Codex CLI installed (Homebrew, npm, or the ChatGPT desktop
app's bundled binary works if it is on your PATH or in `/opt/homebrew/bin`,
`/usr/local/bin`, or `~/.local/bin`).

## Adding another account

Codex keeps everything for one login in a *home* directory — `~/.codex` by
default. A second account simply gets a second home. Codex refuses to start
when the home does not exist yet, so create it first:

```bash
mkdir -p ~/.codex-work && CODEX_HOME=~/.codex-work codex login
```

A browser opens. **Sign in to the account you want in that home.** chatgpt.com
will happily reuse whichever account is already signed in, so sign out first
or paste the login URL into a private window if you are adding several
accounts in a row.

Then open **AgentMeter → Settings → Providers → Codex accounts**. Any
`~/.codex-*` folder that contains a login appears as
"Found signed-in Codex home: work" with an **Add** button. Click it. The
account shows "Loading…" and, within a few seconds, resolves to its email
and plan.

You can also click **Add account…** to enter a label and any home path by
hand; the form shows the exact Terminal command (with `mkdir -p`) and a
**Copy login command** button.

To verify which account landed where:

```bash
CODEX_HOME=~/.codex-work codex login status
codex login status              # your default login, unchanged
```

**Removing** an account in Settings only forgets the path — it does not sign
out. To sign out, run `CODEX_HOME=~/.codex-work codex logout`, or delete the
folder.

## How accounts appear

| Where | Default account (`~/.codex`) | Extra account labeled `work` |
|-------|------------------------------|------------------------------|
| Dropdown section | "Codex" + plan capsule | "Codex — work" + plan capsule + email caption |
| Menu bar | `Cx 12%` | `CxW 40%` (first letter of the label) |
| Snapshot / CLI id | `codex` | `codex:<uuid>` with `accountEmail` and `planType` |

Each account is a separate provider: it has its own visibility setting
(Auto/On/Off), its own menu bar toggle, and its own threshold notifications.

If your default `~/.codex` login is the same account as one of your extra
homes, set the duplicate to **Off** in Settings → Providers.

## Tracking subscription renewal dates

OpenAI does not publish consumer subscription renewal dates through any API,
so AgentMeter lets you record them and keeps them clearly separate from usage
windows. A renewal is about billing; a usage window is about rate limits. The
two never share a meter.

In **Settings → Providers → Codex accounts**, expand **Subscription** under any
account and turn on **Track renewal date**:

- **Renews on** — the date from your billing platform.
- **Billed through** — ChatGPT, Apple, Google Play, or Other. Check the platform
  that actually charges you: for App Store or Play subscriptions the date on
  chatgpt.com may not match.
- **Remind me** — Off, or 1 / 3 / 7 days before. Reminders use macOS
  notifications and respect the global notifications toggle; you get one per
  renewal cycle.
- **I confirmed this date today** — marks the date as verified. After 90 days
  without confirmation the dropdown shows "(expected)" instead of
  "(confirmed)" as a nudge to re-check.

The dropdown shows a calendar row such as "Renews Oct 3 · Apple (confirmed)".
Monthly renewals are computed on the anniversary day with correct month-end
clamping (a Jan 31 anchor renews Feb 28/29, then Mar 31).

Renewal data is stored in AgentMeter's preferences and exposed to agents via
the snapshot's `renewal` field (see [AGENT_INTERFACE.md](AGENT_INTERFACE.md)).

## Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| `Error loading configuration: CODEX_HOME points to … does not exist` | Create the folder first: `mkdir -p <home>`. |
| Account shows "Not signed in" | The home has no `auth.json`. Run the login command for that home. |
| Account shows "Codex CLI not found" | AgentMeter could not find `codex`. Install it via Homebrew or make sure it is in `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, or your login shell's PATH. |
| Numbers seem stale | Live polling happens every 5 minutes. Open the dropdown and press Refresh, or run `agentmeter refresh --wait 15`. |
| Two sections show the same email | Your default `~/.codex` and an extra home are the same account. Turn one Off in Settings → Providers. |
| Nothing found under "Codex accounts" after logging in | Discovery only lists folders named `~/.codex-*` that contain `auth.json`. For other locations use **Add account…** and enter the path. |
