# Security Policy

`cc-session-recover` is a local Claude Code recovery workflow. The highest-risk areas are Claude Code hook behavior, session-id handling, local project files, status line data, and unattended headless resume.

## Supported Versions

Security fixes target the latest release only. Early preview versions before the current `latest` tag are not supported.

Check the current version:

```sh
npm view cc-session-recover version
```

## Reporting a Vulnerability

Do not paste secrets, prompts, transcripts, tool output, local file contents, shell output, or exploit details into a public issue.

Preferred path:

1. Use GitHub private vulnerability reporting for this repository if it is available.
2. If private reporting is not available, open a public issue with only a short summary and ask for a private contact path. Do not include sensitive details.

Useful report details:

- `cc-session-recover` version and install method.
- Claude Code version, Node version, shell, and OS.
- Whether the issue affects install, hooks, status line cache, `HANDOFF.md`, scheduled resume, or `scripts/quota-watcher.sh`.
- A minimal reproduction that uses dummy paths and dummy data.
- Whether any prompt, transcript, shell output, file content, local path, API key, or raw Claude session id was exposed.

## Security-Sensitive Behavior

Please treat these as security-relevant:

- Raw prompts, assistant text, tool output, shell output, command arguments, file contents, local paths, transcript paths, workspace paths, API keys, or raw Claude session ids are printed or stored in an unsafe place.
- Install overwrites Claude Code settings without warning or without leaving the existing file intact.
- Hooks run unexpected commands, change unrelated files, or write files outside the target project.
- `scripts/quota-watcher.sh` resumes the wrong session id.
- `scripts/quota-watcher.sh` runs while the interactive session is still active and causes two sessions to work on the same task.
- Runtime marker files are created with broad permissions or are included in version control.
- Shell command construction can be changed by project paths, settings, or marker contents in a way that changes execution.

These are usually not `cc-session-recover` security bugs:

- Claude Code model behavior.
- Claude Code authentication, billing, or quota behavior.
- A local user intentionally reading files from their own account.
- A scheduled resume failing because quota is still blocked.

## Project Privacy Invariants

`cc-session-recover` should store only the minimum state needed for recovery: handoff notes written by the user or agent, hook event metadata, rate-limit reset time, and a session id needed to resume the recorded Claude Code session.

It must not store or print raw secrets, API keys, unrelated local file contents, unrelated shell output, or unrelated Claude Code transcript content.
