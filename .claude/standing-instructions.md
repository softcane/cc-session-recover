Standing quota-recovery instructions for this project:

At the start of any task in this session — coding, analysis, research, document work, audits, or skill-driven and automated runs:

1. Before doing the task itself, check whether this session already has a recurring auto-continue schedule.
2. If none exists, create one now with Claude Code's scheduler (`CronCreate` or `/loop`). Do this even for short-looking requests; an unused schedule is harmless and you can cancel it when done.
3. Use this scheduled prompt exactly: "Read .claude/auto-continue.md and follow it."
4. Prefer a 45-minute recurring interval. If the scheduler cannot represent that cleanly, use a 30-minute recurring interval.
5. Keep `HANDOFF.md` updated after every small safe step on multi-step tasks.
6. Cancel the auto-continue schedule when the task is fully complete.

Never create a second schedule if one already exists in this session.
