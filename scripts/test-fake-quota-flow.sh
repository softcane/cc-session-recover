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
[ ! -d "$DUMMY/scripts" ] || fail "install must not create a scripts folder in the target"
[ ! -d "$DUMMY/docs" ] || fail "install must not create a docs folder in the target"
jq -e '.hooks.SessionStart and .hooks.UserPromptSubmit and .hooks.StopFailure' "$DUMMY/.claude/settings.local.json" >/dev/null \
  || fail "installed local settings missing recovery hooks"
printf 'ok: installer activated recovery hooks in local settings\n'

step "Existing settings.local should keep settings and receive hooks"
MERGE_DUMMY="$WORK/merge-repo"
mkdir -p "$MERGE_DUMMY/.claude"
printf '{"permissions":{"allow":["Bash(npm test *)"]},"hooks":{"PostToolUse":[{"matcher":"Write","hooks":[{"type":"command","command":"true"}]}]}}\n' \
  > "$MERGE_DUMMY/.claude/settings.local.json"
bash "$TEMPLATE_ROOT/scripts/install-into-project.sh" "$MERGE_DUMMY" >/dev/null
jq -e '
  (.permissions.allow[0] == "Bash(npm test *)") and
  (.hooks.PostToolUse[0].matcher == "Write") and
  (.hooks.SessionStart | length > 0) and
  (.hooks.UserPromptSubmit | length > 0) and
  (.hooks.StopFailure | length > 0)
' "$MERGE_DUMMY/.claude/settings.local.json" >/dev/null || fail "bash installer did not merge hooks into existing settings"
bash "$TEMPLATE_ROOT/scripts/install-into-project.sh" "$MERGE_DUMMY" >/dev/null
DUPES=$(jq '[.hooks.SessionStart[], .hooks.UserPromptSubmit[], .hooks.StopFailure[]] | length' "$MERGE_DUMMY/.claude/settings.local.json")
[ "$DUPES" -eq 3 ] || fail "bash installer duplicated recovery hooks on rerun"
printf 'ok: bash installer preserved existing settings and merged hooks once\n'

step "Older shell-form recovery hooks should not be duplicated"
OLD_DUMMY="$WORK/old-hook-repo"
mkdir -p "$OLD_DUMMY/.claude"
jq -n '{
  hooks: {
    SessionStart: [
      {
        hooks: [
          {
            type: "command",
            command: "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/inject-standing-instructions.sh"
          }
        ]
      }
    ]
  }
}' > "$OLD_DUMMY/.claude/settings.local.json"
bash "$TEMPLATE_ROOT/scripts/install-into-project.sh" "$OLD_DUMMY" >/dev/null
SESSION_START_COUNT=$(jq '.hooks.SessionStart | length' "$OLD_DUMMY/.claude/settings.local.json")
[ "$SESSION_START_COUNT" -eq 1 ] || fail "installer duplicated old SessionStart recovery hook"
jq -e '(.hooks.UserPromptSubmit | length > 0) and (.hooks.StopFailure | length > 0)' \
  "$OLD_DUMMY/.claude/settings.local.json" >/dev/null || fail "installer failed to add missing hooks next to old hook"
printf 'ok: installer recognized old recovery hook commands and added only missing hooks\n'

step "Node installer should also merge existing settings.local"
NODE_DUMMY="$WORK/node-merge-repo"
mkdir -p "$NODE_DUMMY/.claude"
printf '{"permissions":{"allow":["Bash(npm test *)"]}}\n' > "$NODE_DUMMY/.claude/settings.local.json"
node "$TEMPLATE_ROOT/bin/cli.js" init "$NODE_DUMMY" >/dev/null
jq -e '
  (.permissions.allow[0] == "Bash(npm test *)") and
  (.hooks.SessionStart | length > 0) and
  (.hooks.UserPromptSubmit | length > 0) and
  (.hooks.StopFailure | length > 0)
' "$NODE_DUMMY/.claude/settings.local.json" >/dev/null || fail "node installer did not merge hooks into existing settings"
node "$TEMPLATE_ROOT/bin/cli.js" init "$NODE_DUMMY" >/dev/null
DUPES=$(jq '[.hooks.SessionStart[], .hooks.UserPromptSubmit[], .hooks.StopFailure[]] | length' "$NODE_DUMMY/.claude/settings.local.json")
[ "$DUPES" -eq 3 ] || fail "node installer duplicated recovery hooks on rerun"
printf 'ok: node installer preserved existing settings and merged hooks once\n'

step "Fake SessionStart: standing instructions should be injected"
INJECTED=$(printf '{"session_id":"fake-session-123","hook_event_name":"SessionStart","source":"startup"}' \
  | CLAUDE_PROJECT_DIR="$DUMMY" bash "$DUMMY/.claude/hooks/inject-standing-instructions.sh")
printf '%s\n' "$INJECTED" | grep -Fq "auto-continue.md" || fail "injection missing heartbeat instruction"
printf '%s\n' "$INJECTED" | grep -Fq "HANDOFF.md" || fail "injection missing handoff instruction"
printf 'ok: SessionStart hook printed the standing instructions\n'

# Real UserPromptSubmit JSON format captured from Claude Code 2.1.177:
# {"session_id":"...","transcript_path":"...","cwd":"...","permission_mode":"...","hook_event_name":"UserPromptSubmit","prompt":"..."}
REMIND_HOOK="$DUMMY/.claude/hooks/remind-on-prompt.sh"
REMIND_JSON='{"session_id":"remind-test-session","hook_event_name":"UserPromptSubmit","prompt":"do something","cwd":"/tmp","permission_mode":"default","transcript_path":"/tmp/t.jsonl"}'
remind() { printf '%s' "$REMIND_JSON" | CC_REMIND_MODE="${1:-}" bash "$REMIND_HOOK"; }
remind_sid() { printf '%s' "$2" | CC_REMIND_MODE="${1:-}" bash "$REMIND_HOOK"; }

step "remind-on-prompt: CC_REMIND_MODE=1 (default) injects once then stops"
rm -f "/tmp/cc-sr-count-remind-test-session"
OUT1=$(remind 1); OUT2=$(remind 1); OUT3=$(remind 1)
printf '%s' "$OUT1" | grep -Fq "Recovery check" || fail "CC_REMIND_MODE=1: prompt 1 should inject"
[ -z "$OUT2" ] || fail "CC_REMIND_MODE=1: prompt 2 should be silent, got: $OUT2"
[ -z "$OUT3" ] || fail "CC_REMIND_MODE=1: prompt 3 should be silent, got: $OUT3"
printf 'ok: CC_REMIND_MODE=1 injected once then stopped\n'

step "remind-on-prompt: CC_REMIND_MODE=3 injects first 3 prompts then stops"
rm -f "/tmp/cc-sr-count-remind-test-session"
OUT1=$(remind 3); OUT2=$(remind 3); OUT3=$(remind 3); OUT4=$(remind 3); OUT5=$(remind 3)
printf '%s' "$OUT1" | grep -Fq "Recovery check" || fail "CC_REMIND_MODE=3: prompt 1 should inject"
printf '%s' "$OUT2" | grep -Fq "Recovery check" || fail "CC_REMIND_MODE=3: prompt 2 should inject"
printf '%s' "$OUT3" | grep -Fq "Recovery check" || fail "CC_REMIND_MODE=3: prompt 3 should inject"
[ -z "$OUT4" ] || fail "CC_REMIND_MODE=3: prompt 4 should be silent, got: $OUT4"
[ -z "$OUT5" ] || fail "CC_REMIND_MODE=3: prompt 5 should be silent, got: $OUT5"
printf 'ok: CC_REMIND_MODE=3 injected exactly 3 times then stopped\n'

step "remind-on-prompt: CC_REMIND_MODE=0 never injects"
rm -f "/tmp/cc-sr-count-remind-test-session"
OUT1=$(remind 0); OUT2=$(remind 0)
[ -z "$OUT1" ] || fail "CC_REMIND_MODE=0: prompt 1 should be silent, got: $OUT1"
[ -z "$OUT2" ] || fail "CC_REMIND_MODE=0: prompt 2 should be silent, got: $OUT2"
printf 'ok: CC_REMIND_MODE=0 never injected\n'

step "remind-on-prompt: invalid CC_REMIND_MODE falls back to 1"
rm -f "/tmp/cc-sr-count-remind-test-session"
OUT1=$(remind -5); OUT2=$(remind -5)
printf '%s' "$OUT1" | grep -Fq "Recovery check" || fail "negative CC_REMIND_MODE: prompt 1 should inject"
[ -z "$OUT2" ] || fail "negative CC_REMIND_MODE: prompt 2 should be silent (fell back to 1), got: $OUT2"
rm -f "/tmp/cc-sr-count-remind-test-session"
OUT3=$(remind abc); OUT4=$(remind abc)
printf '%s' "$OUT3" | grep -Fq "Recovery check" || fail "non-numeric CC_REMIND_MODE: prompt 1 should inject"
[ -z "$OUT4" ] || fail "non-numeric CC_REMIND_MODE: prompt 2 should be silent (fell back to 1), got: $OUT4"
printf 'ok: invalid CC_REMIND_MODE values fell back to 1\n'

step "remind-on-prompt: missing session_id always injects (safe fallback)"
NO_SID_JSON='{"hook_event_name":"UserPromptSubmit","prompt":"test"}'
OUT1=$(remind_sid 1 "$NO_SID_JSON"); OUT2=$(remind_sid 1 "$NO_SID_JSON")
printf '%s' "$OUT1" | grep -Fq "Recovery check" || fail "no session_id: prompt 1 should inject"
printf '%s' "$OUT2" | grep -Fq "Recovery check" || fail "no session_id: prompt 2 should also inject (no counter available)"
printf 'ok: missing session_id falls through and always injects\n'

rm -f "/tmp/cc-sr-count-remind-test-session"

step "Fake status line input: reset time should be cached"
printf '{"workspace":{"project_dir":"%s"},"model":{"display_name":"Test"},"rate_limits":{"five_hour":{"used_percentage":97,"resets_at":%s}}}' \
  "$DUMMY" "$(( $(date +%s) + 4 ))" \
  | bash "$DUMMY/.claude/statusline-quota-cache.sh" >/dev/null
[ -f "$DUMMY/.claude/rate-limit-state.json" ] || fail "status line wrapper did not cache rate-limit state"
printf 'ok: status line wrapper cached the reset time\n'

step "Fake quota stop: StopFailure(rate_limit) should log and write the marker"
printf '{"session_id":"fake-session-123","hook_event_name":"StopFailure","error":"rate_limit","last_assistant_message":"API Error: Rate limit reached"}' \
  | CLAUDE_PROJECT_DIR="$DUMMY" bash "$DUMMY/.claude/hooks/log-stop-failure.sh"
[ -f "$DUMMY/.claude/stop-failure-events.jsonl" ] || fail "missing stop-failure log"
[ -f "$DUMMY/.claude/quota-blocked.json" ] || fail "missing quota-blocked marker"
grep -Fq "hit a rate limit" "$DUMMY/HANDOFF.md" || fail "missing handoff note"
SESSION=$(jq -r '.hook_input.session_id // empty' "$DUMMY/.claude/quota-blocked.json")
[ "$SESSION" = "fake-session-123" ] || fail "marker has wrong session_id: $SESSION"
ERROR=$(jq -r '.hook_input.error // empty' "$DUMMY/.claude/quota-blocked.json")
[ "$ERROR" = "rate_limit" ] || fail "marker has wrong error field: $ERROR"
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
  bash "$TEMPLATE_ROOT/scripts/quota-watcher.sh" "$DUMMY" >"$WORK/watcher.log" 2>&1 &
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
