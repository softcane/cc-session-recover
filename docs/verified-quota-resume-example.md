# Verified Quota Resume Example

This example uses only documented Claude Code behavior.

## Situation

You are working in `/Users/pradeepsingh/code/my-app`.
Claude Code shows that the 5-hour quota resets at `02:10`.
You want work to continue overnight without sending a prompt every minute.

## What You Type

Inside the same Claude Code terminal, type:

```text
Update HANDOFF.md now.

Then set a one-time reminder for 02:25 local time with this prompt:

Read HANDOFF.md first. If the task is incomplete, run git status --short, inspect the current diff only enough to understand the working tree, continue exactly one small safe step from Next Exact Action, run the narrowest relevant check, update HANDOFF.md, and stop.
```

## Why `02:25`

The quota reset is `02:10`.
The extra 15 minutes gives a buffer.
The time is not exactly `02:00` or `02:30`, so it avoids the special timing offset Claude Code may add at those exact marks.

## What Should Happen

1. Claude updates `HANDOFF.md`.
2. Claude schedules one future prompt for `02:25` local time.
3. If quota blocks the current turn before then, nothing keeps retrying every minute.
4. At about `02:25`, if Claude Code is still open and idle, the scheduled prompt fires.
5. Claude reads the handoff.
6. Claude does one small safe step.
7. Claude updates the handoff again.
8. Claude stops.

## What This Does Not Do

- It does not bypass quota.
- It does not work if the terminal is closed.
- It does not work if Claude Code exits.
- It does not guarantee the whole task finishes.
- It does not use `tmux`, `screen`, `expect`, `claude -p`, or terminal injection.

## If The Reset Time Is Unknown

Use a slow loop only as a fallback:

```text
/loop 1h
```

Do not use `/loop 1m` for quota recovery.
That can add many failed attempts to the session.
