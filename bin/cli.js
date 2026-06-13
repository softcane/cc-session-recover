#!/usr/bin/env node
'use strict';

// npx installer for the Claude Code quota-resume workflow.
// Pure Node so it also works where bash is absent; the installed runtime
// scripts themselves are bash and need a POSIX shell (macOS, Linux, WSL,
// Git Bash).
//
// Only files Claude Code must execute from inside the project are installed
// (the .claude prompts, hooks, and status line wrapper). Tooling like the
// watcher stays in this package and runs via `npx cc-session-recover watch`.

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const TEMPLATE_ROOT = path.join(__dirname, '..');

const FILES = [
  '.claude/auto-continue.md',
  '.claude/standing-instructions.md',
  '.claude/settings.example.json',
  '.claude/statusline-quota-cache.sh',
  '.claude/hooks/log-stop-failure.sh',
  '.claude/hooks/inject-standing-instructions.sh',
  '.claude/hooks/remind-on-prompt.sh',
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
const RECOVERY_HOOK_SCRIPTS = [
  'inject-standing-instructions.sh',
  'remind-on-prompt.sh',
  'log-stop-failure.sh',
];

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (err) {
    throw new Error(`Could not parse ${file}: ${err.message}`);
  }
}

function addMissingHookGroups(existingGroups, incomingGroups) {
  const merged = Array.isArray(existingGroups) ? existingGroups.slice() : [];
  for (const group of incomingGroups || []) {
    const encoded = JSON.stringify(group);
    if (!merged.some((existing) => JSON.stringify(existing) === encoded || hasSameRecoveryHook(existing, group))) {
      merged.push(group);
    }
  }
  return merged;
}

function recoveryHookScripts(group) {
  const handlers = Array.isArray(group && group.hooks) ? group.hooks : [];
  const commands = handlers
    .filter((handler) => handler && handler.type === 'command' && typeof handler.command === 'string')
    .map((handler) => handler.command);
  return RECOVERY_HOOK_SCRIPTS.filter((script) => commands.some((command) => command.includes(script)));
}

function hasSameRecoveryHook(existingGroup, incomingGroup) {
  const incomingScripts = recoveryHookScripts(incomingGroup);
  if (!incomingScripts.length) return false;

  const existingScripts = recoveryHookScripts(existingGroup);
  return incomingScripts.some((script) => existingScripts.includes(script));
}

function mergeHookSettings(localPath, templatePath) {
  if (!fs.existsSync(localPath)) {
    fs.copyFileSync(templatePath, localPath);
    return 'created';
  }

  const localSettings = readJson(localPath);
  const templateSettings = readJson(templatePath);
  const incomingHooks = templateSettings.hooks || {};
  const mergedHooks = { ...(localSettings.hooks || {}) };

  for (const [event, groups] of Object.entries(incomingHooks)) {
    mergedHooks[event] = addMissingHookGroups(mergedHooks[event], groups);
  }

  localSettings.hooks = mergedHooks;
  fs.writeFileSync(localPath, `${JSON.stringify(localSettings, null, 2)}\n`);
  return 'merged';
}

function usage() {
  console.error('Usage: cc-session-recover init [--no-hooks] [target-dir]');
  console.error('       cc-session-recover watch [target-dir]');
  console.error('Hooks are enabled by default; Claude Code still asks you to approve them once.');
  process.exit(2);
}

function watch(target) {
  const script = path.join(TEMPLATE_ROOT, 'scripts', 'quota-watcher.sh');
  const child = spawn('bash', [script, target], { stdio: 'inherit' });
  child.on('exit', (code) => process.exit(code === null ? 1 : code));
  child.on('error', (err) => {
    console.error(`Could not start watcher: ${err.message}`);
    process.exit(1);
  });
}

function main() {
  const args = process.argv.slice(2);
  if (args[0] !== 'init' && args[0] !== 'watch') usage();

  let enableHook = true;
  let target = '.';
  for (const arg of args.slice(1)) {
    if (arg === '--no-hooks') enableHook = false;
    else if (arg === '--enable-local-hook') enableHook = true; // legacy no-op, was the old default-off flag
    else if (arg.startsWith('-')) usage();
    else target = arg;
  }

  target = path.resolve(target);
  if (!fs.existsSync(target) || !fs.statSync(target).isDirectory()) {
    console.error(`Target directory does not exist: ${target}`);
    process.exit(1);
  }

  if (args[0] === 'watch') {
    watch(target);
    return;
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
    const result = mergeHookSettings(local, path.join(TEMPLATE_ROOT, '.claude', 'settings.example.json'));
    if (result === 'merged') {
      console.error('Merged hook settings into existing .claude/settings.local.json.');
    }
  }

  console.log(`Installed Claude Code session recovery workflow into ${target}`);
  console.log('Next: start `claude` there and approve the hooks once when asked.');
}

main();
