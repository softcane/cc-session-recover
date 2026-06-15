#!/usr/bin/env bash

# UserPromptSubmit hook.
# Injects a recovery order on the first N prompts of a session.
#
# Controlled by CC_REMIND_MODE (default: 1):
#
#   0          — never inject (opt-out entirely)
#   1          — inject on the first prompt only (default)
#   N (N > 1)  — inject on the first N prompts then stop; useful for long
#                sessions with auto-compact where Claude may lose the schedule
#                after a compaction — try CC_REMIND_MODE=10 or CC_REMIND_MODE=20
#
# Any negative or non-numeric value falls back to 1 silently.
#
# Per-session counting: session_id is read from the hook's stdin JSON and used
# as a key for a counter file in /tmp.  If session_id cannot be extracted (jq
# absent and grep fallback also fails), the hook falls through and injects
# unconditionally so setup is never silently skipped.

set -u

# Validate CC_REMIND_MODE: must be a non-negative integer; anything else → 1
_raw=${CC_REMIND_MODE:-1}
if printf '%s' "$_raw" | grep -qE '^[0-9]+$'; then
  CC_REMIND_MAX=$_raw
else
  CC_REMIND_MAX=1
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
