# Changelog

## 0.1.3 — 2026-06-12

- Install only the runtime `.claude` files and `HANDOFF.md` into target projects; package tooling now stays in the npm package.
- Enable hooks by default, with `--no-hooks` as the opt-out flag.
- Add `cc-session-recover watch` for running the closed-terminal watcher through `npx`.
- Remove the old one-time reminder flow and its `loop.md` prompt from the packaged workflow.

## 0.1.2 — 2026-06-12

- Stop installing the package docs into target projects.
- Keep runtime files out of target git history by appending the session-recovery ignore block.
- Remove the fake-quota try-it flow from the README.

## 0.1.0 — 2026-06-12

Initial release of the quota-resume template.

### Included

- `HANDOFF.md` notebook and `.claude/auto-continue.md` heartbeat prompt for automatic continuation after quota resets.
- `SessionStart` hook that injects the standing instructions, so the setup never has to be typed.
- `StopFailure` hook that logs quota stops and writes a marker for the unattended watcher.
- Watcher script that resumes the exact recorded session headlessly once quota is back, sleeping until the known reset time plus a 15-minute buffer when the status line cache is configured.
- Installer, verify script, plain-English docs, and a self-test that proves the whole chain in a throwaway repo without using real quota.

### Verification

- Every link was verified against real Claude Code sessions, including one genuine quota stop: the hook captured it, the heartbeat retried while blocked, and the first fire after the reset resumed and completed the task with no human input.
