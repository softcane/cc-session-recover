# Simple Flow: Notebook, Alarm, Watcher

The workflow has three parts.

## Notebook

Claude writes `HANDOFF.md` in the project root.
After each small step, it records the goal, completed work, and next exact action.

If quota stops the session, Claude can read that file later and continue from the same point.
You can also read it yourself and see what happened.

## Alarm

For a long task, Claude creates a 45-minute schedule inside the current Claude Code session:

```text
Read .claude/auto-continue.md and follow it.
```

Treat that schedule as the alarm.

- If Claude still has quota, it reads `HANDOFF.md` and keeps going.
- If the task finished, it reads `HANDOFF.md`, sees that, and stops.
- If quota still blocks the session, the attempt fails and waits for the next alarm.
- After quota resets, the next alarm resumes the work.

The terminal must stay open.
The alarm lives inside that running Claude Code session.

## Watcher

If you need to close the terminal, run the watcher from another shell:

```sh
npx cc-session-recover watch /path/to/project
```

When quota stops Claude, a hook writes a marker file with the session id.
The watcher reads that marker and tries to resume that exact session.

While quota blocks Claude, the watcher waits.
After quota resets, the watcher resumes the session without an open Claude Code window and gives Claude the handoff prompt.

Use the alarm or the watcher.
Do not use both on the same task, because two Claude sessions can edit the same files.

## Normal Use

1. Open the project and run `claude`.
2. Give Claude the task.
3. Let the hook inject the standing instructions.
4. Leave the terminal open, or run the watcher if you need to close it.

If everything else fails, run `claude` again and type:

```text
Read HANDOFF.md and continue.
```
