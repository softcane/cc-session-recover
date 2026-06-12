# Claude Code Handoff

This file lives in the project root on purpose.
Files under `.claude/` are treated as sensitive by Claude Code, so edits to them are blocked in unattended runs.

Use this file for the current task only.
Keep it fresh while work is active.
Update it after each small step and before any long or risky step.

## Goal

- Make this repo GitHub-ready, working through the checklist below in order.
- This is also the live real-quota test: if quota stops a turn, the heartbeat resumes this work after the reset with no human prompt.

## Current Status

- Session restarted with hooks live; heartbeat job 725d39bc armed (:13/:43). Working the checklist.

## Completed Work

- `.gitignore` created excluding all runtime artifacts.

## Remaining Checklist

- [x] Add a `.gitignore` that excludes runtime artifacts: `.claude/settings.local.json`, `.claude/rate-limit-state.json`, `.claude/stop-failure-events.jsonl`, `.claude/quota-blocked.json`.
- [ ] Commit the existing work in logical commits (template core; watcher and tests; status line cache and docs). Do not push anywhere.
- [ ] Write `CHANGELOG.md` summarizing what was built and what was verified live.
- [ ] Re-read `README.md` top to bottom as a newcomer and fix anything confusing or stale.
- [ ] Run `bash scripts/verify-claude-loop-workflow.sh` and `bash scripts/test-fake-quota-flow.sh`; both must pass.

## Files Changed

- None yet.

## Commands Run

- None yet.

## Current Errors or Failing Tests

- None known.

## Known Risks

- Commits are local-only; nothing is pushed. The user reviews before any push.

## Next Exact Action

- Make the logical commits: (1) core template with hooks, prompts, installer, verify script, and docs; (2) watcher and fake-quota test; (3) status line cache wrapper. Local only, no push.
