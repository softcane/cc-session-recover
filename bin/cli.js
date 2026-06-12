#!/usr/bin/env node
'use strict';

// npx installer for the Claude Code quota-resume workflow.
// Pure Node so it also works where bash is absent; the installed runtime
// scripts themselves are bash and need a POSIX shell (macOS, Linux, WSL,
// Git Bash).

const fs = require('fs');
const path = require('path');

const TEMPLATE_ROOT = path.join(__dirname, '..');

const FILES = [
  '.claude/loop.md',
  '.claude/auto-continue.md',
  '.claude/standing-instructions.md',
  '.claude/settings.example.json',
  '.claude/statusline-quota-cache.sh',
  '.claude/hooks/log-stop-failure.sh',
  '.claude/hooks/inject-standing-instructions.sh',
  'scripts/install-into-project.sh',
  'scripts/quota-watcher.sh',
  'scripts/test-fake-quota-flow.sh',
];

const COPY_IF_MISSING = ['HANDOFF.md'];

// HANDOFF.md must stay editable by unattended Claude runs, so it cannot live
// in .claude/ (Claude Code blocks edits there). Ignoring it in git gives the
// same "never committed" result without breaking recovery.
const IGNORE_ENTRIES = [
  'HANDOFF.md',
  '.claude/settings.local.json',
  '.claude/rate-limit-state.json',
  '.claude/stop-failure-events.jsonl',
  '.claude/quota-blocked.json',
];
const IGNORE_HEADER = '# Claude Code session-recovery runtime state';

function usage() {
  console.error('Usage: cc-session-recover init [--enable-local-hook] [target-dir]');
  process.exit(2);
}

function main() {
  const args = process.argv.slice(2);
  if (args[0] !== 'init') usage();

  let enableHook = false;
  let target = '.';
  for (const arg of args.slice(1)) {
    if (arg === '--enable-local-hook') enableHook = true;
    else if (arg.startsWith('-')) usage();
    else target = arg;
  }

  target = path.resolve(target);
  if (!fs.existsSync(target) || !fs.statSync(target).isDirectory()) {
    console.error(`Target directory does not exist: ${target}`);
    process.exit(1);
  }

  for (const rel of FILES) {
    const src = path.join(TEMPLATE_ROOT, rel);
    const dest = path.join(target, rel);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.copyFileSync(src, dest);
    if (rel.endsWith('.sh')) {
      try { fs.chmodSync(dest, 0o755); } catch (_) { /* no-op on Windows */ }
    }
  }

  for (const rel of COPY_IF_MISSING) {
    const dest = path.join(target, rel);
    if (!fs.existsSync(dest)) {
      fs.copyFileSync(path.join(TEMPLATE_ROOT, rel), dest);
    }
  }

  const giPath = path.join(target, '.gitignore');
  const existing = fs.existsSync(giPath) ? fs.readFileSync(giPath, 'utf8') : '';
  const lines = existing.split(/\r?\n/);
  const missing = IGNORE_ENTRIES.filter((e) => !lines.includes(e));
  if (missing.length) {
    const lead = existing && !existing.endsWith('\n') ? '\n' : '';
    const header = lines.includes(IGNORE_HEADER) ? '' : `${IGNORE_HEADER}\n`;
    fs.appendFileSync(giPath, `${lead}${header}${missing.join('\n')}\n`);
  }

  if (enableHook) {
    const local = path.join(target, '.claude', 'settings.local.json');
    if (fs.existsSync(local)) {
      console.error('Skipped hook enablement: .claude/settings.local.json already exists.');
      console.error('Merge .claude/settings.example.json into it manually if wanted.');
    } else {
      fs.copyFileSync(path.join(TEMPLATE_ROOT, '.claude', 'settings.example.json'), local);
    }
  }

  console.log(`Installed Claude Code session recovery workflow into ${target}`);
  console.log('Next: start `claude` there and approve the hooks once when asked.');
}

main();
