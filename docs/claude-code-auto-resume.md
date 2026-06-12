# Claude Code Quota Resume Workflow

This workflow helps Claude Code continue after a quota or rate limit pause without a new prompt from you.

The mechanism is a fresh handoff file plus a recurring in-session heartbeat armed at task start.
It does not bypass quota.
It only waits until quota should be available again.

## Automatic Injection Through Hooks

Hook events differ in what they are allowed to do:

- `SessionStart` can inject context: anything its script prints to stdout is added to Claude's context for the session.
- `UserPromptSubmit` can also inject context, alongside each prompt you send.
- `StopFailure` can only observe: its output is ignored, so it can log and write files but never inject a prompt or schedule anything.

This template uses `SessionStart` to inject `.claude/standing-instructions.md` at the start of every session.
That file tells Claude to keep the handoff fresh, arm the 45-minute heartbeat for any multi-step task, and cancel it when done.
With the local hook settings enabled, you never paste the setup message again.

One honest limit: injected instructions are still instructions.
The harness guarantees Claude receives them, and the heartbeat schedule itself is enforced by the harness once created, but creating it is something Claude does in response to the injected text.

## Recommended Flow: Heartbeat Armed At Task Start

With the hook enabled, just give Claude the task; the arming instructions are injected for you.
Without it, arm the heartbeat when you give the task, not when quota is about to run out.
You do not need to know the reset time.

```text
Keep HANDOFF.md updated after every small safe step.

Also create a recurring schedule every 45 minutes with this prompt:

Read .claude/auto-continue.md and follow it.

Cancel that schedule when the task is fully complete.
```

How it behaves:

- While Claude is working, the session is busy, so heartbeat fires wait or pass quickly.
- If quota blocks a turn, the session goes idle and each heartbeat fire fails cheaply, about once per interval.
- The first fire after the quota reset reads `HANDOFF.md` and continues the task to completion.
- The prompt in `.claude/auto-continue.md` is safe to fire at any time, so a fire after completion is a no-op.

The terminal must stay open for the heartbeat.
Use an interval of 30 to 60 minutes.
Do not use a one-minute interval.

## Install In Any Project

From the template folder:

```sh
cd /path/to/cc-session-recover
bash scripts/install-into-project.sh /path/to/project
```

Hooks are enabled by default; pass `--no-hooks` to install the files without activating anything.
Claude Code asks you to approve the hooks once on the next start either way.

The quota-stop hook is a logger plus a marker writer.
It cannot schedule the same-session resume by itself.
The marker feeds the optional unattended watcher described below.

## The Handoff File

The handoff is the recovery file for the current task.
It should stay fresh while Claude works.
Do not wait until the quota is almost gone.
Claude may not always know that a quota stop is about to happen.

The heartbeat prompt in `.claude/auto-continue.md` keeps working through the remaining checklist until the task is complete or blocked, because a one-step-per-fire prompt would never finish a real task.

Do not use `/loop 1m` or any one-minute schedule for quota recovery.
That adds many failed attempts to the session for no benefit.
To stop the heartbeat, ask Claude to list and cancel its scheduled tasks.

## Hooks And Status Line

Claude Code status lines can receive rate-limit fields such as `rate_limits.five_hour.resets_at`.
That is how the reset time can be shown.

Claude Code hooks can detect a `rate_limit` stop through `StopFailure`.
But `StopFailure` hooks have no decision control.
So a hook can log or notify, but it should not be treated as a documented way to schedule a same-session resume.

This template includes an optional hook logger:

- `.claude/settings.example.json`
- `.claude/hooks/log-stop-failure.sh`

To enable it in one project, copy `.claude/settings.example.json` to `.claude/settings.local.json`.
If that file already exists, merge the hook settings manually.

When quota stops a turn, the hook appends a short note to `HANDOFF.md`.
It also writes raw hook input to `.claude/stop-failure-events.jsonl` and a marker to `.claude/quota-blocked.json`.

## Optional Unattended Watcher

The heartbeat needs the terminal open.
If the terminal might close, run the watcher from another shell:

```sh
npx cc-session-recover watch /path/to/project
```

Or from a clone of this repo:

```sh
bash scripts/quota-watcher.sh /path/to/project
```

It requires `jq`, the `claude` CLI on `PATH`, and the local hook enabled.

When the hook writes `.claude/quota-blocked.json`, the watcher reads the `session_id` from it and retries:

```sh
claude -p --resume <session_id> --permission-mode acceptEdits "<contents of .claude/auto-continue.md>"
```

While quota is blocked, each attempt fails and the watcher sleeps.
After the reset, the resume succeeds, the task continues headlessly, and the watcher clears the marker.

## Precise Resume Using The Status Line Cache

The status line wrapper `.claude/statusline-quota-cache.sh` saves the rate-limit fields, including `five_hour.resets_at`, to `.claude/rate-limit-state.json` while you work.
The StopFailure hook stamps that cached reset time into the quota marker.
When the marker has a reset time, the watcher does not knock on an interval.
It sleeps until the reset time plus `QUOTA_RESUME_BUFFER` seconds, default 900 (15 minutes), and knocks once.
The reset time is Unix epoch seconds, so the arithmetic is timezone-safe; local time appears only in printed messages.
The interval knocking remains only as the fallback when no reset time is known or the precise knock fails.

To keep an existing status line, set `CLAUDE_QUOTA_STATUSLINE_DELEGATE` to its command in the `statusLine` settings entry; the wrapper caches the fields and passes the display through unchanged.

Cautions:

- Exit the interactive Claude Code session before relying on the watcher, or both will work the same task in parallel.
- Headless mode cannot ask for permissions, so configure the project allowlist or accept the default `--permission-mode acceptEdits`, and understand what that allows.
- Set `QUOTA_WATCH_INTERVAL` and `QUOTA_WATCH_CLAUDE_ARGS` to tune the retry interval and claude flags.

## Testing The Flow Without Real Quota

Run:

```sh
bash scripts/test-fake-quota-flow.sh
```

It tests the full chain in a throwaway dummy repo:

1. Installs the template into the dummy repo with the hook enabled.
2. Pipes a fake `SessionStart` event into the injection hook and asserts the standing instructions come out.
3. Pipes a fake `rate_limit` `StopFailure` event into the logger hook and asserts the log line, the handoff note, and the `quota-blocked.json` marker with the right `session_id`.
4. Replaces the `claude` CLI with a stub that fails twice, simulating blocked quota, then succeeds, simulating the reset.
5. Runs the real watcher against the stub and asserts it retried, resumed the exact recorded session with the auto-continue prompt, and cleared the marker.

The one piece this cannot fake is the in-session heartbeat schedule, because that timer lives inside a real Claude Code session.
To check that piece live, start `claude` in a scratch repo, give it a tiny multi-step task, and confirm it creates the 45-minute schedule on its own from the injected instructions.

## Why The Interactive Flow Avoids Terminal Hacks

The in-session flow uses the original Claude Code terminal.
It avoids `tmux`, `screen`, `expect`, terminal-injection hacks, and `TIOCSTI`.

Those tools try to control a terminal from the outside.
That is fragile.
It can also continue the wrong session.

The built-in scheduler is simpler.
It runs inside the same Claude Code session that already has the task context.

The watcher's headless `claude -p --resume` is different from terminal injection.
It is a documented CLI mode, and it targets the exact session recorded by the hook.

## Verified Limits

- Scheduled tasks require Claude Code v2.1.72 or newer.
- Session scheduled tasks only fire while Claude Code is running and idle.
- Closing the terminal or ending the session stops them.
- A missed scheduled time does not catch up later unless Claude was only busy in the same open session.
- Starting a fresh conversation clears session scheduled tasks.
- Resuming with `claude --resume` or `claude --continue` can restore unexpired tasks.
