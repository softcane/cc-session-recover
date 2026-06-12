#!/usr/bin/env bash

set -eu

usage() {
  printf 'Usage: %s [--no-hooks] /path/to/project\n' "$0" >&2
  printf 'Hooks are enabled by default; Claude Code still asks you to approve them once.\n' >&2
}

ENABLE_LOCAL_HOOK=1

case "${1:-}" in
  --no-hooks) ENABLE_LOCAL_HOOK=0; shift ;;
  --enable-local-hook) shift ;; # legacy no-op, was the old default-off flag
esac

if [ "$#" -ne 1 ]; then
  usage
  exit 2
fi

TARGET=$1
TEMPLATE_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

[ -d "$TARGET" ] || {
  printf 'Target directory does not exist: %s\n' "$TARGET" >&2
  exit 1
}

mkdir -p "$TARGET/.claude/hooks"

cp "$TEMPLATE_ROOT/.claude/auto-continue.md" "$TARGET/.claude/auto-continue.md"
cp "$TEMPLATE_ROOT/.claude/standing-instructions.md" "$TARGET/.claude/standing-instructions.md"
cp "$TEMPLATE_ROOT/.claude/statusline-quota-cache.sh" "$TARGET/.claude/statusline-quota-cache.sh"
cp "$TEMPLATE_ROOT/.claude/hooks/inject-standing-instructions.sh" "$TARGET/.claude/hooks/inject-standing-instructions.sh"
cp "$TEMPLATE_ROOT/.claude/settings.example.json" "$TARGET/.claude/settings.example.json"
cp "$TEMPLATE_ROOT/.claude/hooks/log-stop-failure.sh" "$TARGET/.claude/hooks/log-stop-failure.sh"
if [ ! -f "$TARGET/HANDOFF.md" ]; then
  cp "$TEMPLATE_ROOT/HANDOFF.md" "$TARGET/HANDOFF.md"
fi

chmod +x "$TARGET/.claude/hooks/log-stop-failure.sh"
chmod +x "$TARGET/.claude/hooks/inject-standing-instructions.sh"
chmod +x "$TARGET/.claude/statusline-quota-cache.sh"

# Keep runtime state out of the target's git history. HANDOFF.md must stay in
# the project root (Claude Code blocks unattended edits inside .claude/), so
# ignoring it is how it stays uncommitted.
GITIGNORE="$TARGET/.gitignore"
GITIGNORE_HEADER='# Claude Code session-recovery runtime state'
NEEDS_HEADER=1
APPENDED_GITIGNORE=0
touch "$GITIGNORE"
if grep -qxF "$GITIGNORE_HEADER" "$GITIGNORE"; then
  NEEDS_HEADER=0
fi
append_gitignore_line() {
  if [ "$APPENDED_GITIGNORE" -eq 0 ] && [ -s "$GITIGNORE" ] && [ "$(tail -c 1 "$GITIGNORE")" != "" ]; then
    printf '\n' >> "$GITIGNORE"
  fi
  APPENDED_GITIGNORE=1
  printf '%s\n' "$1" >> "$GITIGNORE"
}
for entry in HANDOFF.md .claude/settings.local.json .claude/rate-limit-state.json .claude/stop-failure-events.jsonl .claude/quota-blocked.json; do
  if ! grep -qxF "$entry" "$GITIGNORE"; then
    if [ "$NEEDS_HEADER" -eq 1 ]; then
      append_gitignore_line "$GITIGNORE_HEADER"
      NEEDS_HEADER=0
    fi
    append_gitignore_line "$entry"
  fi
done

if [ "$ENABLE_LOCAL_HOOK" -eq 1 ]; then
  if [ -f "$TARGET/.claude/settings.local.json" ]; then
    printf 'Skipped hook enablement because .claude/settings.local.json already exists.\n' >&2
    printf 'Merge .claude/settings.example.json into it manually if wanted.\n' >&2
  else
    cp "$TEMPLATE_ROOT/.claude/settings.example.json" "$TARGET/.claude/settings.local.json"
  fi
fi

printf 'Installed Claude Code workflow into %s\n' "$TARGET"
