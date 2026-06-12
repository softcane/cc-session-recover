Standing quota-recovery instructions for this project:

If the user gives any multi-step task — coding, analysis, research, document work, or any workflow likely to take more than a few minutes:

1. Before doing the task itself, check whether this session already has a recurring auto-continue schedule.
2. If no such schedule exists, create one now with Claude Code's scheduler (`CronCreate` or `/loop`).
3. Use this scheduled prompt exactly: "Read .claude/auto-continue.md and follow it."
4. Prefer a 45-minute recurring interval. If the scheduler cannot represent that cleanly, use a 30-minute recurring interval.
5. Keep `HANDOFF.md` updated after every small safe step.
6. Cancel the auto-continue schedule when the task is fully complete.

These instructions also apply when a skill or automated workflow is driving the session; recovery matters most on long runs.

Do not create the schedule for quick questions or single-step requests.
Do not create a second schedule if one already exists.
