# Claude Code Handoff

This file lives in the project root on purpose.
Files under `.claude/` are treated as sensitive by Claude Code, so edits to them are blocked in unattended runs.

Use this file for the current task only.
Keep it fresh while work is active.
Update it after each small step and before any long or risky step.

## Goal

- Rewrite `README.md` with the Stop Slop skill and enable `rate_limit` plus `overloaded` by default.

## Current Status

- The previous release preparation is committed locally at `acdd1ff`.
- The new default-selection and documentation changes are uncommitted.
- Baseline check, tests, audit, and package dry-run passed before this change.
- The runtime default, installed YAML, tests, README, docs, changelog, and PRD now describe `rate_limit` plus `overloaded`.
- The filtered missing-YAML packaged test and repository check pass after the change.
- The full release gate, audit, packaged installation, installed-default assertion, and diff check pass.
- User requested a local commit before moving into the `cc-blackbox` testing plan.
- `.gitignore` now excludes `Docs Internal/` and `internal/`; the previously tracked `Docs Internal/configurable-recovery-prd.md` is being removed from git, and the local `internal/` copy remains ignored.
- Release-candidate baseline captured at commit `4c1cc04665aa41dcdfac1ffb46a4bbb2dd7e01e0`.
- Full tests, dependency audit, package dry-run, and packaged CLI smoke pass on Node `v25.2.1`.
- `npm run check` failed because this tracked file had been deleted.
- The isolated `npm run check` rerun passes after restoring this file.
- Release version prepared as `0.2.0`; npm currently contains versions only through `0.1.5`.
- Clean Linux gates pass on Node `16.20.2`, `20.20.2`, `22.23.0`, and `24.17.0`.
- The real Claude CLI plus `cc-blackbox` controlled-proxy recovery flow passes for session `b4447fa3-dee5-4b2d-9d41-d09ad52250db`.

## Completed Work

- Read the complete configurable recovery PRD.
- Read the CI and publish workflows.
- Confirmed the package artifact includes the new YAML, runtime, watcher, installer, and test files.
- Confirmed the current npm registry version is `0.1.5`.
- Restored `HANDOFF.md` and reran the previously failing check successfully.
- Added Node 16 and Node 24 to CI so the declared minimum and release runtime are exercised.
- Documented the observed Claude Code `2.1.178` HTTP 529 classification.
- Ran `actionlint` successfully against both workflows.
- Confirmed a real controlled HTTP 503 becomes typed `server_error` after Claude's native retries.
- Confirmed the installed hook created the expected log, handoff note, and marker with one-minute YAML timing.
- Confirmed the installed watcher resumed the exact session through the proxy with the installed prompt byte-for-byte.
- Confirmed watcher success removed only the marker; the event-log and handoff hashes remained unchanged.
- Removed the isolated proxy containers, network, volume, image, Claude state, package, and scratch project.
- Preserved the pre-existing `cc-blackbox_cc_blackbox_data` Docker volume.
- Ran the final workflow lint, audit, full release gate, package installation smoke, registry check, and npm publish dry-run successfully.
- Read the Stop Slop skill and its phrase, structure, and example references.
- Rewrote `README.md` to explain default behavior and the recovery path in plain language.
- Changed missing-YAML recovery to enable `rate_limit` and `overloaded` with the existing 20-minute fallback.
- Added packaged-artifact assertions for the installed default YAML and overload recovery.
- Added ignore rules for repo-local internal planning/spec folders before committing.

## Remaining Checklist

- [x] Change runtime and installed YAML defaults.
- [x] Rewrite the README with Stop Slop rules.
- [x] Update affected docs, changelog, PRD, and automated expectations.
- [x] Run the full tests, audit, package gate, and final diff review.

## Files Changed

- Configurable recovery implementation and documentation listed by `git status`.
- `HANDOFF.md` restored and updated for release preparation.
- Default-selection changes in `lib/recovery.js` and `session-recover.yaml`.
- README, docs, changelog, PRD, verification script, and configurable recovery tests.

## Commands Run

- `npm ci --ignore-scripts` — pass.
- `npm audit --audit-level=moderate` — pass, zero vulnerabilities.
- `npm run check` — fail: missing `HANDOFF.md`.
- `npm run check` — isolated rerun passes after restoring `HANDOFF.md`.
- `npm test` — pass.
- `npm pack --dry-run --json` — pass.
- CI packaged CLI smoke — pass.
- `npm view cc-session-recover version` — `0.1.5`.
- `actionlint` in its container image — pass.
- Clean Linux Node 16/20/22 runs: install, audit, check, tests — pass.
- Clean Linux Node 20/22 packaged CLI smoke — pass.
- Clean Linux Node 24: install, audit, `prepublishOnly`, packaged CLI smoke — pass.
- Real Claude CLI through isolated `cc-blackbox`: initial response `INITIAL_PROXY_OK` — pass.
- Controlled 503 through real Claude CLI: exit 1 with typed `server_error` — pass after 11 native attempts.
- Installed watcher through the same proxy: exact session, one request, exact prompt, `WATCHER_EXACT_RESUME_OK`, marker cleanup — pass.
- Final `npm run prepublishOnly` — pass.
- Final package version/tag contract — `0.2.0` and `v0.2.0`, pass.
- npm registry availability check — `0.2.0` is not published.
- Fresh `0.2.0` artifact install and installed-file/settings assertions — pass.
- `npm publish --dry-run --ignore-scripts` — pass; no publication occurred.
- New-task baseline `npm run check` — pass.
- New-task baseline `npm test` — pass.
- New-task baseline audit and package dry-run — pass.
- `TEST_FILTER='missing YAML' node scripts/test-configurable-recovery.js` — pass.
- Post-change `npm run check` — pass.
- First `npm run prepublishOnly` — fail: the full guide lost the verifier phrase `quota or rate limit`.
- Isolated `npm run check` after restoring that compatibility phrase — pass.
- Final `npm run prepublishOnly` — pass.
- Final `npm audit --audit-level=moderate` — pass, zero vulnerabilities.
- Final packaged installation — pass; YAML contains `rate_limit`, `overloaded`, and `retry_minutes: 20`.
- Final `git diff --check` — pass.
- Commit-prep `git status --short --branch` — dirty with scoped README/default/docs/runtime/test changes plus tracked internal PRD deletion.
- Commit-prep `npm run prepublishOnly` — pass.
- Commit-prep `git diff --check` — pass.

## Current Errors or Failing Tests

- No active failing test. The documentation verifier regression is fixed.

## Known Risks

- A mocked proxy run proves the repository-owned recovery path but not live Anthropic availability.
- Claude Code `2.1.178` classified controlled HTTP 529 responses as `server_error`, not `overloaded`.
- Live Anthropic verification remains blocked by the organization's Claude Code OAuth policy; no provider traffic was used in the proxy test.
- Existing projects keep their YAML during reinstall, so this new default affects fresh installations and projects that lack the file.

## Next Exact Action

- Stage only scoped files, create the requested local commit, and then plan the `cc-blackbox` proxy scenario tests. Do not push, tag, publish, or release.
