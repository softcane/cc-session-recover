# cc-session-recover

Your long Claude Code task survives quota stops — and continues by itself after the reset, with no prompt from you.

When quota or a rate limit kills a session mid-task, Claude normally just stops until you come back and tell it to continue. This workflow removes that. Claude keeps a recovery note (`HANDOFF.md`) as it works, retries on a slow schedule while quota is blocked, and the first attempt after the reset picks the task up exactly where it stopped.

Every part of this has been verified against a genuine quota stop, end to end.

## Install

```sh
npx cc-session-recover init /path/to/project
```

(Or from a clone: `bash scripts/install-into-project.sh /path/to/project`. Pass `--no-hooks` with either to install the files without activating anything.)

Approve the hooks once when Claude Code asks on the next start. That's the whole setup.

## Use

```sh
cd /path/to/project
claude
```

Give Claude your task, normally. Nothing extra to type — the injected standing instructions make Claude keep the recovery note and set its own retry schedule. Leave the terminal open and walk away.

If quota dies mid-task, work resumes automatically after the reset.

## Why This Approach Is Stronger

- It avoids `tmux`, `screen`, and terminal-injection hacks. Headless `claude -p --resume` is used only by the optional closed-terminal watcher, targeting the exact recorded session.
- It gives you two recovery paths. With the terminal open, the heartbeat resumes inside the active Claude Code session. With the terminal closed, the watcher resumes the saved session id.
- `HANDOFF.md` keeps the next step in the repo, with project state, recent progress, and the exact next action.
- The heartbeat runs inside the active Claude Code session, so the original context stays alive while quota is blocked.

## Limits

- It does not bypass quota. It only waits for the reset.
- The basic flow needs the terminal to stay open. A closed-terminal recovery mode exists; see the docs.
- Worst case is never lost work: the recovery note is always on disk, and "Read HANDOFF.md and continue" restores any session by hand.
- Prompt injection frequency defaults to every prompt. Set `CC_REMIND_MODE=N` to limit to the first N prompts per session. See [Full details](docs/claude-code-auto-resume.md#tuning-prompt-injection-frequency).

## Docs

- [Simple flow](https://github.com/softcane/cc-session-recover/blob/main/docs/simple-flow.md) — how it works, told as a story (notebook, alarm, watchman).
- [FAQ](https://github.com/softcane/cc-session-recover/blob/main/docs/faq.md) — reliability, hook approval, what still needs a human.
- [Full details](https://github.com/softcane/cc-session-recover/blob/main/docs/claude-code-auto-resume.md) — closed-terminal watcher, precise reset-time resume, all limits.
