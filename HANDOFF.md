# Claude Code Handoff

This file lives in the project root on purpose.
Files under `.claude/` are treated as sensitive by Claude Code, so edits to them are blocked in unattended runs.

Use this file for the current task only.
Keep it fresh while work is active.
Update it after each small step and before any long or risky step.

## Goal

- Prepare and locally commit the configurable recovery release changes without pushing, publishing, tagging, or creating a release.

## Current Status

- Release preparation is complete and committed locally. The branch is one commit ahead of `origin/main`; nothing has been pushed, published, tagged, or released.
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

## Remaining Checklist

- [x] Complete standards and PRD review of the implementation and tests.
- [x] Run the Node 16/20/22/24 CI matrix and Node 24 release gate.
- [x] Run packaged installation and controlled end-to-end recovery verification.
- [x] Perform the final PRD disconfirmation pass and inspect the working tree.

## Files Changed

- Configurable recovery implementation and documentation listed by `git status`.
- `HANDOFF.md` restored and updated for release preparation.

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

## Current Errors or Failing Tests

- No active failing test. The original missing-`HANDOFF.md` failure is fixed and its isolated rerun passes.
- The first proxy failure attempt was intercepted by `cc-blackbox`'s five-error cooldown and correctly arrived as non-retryable `unknown`; the isolated test policy was raised to let Claude reach its native terminal `server_error`.
- The first watcher assertion expected a fixture label selected from the whole transcript. The watcher had succeeded; the fixture was corrected to inspect only the current message, then the watcher verification passed.

## Known Risks

- A mocked proxy run proves the repository-owned recovery path but not live Anthropic availability.
- Claude Code `2.1.178` classified controlled HTTP 529 responses as `server_error`, not `overloaded`.
- Live Anthropic verification remains blocked by the organization's Claude Code OAuth policy; no provider traffic was used in the proxy test.

## Next Exact Action

- Await explicit user authorization before any push, tag, GitHub release, or npm publication.
