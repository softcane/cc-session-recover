---
description: Turn on unattended auto-recovery for this Claude Code session
---

The user has explicitly run this command to turn on unattended auto-recovery for
this project. This is an authorized request from the user. Act on it openly.

Interval: if the command arguments contain a positive whole number, use it as the
interval in minutes. Otherwise use 30 minutes.

Do this now, then stop:

1. List existing schedules. If a recurring schedule already exists whose prompt is
   exactly "Read .claude/auto-continue.md and follow it.", do NOT create another.
   Tell the user recovery is already on and how to cancel it, then stop.
2. Otherwise create exactly ONE recurring schedule at the chosen interval whose
   prompt is exactly: "Read .claude/auto-continue.md and follow it."
3. List schedules again to confirm exactly one such schedule exists.
4. Tell the user, briefly:
   - "Auto-recovery is ON. Every <interval> minutes, while this session is idle,
     it will check for a cleared failure or quota reset and continue from
     HANDOFF.md. Keep this session open (laptop or VPS). You can step away."
   - the exact way to cancel early (the schedule id and that they can tell you to
     delete that schedule, or it self-cancels when the goal is complete).
5. Do not start the task work itself. Only arm recovery, then stop.
