# Changelog

## 0.2.0 — 2026-06-22

- Add `session-recover.yaml` with the two supported settings: transient error selection and fixed retry minutes.
- Preserve the existing rate-limit-only, 20-minute behavior when configuration is missing.
- Log every typed StopFailure, cancel same-session stale recovery for disabled or permanent failures, and fail closed on invalid configuration.
- Keep quota reset-time priority for rate limits while using fixed timing for overloads and server errors.
- Preserve edited YAML, unrelated hook handlers, and existing Claude settings across npm and clone-installer upgrades.
- Reject stale quota observations and semantically invalid or non-retryable markers before invoking Claude.
- Add packaged-artifact end-to-end coverage for configuration, malformed state, timing, watcher restart, exact-session resume, race-safe cleanup, and failure paths.

## 0.1.5 — 2026-06-13

- Add a `UserPromptSubmit` recovery reminder hook so the schedule instruction is repeated next to every prompt, not just at session start (it was getting buried in long sessions).
- Make the schedule rule unconditional and consistent across both injection points: always ensure one recurring auto-continue schedule exists, instead of leaving the model a "is this a long task?" judgment call that silently skipped audits and skill-driven runs. An explicit user instruction not to schedule still wins.
- Preserve existing `.claude/settings.local.json` on install by merging the recovery hooks in, rather than skipping when the file exists.
- Use the quoted `"$CLAUDE_PROJECT_DIR"` form in example hook commands (safe for paths with spaces).

## 0.1.4 — 2026-06-12

- Expand standing quota-recovery instructions to cover long analysis, research, document, and automated workflow tasks, not only coding tasks.

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
