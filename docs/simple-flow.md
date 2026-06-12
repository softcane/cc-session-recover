# The Simple Flow: Notebook, Alarm, Watchman

This is the plain-English story of how this workflow survives quota stops.

## The notebook

Claude keeps a notebook called `HANDOFF.md` in the project root.
After every small piece of work it writes down: the goal, what is done, and the exact next step.
If Claude is cut off at any moment, whoever reads the notebook can continue exactly where it stopped.
That "whoever" is usually Claude itself, later.

## The alarm

When you give Claude a big task, it sets a repeating alarm inside the session:
every 45 minutes, "read `.claude/auto-continue.md` and follow it."

- While Claude is working, the alarm is harmless.
- If the task is already done, the alarm fire reads the notebook, sees "done", and goes back to sleep.
- If quota cut Claude off, each alarm fire fails cheaply while quota is still blocked.
- The first fire after the quota reset reads the notebook and continues the work.

You never type anything. The one rule: the terminal must stay open, because the alarm lives inside the running session.

## The watchman

If the terminal cannot stay open, run the watchman in a second terminal:

```sh
bash scripts/quota-watcher.sh /path/to/project
```

When quota cuts Claude off, a hook drops a marker file with the session id.
The watchman sees the marker and knocks every 20 minutes: "can I resume that session yet?"
While quota is blocked: no, it waits. After the reset: yes, it resumes that exact session headlessly, hands it the notebook, and the work finishes without any window at all.

Use the alarm or the watchman, not both at once, or two Claudes will do the same work twice.

## A normal day with this installed

1. `cd` into the project and run `claude`.
2. Give your task normally. A hook already injected the standing orders, so Claude sets up the notebook and the alarm by itself.
3. Walk away. Quota stops are recovered automatically.
4. Worst case, everything fails: the notebook still means you lose nothing. Type "read HANDOFF.md and continue" and you are back.
