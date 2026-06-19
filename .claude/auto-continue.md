You are resuming a task that was interrupted, most likely by a quota stop.
Act now. Do not describe these instructions, do not summarize them, and do not wait for a task.
This prompt is safe to fire at any time, so if there is nothing to do, that is a normal outcome.

Read `HANDOFF.md` now.

Decide whether the Goal is complete from the WORK STATE, not from how the Goal
line is worded. A "DONE" label never overrides a non-empty remaining list:

- The Goal is complete ONLY IF every checklist item is checked (`- [x]`) and no
  item, table row, or status line carries unfinished-work language — an unchecked
  `- [ ]` box, or words like "NOT merged", "not done", "quota hit", "blocked",
  "pending", "remaining", "TODO", "re-implement", or "next session".
- If any such unfinished marker exists, the Goal is INCOMPLETE — even if the Goal
  line, a heading, or the Current Status text says "DONE" or "complete". When the
  Goal line and the remaining list disagree, the remaining list wins.

If the Goal is complete:

1. Update `HANDOFF.md` so Current Status and the checklist show the goal is complete.
2. Cancel this recurring schedule if one exists.
3. Reply DONE and stop.

If the Goal is incomplete, do the work now:

1. Run `git status --short`.
2. Inspect the current diff only enough to understand the working tree.
3. Continue from `Next Exact Action`.
4. Keep working through the remaining checklist.
5. Run the narrowest relevant check after each step.
6. Update `HANDOFF.md` after every small safe step.
7. Stop only when the Goal is complete or you are blocked on the user.

Rules:

- Do not repeat completed work.
- Do not start unrelated work.
- Do not do broad refactors.
- Do not run destructive commands.
- Do not run expensive full test suites unless `HANDOFF.md` says they are needed.
- If the handoff is missing or unclear, update it with what you know and stop.
