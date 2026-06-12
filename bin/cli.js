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
  'docs/claude-code-auto-resume.md',
  'docs/verified-quota-resume-example.md',
  'docs/simple-flow.md',
  'docs/faq.md',
  'scripts/install-into-project.sh',
  'scripts/verify-claude-loop-workflow.sh',
  'scripts/quota-watcher.sh',
  'scripts/test-fake-quota-flow.sh',
];

const COPY_IF_MISSING = ['HANDOFF.md', 'README.md'];

function usage() {
  console.error('Usage: claude-quota-workflow init [--enable-local-hook] [target-dir]');
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

  if (enableHook) {
    const local = path.join(target, '.claude', 'settings.local.json');
    if (fs.existsSync(local)) {
      console.error('Skipped hook enablement: .claude/settings.local.json already exists.');
      console.error('Merge .claude/settings.example.json into it manually if wanted.');
    } else {
      fs.copyFileSync(path.join(TEMPLATE_ROOT, '.claude', 'settings.example.json'), local);
    }
  }

  console.log(`Installed Claude Code quota workflow into ${target}`);
  console.log('Next: start `claude` there and approve the hooks once when asked.');
}

main();
