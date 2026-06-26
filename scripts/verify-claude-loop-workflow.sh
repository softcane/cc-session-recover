#!/usr/bin/env bash

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

require_file() {
  [ -f "$ROOT/$1" ] || fail "missing $1"
}

require_text() {
  file=$1
  text=$2

  grep -Fqi -- "$text" "$ROOT/$file" || fail "$file must mention: $text"
}

require_file ".claude/auto-continue.md"
require_file "HANDOFF.md"
require_file "templates/HANDOFF.md"
require_file ".claude/settings.example.json"
require_file ".claude/hooks/log-stop-failure.sh"
require_file ".claude/hooks/inject-standing-instructions.sh"
require_file ".claude/hooks/remind-on-prompt.sh"
require_file ".claude/standing-instructions.md"
require_file "lib/recovery.js"
require_file "session-recover.yaml"
require_file "scripts/test-fake-quota-flow.sh"
require_file "README.md"
require_file "docs/claude-code-auto-resume.md"
require_file "docs/simple-flow.md"
require_file "docs/faq.md"
require_file "scripts/install-into-project.sh"
require_file "scripts/quota-watcher.sh"
require_file "package.json"
require_file "bin/cli.js"
require_file "LICENSE"

require_text ".claude/auto-continue.md" "HANDOFF.md"
require_text "templates/HANDOFF.md" "Not set yet"
require_text ".claude/auto-continue.md" "git status --short"
require_text ".claude/auto-continue.md" "remaining checklist"
require_text ".claude/auto-continue.md" "safe to fire at any time"
require_text ".claude/auto-continue.md" "Cancel this recurring schedule"

require_text "docs/claude-code-auto-resume.md" "auto-continue.md"
require_text "docs/claude-code-auto-resume.md" "heartbeat"
require_text "docs/claude-code-auto-resume.md" "claude"
require_text "docs/claude-code-auto-resume.md" "quota or rate limit"
require_text "docs/claude-code-auto-resume.md" "does not bypass quota"
require_text "docs/claude-code-auto-resume.md" "terminal must stay open"
require_text "docs/claude-code-auto-resume.md" "rate_limits.five_hour.resets_at"
require_text "docs/claude-code-auto-resume.md" "StopFailure"
require_text "docs/claude-code-auto-resume.md" "Do not use"
require_text "docs/claude-code-auto-resume.md" "/loop 1m"

require_text "README.md" "install-into-project.sh"
require_text "README.md" "npx cc-session-recover init"
require_text "README.md" "not bypass quota"

require_text ".claude/settings.example.json" "SessionStart"
require_text ".claude/settings.example.json" "inject-standing-instructions.sh"
require_text ".claude/standing-instructions.md" "auto-continue.md"
require_text ".claude/standing-instructions.md" "HANDOFF.md"
require_text ".claude/settings.example.json" "UserPromptSubmit"
require_text ".claude/settings.example.json" "remind-on-prompt.sh"
require_text ".claude/hooks/remind-on-prompt.sh" "HANDOFF.md"
require_text ".claude/hooks/remind-on-prompt.sh" "auto-continue.md"
require_text ".claude/settings.example.json" "StopFailure"
require_text ".claude/settings.example.json" "log-stop-failure.sh"

if jq -e '.hooks.StopFailure[] | has("matcher")' "$ROOT/.claude/settings.example.json" >/dev/null; then
  fail ".claude/settings.example.json StopFailure hook must receive every API failure"
fi

require_text ".claude/hooks/log-stop-failure.sh" "session-recover.js"
require_text "lib/recovery.js" "stop-failure-events.jsonl"
require_text "lib/recovery.js" "cannot schedule"
require_text "lib/recovery.js" "quota-blocked.json"
require_text "lib/recovery.js" "rate_limit"
require_text "lib/recovery.js" "overloaded"
require_text "lib/recovery.js" "server_error"
require_text "session-recover.yaml" "errors"
require_text "session-recover.yaml" "overloaded"
require_text "session-recover.yaml" "retry_minutes"

require_text "scripts/quota-watcher.sh" "quota-blocked.json"
require_text "scripts/quota-watcher.sh" "auto-continue.md"
require_text "scripts/quota-watcher.sh" "session_id"

[ -x "$ROOT/.claude/hooks/log-stop-failure.sh" ] || fail ".claude/hooks/log-stop-failure.sh must be executable"
[ -x "$ROOT/scripts/install-into-project.sh" ] || fail "scripts/install-into-project.sh must be executable"
[ -x "$ROOT/scripts/quota-watcher.sh" ] || fail "scripts/quota-watcher.sh must be executable"
[ -x "$ROOT/.claude/hooks/inject-standing-instructions.sh" ] || fail ".claude/hooks/inject-standing-instructions.sh must be executable"
[ -x "$ROOT/.claude/hooks/remind-on-prompt.sh" ] || fail ".claude/hooks/remind-on-prompt.sh must be executable"
[ -x "$ROOT/scripts/test-fake-quota-flow.sh" ] || fail "scripts/test-fake-quota-flow.sh must be executable"

if grep -Fqi -- "claude -p" "$ROOT/.claude/auto-continue.md" "$ROOT/HANDOFF.md"; then
  fail "runtime workflow must not require claude -p"
fi

for forbidden in "tmux" "screen" "expect" "TIOCSTI"; do
  if grep -Eqi -- "(^|[^[:alnum:]_])${forbidden}([^[:alnum:]_]|$)" \
    "$ROOT/.claude/auto-continue.md" "$ROOT/HANDOFF.md"; then
    fail "runtime workflow must not require $forbidden"
  fi
done

printf 'All Claude Code loop workflow checks passed.\n'
