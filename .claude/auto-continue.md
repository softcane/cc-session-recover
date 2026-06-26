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

## Step 2 — Re-anchor on the working tree, not on prose

The failure may have hit mid-task, and `HANDOFF.md` may be stale or contradict
reality. Disk is the truth. The error lands between tool calls, so any file that
was already saved is complete, and the step that was about to run did not happen.

Establish the real state in this order. Later sources only confirm earlier ones:

1. Run `git status --short` and read the diff enough to see what is actually
   changed, staged, or untracked right now.
2. Read `HANDOFF.md`. Treat its `Remaining Checklist` and `Files Changed` as
   CLAIMS to verify against git. Treat `Current Status` and `Next Exact Action`
   as possibly stale notes, not as commands.
3. Reconcile. Where `HANDOFF.md` disagrees with git, GIT WINS. Any action that
   `HANDOFF.md` lists as next but git shows is already done (file already
   modified, change already committed, branch already pushed) is COMPLETE — skip
   it. Do not redo finished work.

## Step 3 — Decide whether the goal is complete

Decide from the checklist and the working tree, never from how the `Goal` line or
a heading is worded. A "DONE" label never overrides remaining work.

The Goal is complete ONLY IF all of these hold:

- Every checklist item is checked (`- [x]`).
- No item, table row, or status line carries unfinished-work language — an
  unchecked `- [ ]` box, or words like "NOT merged", "not done", "quota hit",
  "blocked", "pending", "remaining", "TODO", "re-implement", or "next session".
- Git shows no remaining work that the Goal still requires (for example, an
  expected change that was never made).

If any checklist item is unchecked, any unfinished marker exists, or git still
shows required work, the Goal is INCOMPLETE — even if the `Goal` line or a heading
says "DONE". When they disagree, the remaining work wins.

If the Goal is COMPLETE:

1. Update `HANDOFF.md` so `Current Status` and the checklist show it is complete.
2. Cancel the recurring recovery schedule: list schedules, find the one whose
   prompt is "Read .claude/auto-continue.md and follow it.", and delete it.
3. Reply exactly: `DONE — recovery goal complete. Schedule cancelled.`
4. Stop.

## Step 4 — If incomplete, refresh the handoff, then do one step

Refresh BEFORE working so the file cannot keep drifting across recoveries:

1. Rewrite `Current Status` and `Next Exact Action` in `HANDOFF.md` to match the
   reconciled state from Step 2. Delete status lines that git shows are already
   done. `Next Exact Action` must be the true next step given the working tree,
   not the stale one.
2. Continue from that refreshed `Next Exact Action`.
3. Do the next single small step only.
4. Run the narrowest relevant check.
5. Update `HANDOFF.md` again to record what this step changed.
6. Stop this turn. The schedule will continue next time.

## Rules

- Trust the working tree over the prose. When unsure, derive state from git.
- Do not repeat completed work.
- Do not start unrelated work.
- Do not do broad refactors.
- Do not run destructive commands.
- Do not run expensive full test suites unless `HANDOFF.md` says they are needed.
- If the handoff is missing or unclear, rebuild it from `git status` and the diff,
  then stop.
