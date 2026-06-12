#!/usr/bin/env bash

# SessionStart hook.
# Whatever this prints to stdout is added to Claude's context for the session,
# so the user does not have to paste the heartbeat instructions every time.

set -u

PROJECT_DIR=${CLAUDE_PROJECT_DIR:-$(pwd)}
INSTRUCTIONS="$PROJECT_DIR/.claude/standing-instructions.md"

[ -f "$INSTRUCTIONS" ] || exit 0

cat "$INSTRUCTIONS"

exit 0
