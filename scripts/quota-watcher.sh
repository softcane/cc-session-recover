#!/usr/bin/env bash

# Optional unattended resume layer.
#
# When the StopFailure hook writes .claude/quota-blocked.json, this script
# retries a headless resume of that exact session until the transient failure
# clears.
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
#   QUOTA_WATCH_INTERVAL     seconds between fallback attempts (overrides YAML)
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
DEFAULT_INTERVAL=1200
INTERVAL_OVERRIDE=${QUOTA_WATCH_INTERVAL:-}
RESUME_BUFFER=${QUOTA_RESUME_BUFFER:-900}
RATE_STATE_MAX_AGE=21600
SNAPSHOT=''

cleanup() {
  if [ -n "$SNAPSHOT" ]; then rm -f "$SNAPSHOT"; fi
}

trap cleanup EXIT
trap 'exit 0' HUP INT TERM

# Epoch seconds -> local HH:MM for display only. macOS uses date -r, GNU uses date -d.
epoch_to_local() {
  date -r "$1" '+%H:%M %Z' 2>/dev/null || date -d "@$1" '+%H:%M %Z' 2>/dev/null || printf 'epoch %s' "$1"
}
CLAUDE_ARGS=${QUOTA_WATCH_CLAUDE_ARGS:---permission-mode acceptEdits}

case "$INTERVAL_OVERRIDE" in
  '') ;;
  *[!0-9]*)
    printf 'QUOTA_WATCH_INTERVAL must be a positive whole number of seconds.\n' >&2
    exit 1
    ;;
  *)
    if ! [ "$INTERVAL_OVERRIDE" -gt 0 ] 2>/dev/null; then
      printf 'QUOTA_WATCH_INTERVAL must be a positive whole number of seconds.\n' >&2
      exit 1
    fi
    ;;
esac

case "$RESUME_BUFFER" in
  *[!0-9]*)
    printf 'QUOTA_RESUME_BUFFER must be a non-negative whole number of seconds.\n' >&2
    exit 1
    ;;
esac

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

printf 'Watching %s for configured transient failures.\n' "$MARKER"

while :; do
  if [ -f "$MARKER" ]; then
    SNAPSHOT=$(mktemp "${TMPDIR:-/tmp}/cc-session-recover-marker.XXXXXX") || {
      printf 'Could not create a marker snapshot.\n' >&2
      exit 1
    }
    if ! cp "$MARKER" "$SNAPSHOT" 2>/dev/null; then
      rm -f "$SNAPSHOT"
      SNAPSHOT=''
      continue
    fi

    if ! jq -e '
      (type == "object") and
      ((.hook_input | type) == "object") and
      ((.hook_input.session_id | type) == "string") and
      ((.hook_input.session_id | length) > 0) and
      ((.hook_input.error | type) == "string") and
      (
        (.hook_input.error == "rate_limit") or
        (.hook_input.error == "overloaded") or
        (.hook_input.error == "server_error")
      ) and
      (
        (has("recovery") | not) or
        (
          ((.recovery | type) == "object") and
          (.recovery.error == .hook_input.error) and
          ((.recovery.retry_seconds | type) == "number") and
          ((.recovery.retry_seconds | floor) == .recovery.retry_seconds) and
          (.recovery.retry_seconds > 0) and
          (.recovery.retry_seconds <= 9007199254740991)
        )
      )
    ' "$SNAPSHOT" >/dev/null 2>&1; then
      printf 'Marker is invalid or non-retryable; removing it without invoking Claude.\n' >&2
      if cmp -s "$SNAPSHOT" "$MARKER" 2>/dev/null; then rm -f "$MARKER"; fi
      rm -f "$SNAPSHOT"
      SNAPSHOT=''
      sleep "${INTERVAL_OVERRIDE:-$DEFAULT_INTERVAL}"
      continue
    fi

    SESSION_ID=$(jq -r '.hook_input.session_id // empty' "$SNAPSHOT" 2>/dev/null)

    if [ -z "$SESSION_ID" ]; then
      printf 'Marker has no session_id; removing it without invoking Claude.\n' >&2
      if cmp -s "$SNAPSHOT" "$MARKER" 2>/dev/null; then rm -f "$MARKER"; fi
      rm -f "$SNAPSHOT"
      SNAPSHOT=''
    else
      ERROR_TYPE=$(jq -r '.hook_input.error // .recovery.error // empty' "$SNAPSHOT" 2>/dev/null)
      MARKER_INTERVAL=$(jq -r '.recovery.retry_seconds // empty' "$SNAPSHOT" 2>/dev/null)
      case "$MARKER_INTERVAL" in
        *[!0-9]*|0) MARKER_INTERVAL='' ;;
      esac
      INTERVAL=${INTERVAL_OVERRIDE:-${MARKER_INTERVAL:-$DEFAULT_INTERVAL}}

      NOW=$(date +%s)
      RESETS_AT=''
      if [ "$ERROR_TYPE" = "rate_limit" ]; then
        RESETS_AT=$(jq -r \
          --argjson now "$NOW" \
          --argjson max_age "$RATE_STATE_MAX_AGE" '
          (.rate_limit_state.five_hour_resets_at // null) as $reset |
          (.rate_limit_state.cached_at // null) as $cached |
          if
            (($reset | type) == "number") and
            (($cached | type) == "number") and
            (($reset | floor) == $reset) and
            (($cached | floor) == $cached) and
            ($reset > $now) and
            ($cached <= $now) and
            (($now - $cached) <= $max_age) and
            (($reset - $cached) > 0) and
            (($reset - $cached) <= $max_age)
          then $reset
          else empty
          end
        ' "$SNAPSHOT" 2>/dev/null)
      fi

      if [ -n "$RESETS_AT" ] &&
         [ "$RESETS_AT" -gt "$NOW" ] 2>/dev/null; then
        TARGET=$((RESETS_AT + RESUME_BUFFER))
        printf 'Quota resets at %s; sleeping until %s for one precise knock.\n' \
          "$(epoch_to_local "$RESETS_AT")" \
          "$(epoch_to_local "$TARGET")"
        sleep $((TARGET - NOW))
        if ! cmp -s "$SNAPSHOT" "$MARKER" 2>/dev/null; then
          printf 'Recovery marker changed while waiting; reloading current state.\n'
          rm -f "$SNAPSHOT"
          SNAPSHOT=''
          continue
        fi
      fi

      printf 'Trying headless resume of session %s after %s\n' "$SESSION_ID" "${ERROR_TYPE:-unknown failure}"
      PROMPT_CONTENT=$(cat "$PROMPT_FILE"; printf '.')
      PROMPT_CONTENT=${PROMPT_CONTENT%.}

      if (cd "$PROJECT_DIR" && claude -p --resume "$SESSION_ID" $CLAUDE_ARGS "$PROMPT_CONTENT"); then
        if cmp -s "$SNAPSHOT" "$MARKER" 2>/dev/null; then
          printf 'Resume succeeded; clearing active marker.\n'
          rm -f "$MARKER"
        else
          printf 'Resume succeeded, but the marker changed; preserving newer recovery state.\n'
        fi
      else
        printf 'Resume failed; preserving marker and retrying in %ss.\n' "$INTERVAL"
      fi
      rm -f "$SNAPSHOT"
      SNAPSHOT=''

      sleep "$INTERVAL"
      continue
    fi
  fi

  sleep "${INTERVAL_OVERRIDE:-$DEFAULT_INTERVAL}"
done
