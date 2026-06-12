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

mkdir -p "$TARGET/.claude/hooks" "$TARGET/docs" "$TARGET/scripts"

if [ ! -f "$TARGET/README.md" ]; then
  cp "$TEMPLATE_ROOT/README.md" "$TARGET/README.md"
fi
cp "$TEMPLATE_ROOT/.claude/loop.md" "$TARGET/.claude/loop.md"
cp "$TEMPLATE_ROOT/.claude/auto-continue.md" "$TARGET/.claude/auto-continue.md"
cp "$TEMPLATE_ROOT/.claude/standing-instructions.md" "$TARGET/.claude/standing-instructions.md"
cp "$TEMPLATE_ROOT/.claude/statusline-quota-cache.sh" "$TARGET/.claude/statusline-quota-cache.sh"
cp "$TEMPLATE_ROOT/.claude/hooks/inject-standing-instructions.sh" "$TARGET/.claude/hooks/inject-standing-instructions.sh"
cp "$TEMPLATE_ROOT/.claude/settings.example.json" "$TARGET/.claude/settings.example.json"
cp "$TEMPLATE_ROOT/.claude/hooks/log-stop-failure.sh" "$TARGET/.claude/hooks/log-stop-failure.sh"
cp "$TEMPLATE_ROOT/docs/claude-code-auto-resume.md" "$TARGET/docs/claude-code-auto-resume.md"
cp "$TEMPLATE_ROOT/docs/verified-quota-resume-example.md" "$TARGET/docs/verified-quota-resume-example.md"
cp "$TEMPLATE_ROOT/scripts/install-into-project.sh" "$TARGET/scripts/install-into-project.sh"
cp "$TEMPLATE_ROOT/scripts/verify-claude-loop-workflow.sh" "$TARGET/scripts/verify-claude-loop-workflow.sh"
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
chmod +x "$TARGET/scripts/verify-claude-loop-workflow.sh"
chmod +x "$TARGET/scripts/quota-watcher.sh"

if [ "$ENABLE_LOCAL_HOOK" -eq 1 ]; then
  if [ -f "$TARGET/.claude/settings.local.json" ]; then
    printf 'Skipped hook enablement because .claude/settings.local.json already exists.\n' >&2
    printf 'Merge .claude/settings.example.json into it manually if wanted.\n' >&2
  else
    cp "$TEMPLATE_ROOT/.claude/settings.example.json" "$TARGET/.claude/settings.local.json"
  fi
fi

printf 'Installed Claude Code workflow into %s\n' "$TARGET"
