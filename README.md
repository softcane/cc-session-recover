# cc-session-recover

Claude Code can stop after a rate limit or a provider capacity error. This
package records the session, saves the work state, waits, and resumes the same
session.

[![Claude Code continuing after a real quota stop](docs/assets/cc-session-recover-demo.gif)](docs/assets/cc-session-recover-demo.mp4)

The demo shows a quota stop from June 12. Claude waited for the reset and
continued the same task.

## Install

```sh
npx cc-session-recover init /path/to/project
```

You can install from a clone:

```sh
bash scripts/install-into-project.sh /path/to/project
```

Pass `--no-hooks` to install the files without adding hooks. Claude Code asks
you to approve the hooks when you open the project.

## Default behavior

The installer creates this `session-recover.yaml`:

```yaml
errors:
  - rate_limit
  - overloaded

retry_minutes: 20
```

The default recovers from:

- `rate_limit`
- `overloaded`

The hook logs `server_error`, but the watcher will not retry it until you add it
to `errors`.

A missing YAML file uses the same defaults. The 20-minute interval applies when
the hook has no future quota reset time. A known rate-limit reset time takes
priority.

Claude Code chooses the typed StopFailure name. Claude Code `2.1.178` reported
controlled HTTP 529 responses as `server_error`. Add `server_error` if you want
the watcher to cover that classification.

## How recovery works

1. Claude Code sends a typed `StopFailure` event to the installed hook.
2. The hook writes the event to `.claude/stop-failure-events.jsonl` and adds a
   note to `HANDOFF.md`.
3. An enabled error creates `.claude/quota-blocked.json` with the session ID,
   error type, and retry interval.
4. The watcher runs `claude -p --resume` for that session. Failed attempts keep
   the marker. A successful attempt removes the marker.

Rate limits can use the cached reset time plus the configured buffer.
Overloads use `retry_minutes`.

Disabled errors stop recovery for the same session. Invalid YAML also stops
recovery, so a configuration mistake cannot start a retry loop.

## Run it

Start Claude Code in the project:

```sh
cd /path/to/project
claude
```

The installed instructions ask Claude to update `HANDOFF.md` and create an
in-session recovery schedule. Claude controls that schedule.

Run the watcher from another terminal if you plan to close the Claude Code
session:

```sh
npx cc-session-recover watch /path/to/project
```

Close the interactive Claude Code session before starting the watcher. Two
sessions can edit the same files if you run both recovery paths at once.

## Change the configuration

Enable server errors:

```yaml
errors:
  - rate_limit
  - overloaded
  - server_error

retry_minutes: 10
```

Keep quota recovery alone:

```yaml
errors:
  - rate_limit

retry_minutes: 20
```

The installer preserves an existing YAML file during upgrades. The file accepts
two fields: `errors` and `retry_minutes`.

## Limits

- The package cannot bypass quota or provider failures.
- Authentication, billing, invalid-request, model-not-found, and unknown errors
  stay out of the retry loop.
- Claude must follow the injected instructions for the in-session schedule.
- The watcher needs `jq`, Node.js, and the `claude` command on `PATH`.

## Docs

- [Simple flow](https://github.com/softcane/cc-session-recover/blob/main/docs/simple-flow.md):
  notebook, schedule, and watcher.
- [FAQ](https://github.com/softcane/cc-session-recover/blob/main/docs/faq.md):
  hook approval and failure handling.
- [Full details](https://github.com/softcane/cc-session-recover/blob/main/docs/claude-code-auto-resume.md):
  watcher timing, reset-time cache, and operational limits.
