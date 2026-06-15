#!/usr/bin/env bash

# UserPromptSubmit hook.
# Injects a recovery order alongside each user prompt.
#
# Default behaviour (CC_REMIND_MODE unset): inject on every prompt.
# This preserves the original design — repeated injection ensures Claude sets
# up the heartbeat schedule even after context rolls over in long sessions or
# after an auto-compact, which can keep a session running indefinitely.
#
# Set CC_REMIND_MODE to opt into a quieter mode:
#
#   0          — never inject (opt-out entirely)
#   1          — first prompt of the session only
#   N (N > 1)  — first N prompts then stop; a middle ground for auto-compact
#                sessions where occasional reminders help without full verbosity
#
# Negative or non-numeric values fall back to always-inject (original behaviour).
#
# Per-session counting (when CC_REMIND_MODE is set): session_id is read from
# the hook's stdin JSON (format confirmed against Claude Code 2.1.177) and used
# as a key for a counter file in /tmp.  If session_id cannot be extracted the
# hook injects unconditionally so setup is never silently skipped.

set -u

# Unset or empty → always inject (original behaviour)
if [ -z "${CC_REMIND_MODE:-}" ]; then
  cat > /dev/null
  printf 'Recovery check (do this before the request itself): if no recurring auto-continue schedule exists in this session, create one now — every 45 minutes, prompt: "Read .claude/auto-continue.md and follow it". Never create a duplicate. On multi-step tasks, update HANDOFF.md after each work step.\n'
  exit 0
fi

# Validate: must be a non-negative integer; anything else → always inject
if printf '%s' "$CC_REMIND_MODE" | grep -qE '^[0-9]+$'; then
  CC_REMIND_MAX=$CC_REMIND_MODE
else
  cat > /dev/null
  printf 'Recovery check (do this before the request itself): if no recurring auto-continue schedule exists in this session, create one now — every 45 minutes, prompt: "Read .claude/auto-continue.md and follow it". Never create a duplicate. On multi-step tasks, update HANDOFF.md after each work step.\n'
  exit 0
fi

# 0 = opt-out: consume stdin and exit silently
if [ "$CC_REMIND_MAX" -eq 0 ]; then
  cat > /dev/null
  exit 0
fi

INPUT=$(cat)

SESSION_ID=''
if command -v jq >/dev/null 2>&1; then
  SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
else
  # Grep fallback for environments without jq
  SESSION_ID=$(printf '%s' "$INPUT" | grep -o '"session_id":"[^"]*"' | cut -d'"' -f4 | head -1)
fi

if [ -n "$SESSION_ID" ]; then
  COUNTER="${TMPDIR:-/tmp}/cc-sr-count-${SESSION_ID}"
  COUNT=$(cat "$COUNTER" 2>/dev/null || echo 0)
  if [ "$COUNT" -ge "$CC_REMIND_MAX" ]; then
    exit 0
  fi
  printf '%s\n' $((COUNT + 1)) > "$COUNTER"
fi

printf 'Recovery check (do this before the request itself): if no recurring auto-continue schedule exists in this session, create one now — every 45 minutes, prompt: "Read .claude/auto-continue.md and follow it". Never create a duplicate. On multi-step tasks, update HANDOFF.md after each work step.\n'

exit 0
