# Claude Code Quota Resume Workflow

Use this workflow when Claude Code hits a quota or rate limit pause and you do not want to send another prompt.

It uses `HANDOFF.md` plus a recurring in-session heartbeat.
It does not bypass quota.
It waits until quota becomes available again.

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

Claude Code hooks can detect a `rate_limit` stop through `StopFailure`.
`StopFailure` has no decision control, so use it for logs and marker files only.

The template includes:

- `.claude/settings.example.json`
- `.claude/hooks/log-stop-failure.sh`

To enable hooks in one project, copy `.claude/settings.example.json` to `.claude/settings.local.json`.
If `.claude/settings.local.json` already exists, merge the settings by hand.

When quota stops a turn, the hook appends a note to `HANDOFF.md`.
It also writes raw hook input to `.claude/stop-failure-events.jsonl` and a marker to `.claude/quota-blocked.json`.

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

When the hook writes `.claude/quota-blocked.json`, the watcher reads the `session_id` and retries:

```sh
claude -p --resume <session_id> --permission-mode acceptEdits "<contents of .claude/auto-continue.md>"
```

While quota blocks Claude, each attempt fails and the watcher sleeps.
After quota resets, the resume succeeds, Claude continues headlessly, and the watcher clears the marker.

## Precise Resume With The Status Line Cache

`.claude/statusline-quota-cache.sh` saves rate-limit fields while you work, including `five_hour.resets_at`.
The `StopFailure` hook copies that cached reset time into `.claude/quota-blocked.json`.

When the marker has a reset time, the watcher sleeps until the reset time plus `QUOTA_RESUME_BUFFER` seconds.
The default buffer is 900 seconds, or 15 minutes.
Then the watcher tries one precise resume.

The reset time uses Unix epoch seconds.
The script can compare it safely across time zones.
Printed messages use local time.

If the marker has no reset time, or the precise resume fails, the watcher falls back to interval retries.

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

The test uses a throwaway repo.
It installs the template, sends fake hook events, writes a fake quota marker, and replaces the `claude` CLI with a stub.
The stub fails twice to simulate blocked quota, then succeeds to simulate a reset.

The test proves the watcher retries, resumes the recorded session with `.claude/auto-continue.md`, and clears the marker.

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
