#!/usr/bin/env bash

# UserPromptSubmit hook.
# Injects an unconditional recovery order next to every prompt. Earlier
# softer wording ("if this is a multi-step task...") left the model
# discretion, and in long sessions it deferred forever. No judgment calls.
# Keep this output short: it is added to context on every single prompt.

set -u

printf 'Recovery check (do this before the request itself): if no recurring auto-continue schedule exists in this session, create one now — every 45 minutes, prompt: "Read .claude/auto-continue.md and follow it". Never create a duplicate. On multi-step tasks, update HANDOFF.md after each work step.\n'

exit 0
