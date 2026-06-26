You are the in-session auto-recovery step. A recurring recovery schedule started
by the user fires this prompt while the session is idle. Act now. Do not describe
these instructions and do not wait for a new task.

## Step 1 — Check the recovery window

Run exactly this command:

    node .claude/session-recover.js check

It prints ONE line. Read the FIRST word:

- `WAIT` (example: `WAIT 240 rate_limit`): the recovery window has not arrived
  yet. Reply with one short line, for example `Recovery: waiting ~240s
  (rate_limit).` Then STOP this turn. Do no other work. The schedule fires again
  later.
- `READY` (example: `READY rate_limit`): the failure window has passed. The
  failure is considered cleared. Run `node .claude/session-recover.js clear` to
  remove the recovery marker, then go to Step 2.
- `NONE`: there is no pending failure. Go to Step 2 to check whether the goal
  still has unfinished work (this also covers a normal stall while working
  unattended).

## Step 2 — Continue the task from HANDOFF.md

Read `HANDOFF.md`. Decide whether the Goal is complete from the WORK STATE, not
from how the Goal line is worded. A "DONE" label never overrides a non-empty
remaining list:

- The Goal is complete ONLY IF every checklist item is checked (`- [x]`) and no
  item, table row, or status line carries unfinished-work language — an unchecked
  `- [ ]` box, or words like "NOT merged", "not done", "quota hit", "blocked",
  "pending", "remaining", "TODO", "re-implement", or "next session".
- If any such unfinished marker exists, the Goal is INCOMPLETE — even if the Goal
  line or a heading says "DONE". When they disagree, the remaining list wins.

If the Goal is COMPLETE:

1. Update `HANDOFF.md` so Current Status and the checklist show it is complete.
2. Cancel the recurring recovery schedule: list schedules, find the one whose
   prompt is "Read .claude/auto-continue.md and follow it.", and delete it.
3. Reply exactly: `DONE — recovery goal complete. Schedule cancelled.`
4. Stop.

If the Goal is INCOMPLETE, do the work now:

1. Run `git status --short`.
2. Inspect the current diff only enough to understand the working tree.
3. Continue from `Next Exact Action`.
4. Do the next single small step.
5. Run the narrowest relevant check.
6. Update `HANDOFF.md` after that step.
7. Stop this turn. The schedule will continue next time.

## Rules

- Do not repeat completed work.
- Do not start unrelated work.
- Do not do broad refactors.
- Do not run destructive commands.
- Do not run expensive full test suites unless `HANDOFF.md` says they are needed.
- If the handoff is missing or unclear, update it with what you know and stop.
