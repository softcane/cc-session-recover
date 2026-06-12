# FAQ

Honest answers, including the parts that are not proven.

## Where does the 45-minute alarm live?

Inside the running Claude Code session, in memory.
It is not a system cron job, not a launchd job, and not a file on disk.
The standing-instructions hook asks Claude to create it at task start, and Claude creates it with Claude Code's built-in scheduler.
Because it lives in the process, closing the terminal kills it.

## Is this 100% reliable?

No. Three layers, three confidence levels:

- The scripts and the watchman: tested end to end with real sessions. Strong.
- The harness behavior (hooks firing, schedules firing): documented by Claude Code, and the injection and resume paths were verified live.
- Claude obeying the standing orders (keeping the notebook fresh, arming the alarm): this is a model following instructions. It is very reliable, not guaranteed. This is the weakest link.

The first genuine quota stop is the final exam: afterwards, check `.claude/stop-failure-events.jsonl` to confirm the hook fired for real.

## What still needs a human?

- Opening the session and giving the task.
- Keeping the terminal open for the alarm, or starting the watchman if it cannot stay open.
- Approving the hooks once per project, the first time Claude Code sees them.
- Judging the finished work. The workflow recovers progress; it does not review quality.

## What happens if the terminal closes?

The alarm dies with the session, but nothing is lost:

- The notebook (`HANDOFF.md`) is still on disk with the exact next step.
- If the watchman is running and a quota stop was recorded, it resumes the session headlessly on its own.
- Otherwise, reopen the project, run `claude`, and say: "Read HANDOFF.md and continue."

Worst case equals one typed line, never lost work.
