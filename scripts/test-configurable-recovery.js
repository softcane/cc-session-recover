#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync, spawn, spawnSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const WORK = fs.mkdtempSync(path.join(os.tmpdir(), 'cc-session-recover-config-'));
const PACK_DIR = path.join(WORK, 'pack');
const TOOL_PROJECT = path.join(WORK, 'tool-project');
const TARGETS = path.join(WORK, 'targets');
const FAKE_BIN = path.join(WORK, 'fake-bin');
const CONTROL = path.join(WORK, 'control');
let CLI;
let PACKAGE_ROOT;
let passed = false;
const TEST_FILTER = process.env.TEST_FILTER || '';

function cleanup() {
  fs.rmSync(WORK, { recursive: true, force: true });
  if (passed) {
    process.stdout.write('\nAll configurable recovery tests passed.\n');
  } else {
    process.stderr.write(`\nCONFIGURABLE RECOVERY TEST FAILED. Temporary files were under ${WORK}.\n`);
  }
}

process.on('exit', cleanup);

function command(commandName, args, options = {}) {
  const result = spawnSync(commandName, args, {
    cwd: options.cwd || ROOT,
    env: { ...process.env, ...(options.env || {}) },
    input: options.input,
    encoding: 'utf8',
    timeout: options.timeout || 30000,
  });
  if (result.error) throw result.error;
  if (!options.allowFailure && result.status !== 0) {
    throw new Error(
      `${commandName} ${args.join(' ')} exited ${result.status}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`,
    );
  }
  return result;
}

function write(file, contents, mode) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, contents);
  if (mode) fs.chmodSync(file, mode);
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function readJsonLines(file) {
  if (!fs.existsSync(file)) return [];
  return fs.readFileSync(file, 'utf8')
    .split(/\r?\n/)
    .filter(Boolean)
    .map((line) => JSON.parse(line));
}

function markerPath(target) {
  return path.join(target, '.claude', 'quota-blocked.json');
}

function logPath(target) {
  return path.join(target, '.claude', 'stop-failure-events.jsonl');
}

function configPath(target) {
  return path.join(target, 'session-recover.yaml');
}

function handoffPath(target) {
  return path.join(target, 'HANDOFF.md');
}

function realisticEvent(error, sessionId, extra = {}) {
  const event = {
    session_id: sessionId,
    transcript_path: `/tmp/${sessionId || 'missing'}.jsonl`,
    cwd: '/tmp/fake-project',
    permission_mode: 'default',
    hook_event_name: 'StopFailure',
    error,
    last_assistant_message: `API Error: ${error}`,
    ...extra,
  };
  if (sessionId === undefined) delete event.session_id;
  return event;
}

function runHook(target, input) {
  const raw = typeof input === 'string' ? input : JSON.stringify(input);
  return command('bash', [path.join(target, '.claude', 'hooks', 'log-stop-failure.sh')], {
    cwd: target,
    env: { CLAUDE_PROJECT_DIR: target },
    input: raw,
    allowFailure: true,
  });
}

function runInstalledRecovery(target, mode) {
  const recoveryJsPath = path.join(target, '.claude', 'session-recover.js');
  return execFileSync('node', [recoveryJsPath, mode], {
    cwd: target,
    encoding: 'utf8',
  }).trim();
}

function writeConfig(target, errors, retryMinutes = 1) {
  const list = errors.map((error) => `  - ${error}`).join('\n');
  write(configPath(target), `errors:\n${list}\n\nretry_minutes: ${retryMinutes}\n`);
}

function initTarget(name) {
  const target = path.join(TARGETS, name);
  fs.mkdirSync(target, { recursive: true });
  command(CLI, ['init', target], { cwd: TOOL_PROJECT });
  return target;
}

async function waitFor(predicate, description, timeout = 8000) {
  const started = Date.now();
  while (Date.now() - started < timeout) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error(`Timed out waiting for ${description}`);
}

function resetControl(options = {}) {
  fs.rmSync(CONTROL, { recursive: true, force: true });
  fs.mkdirSync(CONTROL, { recursive: true });
  write(path.join(CONTROL, 'failures'), `${options.failures || 0}\n`);
  if (options.block) write(path.join(CONTROL, 'block'), '1\n');
}

function calls() {
  return readJsonLines(path.join(CONTROL, 'claude-calls.jsonl'));
}

function sleeps() {
  if (!fs.existsSync(path.join(CONTROL, 'sleep-calls.log'))) return [];
  return fs.readFileSync(path.join(CONTROL, 'sleep-calls.log'), 'utf8')
    .split(/\r?\n/)
    .filter(Boolean)
    .map(Number);
}

function startWatcher(target, extraEnv = {}) {
  const child = spawn(CLI, ['watch', target], {
    cwd: TOOL_PROJECT,
    env: {
      ...process.env,
      PATH: `${FAKE_BIN}${path.delimiter}${process.env.PATH}`,
      FAKE_CLAUDE_CONTROL: CONTROL,
      ...extraEnv,
    },
    detached: true,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let stdout = '';
  let stderr = '';
  child.stdout.on('data', (chunk) => { stdout += chunk.toString(); });
  child.stderr.on('data', (chunk) => { stderr += chunk.toString(); });
  return {
    child,
    output: () => `${stdout}${stderr}`,
  };
}

async function stopWatcher(watcher) {
  if (watcher.child.exitCode !== null) return;
  try {
    process.kill(-watcher.child.pid, 'SIGTERM');
  } catch (_) {
    try { watcher.child.kill('SIGTERM'); } catch (_) {}
  }
  await Promise.race([
    new Promise((resolve) => watcher.child.once('exit', resolve)),
    new Promise((resolve) => setTimeout(resolve, 1000)),
  ]);
  if (watcher.child.exitCode === null) {
    try { process.kill(-watcher.child.pid, 'SIGKILL'); } catch (_) {}
  }
}

async function runWatcherToSuccess(target, failures, extraEnv = {}, expectedCalls = failures + 1) {
  resetControl({ failures });
  const watcher = startWatcher(target, extraEnv);
  try {
    await waitFor(
      () => calls().length >= expectedCalls && !fs.existsSync(markerPath(target)),
      `${expectedCalls} Claude calls and marker cleanup`,
    );
    return { watcher, recordedCalls: calls(), recordedSleeps: sleeps(), output: watcher.output() };
  } finally {
    await stopWatcher(watcher);
  }
}

async function test(name, fn) {
  if (TEST_FILTER && !name.includes(TEST_FILTER)) return;
  await fn();
  process.stdout.write(`ok: ${name}\n`);
}

function assertMarker(target, sessionId, errorType, retryMinutes) {
  const marker = readJson(markerPath(target));
  assert.strictEqual(marker.hook_input.session_id, sessionId);
  assert.strictEqual(marker.hook_input.error, errorType);
  assert.strictEqual(marker.recovery.error, errorType);
  assert.strictEqual(marker.recovery.retry_minutes, retryMinutes);
  assert.strictEqual(marker.recovery.retry_seconds, retryMinutes * 60);
  return marker;
}

function installFakeExecutables() {
  write(path.join(FAKE_BIN, 'claude'), `#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');
const control = process.env.FAKE_CLAUDE_CONTROL;
fs.mkdirSync(control, { recursive: true });
const callsFile = path.join(control, 'claude-calls.jsonl');
const existing = fs.existsSync(callsFile)
  ? fs.readFileSync(callsFile, 'utf8').split(/\\r?\\n/).filter(Boolean).length
  : 0;
const callNumber = existing + 1;
fs.appendFileSync(callsFile, JSON.stringify({
  call: callNumber,
  argv: process.argv.slice(2),
  cwd: process.cwd()
}) + '\\n');
fs.writeFileSync(path.join(control, 'started'), String(callNumber));
while (fs.existsSync(path.join(control, 'block'))) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 25);
}
const failures = Number(fs.readFileSync(path.join(control, 'failures'), 'utf8').trim() || 0);
if (callNumber <= failures) {
  process.stderr.write('controlled transient failure\\n');
  process.exit(1);
}
process.stdout.write('controlled resume success\\n');
`, 0o755);

  write(path.join(FAKE_BIN, 'sleep'), `#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');
const control = process.env.FAKE_CLAUDE_CONTROL;
fs.mkdirSync(control, { recursive: true });
fs.appendFileSync(path.join(control, 'sleep-calls.log'), String(process.argv[2]) + '\\n');
const delay = Number(process.env.FAKE_SLEEP_DELAY_MS || 15);
Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, delay);
`, 0o755);
}

async function main() {
  fs.mkdirSync(PACK_DIR, { recursive: true });
  fs.mkdirSync(TOOL_PROJECT, { recursive: true });
  fs.mkdirSync(TARGETS, { recursive: true });
  installFakeExecutables();

  const pack = command('npm', ['pack', '--json', '--pack-destination', PACK_DIR]);
  const packMetadata = JSON.parse(pack.stdout)[0];
  const packagedFiles = new Set(packMetadata.files.map((entry) => entry.path));
  for (const required of [
    'session-recover.yaml',
    'lib/recovery.js',
    '.claude/hooks/log-stop-failure.sh',
    '.claude/commands/session-recover.md',
    '.claude/settings.example.json',
    'scripts/quota-watcher.sh',
    'bin/cli.js',
    'templates/HANDOFF.md',
  ]) {
    assert(packagedFiles.has(required), `package is missing ${required}`);
  }
  assert(!packagedFiles.has('HANDOFF.md'), 'package must not contain the live repository HANDOFF.md');
  const tarball = path.join(PACK_DIR, packMetadata.filename);

  write(path.join(TOOL_PROJECT, 'package.json'), '{"name":"installed-recovery-test","private":true}\n');
  command('npm', ['install', '--ignore-scripts', '--no-audit', '--no-fund', tarball], {
    cwd: TOOL_PROJECT,
    timeout: 60000,
  });
  PACKAGE_ROOT = path.join(TOOL_PROJECT, 'node_modules', 'cc-session-recover');
  CLI = path.join(TOOL_PROJECT, 'node_modules', '.bin', 'cc-session-recover');
  assert(fs.existsSync(CLI), 'installed package has no CLI');

  await test('packaged artifact installs every runtime file and injects the StopFailure hook only', async () => {
    const target = initTarget('installed-files');
    for (const required of [
      'HANDOFF.md',
      'session-recover.yaml',
      '.claude/session-recover.js',
      '.claude/auto-continue.md',
      '.claude/commands/session-recover.md',
      '.claude/settings.example.json',
      '.claude/settings.local.json',
      '.claude/statusline-quota-cache.sh',
      '.claude/hooks/log-stop-failure.sh',
    ]) {
      assert(fs.existsSync(path.join(target, required)), `installed target is missing ${required}`);
    }
    for (const deleted of [
      '.claude/standing-instructions.md',
      '.claude/hooks/inject-standing-instructions.sh',
      '.claude/hooks/remind-on-prompt.sh',
    ]) {
      assert(!fs.existsSync(path.join(target, deleted)), `installed target still has ${deleted}`);
    }
    assert(!fs.existsSync(path.join(target, 'scripts')));
    assert(!fs.existsSync(path.join(target, 'docs')));
    assert(fs.readFileSync(handoffPath(target), 'utf8').includes('- Not set yet.'));
    assert.deepStrictEqual(
      fs.readFileSync(configPath(target), 'utf8'),
      'errors:\n  - rate_limit\n  - overloaded\n\nretry_minutes: 20\n',
    );

    const settings = readJson(path.join(target, '.claude', 'settings.local.json'));
    assert.deepStrictEqual(Object.keys(settings.hooks), ['StopFailure']);
    assert.strictEqual(settings.hooks.StopFailure.length, 1);
    assert(!Object.prototype.hasOwnProperty.call(settings.hooks.StopFailure[0], 'matcher'));
  });

  await test('npm and clone installers create YAML once, preserve edits, update old hooks, and avoid duplicates', async () => {
    const npmTarget = path.join(TARGETS, 'npm-upgrade');
    fs.mkdirSync(path.join(npmTarget, '.claude'), { recursive: true });
    write(path.join(npmTarget, '.claude', 'settings.local.json'), JSON.stringify({
      permissions: { allow: ['Bash(npm test *)'] },
      hooks: {
        PostToolUse: [{ matcher: 'Write', hooks: [{ type: 'command', command: 'true' }] }],
        StopFailure: [{
          matcher: 'rate_limit',
          hooks: [
            { type: 'command', command: '"$CLAUDE_PROJECT_DIR"/.claude/hooks/log-stop-failure.sh' },
            { type: 'command', command: 'custom-stop-handler' },
          ],
        }],
      },
    }));
    command(CLI, ['init', npmTarget], { cwd: TOOL_PROJECT });
    writeConfig(npmTarget, ['overloaded'], 7);
    command(CLI, ['init', npmTarget], { cwd: TOOL_PROJECT });
    assert(fs.readFileSync(configPath(npmTarget), 'utf8').includes('retry_minutes: 7'));
    const npmSettings = readJson(path.join(npmTarget, '.claude', 'settings.local.json'));
    assert.deepStrictEqual(npmSettings.permissions.allow, ['Bash(npm test *)']);
    assert.strictEqual(npmSettings.hooks.PostToolUse.length, 1);
    const npmStopGroups = npmSettings.hooks.StopFailure;
    assert.strictEqual(npmStopGroups.length, 2);
    const npmCustomGroup = npmStopGroups.find((group) =>
      group.hooks.some((hook) => hook.command === 'custom-stop-handler'));
    assert(npmCustomGroup, 'npm installer deleted an unrelated StopFailure handler');
    assert.strictEqual(npmCustomGroup.matcher, 'rate_limit');
    const npmRecoveryGroups = npmStopGroups.filter((group) =>
      group.hooks.some((hook) => hook.command.includes('log-stop-failure.sh')));
    assert.strictEqual(npmRecoveryGroups.length, 1);
    assert(!Object.prototype.hasOwnProperty.call(npmRecoveryGroups[0], 'matcher'));

    const cloneTarget = path.join(TARGETS, 'clone-upgrade');
    fs.mkdirSync(path.join(cloneTarget, '.claude'), { recursive: true });
    write(path.join(cloneTarget, '.claude', 'settings.local.json'), JSON.stringify({
      custom: 'preserved',
      hooks: {
        StopFailure: [{
          matcher: 'rate_limit',
          hooks: [
            { type: 'command', command: '"$CLAUDE_PROJECT_DIR"/.claude/hooks/log-stop-failure.sh' },
            { type: 'command', command: 'custom-clone-stop-handler' },
          ],
        }],
      },
    }));
    const packagedShellInstaller = path.join(PACKAGE_ROOT, 'scripts', 'install-into-project.sh');
    command('bash', [packagedShellInstaller, cloneTarget]);
    writeConfig(cloneTarget, ['server_error'], 9);
    command('bash', [packagedShellInstaller, cloneTarget]);
    assert(fs.readFileSync(configPath(cloneTarget), 'utf8').includes('retry_minutes: 9'));
    const cloneSettings = readJson(path.join(cloneTarget, '.claude', 'settings.local.json'));
    assert.strictEqual(cloneSettings.custom, 'preserved');
    const cloneStopGroups = cloneSettings.hooks.StopFailure;
    assert.strictEqual(cloneStopGroups.length, 2);
    const cloneCustomGroup = cloneStopGroups.find((group) =>
      group.hooks.some((hook) => hook.command === 'custom-clone-stop-handler'));
    assert(cloneCustomGroup, 'clone installer deleted an unrelated StopFailure handler');
    assert.strictEqual(cloneCustomGroup.matcher, 'rate_limit');
    assert.strictEqual(cloneStopGroups.filter((group) =>
      group.hooks.some((hook) => hook.command.includes('log-stop-failure.sh'))).length, 1);
  });

  await test('installed runtime check and clear modes report marker readiness exactly', async () => {
    const target = initTarget('check-clear-runtime');
    const targetMarker = markerPath(target);

    assert.strictEqual(runInstalledRecovery(target, 'check'), 'NONE');

    const marker = {
      rate_limit_state: null,
      hook_input: realisticEvent('rate_limit', 'check-clear-session'),
      recovery: { error: 'rate_limit', retry_seconds: 100000 },
    };
    write(targetMarker, `${JSON.stringify(marker)}\n`);
    const wait = runInstalledRecovery(target, 'check');
    assert.match(wait, /^WAIT [0-9]+ rate_limit$/);
    assert(Number(wait.split(' ')[1]) > 0, `WAIT seconds were not positive: ${wait}`);

    const oldTime = new Date(Date.now() - 200000000);
    fs.utimesSync(targetMarker, oldTime, oldTime);
    assert.strictEqual(runInstalledRecovery(target, 'check'), 'READY rate_limit');

    write(targetMarker, `${JSON.stringify({
      hook_input: realisticEvent('authentication_failed', 'check-clear-auth'),
      recovery: { error: 'authentication_failed', retry_seconds: 100000 },
    })}\n`);
    assert.strictEqual(runInstalledRecovery(target, 'check'), 'NONE');

    assert.strictEqual(runInstalledRecovery(target, 'clear'), '');
    assert(!fs.existsSync(targetMarker), 'clear did not remove the marker');
    assert.strictEqual(runInstalledRecovery(target, 'check'), 'NONE');
  });

  await test('missing YAML enables rate limits and overloads with the 20-minute marker fallback', async () => {
    const target = initTarget('missing-yaml-selection');
    fs.unlinkSync(configPath(target));
    runHook(target, realisticEvent('rate_limit', 'missing-yaml-rate'));
    assertMarker(target, 'missing-yaml-rate', 'rate_limit', 20);
    runHook(target, realisticEvent('overloaded', 'missing-yaml-overload'));
    assertMarker(target, 'missing-yaml-overload', 'overloaded', 20);
    const overloadResult = await runWatcherToSuccess(target, 1);
    assert.strictEqual(overloadResult.recordedSleeps[0], 1200);
    assert(overloadResult.recordedCalls[0].argv.includes('missing-yaml-overload'));
    runHook(target, realisticEvent('server_error', 'missing-yaml-server'));
    assert(!fs.existsSync(markerPath(target)));
    assert.strictEqual(readJsonLines(logPath(target)).length, 3);
  });

  await test('installed recovery works from a project path containing spaces', async () => {
    const target = initTarget('project path with spaces');
    writeConfig(target, ['overloaded'], 1);
    runHook(target, realisticEvent('overloaded', 'path-space-session'));
    assertMarker(target, 'path-space-session', 'overloaded', 1);
    const result = await runWatcherToSuccess(target, 1);
    assert.strictEqual(result.recordedSleeps[0], 60);
    assert(result.recordedCalls[0].argv.includes('path-space-session'));
    assert.strictEqual(fs.realpathSync(result.recordedCalls[0].cwd), fs.realpathSync(target));
  });

  await test('rate-only, all-errors, subset, and duplicate selections create only expected typed markers', async () => {
    const rateOnly = initTarget('rate-only');
    writeConfig(rateOnly, ['rate_limit'], 2);
    runHook(rateOnly, realisticEvent('overloaded', 'rate-only-overload'));
    assert(!fs.existsSync(markerPath(rateOnly)));
    runHook(rateOnly, realisticEvent('server_error', 'rate-only-server'));
    assert(!fs.existsSync(markerPath(rateOnly)));
    runHook(rateOnly, realisticEvent('rate_limit', 'rate-only-rate'));
    assertMarker(rateOnly, 'rate-only-rate', 'rate_limit', 2);
    const rateOnlyResult = await runWatcherToSuccess(rateOnly, 1);
    assert.strictEqual(rateOnlyResult.recordedSleeps[0], 120);
    assert(rateOnlyResult.recordedCalls[0].argv.includes('rate-only-rate'));

    const all = initTarget('all-errors');
    writeConfig(all, ['rate_limit', 'overloaded', 'server_error'], 3);
    for (const errorType of ['rate_limit', 'overloaded', 'server_error']) {
      const sessionId = `all-${errorType}`;
      runHook(all, realisticEvent(errorType, sessionId));
      const marker = assertMarker(all, sessionId, errorType, 3);
      if (errorType !== 'rate_limit') assert.strictEqual(marker.rate_limit_state, null);
      const result = await runWatcherToSuccess(all, 1);
      assert.strictEqual(result.recordedSleeps[0], 180);
      assert(result.recordedCalls[0].argv.includes(sessionId));
    }
    assert.deepStrictEqual(
      readJsonLines(logPath(all)).map((entry) => entry.hook_input.error),
      ['rate_limit', 'overloaded', 'server_error'],
    );
    const handoff = fs.readFileSync(handoffPath(all), 'utf8');
    assert(handoff.includes('a rate limit'));
    assert(handoff.includes('an overloaded service'));
    assert(handoff.includes('a temporary server error'));

    const subset = initTarget('subset');
    writeConfig(subset, ['overloaded', 'server_error'], 4);
    runHook(subset, realisticEvent('rate_limit', 'subset-rate'));
    assert(!fs.existsSync(markerPath(subset)));
    runHook(subset, realisticEvent('overloaded', 'subset-overload'));
    assertMarker(subset, 'subset-overload', 'overloaded', 4);
    const subsetOverload = await runWatcherToSuccess(subset, 1);
    assert.strictEqual(subsetOverload.recordedSleeps[0], 240);
    assert(subsetOverload.recordedCalls[0].argv.includes('subset-overload'));
    runHook(subset, realisticEvent('server_error', 'subset-server'));
    assertMarker(subset, 'subset-server', 'server_error', 4);
    const subsetServer = await runWatcherToSuccess(subset, 1);
    assert.strictEqual(subsetServer.recordedSleeps[0], 240);
    assert(subsetServer.recordedCalls[0].argv.includes('subset-server'));

    const duplicate = initTarget('duplicates');
    write(configPath(duplicate), 'errors: [rate_limit, rate_limit, overloaded]\nretry_minutes: 5\n');
    runHook(duplicate, realisticEvent('rate_limit', 'duplicate-rate'));
    assertMarker(duplicate, 'duplicate-rate', 'rate_limit', 5);
    const duplicateResult = await runWatcherToSuccess(duplicate, 1);
    assert.strictEqual(duplicateResult.recordedSleeps[0], 300);
    assert(duplicateResult.recordedCalls[0].argv.includes('duplicate-rate'));

    const indented = initTarget('yaml-indentation');
    write(
      configPath(indented),
      'errors:\n    - "rate_limit" # valid YAML may use more than two spaces\nretry_minutes: 1\n',
    );
    runHook(indented, realisticEvent('rate_limit', 'yaml-indentation-session'));
    assertMarker(indented, 'yaml-indentation-session', 'rate_limit', 1);
  });

  await test('invalid YAML and every invalid configuration class fail closed and report the file', async () => {
    const invalidCases = [
      ['invalid-yaml', 'errors:\n  - rate_limit\nretry_minutes: [20\n'],
      ['inconsistent-indent', 'errors:\n  - rate_limit\n    - overloaded\nretry_minutes: 1\n'],
      ['unknown-error', 'errors:\n  - not_real\nretry_minutes: 1\n'],
      ['empty-errors', 'errors: []\nretry_minutes: 1\n'],
      ['missing-errors', 'retry_minutes: 1\n'],
      ['missing-retry', 'errors:\n  - rate_limit\n'],
      ['unknown-field', 'errors:\n  - rate_limit\nretry_minutes: 1\nbackoff: true\n'],
      ['retry-zero', 'errors:\n  - rate_limit\nretry_minutes: 0\n'],
      ['retry-negative', 'errors:\n  - rate_limit\nretry_minutes: -1\n'],
      ['retry-fraction', 'errors:\n  - rate_limit\nretry_minutes: 1.5\n'],
      ['retry-string', 'errors:\n  - rate_limit\nretry_minutes: "1"\n'],
      ['retry-null', 'errors:\n  - rate_limit\nretry_minutes: null\n'],
      ['retry-unsafe', 'errors:\n  - rate_limit\nretry_minutes: 150119987579017\n'],
    ];

    for (const [name, yaml] of invalidCases) {
      const target = initTarget(`invalid-${name}`);
      write(configPath(target), yaml);
      const result = runHook(target, realisticEvent('rate_limit', `invalid-${name}`));
      assert(!fs.existsSync(markerPath(target)), `${name} created a marker`);
      assert(result.stderr.includes(configPath(target)), `${name} did not report the config path`);
      const entries = readJsonLines(logPath(target));
      assert.strictEqual(entries.length, 1);
      assert(entries[0].configuration_error, `${name} was not logged as a configuration error`);
      assert(!result.stderr.includes(yaml.trim()), `${name} exposed configuration contents`);
    }

    const maxBoundary = initTarget('valid-retry-max-boundary');
    write(configPath(maxBoundary), 'errors:\n  - rate_limit\nretry_minutes: 150119987579016\n');
    runHook(maxBoundary, realisticEvent('rate_limit', 'valid-retry-max-boundary'));
    assertMarker(maxBoundary, 'valid-retry-max-boundary', 'rate_limit', 150119987579016);
  });

  await test('malformed input, missing sessions, unknown errors, and stale markers are handled without partial state', async () => {
    const target = initTarget('malformed-and-stale');
    writeConfig(target, ['rate_limit'], 1);
    runHook(target, realisticEvent('rate_limit', 'stable-session'));
    const stableMarker = fs.readFileSync(markerPath(target), 'utf8');

    const malformed = runHook(target, '{"session_id":');
    assert(malformed.stderr.includes('invalid StopFailure JSON'));
    assert.strictEqual(fs.readFileSync(markerPath(target), 'utf8'), stableMarker);
    const malformedEntry = readJsonLines(logPath(target)).at(-1);
    assert(malformedEntry.input_error);
    assert.strictEqual(malformedEntry.raw_input, '{"session_id":');

    fs.unlinkSync(markerPath(target));
    runHook(target, realisticEvent('rate_limit', undefined));
    assert(!fs.existsSync(markerPath(target)));
    runHook(target, realisticEvent('authentication_failed', 'permanent-session'));
    assert(!fs.existsSync(markerPath(target)));

    runHook(target, realisticEvent('rate_limit', 'same-session'));
    runHook(target, realisticEvent('billing_error', 'same-session'));
    assert(!fs.existsSync(markerPath(target)), 'same-session permanent error left a stale marker');

    runHook(target, realisticEvent('rate_limit', 'other-active'));
    const otherMarker = fs.readFileSync(markerPath(target), 'utf8');
    runHook(target, realisticEvent('invalid_request', 'different-session'));
    assert.strictEqual(fs.readFileSync(markerPath(target), 'utf8'), otherMarker);

    write(configPath(target), 'errors: [unknown]\nretry_minutes: 1\n');
    runHook(target, realisticEvent('rate_limit', 'different-invalid-config-session'));
    assert(!fs.existsSync(markerPath(target)), 'invalid config did not stop active automatic recovery');
  });

  await test('malformed cached quota data is ignored and repeated incidents do not duplicate handoff notes', async () => {
    const target = initTarget('cache-and-handoff');
    writeConfig(target, ['rate_limit'], 1);
    write(path.join(target, '.claude', 'rate-limit-state.json'), '{bad cache');
    const first = runHook(target, realisticEvent('rate_limit', 'cache-session'));
    assert(first.stderr.includes('Ignoring malformed cached rate-limit state'));
    assert.strictEqual(assertMarker(target, 'cache-session', 'rate_limit', 1).rate_limit_state, null);
    const marker = readJson(markerPath(target));
    assert.match(marker.logged_at, /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} .+$/);
    assert.match(readJsonLines(logPath(target))[0].logged_at, /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} .+$/);
    fs.appendFileSync(
      handoffPath(target),
      `\n${Array.from({ length: 20 }, (_, index) => `intervening handoff line ${index}`).join('\n')}\n`,
    );
    runHook(target, realisticEvent('rate_limit', 'cache-session'));
    const handoff = fs.readFileSync(handoffPath(target), 'utf8');
    const notes = (handoff.match(/Automatic note: Claude Code stopped with a rate limit/g) || []).length;
    assert.strictEqual(notes, 1);
    fs.unlinkSync(markerPath(target));
    runHook(target, realisticEvent('rate_limit', 'cache-session'));
    const laterHandoff = fs.readFileSync(handoffPath(target), 'utf8');
    const laterNotes = (laterHandoff.match(/Automatic note: Claude Code stopped with a rate limit/g) || []).length;
    assert.strictEqual(laterNotes, 2, 'a new incident after marker cleanup needs a new handoff note');
  });

  await test('configured fallback timing, legacy default timing, and environment override are used by the installed watcher', async () => {
    const configured = initTarget('timing-configured');
    writeConfig(configured, ['rate_limit'], 1);
    runHook(configured, realisticEvent('rate_limit', 'timing-configured-session'));
    const configuredResult = await runWatcherToSuccess(configured, 1);
    assert.strictEqual(configuredResult.recordedSleeps[0], 60);

    const missing = initTarget('timing-missing-yaml');
    fs.unlinkSync(configPath(missing));
    runHook(missing, realisticEvent('rate_limit', 'timing-default-session'));
    const missingResult = await runWatcherToSuccess(missing, 1);
    assert.strictEqual(missingResult.recordedSleeps[0], 1200);

    const overridden = initTarget('timing-env-override');
    writeConfig(overridden, ['rate_limit'], 2);
    runHook(overridden, realisticEvent('rate_limit', 'timing-override-session'));
    const overrideResult = await runWatcherToSuccess(overridden, 1, {
      QUOTA_WATCH_INTERVAL: '7',
      QUOTA_WATCH_CLAUDE_ARGS: '--permission-mode plan',
    });
    assert.strictEqual(overrideResult.recordedSleeps[0], 7);
    assert(overrideResult.recordedCalls[0].argv.includes('plan'));
  });

  await test('future rate-limit reset wins; unusable reset values fall back; non-rate failures ignore cache', async () => {
    const future = initTarget('timing-future-reset');
    writeConfig(future, ['rate_limit'], 1);
    const futureReset = Math.floor(Date.now() / 1000) + 300;
    write(path.join(future, '.claude', 'rate-limit-state.json'), JSON.stringify({
      five_hour_resets_at: futureReset,
      cached_at: Math.floor(Date.now() / 1000),
    }));
    runHook(future, realisticEvent('rate_limit', 'future-reset-session'));
    const futureResult = await runWatcherToSuccess(future, 0, { QUOTA_RESUME_BUFFER: '0' }, 1);
    assert(futureResult.recordedSleeps[0] >= 295, `future reset sleep was ${futureResult.recordedSleeps[0]}`);
    assert(futureResult.output.includes('one precise knock'));

    const fallbackCases = [
      ['missing', null],
      ['null', { five_hour_resets_at: null }],
      ['malformed', { five_hour_resets_at: 'soon' }],
      ['boundary-now', { five_hour_resets_at: Math.floor(Date.now() / 1000) }],
      ['past', { five_hour_resets_at: Math.floor(Date.now() / 1000) - 30 }],
      ['stale-future', {
        five_hour_resets_at: Math.floor(Date.now() / 1000) + 300,
        cached_at: 1,
      }],
    ];
    for (const [name, state] of fallbackCases) {
      const target = initTarget(`timing-fallback-${name}`);
      writeConfig(target, ['rate_limit'], 1);
      if (state) write(path.join(target, '.claude', 'rate-limit-state.json'), JSON.stringify(state));
      runHook(target, realisticEvent('rate_limit', `fallback-${name}`));
      const result = await runWatcherToSuccess(target, 1);
      assert.strictEqual(result.recordedSleeps[0], 60, `${name} reset did not fall back`);
    }

    for (const errorType of ['overloaded', 'server_error']) {
      const target = initTarget(`timing-ignore-cache-${errorType}`);
      writeConfig(target, [errorType], 1);
      write(path.join(target, '.claude', 'rate-limit-state.json'), JSON.stringify({
        five_hour_resets_at: Math.floor(Date.now() / 1000) + 300,
      }));
      runHook(target, realisticEvent(errorType, `ignore-cache-${errorType}`));
      const marker = readJson(markerPath(target));
      marker.rate_limit_state = { five_hour_resets_at: Math.floor(Date.now() / 1000) + 300 };
      write(markerPath(target), `${JSON.stringify(marker)}\n`);
      const result = await runWatcherToSuccess(target, 1);
      assert.strictEqual(result.recordedSleeps[0], 60);
      assert(!result.output.includes('one precise knock'));
      assert(result.recordedCalls[0].argv.includes(`ignore-cache-${errorType}`));
    }
  });

  await test('resume arguments, failed-attempt persistence, restart recovery, and successful cleanup are exact', async () => {
    const target = initTarget('resume-contract');
    writeConfig(target, ['overloaded'], 1);
    runHook(target, realisticEvent('overloaded', 'resume-exact-session'));
    const prompt = fs.readFileSync(path.join(target, '.claude', 'auto-continue.md'), 'utf8');

    resetControl({ failures: 999 });
    const firstWatcher = startWatcher(target, { FAKE_SLEEP_DELAY_MS: '500' });
    await waitFor(() => calls().length >= 1, 'first failed resume');
    await stopWatcher(firstWatcher);
    assert(fs.existsSync(markerPath(target)), 'failed resume removed marker');

    const previousCalls = calls().length;
    write(path.join(CONTROL, 'failures'), `${previousCalls}\n`);
    const restarted = startWatcher(target);
    try {
      await waitFor(
        () => calls().length > previousCalls && !fs.existsSync(markerPath(target)),
        'restart success and marker cleanup',
      );
    } finally {
      await stopWatcher(restarted);
    }

    const finalCall = calls().at(-1);
    assert.deepStrictEqual(finalCall.argv, [
      '-p',
      '--resume',
      'resume-exact-session',
      '--permission-mode',
      'acceptEdits',
      prompt,
    ]);
    assert.strictEqual(fs.realpathSync(finalCall.cwd), fs.realpathSync(target));
    assert(fs.existsSync(logPath(target)), 'success removed failure log');
    assert(fs.existsSync(handoffPath(target)), 'success removed handoff');
  });

  await test('old-format markers resume, invalid markers never invoke Claude, and missing dependencies fail clearly', async () => {
    const old = initTarget('old-marker');
    write(markerPath(old), JSON.stringify({
      logged_at: new Date().toISOString(),
      rate_limit_state: null,
      hook_input: realisticEvent('rate_limit', 'old-marker-session'),
    }));
    const oldResult = await runWatcherToSuccess(old, 0, { QUOTA_WATCH_INTERVAL: '1' }, 1);
    assert(oldResult.recordedCalls[0].argv.includes('old-marker-session'));

    for (const [name, contents] of [
      ['invalid-json', '{partial'],
      ['missing-session', JSON.stringify({ hook_input: { error: 'rate_limit' } })],
      ['numeric-session', JSON.stringify({ hook_input: { session_id: 42, error: 'rate_limit' } })],
      ['missing-error', JSON.stringify({ hook_input: { session_id: 'missing-error' } })],
      ['unknown-error', JSON.stringify({
        hook_input: { session_id: 'unknown-error', error: 'authentication_failed' },
      })],
      ['mismatched-recovery-error', JSON.stringify({
        hook_input: { session_id: 'mismatched-error', error: 'rate_limit' },
        recovery: { error: 'overloaded', retry_seconds: 60 },
      })],
      ['invalid-retry-seconds', JSON.stringify({
        hook_input: { session_id: 'invalid-retry', error: 'rate_limit' },
        recovery: { error: 'rate_limit', retry_seconds: '60' },
      })],
    ]) {
      const target = initTarget(`bad-marker-${name}`);
      write(markerPath(target), contents);
      resetControl({ failures: 0 });
      const watcher = startWatcher(target);
      try {
        await waitFor(() => !fs.existsSync(markerPath(target)), `${name} marker cleanup`);
      } finally {
        await stopWatcher(watcher);
      }
      assert.strictEqual(calls().length, 0, `${name} marker invoked Claude`);
    }

    const missingPrompt = initTarget('missing-prompt');
    fs.unlinkSync(path.join(missingPrompt, '.claude', 'auto-continue.md'));
    resetControl({ failures: 0 });
    const promptResult = command(CLI, ['watch', missingPrompt], {
      cwd: TOOL_PROJECT,
      env: {
        PATH: `${FAKE_BIN}${path.delimiter}${process.env.PATH}`,
        FAKE_CLAUDE_CONTROL: CONTROL,
      },
      allowFailure: true,
    });
    assert.notStrictEqual(promptResult.status, 0);
    assert(promptResult.stderr.includes('Missing'));

    const missingClaude = initTarget('missing-claude');
    const jqOnly = path.join(WORK, 'jq-only');
    fs.mkdirSync(jqOnly, { recursive: true });
    fs.symlinkSync(command('sh', ['-c', 'command -v jq']).stdout.trim(), path.join(jqOnly, 'jq'));
    const claudeResult = command('/bin/bash', [path.join(PACKAGE_ROOT, 'scripts', 'quota-watcher.sh'), missingClaude], {
      env: { PATH: jqOnly },
      allowFailure: true,
    });
    assert.notStrictEqual(claudeResult.status, 0);
    assert(claudeResult.stderr.includes('claude CLI on PATH'));
  });

  await test('stopping the installed watcher CLI terminates its watcher process group', async () => {
    const target = initTarget('watcher-stop');
    resetControl({ failures: 0 });
    const watcher = startWatcher(target, { FAKE_SLEEP_DELAY_MS: '50' });
    await waitFor(() => watcher.output().includes('Watching'), 'watcher startup');
    watcher.child.kill('SIGTERM');
    await waitFor(() => watcher.child.exitCode !== null, 'watcher CLI termination');
    assert.strictEqual(watcher.child.exitCode, 0);
  });

  await test('a newer marker written during an older resume is preserved', async () => {
    const target = initTarget('newer-marker-race');
    writeConfig(target, ['rate_limit', 'overloaded'], 1);
    runHook(target, realisticEvent('rate_limit', 'older-session'));
    resetControl({ failures: 0, block: true });
    const watcher = startWatcher(target, { QUOTA_WATCH_INTERVAL: '30', FAKE_SLEEP_DELAY_MS: '1000' });
    try {
      await waitFor(() => fs.existsSync(path.join(CONTROL, 'started')), 'older resume to start');
      runHook(target, realisticEvent('overloaded', 'newer-session'));
      fs.unlinkSync(path.join(CONTROL, 'block'));
      await waitFor(
        () => watcher.output().includes('preserving newer recovery state'),
        'newer marker preservation message',
      );
      const marker = assertMarker(target, 'newer-session', 'overloaded', 1);
      assert.strictEqual(marker.hook_input.session_id, 'newer-session');
    } finally {
      await stopWatcher(watcher);
    }
  });

  passed = true;
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exitCode = 1;
});
