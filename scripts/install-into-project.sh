#!/usr/bin/env bash

set -eu

usage() {
  printf 'Usage: %s [--enable-local-hook] /path/to/project\n' "$0" >&2
}

ENABLE_LOCAL_HOOK=0

if [ "${1:-}" = "--enable-local-hook" ]; then
  ENABLE_LOCAL_HOOK=1
  shift
fi

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

mkdir -p "$TARGET/.claude/hooks" "$TARGET/scripts"

cp "$TEMPLATE_ROOT/.claude/loop.md" "$TARGET/.claude/loop.md"
cp "$TEMPLATE_ROOT/.claude/auto-continue.md" "$TARGET/.claude/auto-continue.md"
cp "$TEMPLATE_ROOT/.claude/standing-instructions.md" "$TARGET/.claude/standing-instructions.md"
cp "$TEMPLATE_ROOT/.claude/statusline-quota-cache.sh" "$TARGET/.claude/statusline-quota-cache.sh"
cp "$TEMPLATE_ROOT/.claude/hooks/inject-standing-instructions.sh" "$TARGET/.claude/hooks/inject-standing-instructions.sh"
cp "$TEMPLATE_ROOT/.claude/settings.example.json" "$TARGET/.claude/settings.example.json"
cp "$TEMPLATE_ROOT/.claude/hooks/log-stop-failure.sh" "$TARGET/.claude/hooks/log-stop-failure.sh"
cp "$TEMPLATE_ROOT/scripts/install-into-project.sh" "$TARGET/scripts/install-into-project.sh"
cp "$TEMPLATE_ROOT/scripts/quota-watcher.sh" "$TARGET/scripts/quota-watcher.sh"
cp "$TEMPLATE_ROOT/scripts/test-fake-quota-flow.sh" "$TARGET/scripts/test-fake-quota-flow.sh"

if [ ! -f "$TARGET/HANDOFF.md" ]; then
  cp "$TEMPLATE_ROOT/HANDOFF.md" "$TARGET/HANDOFF.md"
fi

chmod +x "$TARGET/.claude/hooks/log-stop-failure.sh"
chmod +x "$TARGET/.claude/hooks/inject-standing-instructions.sh"
chmod +x "$TARGET/.claude/statusline-quota-cache.sh"
chmod +x "$TARGET/scripts/test-fake-quota-flow.sh"
chmod +x "$TARGET/scripts/install-into-project.sh"
chmod +x "$TARGET/scripts/quota-watcher.sh"

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
