# Goal: Add Simple YAML Configuration for Transient Failure Recovery

## Goal

Extend the existing quota recovery workflow so a user can choose which transient Claude Code failures should trigger automatic session recovery.

Keep the current rate-limit behavior as the default. Add one YAML configuration file with two user-facing settings:

- The error types to recover from.
- The number of minutes to wait between retries when no quota reset time is available.

The change must remain compatible with projects that already use the current quota watcher.

## Success Criteria

- An existing installation with no YAML configuration continues to recover from rate limits every 20 minutes.
- A user can enable recovery for `rate_limit`, `overloaded`, and `server_error`.
- A user can enable only a subset of those errors.
- A user can change the fixed retry interval in minutes.
- A known rate-limit reset time still takes priority over the fixed retry interval.
- Disabled and non-retryable errors are logged but do not start or continue automatic recovery.
- Restarting the watcher continues from an existing recovery marker.
- Invalid configuration stops automatic recovery and reports the configuration error.
- The installer does not overwrite an existing YAML configuration.
- The packaged npm artifact passes the complete fake StopFailure-to-resume flow in a temporary project.
- Every supported error and configuration choice has an automated test for the files created, resume command issued, retry behavior, and cleanup behavior.
- Tests confirm that disabled and permanent errors cannot inherit a stale retry marker.
- Existing checks and the packaged npm installation continue to pass.

## Problem Statement

The current workflow listens only for the `rate_limit` StopFailure type. The watcher treats every failed resume as another quota failure and waits for a fixed 20-minute interval.

Claude Code also reports temporary failures such as `overloaded` for 529 responses and `server_error` for temporary server failures. These failures can recover after waiting, but the current hook does not create a recovery marker for them.

Users need control over this behavior. Some users want quota recovery only. Others want recovery for all supported transient errors. They also need a simple way to change the retry interval without editing scripts or setting shell variables.

## Solution

Install a YAML configuration file named `session-recover.yaml` with this default behavior:

```yaml
errors:
  - rate_limit

retry_minutes: 20
```

The configuration has two settings:

- `errors` is a list containing any combination of `rate_limit`, `overloaded`, and `server_error`.
- `retry_minutes` is a positive whole number used when the watcher does not have a future quota reset time.

The StopFailure hook will run for every Claude Code API failure. It will always record the failure. It will create or update the active recovery marker only when the error appears in the configured `errors` list.

For a configured `rate_limit`, the watcher will use the cached quota reset time when one exists. It will preserve the current reset buffer. If no future reset time exists, it will wait for `retry_minutes`.

For configured `overloaded` and `server_error` failures, the watcher will wait for `retry_minutes` and resume the recorded session.

If a later StopFailure is not enabled, the hook will log it and cancel the active automatic recovery for that session. This prevents an authentication, billing, request, or other permanent failure from being retried as though it were still a quota failure.

If the watcher or Claude subprocess exits unexpectedly, the recovery marker remains on disk. Restarting the watcher continues from that marker.

## End-to-End Recovery Contract

The automated end-to-end test starts at Claude Code's documented hook boundary. It sends the same JSON that Claude Code sends to a `StopFailure` command hook.

The test does not mock Anthropic's private HTTP API. Claude Code owns the conversion from an HTTP failure such as 429 or 529 into a typed hook event such as `rate_limit` or `overloaded`. This project owns everything after that event.

The automated test must cover this complete path:

1. Pack and install the npm package into a temporary project.
2. Write or preserve the project's YAML configuration.
3. Send a fake typed `StopFailure` JSON event to the installed hook.
4. Verify the failure log, handoff note, and recovery marker.
5. Start the installed watcher.
6. Put a fake `claude` executable first on `PATH`.
7. Make the fake executable record its arguments, fail for a controlled number of calls, and then succeed.
8. Verify that the watcher waits according to the YAML configuration or the known quota reset time.
9. Verify that the watcher resumes the exact session ID and passes the recovery prompt.
10. Verify that failed attempts leave recovery state in place.
11. Verify that success removes only the active recovery marker.
12. Stop the watcher and clean the temporary project.

This contract proves the behavior owned by this repository:

```text
typed StopFailure event
  -> configuration decision
  -> log and marker files
  -> watcher
  -> exact-session resume command
  -> retry
  -> successful cleanup
```

The automated contract does not prove that the model will create the in-session recurring schedule or keep `HANDOFF.md` current while working. Tests can prove that the SessionStart and UserPromptSubmit hooks inject the required instructions. Actual model compliance remains a Claude Code behavior and requires an optional manual smoke test in a real session.

## User Stories

1. As an existing user, I want the default behavior to remain quota-only, so that an upgrade does not change which failures are retried.

2. As an existing user, I want the default retry interval to remain 20 minutes, so that an upgrade preserves the current watcher timing.

3. As a user, I want configuration written in YAML, so that I can read and edit it without changing scripts.

4. As a user, I want to enable recovery for rate limits only, so that server incidents do not trigger unattended retries.

5. As a user, I want to enable recovery for 529 overloads, so that a temporary capacity incident can recover without another prompt.

6. As a user, I want to enable recovery for temporary server errors, so that a temporary 5xx failure can recover without another prompt.

7. As a user, I want to enable all supported transient errors, so that the watcher can recover from rate limits, overloads, and server errors.

8. As a user, I want to choose a subset of supported errors, so that the watcher follows my preferred risk level.

9. As a user, I want to set one retry interval in minutes, so that retry timing stays easy to understand.

10. As a user, I want a known quota reset time to take priority, so that the watcher does not retry before quota becomes available.

11. As a user, I want unsupported errors logged, so that I can see why the task stopped.

12. As a user, I want unsupported errors to stop automatic recovery, so that the watcher does not loop on authentication, billing, or request problems.

13. As a user, I want an invalid configuration to fail closed, so that a typo does not enable retries I did not request.

14. As a user, I want installer upgrades to preserve my YAML file, so that my recovery choices do not get reset.

15. As a user, I want a watcher restart to reuse the existing marker, so that a watcher crash does not lose the interrupted session.

16. As a maintainer, I want the old quota flow covered by the existing end-to-end test, so that the backport does not change proven behavior.

17. As a maintainer, I want each supported error selection tested through the hook and watcher boundary, so that configuration affects real recovery behavior.

18. As a maintainer, I want the npm package tested after installation into a temporary project, so that source-tree tests do not hide packaging mistakes.

19. As a maintainer, I want tests to send realistic StopFailure JSON to the installed hook, so that tests cover the same boundary used by Claude Code.

20. As a maintainer, I want the fake Claude executable to fail and recover in controlled ways, so that retry and cleanup behavior can be tested without causing real provider failures.

21. As a maintainer, I want every file created by recovery inspected in tests, so that malformed or stale state cannot pass unnoticed.

22. As a maintainer, I want tests to distinguish repository behavior from model compliance, so that a passing test does not make a false claim about Claude following injected instructions.

## Implementation Decisions

- Add a small recovery configuration module that loads YAML, applies defaults, and validates the two supported settings.
- Keep the configuration interface limited to `errors` and `retry_minutes`.
- Accept only `rate_limit`, `overloaded`, and `server_error` in the error list.
- Treat a missing configuration file as the current behavior: rate-limit recovery with a 20-minute retry interval.
- Treat invalid YAML, unknown error names, an empty error list, and invalid retry values as configuration errors. Log the problem and do not recover automatically.
- Change the StopFailure hook matcher so the hook receives all API failure types.
- Separate failure logging from the decision to create a recovery marker.
- Keep the current marker format and filename for compatibility. Add fields only when the new implementation needs them.
- Keep rate-limit reset-time handling. Do not apply cached quota reset times to overload or server errors.
- Use one fixed retry interval. Do not add exponential backoff, factors, maximum delays, retry budgets, presets, or per-error timing.
- Preserve existing environment-variable overrides for compatibility. YAML becomes the normal user-facing configuration.
- Move YAML parsing and recovery decisions into the Node runtime used by the npm package. Do not require `yq`, Python packages, or dependencies in the target project.
- Keep the hook input compatible with Claude Code's documented JSON event shape and read it from standard input.
- Keep the watcher executable replaceable through `PATH` during tests. Production continues to invoke the user's `claude` executable.
- Keep the small instruction-printing hooks in shell unless replacing them removes a concrete compatibility problem.
- Keep the clone-based shell installer. Update it to copy the default YAML file only when the target does not already have one.
- Keep the npm installer as the primary installation path.
- Do not add new operational commands.

## Testing Decisions

Tests will assert external behavior. They will inspect installed files, hook output, recovery state, watcher output, process arguments, timing decisions, and exit results. They will not assert private helper functions or parser implementation details.

### Baseline

- Before implementation, record the current commit, working-tree state, and results of the repository check, fake quota-flow test, dependency audit, and package dry run.
- Keep the current no-configuration rate-limit flow passing. Missing YAML must remain equivalent to `errors: [rate_limit]` and `retry_minutes: 20`.
- After each meaningful implementation step, run the relevant narrow test and then the full gate. Record any delta from the baseline.

### Installed-package end-to-end tests

- Pack the package and install that artifact into a temporary project. Do not test only files from the source checkout.
- Send fake `SessionStart` and `UserPromptSubmit` events to the installed hooks and verify that recovery instructions are injected.
- Send typed `StopFailure` JSON through standard input to the installed StopFailure hook.
- Use a fake `claude` executable that records every argument, returns controlled exit codes, and can fail before succeeding.
- Run the installed watcher against the temporary project.
- Verify the generated log, handoff note, recovery marker, watcher output, exact session ID, recovery prompt, number of attempts, and final marker cleanup.

### Error-selection matrix

- Missing YAML: `rate_limit` creates recovery state; `overloaded` and `server_error` do not.
- Rate-limit-only YAML: `rate_limit` creates recovery state; `overloaded` and `server_error` are logged without recovery state.
- All-supported-errors YAML: `rate_limit`, `overloaded`, and `server_error` each create recovery state and resume the recorded session.
- Subset YAML: only listed error types create recovery state.
- Duplicate error names: either accept them as one value or reject them consistently. The chosen behavior must be documented and tested.
- Unknown error name: report invalid configuration and create no recovery state.
- Empty error list: report invalid configuration and create no recovery state.
- Missing `errors`: report invalid configuration and create no recovery state.

### Retry timing

- Missing YAML uses the current 20-minute fallback.
- A valid `retry_minutes` value controls the fallback delay.
- Test timing with a short fixture value so the suite does not wait for real minutes.
- A future rate-limit reset time takes priority over `retry_minutes`.
- A past, missing, null, malformed, or stale reset time falls back to `retry_minutes`.
- `overloaded` and `server_error` ignore cached quota reset time.
- `retry_minutes` rejects zero, negative numbers, fractions, strings, null, and values outside the accepted safe integer range.

### State and file behavior

- Every StopFailure event is appended to the failure log, including disabled and unknown errors.
- Enabled errors create a marker containing the correct session ID and typed error.
- Disabled errors do not create a marker.
- A disabled or permanent error for the same session removes an older active retry marker so the watcher cannot continue retrying stale state.
- A disabled or permanent error for a different session does not delete another session's active marker.
- A hook event without a session ID is logged but cannot create actionable recovery state.
- Malformed hook JSON does not create a partial marker or corrupt an existing valid marker.
- Malformed cached rate-limit state does not corrupt the recovery marker.
- Handoff notes name the actual failure type instead of describing every failure as a rate limit.
- Repeated failures do not append unbounded duplicate handoff notes for the same active incident.

### Watcher behavior

- Failed resume attempts preserve the marker.
- A successful resume removes the marker.
- The watcher resumes the session ID stored in the marker, not another session.
- The watcher passes the installed recovery prompt.
- Restarting the watcher with an existing marker continues recovery.
- A marker without a session ID is handled without invoking Claude.
- Invalid or partially written marker data does not invoke Claude.
- A newer marker written while an older resume attempt is running is not removed by the older successful attempt.
- The watcher reports missing prompt files and missing Claude executable clearly.
- Existing environment-variable overrides continue to work and take precedence according to the documented compatibility rule.

### Installer and upgrade behavior

- First installation creates the default YAML file.
- Reinstalling preserves user edits to the YAML file.
- Both the npm installer and clone-based shell installer follow the same create-if-missing rule.
- Existing Claude settings are preserved while the StopFailure hook configuration is updated.
- Reinstalling does not duplicate hooks.
- The packaged artifact contains the YAML template and all runtime files needed by installed hooks and the watcher.

### Configuration failure behavior

- Invalid YAML reports the file and parse failure without exposing unrelated file contents.
- Invalid YAML creates no recovery marker.
- Invalid configuration does not silently use permissive defaults.
- Missing YAML uses backward-compatible defaults and is not treated as invalid.

### Completion gate

- Run the repository check.
- Run the complete automated test suite.
- Run the dependency audit.
- Pack the npm artifact and run the installed-package smoke and end-to-end tests against it.
- Investigate every failure found during implementation. Fix defects caused by this work and rerun the failing test alone before rerunning the full gate.
- Run a disconfirmation pass against the final implementation: disabled errors, malformed inputs, stale state, restart behavior, and package installation must fail or recover as specified.
- Inspect the final diff for unrelated changes and generated runtime files.
- Compare final results with the recorded baseline. Any new failure, skipped required case, unexplained flaky result, or unverified success claim blocks completion.
- Review every Success Criterion and Testing Decision against test output before marking the PRD complete.
- Leave no required item as a TODO, skipped test, or undocumented assumption. If an external limitation prevents verification, record the exact limitation and do not mark that criterion complete.

## Out of Scope

- Exponential backoff.
- Separate retry timing for each error.
- Maximum attempts or maximum elapsed time.
- A doctor command.
- A simulator command.
- A dry-run command.
- Operating-system services that start the watcher after reboot.
- Automatic model switching.
- Automatic retries for authentication, billing, invalid request, model-not-found, or unknown errors.
- Automatic recovery from auto-mode classifier denial or classifier unavailability. Claude Code reports those through a different hook path and does not provide the same stable typed StopFailure contract.
- Changes to the in-session scheduler beyond updating documentation to describe the supported failures.
- Renaming existing runtime marker files.

## Further Notes

Claude Code performs its own retries before StopFailure runs. This workflow starts only after Claude Code gives up on the current turn.

The watcher still requires the interactive session to be closed. Running the watcher beside an open heartbeat session can make two sessions work on the same task.

The implementation can guarantee local configuration, failure selection, waiting, marker persistence, and exact-session resume behavior. It cannot force a real provider outage during tests, so tests will use typed StopFailure events and a fake Claude executable, matching the existing test approach.
