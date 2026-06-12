# cc-session-recover

Your long Claude Code task survives quota stops — and continues by itself after the reset, with no prompt from you.

When quota or a rate limit kills a session mid-task, Claude normally just stops until you come back and tell it to continue. This workflow removes that. Claude keeps a recovery note (`HANDOFF.md`) as it works, retries on a slow schedule while quota is blocked, and the first attempt after the reset picks the task up exactly where it stopped.

Every part of this has been verified against a genuine quota stop, end to end.

## Install

```sh
npx cc-session-recover init --enable-local-hook /path/to/project
```

(Or from a clone: `bash scripts/install-into-project.sh --enable-local-hook /path/to/project`.)

Approve the hooks once when Claude Code asks on the next start. That's the whole setup.

## Use

```sh
cd /path/to/project
claude
```

Give Claude your task, normally. Nothing extra to type — the injected standing instructions make Claude keep the recovery note and set its own retry schedule. Leave the terminal open and walk away.

If quota dies mid-task, work resumes automatically after the reset.

## Try It Without Using Real Quota

```sh
bash scripts/test-fake-quota-flow.sh
```

This proves the whole chain in a throwaway repo in under a minute: it fakes a quota stop, fakes the reset, and shows the recovery happen.

## Limits

- It does not bypass quota. It only waits for the reset.
- The basic flow needs the terminal to stay open. A closed-terminal recovery mode exists; see the docs.
- Worst case is never lost work: the recovery note is always on disk, and "Read HANDOFF.md and continue" restores any session by hand. A one-time reminder at the reset time is also supported; see the docs.

## Docs

- [Simple flow](docs/simple-flow.md) — how it works, told as a story (notebook, alarm, watchman).
- [FAQ](docs/faq.md) — reliability, hook approval, what still needs a human.
- [Full details](docs/claude-code-auto-resume.md) — closed-terminal watcher, precise reset-time resume, one-time reminders, all limits.
- [Worked example](docs/verified-quota-resume-example.md) — a concrete one-time reminder example.
