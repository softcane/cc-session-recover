# cc-session-recover

Keep a long Claude Code task recoverable when quota or a rate limit stops it.

This project installs a small workflow into another repo. Claude keeps a handoff file and sets a slow in-session heartbeat. If the terminal closes after a quota stop is recorded, an optional watcher can resume the same Claude session from another shell.

## Why This Approach Is Stronger

- It has two recovery paths. With the terminal open, the heartbeat resumes inside the active Claude Code session. With the terminal closed, the watcher can resume the saved session id.
- Claude Code hooks record the quota stop. The watcher uses `claude -p --resume` only for closed-terminal recovery, so it does not depend on terminal text.
- `HANDOFF.md` keeps the next step in the repo. A resume has project state, recent progress, and the exact next action.
- The heartbeat runs inside the active Claude Code session. It keeps the original context alive while quota is blocked.
- The watcher covers closed terminals. It reads the quota marker, waits for the reset time when available, and resumes the saved session id.
- The status line cache reduces noisy retries. When Claude Code exposes a reset time, the watcher sleeps until that time plus a buffer.
- The fake quota test checks the full path: install, hook injection, quota marker, retry loop, exact-session resume, and marker cleanup.

## What You Get

- `HANDOFF.md`: the recovery note for the current task.
- `.claude/auto-continue.md`: the prompt used by the recurring heartbeat.
- `.claude/loop.md`: a one-step resume prompt for a scheduled one-time reminder.
- A `SessionStart` hook that injects the standing instructions at the start of each Claude Code session.
- A `StopFailure` hook that records quota stops and writes `.claude/quota-blocked.json`.
- `scripts/quota-watcher.sh`: an optional watcher that uses the marker file to resume the recorded session with `claude -p --resume`.
- `scripts/test-fake-quota-flow.sh`: an end-to-end test that proves the install, hooks, marker, and watcher without using real quota.

## Install

Use `npx` from any project:

```sh
npx cc-session-recover init /path/to/project
```

Enable the local Claude Code hooks during install:

```sh
npx cc-session-recover init --enable-local-hook /path/to/project
```

You can also install from a clone of this repo:

```sh
cd /path/to/cc-session-recover
bash scripts/install-into-project.sh --enable-local-hook /path/to/project
```

Claude Code may ask you to approve the hooks the next time you start `claude` in that project. Approve them once.

## Use It

Start Claude Code in the target project:

```sh
cd /path/to/project
claude
```

Then give Claude your real task.

With hooks enabled, the `SessionStart` hook prints `.claude/standing-instructions.md` into Claude's context. That tells Claude to:

1. Keep `HANDOFF.md` current after each small step.
2. Create a recurring schedule every 45 minutes.
3. Use this scheduled prompt: `Read .claude/auto-continue.md and follow it.`
4. Cancel the schedule when the task is complete.

If quota blocks the session, each heartbeat fails while quota remains blocked. The first heartbeat after the reset reads `HANDOFF.md` and continues from the recorded next step.

The terminal must stay open for this heartbeat. The schedule lives inside the running Claude Code session.

## Use Without Hooks

If you install without hooks, include this with your task:

```text
Keep HANDOFF.md updated after every small safe step.

Also create a recurring schedule every 45 minutes with this prompt:

Read .claude/auto-continue.md and follow it.

Cancel that schedule when the task is complete.
```

## One-Time Resume

Use this when you know the quota reset time and want one future resume.

Look at the reset time in the Claude Code status line. Add 10 to 15 minutes. Then ask Claude Code to schedule one reminder.

Example:

```text
Update HANDOFF.md now.

Then set a one-time reminder for 02:25 local time with this prompt:

Read HANDOFF.md first. If the task is incomplete, run git status --short, inspect the current diff only enough to understand the working tree, continue exactly one small safe step from Next Exact Action, run the narrowest relevant check, update HANDOFF.md, and stop.
```

Pick a time like `02:25`, rather than exactly `02:00` or `02:30`.

Use `/loop` for short polling jobs, such as checking CI. Avoid `/loop 1m` for overnight quota recovery.

## Watcher For Closed Terminals

The heartbeat dies when the terminal closes. If you need unattended recovery after that, enable the local hook and run the watcher from another shell:

```sh
bash scripts/quota-watcher.sh /path/to/project
```

The watcher needs `jq` and the `claude` CLI on `PATH`.

When quota stops a turn, the hook writes `.claude/quota-blocked.json`. The watcher reads the saved `session_id` and runs:

```sh
claude -p --resume <session_id> --permission-mode acceptEdits "<contents of .claude/auto-continue.md>"
```

If the status line cache has a reset time, the watcher sleeps until that time plus a 15-minute buffer before it tries. Without a reset time, it retries on an interval.

Close the interactive Claude Code session before you rely on the watcher. Otherwise the open session and the watcher may work on the same task.

## Status Line Cache

`.claude/statusline-quota-cache.sh` saves Claude Code rate-limit fields into `.claude/rate-limit-state.json`.

The `StopFailure` hook copies that reset time into `.claude/quota-blocked.json`. The watcher uses it to wait for the reset instead of retrying blind.

To keep your existing status line, set `CLAUDE_QUOTA_STATUSLINE_DELEGATE` to your current status line command. The wrapper passes the display through after it caches the quota data.

## Test The Workflow

Run the static project check:

```sh
bash scripts/verify-claude-loop-workflow.sh
```

Run the fake quota flow:

```sh
bash scripts/test-fake-quota-flow.sh
```

When you run the fake test, the script creates a throwaway repo, installs the workflow, fakes a `SessionStart` event, fakes a `rate_limit` `StopFailure`, replaces `claude` with a stub that fails twice, then checks that the watcher resumes the recorded session.

## Limits

- This does not bypass quota.
- The heartbeat needs Claude Code to stay open and idle when the scheduled prompt fires.
- The watcher needs the local hook marker file. It only acts after a quota stop gets recorded.
- Headless resume cannot ask for permission. Review `--permission-mode acceptEdits` before you use it.
- Scheduled tasks require Claude Code v2.1.72 or newer.

## More Docs

- [Simple flow](docs/simple-flow.md): the notebook, alarm, and watcher explained without code.
- [FAQ](docs/faq.md): reliability, hook approval, and what still needs a human.
- [Auto-resume details](docs/claude-code-auto-resume.md): full behavior and limits.
- [Verified quota resume example](docs/verified-quota-resume-example.md): a concrete one-time reminder example.
