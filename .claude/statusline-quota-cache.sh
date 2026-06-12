#!/usr/bin/env bash

# Status line wrapper that caches rate-limit state for the quota workflow.
#
# Claude Code feeds the status line JSON that includes
# rate_limits.five_hour.resets_at. This script saves those fields to
# .claude/rate-limit-state.json so the StopFailure hook can stamp the exact
# reset time into the quota marker when a quota stop happens.
#
# Display:
# - If CLAUDE_QUOTA_STATUSLINE_DELEGATE is set, the same JSON is passed to
#   that command and its output is shown, so an existing status line keeps
#   working unchanged.
# - Otherwise a minimal line with model and quota usage is printed.

set -u

INPUT=$(cat)

DIR=$(printf '%s' "$INPUT" | jq -r '.workspace.project_dir // .cwd // empty' 2>/dev/null)

if [ -n "$DIR" ] && [ -d "$DIR/.claude" ]; then
  STATE=$(printf '%s' "$INPUT" | jq -c '{
    five_hour_used: (.rate_limits.five_hour.used_percentage // null),
    five_hour_resets_at: (.rate_limits.five_hour.resets_at // null),
    seven_day_used: (.rate_limits.seven_day.used_percentage // null),
    seven_day_resets_at: (.rate_limits.seven_day.resets_at // null),
    cached_at: now | floor
  }' 2>/dev/null)

  if [ -n "$STATE" ] && [ "$(printf '%s' "$STATE" | jq -r '.five_hour_resets_at')" != "null" ]; then
    printf '%s\n' "$STATE" > "$DIR/.claude/rate-limit-state.json" 2>/dev/null || true
  fi
fi

if [ -n "${CLAUDE_QUOTA_STATUSLINE_DELEGATE:-}" ]; then
  printf '%s' "$INPUT" | "$CLAUDE_QUOTA_STATUSLINE_DELEGATE"
  exit 0
fi

MODEL=$(printf '%s' "$INPUT" | jq -r '.model.display_name // "Claude"' 2>/dev/null)
FIVE=$(printf '%s' "$INPUT" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
RESETS=$(printf '%s' "$INPUT" | jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null)

if [ -n "$FIVE" ] && [ -n "$RESETS" ]; then
  RESETS_LOCAL=$(date -r "$RESETS" '+%H:%M' 2>/dev/null || date -d "@$RESETS" '+%H:%M' 2>/dev/null || echo '?')
  printf '%s | 5h quota: %s%% (resets %s)' "$MODEL" "$FIVE" "$RESETS_LOCAL"
else
  printf '%s' "$MODEL"
fi
