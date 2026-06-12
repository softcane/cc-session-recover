#!/usr/bin/env bash

set -u

PROJECT_DIR=${CLAUDE_PROJECT_DIR:-$(pwd)}
CLAUDE_DIR="$PROJECT_DIR/.claude"
HANDOFF="$PROJECT_DIR/HANDOFF.md"
LOG="$CLAUDE_DIR/stop-failure-events.jsonl"
MARKER="$CLAUDE_DIR/quota-blocked.json"
STAMP=$(date '+%Y-%m-%d %H:%M:%S %Z')
INPUT=$(cat)

mkdir -p "$CLAUDE_DIR" || exit 0

printf '{"logged_at":"%s","hook_input":%s}\n' "$STAMP" "$INPUT" >> "$LOG" 2>/dev/null || true

# Marker for the optional unattended watcher. The watcher deletes it after a
# successful resume; a stale marker is harmless otherwise.
# If the status line cached the rate-limit reset time, stamp it in so the
# watcher can sleep until exactly then instead of knocking on an interval.
RATE_STATE='null'
if [ -f "$CLAUDE_DIR/rate-limit-state.json" ]; then
  RATE_STATE=$(cat "$CLAUDE_DIR/rate-limit-state.json" 2>/dev/null) || RATE_STATE='null'
fi

printf '{"logged_at":"%s","rate_limit_state":%s,"hook_input":%s}\n' "$STAMP" "${RATE_STATE:-null}" "$INPUT" > "$MARKER" 2>/dev/null || true

# Dedupe: during one outage every blocked retry fires this hook again, so
# only append a note when the handoff does not already end with one.
if [ -f "$HANDOFF" ] && ! tail -5 "$HANDOFF" | grep -Fq 'claude-code-stop-failure'; then
  {
    printf '\n<!-- claude-code-stop-failure: %s -->\n' "$STAMP"
    printf '\nAutomatic note: Claude Code hit a rate limit at %s.\n' "$STAMP"
    printf 'Raw hook input was saved to `.claude/stop-failure-events.jsonl`.\n'
    printf 'This hook cannot schedule a same-session resume by itself.\n'
  } >> "$HANDOFF" 2>/dev/null || true
fi

exit 0
