# cc-session-recover

`cc-session-recover` helps a Claude Code task recover after sustained transient
failures: rate limits, overloads, and server errors you opt into. It records the
failure, keeps a project-local handoff, waits for the retry window, and lets
Claude continue from that handoff.

[![Claude Code continuing after a real quota stop](docs/assets/cc-session-recover-demo.gif)](docs/assets/cc-session-recover-demo.mp4)

The demo shows Claude Code hitting a quota stop on June 12, waiting for the
reset, and continuing the same task.

## Install

```sh
npx cc-session-recover init /path/to/project
```

Install from a clone:

```sh
bash scripts/install-into-project.sh /path/to/project
```

The installer adds the StopFailure hook, the `/session-recover` slash command,
the status-line quota cache, and a local runtime at
`.claude/session-recover.js`. It preserves an existing `HANDOFF.md` or
`session-recover.yaml`.

Use `--no-hooks` to install the files without merging hook settings into
`.claude/settings.local.json`. Claude Code asks you to approve the hook command
when you open the project.

## Default configuration

The installer creates this `session-recover.yaml`:

```yaml
errors:
  - rate_limit
  - overloaded

retry_minutes: 20
```

The default retries:

- `rate_limit`
- `overloaded`

`server_error` events are logged, but they do not create a retry marker until you
add `server_error` to `errors`.

If `session-recover.yaml` is missing, the runtime uses the same defaults. For
rate limits, a valid cached quota reset time wins over `retry_minutes`. Overload
and server-error recovery use `retry_minutes`.

Claude Code chooses the typed StopFailure name. Claude Code `2.1.178` reported
controlled HTTP 529 responses as `server_error`. Add `server_error` if you want
recovery for that classification.

## Same-session recovery

Start Claude Code in the project:

```sh
cd /path/to/project
claude
```

Start your task, then turn on recovery:

```text
/session-recover
```

Pass a minute count to change the schedule interval:

```text
/session-recover 15
```

Keep that Claude Code session open. The slash command creates one recurring
Claude Code schedule with this prompt:

```text
Read .claude/auto-continue.md and follow it.
```

When the session is idle, the schedule runs the marker-aware recovery prompt.
That prompt calls:

```sh
node .claude/session-recover.js check
```

The check command prints one line:

- `WAIT <seconds> <error>`: the retry window has not arrived, so Claude stops
  and waits for the next scheduled check.
- `READY <error>`: the retry window has passed, so Claude clears
  `.claude/quota-blocked.json`, reads `HANDOFF.md`, and does the next small step
  in the same session.
- `NONE`: no pending failure exists, so Claude reads `HANDOFF.md` and continues
  only if work remains.

When the handoff checklist is complete, Claude cancels the recovery schedule and
prints `DONE`.

## External watcher

Use the watcher when the original Claude Code process will not stay open:

```sh
npx cc-session-recover watch /path/to/project
```

The watcher reads the same marker file and resumes with `claude -p --resume`.
That starts a separate Claude Code session. Do not run the watcher and
`/session-recover` on the same project at the same time unless you are prepared
for two sessions to edit the same files.

Recovery is opt-in because a StopFailure hook cannot make a failed Claude Code
turn continue. Same-session recovery needs a live Claude Code process so the
user-created schedule can re-drive the idle session.

## How the marker works

1. Claude Code sends a typed `StopFailure` event to the installed hook.
2. The hook writes the event to `.claude/stop-failure-events.jsonl` and appends a
   note to `HANDOFF.md`.
3. If the error is enabled in `session-recover.yaml`, the hook writes
   `.claude/quota-blocked.json` with the session ID, error type, retry interval,
   and any cached rate-limit reset time.
4. The same-session schedule or external watcher checks the marker. A waiting
   marker stays in place. A ready marker gets removed after recovery starts.

Disabled errors do not create a marker. Invalid YAML also fails closed, so a
configuration mistake cannot start a retry loop.

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
- Same-session recovery needs the Claude Code session and process to stay open.
- Authentication, billing, invalid-request, model-not-found, and unknown errors
  stay out of the retry loop.
- Claude must follow the user-created recovery schedule for same-session
  recovery.
- The watcher needs `jq`, Node.js, and the `claude` command on `PATH`.

## Docs

- [Simple flow](https://github.com/softcane/cc-session-recover/blob/main/docs/simple-flow.md):
  notebook, schedule, and watcher.
- [FAQ](https://github.com/softcane/cc-session-recover/blob/main/docs/faq.md):
  hook approval and failure handling.
- [Full details](https://github.com/softcane/cc-session-recover/blob/main/docs/claude-code-auto-resume.md):
  watcher timing, reset-time cache, and operational limits.
