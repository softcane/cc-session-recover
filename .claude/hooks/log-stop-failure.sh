#!/usr/bin/env bash

set -u

PROJECT_DIR=${CLAUDE_PROJECT_DIR:-$(pwd)}
RUNTIME="$PROJECT_DIR/.claude/session-recover.js"

[ -f "$RUNTIME" ] || {
  printf 'Missing session recovery runtime: %s\n' "$RUNTIME" >&2
  exit 0
}

command -v node >/dev/null 2>&1 || {
  printf 'Session recovery hook needs Node.js on PATH.\n' >&2
  exit 0
}

exec node "$RUNTIME"
