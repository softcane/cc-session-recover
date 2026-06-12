#!/usr/bin/env bash

# End-to-end test of the quota-recovery flow in a throwaway dummy repo.
#
# No real quota is touched. It fakes:
#   - a SessionStart event, to prove the standing instructions get injected
#   - a rate_limit StopFailure event, to prove the hook logs and writes the marker
#   - the claude CLI itself, failing twice (quota blocked) then succeeding
#     (quota reset), to prove the watcher retries and resumes the right session

set -eu

TEMPLATE_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d)
DUMMY="$WORK/dummy-repo"
BIN="$WORK/bin"
PASS=0

cleanup() {
  [ -n "${WATCHER_PID:-}" ] && kill "$WATCHER_PID" 2>/dev/null
  rm -rf "$WORK"

  if [ "$PASS" -eq 1 ]; then
    printf '\nAll fake-quota flow tests passed.\n'
  else
    printf '\nFAKE-QUOTA FLOW TEST FAILED.\n' >&2
  fi
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

step() {
  printf '\n== %s\n' "$1"
}

step "Create dummy repo and install template"
mkdir -p "$DUMMY"
git -C "$DUMMY" init -q
bash "$TEMPLATE_ROOT/scripts/install-into-project.sh" --enable-local-hook "$DUMMY" >/dev/null
[ -f "$DUMMY/.claude/settings.local.json" ] || fail "hook settings not installed"

step "Fake SessionStart: standing instructions should be injected"
INJECTED=$(printf '{"session_id":"fake-session-123","hook_event_name":"SessionStart","source":"startup"}' \
  | CLAUDE_PROJECT_DIR="$DUMMY" bash "$DUMMY/.claude/hooks/inject-standing-instructions.sh")
printf '%s\n' "$INJECTED" | grep -Fq "auto-continue.md" || fail "injection missing heartbeat instruction"
printf '%s\n' "$INJECTED" | grep -Fq "HANDOFF.md" || fail "injection missing handoff instruction"
printf 'ok: SessionStart hook printed the standing instructions\n'

step "Fake status line input: reset time should be cached"
printf '{"workspace":{"project_dir":"%s"},"model":{"display_name":"Test"},"rate_limits":{"five_hour":{"used_percentage":97,"resets_at":%s}}}' \
  "$DUMMY" "$(( $(date +%s) + 4 ))" \
  | bash "$DUMMY/.claude/statusline-quota-cache.sh" >/dev/null
[ -f "$DUMMY/.claude/rate-limit-state.json" ] || fail "status line wrapper did not cache rate-limit state"
printf 'ok: status line wrapper cached the reset time\n'

step "Fake quota stop: StopFailure(rate_limit) should log and write the marker"
printf '{"session_id":"fake-session-123","hook_event_name":"StopFailure","error_type":"rate_limit"}' \
  | CLAUDE_PROJECT_DIR="$DUMMY" bash "$DUMMY/.claude/hooks/log-stop-failure.sh"
[ -f "$DUMMY/.claude/stop-failure-events.jsonl" ] || fail "missing stop-failure log"
[ -f "$DUMMY/.claude/quota-blocked.json" ] || fail "missing quota-blocked marker"
grep -Fq "hit a rate limit" "$DUMMY/HANDOFF.md" || fail "missing handoff note"
SESSION=$(jq -r '.hook_input.session_id // empty' "$DUMMY/.claude/quota-blocked.json")
[ "$SESSION" = "fake-session-123" ] || fail "marker has wrong session_id: $SESSION"
RESETS=$(jq -r '.rate_limit_state.five_hour_resets_at // empty' "$DUMMY/.claude/quota-blocked.json")
[ -n "$RESETS" ] || fail "marker missing cached reset time"
printf 'ok: hook wrote log, handoff note, and marker with session_id and reset time\n'

step "Fake claude CLI: fails twice (blocked), succeeds on third try (reset)"
mkdir -p "$BIN"
cat > "$BIN/claude" <<EOF
#!/usr/bin/env bash
COUNT_FILE="$WORK/claude-call-count"
CALLS=\$(cat "\$COUNT_FILE" 2>/dev/null || echo 0)
CALLS=\$((CALLS + 1))
echo "\$CALLS" > "\$COUNT_FILE"
printf '%s\n' "\$*" >> "$WORK/claude-calls.log"
if [ "\$CALLS" -lt 3 ]; then
  echo "Limit reached. Resets later." >&2
  exit 1
fi
echo "Resumed and continued the task."
exit 0
EOF
chmod +x "$BIN/claude"

step "Run the watcher against the fake CLI"
QUOTA_WATCH_INTERVAL=1 QUOTA_RESUME_BUFFER=1 PATH="$BIN:$PATH" \
  bash "$DUMMY/scripts/quota-watcher.sh" "$DUMMY" >"$WORK/watcher.log" 2>&1 &
WATCHER_PID=$!
disown "$WATCHER_PID" 2>/dev/null || true

for _ in $(seq 1 30); do
  [ ! -f "$DUMMY/.claude/quota-blocked.json" ] && break
  sleep 1
done

[ ! -f "$DUMMY/.claude/quota-blocked.json" ] || fail "watcher never cleared the marker"
CALLS=$(cat "$WORK/claude-call-count")
[ "$CALLS" -eq 3 ] || fail "expected 3 claude calls (2 blocked + 1 success), got $CALLS"
grep -Fq -- "-p --resume fake-session-123" "$WORK/claude-calls.log" || fail "watcher did not resume the recorded session"
grep -Fq "HANDOFF.md" "$WORK/claude-calls.log" || fail "watcher did not pass the auto-continue prompt"
grep -Fq "sleeping until" "$WORK/watcher.log" || fail "watcher did not use the cached reset time for a precise knock"
printf 'ok: watcher slept to the known reset time, retried while blocked, resumed the exact session, cleared the marker\n'

PASS=1
