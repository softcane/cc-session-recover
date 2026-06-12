# FAQ

## Where Does The 45-Minute Alarm Live?

Claude Code keeps the alarm inside the running session.
It does not create a cron job, a launchd job, or a file on disk.

The standing-instructions hook asks Claude to create the alarm when you give a long task.
Claude creates it with the Claude Code scheduler.

If you close the terminal, the session ends and the alarm dies.

## Is This 100% Reliable?

No.

The scripts and watcher have end-to-end tests.
The Claude Code hooks and schedules use documented behavior.
The weak part is Claude following the injected instructions, such as keeping `HANDOFF.md` fresh and creating the alarm.

After your first real quota stop, check `.claude/stop-failure-events.jsonl`.
That file confirms whether the hook fired.

## What Still Needs A Human?

You still need to:

- Start Claude Code.
- Give the task.
- Approve the hooks once per project.
- Keep the terminal open for the alarm, or run the watcher from another shell.
- Review the finished work.

The workflow resumes progress.
It does not judge quality.

## What Happens If The Terminal Closes?

The alarm stops with the session.
Your work state remains in `HANDOFF.md`.

If the watcher runs and the hook recorded a quota stop, the watcher resumes the saved session.
If the watcher does not run, reopen the project, start `claude`, and type:

```text
Read HANDOFF.md and continue.
```
