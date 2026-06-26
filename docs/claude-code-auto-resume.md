# Claude Code Transient Failure Resume Workflow

Use this workflow when Claude Code hits a configured transient failure and you
do not want to send another prompt.
Rate limits and overloads are enabled by default.
A quota or rate limit uses the cached reset time when Claude Code provides one.

It uses `HANDOFF.md` plus a recurring in-session heartbeat.
It does not bypass quota or provider failures.
It waits and resumes the exact recorded session.

## Hook Behavior

Claude Code hooks can do different things:

- `SessionStart` can add text to Claude's session context.
- `UserPromptSubmit` can add text beside each prompt you send.
- `StopFailure` can log data and write files. It cannot inject a prompt or create a schedule.

The template uses `SessionStart` to inject `.claude/standing-instructions.md`.
Those instructions tell Claude to keep `HANDOFF.md` fresh, create a 45-minute heartbeat for long tasks, and cancel the heartbeat when the task ends.

The hook guarantees Claude receives the instructions.
Claude still has to follow them.

## Recommended Flow

With hooks enabled, start `claude` and give the task.
Claude receives the setup instructions at session start.

Without hooks, include this setup with the task:

```text
Keep HANDOFF.md updated after every small safe step.

Also create a recurring schedule every 45 minutes with this prompt:

Read .claude/auto-continue.md and follow it.

Cancel that schedule when the task is fully complete.
```

The heartbeat behaves like this:

- While Claude works, the session stays busy and the heartbeat waits.
- If quota blocks a turn, each heartbeat attempt fails while quota remains blocked.
- After quota resets, the next heartbeat reads `HANDOFF.md` and continues the task.
- `.claude/auto-continue.md` is safe to fire at any time, so a late heartbeat after completion stops cleanly.

The terminal must stay open for the heartbeat.
Use a 30 to 60 minute interval.
Do not use a one-minute interval.

## Install In A Project

From npm:

```sh
npx cc-session-recover@latest init /path/to/project
```

From a clone of this repo:

```sh
bash scripts/install-into-project.sh /path/to/project
```

The installer enables hooks by default.
Pass `--no-hooks` if you only want to copy the files.

Claude Code asks you to approve the hooks once on the next start.

The quota-stop hook writes logs and a marker file.
It cannot resume the same session by itself.
The optional watcher uses that marker.

## Handoff File

`HANDOFF.md` stores the current task state.
Claude should update it after each small safe step.

Do not wait until quota is almost gone.
Claude may not know that a quota stop is coming.

The heartbeat prompt in `.claude/auto-continue.md` works through the remaining checklist until the task finishes or blocks.
A one-step prompt would leave real tasks half done.

Do not use `/loop 1m` or any one-minute schedule for quota recovery.
That creates repeated failed attempts while quota stays blocked.

To stop the heartbeat, ask Claude to list and cancel its scheduled tasks.

## Hooks And Status Line

Claude Code status lines can receive rate-limit fields such as `rate_limits.five_hour.resets_at`.
The status line can show that reset time.

Claude Code hooks report typed API failures through `StopFailure`.
`StopFailure` has no decision control, so use it for logs and marker files only.

The template includes:

- `.claude/settings.example.json`
- `.claude/hooks/log-stop-failure.sh`

The installer enables these hooks in `.claude/settings.local.json`.
If that file already exists, the installer preserves it and merges in the recovery hooks.

When an API failure stops a turn, the hook appends a typed note to `HANDOFF.md`.
It also writes raw hook input to `.claude/stop-failure-events.jsonl` and a marker to `.claude/quota-blocked.json`.

## Recovery Configuration

The installer creates `session-recover.yaml` in the project root without
overwriting an existing file:

```yaml
errors:
  - rate_limit
  - overloaded

retry_minutes: 20
```

The file has exactly two settings:

- `errors` is a non-empty list containing any combination of `rate_limit`,
  `overloaded`, and `server_error`. Duplicate names are accepted and treated as
  one value.
- `retry_minutes` is a positive whole number used when no future rate-limit
  reset time is available.

If the file is missing, recovery uses `rate_limit` and `overloaded` with a
20-minute fallback. `server_error` remains opt-in. Invalid YAML, unknown fields,
unknown error names, empty selections, and invalid retry values fail closed.

Claude Code determines the typed StopFailure error. In Claude Code `2.1.178`,
controlled HTTP 529 responses were classified as `server_error` rather than
`overloaded`. Enable both names when capacity-failure coverage matters across
CLI versions.

Every StopFailure is logged. A configured transient failure creates the active
marker. A disabled or permanent failure for the same session removes that
session's marker so stale recovery cannot continue. A failure from another
session does not remove the active marker.

## Optional Unattended Watcher

The heartbeat needs an open terminal.
If the terminal may close, run the watcher from another shell:

```sh
npx cc-session-recover watch /path/to/project
```

Or run it from a clone:

```sh
bash scripts/quota-watcher.sh /path/to/project
```

The watcher needs `jq`, the `claude` CLI on `PATH`, and the local hook enabled.

When the hook writes `.claude/quota-blocked.json`, the watcher reads the
`session_id`, failure type, and retry interval, then retries:

```sh
claude -p --resume <session_id> --permission-mode acceptEdits "<contents of .claude/auto-continue.md>"
```

While the transient failure remains, each attempt fails and the watcher sleeps.
After recovery, the resume succeeds, Claude continues headlessly, and the
watcher clears only the marker that it resumed. A newer marker is preserved.
Stopping or restarting the watcher leaves the active marker on disk.

## Precise Resume With The Status Line Cache

`.claude/statusline-quota-cache.sh` saves rate-limit fields while you work, including `five_hour.resets_at`.
The `StopFailure` hook copies that cached reset time into `.claude/quota-blocked.json`.

For `rate_limit` only, when the marker has a future reset time, the watcher
sleeps until the reset time plus `QUOTA_RESUME_BUFFER` seconds.
The default buffer is 900 seconds, or 15 minutes.
Then the watcher tries one precise resume.

The reset time uses Unix epoch seconds.
The script can compare it safely across time zones.
Printed messages use local time.

If the reset time is missing, null, malformed, or in the past, the watcher uses
`retry_minutes`. `overloaded` and `server_error` always use `retry_minutes`.
A cached quota observation is also treated as stale after six hours, or when
its reset timestamp is not plausible for that observation.

The watcher fails closed on malformed markers, non-string session IDs, missing
typed errors, and error types outside `rate_limit`, `overloaded`, and
`server_error`. Those markers are removed without invoking Claude.

The existing environment variables remain compatible:

- `QUOTA_WATCH_INTERVAL` is a seconds-based override and takes priority over
  `retry_minutes`.
- `QUOTA_RESUME_BUFFER` overrides the reset-time buffer in seconds.
- `QUOTA_WATCH_CLAUDE_ARGS` overrides the extra Claude CLI arguments.

To keep an existing status line, set `CLAUDE_QUOTA_STATUSLINE_DELEGATE` to its command in the `statusLine` settings entry.
The wrapper caches the fields and passes the display through unchanged.

Before you rely on the watcher:

- Exit the interactive Claude Code session, or two sessions may work on the same task.
- Configure project permissions, or accept the default `--permission-mode acceptEdits`.
- Set `QUOTA_WATCH_INTERVAL` and `QUOTA_WATCH_CLAUDE_ARGS` if you need different retry timing or claude flags.

## Test Without Real Quota

Run:

```sh
bash scripts/test-fake-quota-flow.sh
```

The complete test packs the npm artifact, installs it into a throwaway npm
project, sends realistic typed StopFailure events to the installed hook, and
replaces `claude` with a controlled executable.

The test covers every supported failure selection, invalid configuration,
malformed input and state, timing choices, installer upgrades, watcher
restarts, exact resume arguments, failed-attempt persistence, and cleanup.

The test cannot fake the in-session heartbeat schedule.
That timer lives inside a real Claude Code session.
To test it live, start `claude` in a scratch repo, give a small multi-step task, and confirm Claude creates the 45-minute schedule from the injected instructions.

## Why The Interactive Flow Avoids Terminal Hacks

The interactive flow uses the original Claude Code terminal.
It avoids `tmux`, `screen`, `expect`, terminal injection, and `TIOCSTI`.

External terminal control can target the wrong session.
The built-in scheduler runs inside the same session that has the task context.

The watcher's headless `claude -p --resume` call is different.
It uses the Claude Code CLI and targets the exact session recorded by the hook.

## Verified Limits

- Scheduled tasks require Claude Code v2.1.72 or newer.
- Session scheduled tasks only fire while Claude Code runs and sits idle.
- Closing the terminal or ending the session stops scheduled tasks.
- A missed scheduled time does not catch up later unless Claude was only busy in the same open session.
- Starting a fresh conversation clears session scheduled tasks.
- Resuming with `claude --resume` or `claude --continue` can restore unexpired tasks.
- Automatic watcher recovery is limited to `rate_limit`, `overloaded`, and
  `server_error`. Authentication, billing, invalid-request, model-not-found,
  and unknown failures are not retried.
