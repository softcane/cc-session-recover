# Claude Code Handoff

This file lives in the project root on purpose.
Files under `.claude/` are treated as sensitive by Claude Code, so edits to them are blocked in unattended runs.

## Goal

- End-to-end reverification of the unconditional schedule rule across instruction types. COMPLETE.

## Current Status

- Done. Fresh dummy repo, install from local build, four real Sonnet sessions. Heartbeat cancelled.

## Result (2026-06-13)

- Install footprint correct: 8 `.claude` files + HANDOFF + gitignore; all three hooks wired.
- Case A (quick question): created schedule — CronCreate tool_use = 1.
- Case B (multi-step coding): created schedule + did the work (subtract/multiply added) — CronCreate = 1.
- Case C (read-only audit, the type that failed before): created schedule — CronCreate = 1.
- Case D (explicit "do not create schedules"): correctly did NOT — CronCreate = 0; user override wins.
- Confirmed headless automation supports CronCreate (real tool_use, not prose).

## Next Exact Action

- None. Verification complete; ready for a 0.1.5 release when desired.
