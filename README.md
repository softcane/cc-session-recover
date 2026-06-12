# Claude Code Workflow

This is a reusable Claude Code quota-resume template.

It helps you use Claude Code on a long task without losing the recovery point when quota or rate limit stops the session.
With the heartbeat armed at task start, work continues after a quota reset without any new prompt from you.

## Plain-English Guides

- [The Simple Flow: Notebook, Alarm, Watchman](docs/simple-flow.md) — how this works, told as a story.
- [FAQ](docs/faq.md) — where the alarm lives, how reliable this is, and what still needs a human.

## What Is Automatic

- The `SessionStart` hook injects the heartbeat and handoff instructions into every session, so you never paste them.
- Claude keeps `HANDOFF.md` fresh per those injected instructions.
- A recurring in-session heartbeat can resume the task after a quota reset without a new prompt.
- A one-time scheduled resume can run later in the same open Claude Code session.
- The optional `StopFailure` hook can log when quota or rate limit stops a turn, and writes a marker for the optional watcher.
- The optional watcher script can resume the session headlessly after the terminal session ends.

## What Is Not Automatic

- The hook cannot create a same-session scheduled Claude prompt by itself.
- This workflow does not bypass quota.
- The in-session heartbeat does not keep working if the terminal is closed; only the optional watcher covers that.

## Install Into Any Project

From this template folder:

```sh
cd /path/to/claude-code-workflow
bash scripts/install-into-project.sh /path/to/project
```

To also enable the hooks (standing-instruction injection at session start, plus the quota stop logger):

```sh
bash scripts/install-into-project.sh --enable-local-hook /path/to/project
```

The first time you start `claude` in that project afterwards, Claude Code may ask you to approve the new hooks.
Approve them once; that is a security feature, not an error.

## Use In A Project

Start Claude Code:

```sh
cd /path/to/project
claude
```

If the local hook settings are enabled, the heartbeat instructions are injected automatically at session start.
Just give Claude your main task.

The `SessionStart` hook prints `.claude/standing-instructions.md` into Claude's context every session, so you never paste the setup message again.

Without the hook enabled, arm the heartbeat yourself in the same message as the task:

```text
Keep HANDOFF.md updated after every small safe step.

Also create a recurring schedule every 45 minutes with this prompt:

Read .claude/auto-continue.md and follow it.

Cancel that schedule when the task is fully complete.
```

That is the whole quota-recovery setup.
If quota blocks a turn, each heartbeat fire fails cheaply while blocked, and the first fire after the reset resumes the task with no new prompt from you.
The terminal must stay open.

## Optional One-Time Resume

If you prefer a single resume instead of a heartbeat, look at the quota reset time in the Claude Code status line.
Add a 10 to 15 minute buffer.
Then ask Claude to schedule one resume.

Example:

```text
Update HANDOFF.md now.

Then set a one-time reminder for 02:25 local time with this prompt:

Read HANDOFF.md first. If the task is incomplete, run git status --short, inspect the current diff only enough to understand the working tree, continue exactly one small safe step from Next Exact Action, run the narrowest relevant check, update HANDOFF.md, and stop.
```

Use `/loop` only for short polling tasks.
Do not use `/loop 1m` for overnight quota recovery.

## Optional Unattended Watcher

If the terminal cannot stay open, enable the local hook and run the watcher from another shell:

```sh
bash scripts/quota-watcher.sh /path/to/project
```

When a quota stop happens, the hook writes `.claude/quota-blocked.json`.
The watcher then resumes that exact session headlessly once quota is back.
If the status line cache wrapper is configured, the marker carries the exact reset time, and the watcher sleeps until reset plus 15 minutes and knocks once; otherwise it falls back to retrying on an interval.
Exit the interactive Claude Code session before relying on the watcher, or both will work the same task.

## Test The Flow Without Burning Quota

```sh
bash scripts/test-fake-quota-flow.sh
```

This builds a throwaway dummy repo, fakes a `SessionStart` event, fakes a `rate_limit` quota stop, and replaces the `claude` CLI with a stub that fails twice and then succeeds.
It proves the instructions get injected, the marker gets written, and the watcher resumes the exact recorded session after the fake reset.
