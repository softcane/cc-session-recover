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

merge_hook_settings() {
  local local_settings=$1
  local template_settings=$2
  local tmp

  if [ ! -f "$local_settings" ]; then
    cp "$template_settings" "$local_settings"
    return
  fi

  if ! command -v jq >/dev/null 2>&1; then
    printf 'Cannot merge hooks into existing .claude/settings.local.json because jq is not on PATH.\n' >&2
    printf 'Install jq, then rerun this installer.\n' >&2
    exit 1
  fi

  tmp=$(mktemp "${local_settings}.tmp.XXXXXX")
  if jq -s '
    def recovery_scripts: [
      "log-stop-failure.sh"
    ];
    def as_array: if type == "array" then . else [] end;
    def as_object: if type == "object" then . else {} end;
    def recovery_hook_scripts:
      [(.hooks // [])[]? |
        select(.type == "command" and (.command | type == "string")) |
        .command as $command |
        recovery_scripts[] |
        select($command | contains(.))
      ];
    def same_recovery_hook($existing; $incoming):
      (($existing | recovery_hook_scripts) as $existing_scripts |
        ($incoming | recovery_hook_scripts) as $incoming_scripts |
        (($incoming_scripts | length) > 0) and
        any($incoming_scripts[]; . as $script | any($existing_scripts[]; . == $script))
      );
    def handler_uses_any($scripts):
      (.type == "command") and
      (.command | type == "string") and
      (.command as $command |
        any($scripts[]; . as $script | $command | contains($script))
      );
    def merge_one($incoming):
      ($incoming | recovery_hook_scripts) as $incoming_scripts |
      if ($incoming_scripts | length) == 0 then
        if any(.[]; . == $incoming) then . else . + [$incoming] end
      else
        reduce .[] as $group ({groups: [], exact: false};
          if $group == $incoming then
            if .exact then . else .groups += [$group] | .exact = true end
          elif same_recovery_hook($group; $incoming) then
            ($group | .hooks = [
              (.hooks // [])[] |
              select((handler_uses_any($incoming_scripts)) | not)
            ]) as $remaining |
            if (($remaining.hooks // []) | length) > 0
            then .groups += [$remaining]
            else .
            end
          else
            .groups += [$group]
          end
        ) |
        if .exact then .groups else .groups + [$incoming] end
      end;
    def add_missing($incoming):
      as_array |
      reduce (($incoming // []) | as_array)[] as $item (.;
        merge_one($item)
      );
    def merge_hooks($incoming):
      as_object as $base |
      reduce (($incoming // {}) | as_object | keys_unsorted[]) as $event ($base;
        .[$event] = (.[$event] | add_missing($incoming[$event]))
      );

    .[0] as $local |
    .[1] as $template |
    $local + {hooks: (($local.hooks // {}) | merge_hooks($template.hooks // {}))}
  ' "$local_settings" "$template_settings" > "$tmp"; then
    mv "$tmp" "$local_settings"
    printf 'Merged hook settings into existing .claude/settings.local.json.\n' >&2
  else
    rm -f "$tmp"
    printf 'Could not merge hooks into .claude/settings.local.json.\n' >&2
    exit 1
  fi
}

mkdir -p "$TARGET/.claude/hooks" "$TARGET/.claude/commands"

cp "$TEMPLATE_ROOT/.claude/auto-continue.md" "$TARGET/.claude/auto-continue.md"
cp "$TEMPLATE_ROOT/.claude/statusline-quota-cache.sh" "$TARGET/.claude/statusline-quota-cache.sh"
cp "$TEMPLATE_ROOT/.claude/settings.example.json" "$TARGET/.claude/settings.example.json"
cp "$TEMPLATE_ROOT/.claude/hooks/log-stop-failure.sh" "$TARGET/.claude/hooks/log-stop-failure.sh"
cp "$TEMPLATE_ROOT/.claude/commands/session-recover.md" "$TARGET/.claude/commands/session-recover.md"
cp "$TEMPLATE_ROOT/lib/recovery.js" "$TARGET/.claude/session-recover.js"
if [ ! -f "$TARGET/HANDOFF.md" ]; then
  cp "$TEMPLATE_ROOT/templates/HANDOFF.md" "$TARGET/HANDOFF.md"
fi
if [ ! -f "$TARGET/session-recover.yaml" ]; then
  cp "$TEMPLATE_ROOT/session-recover.yaml" "$TARGET/session-recover.yaml"
fi

chmod +x "$TARGET/.claude/hooks/log-stop-failure.sh"
chmod +x "$TARGET/.claude/statusline-quota-cache.sh"
chmod +x "$TARGET/.claude/session-recover.js"

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
  merge_hook_settings "$TARGET/.claude/settings.local.json" "$TEMPLATE_ROOT/.claude/settings.example.json"
fi

printf 'Installed Claude Code workflow into %s\n' "$TARGET"
