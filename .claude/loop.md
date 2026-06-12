# Claude Code Resume Prompt

Use this prompt for a one-time scheduled resume or for a slow `/loop`.

Resume only if the task is incomplete.

First read `HANDOFF.md`.

Then:

1. Run `git status --short`.
2. Inspect the current diff only enough to understand the working tree.
3. Continue exactly one small safe step from `Next Exact Action`.
4. Run the narrowest relevant check for that step.
5. Update HANDOFF.md with the new state.
6. Stop after that small step.

Rules:

- Do not repeat completed work.
- Do not start unrelated work.
- Do not do broad refactors.
- Do not run destructive commands.
- Do not run expensive full test suites unless `HANDOFF.md` says they are needed.
- If the handoff is missing or unclear, update it with what you know and stop.
