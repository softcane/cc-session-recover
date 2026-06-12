#!/usr/bin/env bash

# Optional unattended resume layer.
#
# When the StopFailure hook writes .claude/quota-blocked.json, this script
# retries a headless resume of that exact session until quota is back.
#
# Run it only when the interactive Claude Code session is closed.
# If the session is still open and idle, use the in-session heartbeat instead,
# or the two will work the same task in parallel.
#
# If the marker contains the cached rate-limit reset time (written by the
# status line wrapper), the watcher sleeps until that time plus a buffer and
# knocks once, instead of knocking blindly on an interval. The interval is
# only the fallback when no reset time is known or the precise knock fails.
#
# Environment:
#   QUOTA_WATCH_INTERVAL     seconds between fallback attempts (default 1200)
#   QUOTA_RESUME_BUFFER      seconds to wait past the known reset time (default 900)
#
# Timezone note: resets_at is Unix epoch seconds (UTC-based by definition),
# and so is `date +%s`, so the sleep arithmetic needs no timezone conversion.
# Local time only appears in the printed messages.
#   QUOTA_WATCH_CLAUDE_ARGS  extra claude args (default: --permission-mode acceptEdits)

set -u

usage() {
  printf 'Usage: %s /path/to/project\n' "$0" >&2
}

if [ "$#" -ne 1 ]; then
  usage
  exit 2
fi

PROJECT_DIR=$1
MARKER="$PROJECT_DIR/.claude/quota-blocked.json"
PROMPT_FILE="$PROJECT_DIR/.claude/auto-continue.md"
INTERVAL=${QUOTA_WATCH_INTERVAL:-1200}
RESUME_BUFFER=${QUOTA_RESUME_BUFFER:-900}

# Epoch seconds -> local HH:MM for display only. macOS uses date -r, GNU uses date -d.
epoch_to_local() {
  date -r "$1" '+%H:%M %Z' 2>/dev/null || date -d "@$1" '+%H:%M %Z' 2>/dev/null || printf 'epoch %s' "$1"
}
CLAUDE_ARGS=${QUOTA_WATCH_CLAUDE_ARGS:---permission-mode acceptEdits}

command -v jq >/dev/null 2>&1 || {
  printf 'quota-watcher needs jq.\n' >&2
  exit 1
}

command -v claude >/dev/null 2>&1 || {
  printf 'quota-watcher needs the claude CLI on PATH.\n' >&2
  exit 1
}

[ -f "$PROMPT_FILE" ] || {
  printf 'Missing %s\n' "$PROMPT_FILE" >&2
  exit 1
}

printf 'Watching %s every %ss\n' "$MARKER" "$INTERVAL"

while :; do
  if [ -f "$MARKER" ]; then
    SESSION_ID=$(jq -r '.hook_input.session_id // empty' "$MARKER" 2>/dev/null)

    if [ -z "$SESSION_ID" ]; then
      printf 'Marker has no session_id; removing it.\n' >&2
      rm -f "$MARKER"
    else
      RESETS_AT=$(jq -r '.rate_limit_state.five_hour_resets_at // empty' "$MARKER" 2>/dev/null)
      NOW=$(date +%s)

      if [ -n "$RESETS_AT" ] && [ "$RESETS_AT" -gt "$NOW" ] 2>/dev/null; then
        TARGET=$((RESETS_AT + RESUME_BUFFER))
        printf 'Quota resets at %s; sleeping until %s for one precise knock.\n' \
          "$(epoch_to_local "$RESETS_AT")" \
          "$(epoch_to_local "$TARGET")"
        sleep $((TARGET - NOW))
      fi

      printf 'Trying headless resume of session %s\n' "$SESSION_ID"

      if (cd "$PROJECT_DIR" && claude -p --resume "$SESSION_ID" $CLAUDE_ARGS "$(cat "$PROMPT_FILE")"); then
        printf 'Resume succeeded; clearing marker.\n'
        rm -f "$MARKER"
      else
        printf 'Resume failed (quota likely still blocked); retrying in %ss.\n' "$INTERVAL"
      fi
    fi
  fi

  sleep "$INTERVAL"
done
