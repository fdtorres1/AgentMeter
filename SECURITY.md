# Security Policy

AgentMeter reads authentication tokens that other apps (Codex CLI, Cursor,
Claude Code, Gemini CLI) store locally, so security reports are taken
seriously.

## Reporting a vulnerability

Please **do not open a public issue** for security problems. Instead, use
GitHub's private reporting: go to the repository's **Security** tab →
**Report a vulnerability** (GitHub private vulnerability reporting).

You can expect an acknowledgment within a few days. Please include steps to
reproduce and the version of AgentMeter affected.

## Scope

Particularly interested in:

- Any path where credentials could be written to disk, logged, or sent to a
  host other than the provider's own API
- Code execution via crafted provider API responses or local files
- Privilege escalation via the app bundle, launch-at-login registration, or
  the update checker
