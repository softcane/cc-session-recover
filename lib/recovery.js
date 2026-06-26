#!/usr/bin/env node
'use strict';

const crypto = require('crypto');
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const DEFAULT_CONFIG = Object.freeze({
  errors: Object.freeze(['rate_limit', 'overloaded']),
  retry_minutes: 20,
});
const SUPPORTED_ERRORS = new Set(['rate_limit', 'overloaded', 'server_error']);
const MAX_RETRY_MINUTES = Math.floor(Number.MAX_SAFE_INTEGER / 60);

class ConfigurationError extends Error {}

function stripComment(line) {
  let quote = null;
  for (let index = 0; index < line.length; index += 1) {
    const char = line[index];
    if (quote) {
      if (char === quote && line[index - 1] !== '\\') quote = null;
    } else if (char === '"' || char === "'") {
      quote = char;
    } else if (char === '#') {
      return line.slice(0, index);
    }
  }
  if (quote) throw new ConfigurationError('unterminated quoted value');
  return line;
}

function parseStringScalar(raw, lineNumber) {
  const value = raw.trim();
  if (!value) throw new ConfigurationError(`line ${lineNumber}: missing value`);

  if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
    const quote = value[0];
    const inner = value.slice(1, -1);
    if (quote === '"') {
      try {
        return JSON.parse(value);
      } catch (error) {
        throw new ConfigurationError(`line ${lineNumber}: invalid quoted value`);
      }
    }
    return inner.replace(/''/g, "'");
  }

  if (/[[\]{}:,]/.test(value)) {
    throw new ConfigurationError(`line ${lineNumber}: invalid scalar value`);
  }
  return value;
}

function parseFlowList(raw, lineNumber) {
  const value = raw.trim();
  if (!value.startsWith('[') || !value.endsWith(']')) {
    throw new ConfigurationError(`line ${lineNumber}: errors must be a YAML list`);
  }

  const inner = value.slice(1, -1).trim();
  if (!inner) return [];

  const items = [];
  let current = '';
  let quote = null;
  for (let index = 0; index < inner.length; index += 1) {
    const char = inner[index];
    if (quote) {
      current += char;
      if (char === quote && inner[index - 1] !== '\\') quote = null;
    } else if (char === '"' || char === "'") {
      quote = char;
      current += char;
    } else if (char === ',') {
      items.push(parseStringScalar(current, lineNumber));
      current = '';
    } else {
      current += char;
    }
  }
  if (quote) throw new ConfigurationError(`line ${lineNumber}: unterminated quoted value`);
  items.push(parseStringScalar(current, lineNumber));
  return items;
}

function validateConfig(values) {
  if (!Object.prototype.hasOwnProperty.call(values, 'errors')) {
    throw new ConfigurationError('missing required field "errors"');
  }
  if (!Object.prototype.hasOwnProperty.call(values, 'retry_minutes')) {
    throw new ConfigurationError('missing required field "retry_minutes"');
  }
  if (!Array.isArray(values.errors) || values.errors.length === 0) {
    throw new ConfigurationError('"errors" must be a non-empty list');
  }

  const errors = [];
  for (const errorName of values.errors) {
    if (!SUPPORTED_ERRORS.has(errorName)) {
      throw new ConfigurationError(`unsupported error name "${errorName}"`);
    }
    if (!errors.includes(errorName)) errors.push(errorName);
  }

  if (!Number.isSafeInteger(values.retry_minutes) ||
      values.retry_minutes < 1 ||
      values.retry_minutes > MAX_RETRY_MINUTES) {
    throw new ConfigurationError(
      `"retry_minutes" must be a positive whole number no greater than ${MAX_RETRY_MINUTES}`,
    );
  }

  return { errors, retry_minutes: values.retry_minutes };
}

function parseConfiguration(text) {
  const values = {};
  const lines = text.replace(/^\uFEFF/, '').split(/\r?\n/);
  let activeList = null;
  let activeListIndent = null;

  for (let index = 0; index < lines.length; index += 1) {
    const lineNumber = index + 1;
    const rawLine = lines[index];
    if (rawLine.includes('\t')) {
      throw new ConfigurationError(`line ${lineNumber}: tabs are not supported`);
    }

    const withoutComment = stripComment(rawLine).replace(/\s+$/, '');
    if (!withoutComment.trim()) continue;

    const listMatch = withoutComment.match(/^( +)-\s*(.+)$/);
    if (listMatch) {
      if (activeList !== 'errors') {
        throw new ConfigurationError(`line ${lineNumber}: unexpected list item`);
      }
      const indent = listMatch[1].length;
      if (activeListIndent === null) activeListIndent = indent;
      if (indent !== activeListIndent) {
        throw new ConfigurationError(`line ${lineNumber}: inconsistent list indentation`);
      }
      values.errors.push(parseStringScalar(listMatch[2], lineNumber));
      continue;
    }

    if (/^\s/.test(withoutComment)) {
      throw new ConfigurationError(`line ${lineNumber}: invalid indentation`);
    }

    activeList = null;
    activeListIndent = null;
    const keyMatch = withoutComment.match(/^([A-Za-z_][A-Za-z0-9_-]*):(?:\s*(.*))?$/);
    if (!keyMatch) throw new ConfigurationError(`line ${lineNumber}: expected "key: value"`);

    const key = keyMatch[1];
    const rawValue = keyMatch[2] || '';
    if (key !== 'errors' && key !== 'retry_minutes') {
      throw new ConfigurationError(`unknown field "${key}"`);
    }
    if (Object.prototype.hasOwnProperty.call(values, key)) {
      throw new ConfigurationError(`duplicate field "${key}"`);
    }

    if (key === 'errors') {
      if (!rawValue.trim()) {
        values.errors = [];
        activeList = 'errors';
        activeListIndent = null;
      } else {
        values.errors = parseFlowList(rawValue, lineNumber);
      }
    } else {
      const scalar = rawValue.trim();
      if (!/^[0-9]+$/.test(scalar)) {
        throw new ConfigurationError(`line ${lineNumber}: "retry_minutes" must be a positive whole number`);
      }
      values.retry_minutes = Number(scalar);
    }
  }

  return validateConfig(values);
}

function loadConfiguration(projectDir) {
  const file = path.join(projectDir, 'session-recover.yaml');
  if (!fs.existsSync(file)) {
    return {
      config: {
        errors: [...DEFAULT_CONFIG.errors],
        retry_minutes: DEFAULT_CONFIG.retry_minutes,
      },
      file,
      source: 'defaults',
    };
  }

  let text;
  try {
    text = fs.readFileSync(file, 'utf8');
  } catch (error) {
    throw new ConfigurationError(`cannot read ${file}: ${error.message}`);
  }

  try {
    return { config: parseConfiguration(text), file, source: 'yaml' };
  } catch (error) {
    if (error instanceof ConfigurationError) {
      throw new ConfigurationError(`${file}: ${error.message}`);
    }
    throw error;
  }
}

function parseJsonObject(raw, description) {
  let value;
  try {
    value = JSON.parse(raw);
  } catch (error) {
    throw new Error(`${description}: ${error.message}`);
  }
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(`${description}: expected a JSON object`);
  }
  return value;
}

function readMarker(markerPath) {
  try {
    return parseJsonObject(fs.readFileSync(markerPath, 'utf8'), 'invalid recovery marker');
  } catch (_) {
    return null;
  }
}

function validRateLimitReset(rateLimitState, now) {
  if (!rateLimitState || typeof rateLimitState !== 'object' || Array.isArray(rateLimitState)) {
    return null;
  }
  const reset = rateLimitState.five_hour_resets_at;
  const cached = rateLimitState.cached_at;
  const maxAge = 21600;
  if (!Number.isInteger(reset) || !Number.isInteger(cached)) return null;
  if (reset <= now) return null;
  if (cached > now) return null;
  if (now - cached > maxAge) return null;
  if (reset - cached <= 0 || reset - cached > maxAge) return null;
  return reset;
}

function clearMarker(projectDir) {
  const markerPath = path.join(projectDir, '.claude', 'quota-blocked.json');
  try { fs.unlinkSync(markerPath); } catch (_) {}
}

function checkMarker(projectDir) {
  const markerPath = path.join(projectDir, '.claude', 'quota-blocked.json');
  if (!fs.existsSync(markerPath)) return 'NONE';

  const marker = readMarker(markerPath);
  if (!marker) return 'NONE';

  const error = marker.hook_input && marker.hook_input.error;
  if (!SUPPORTED_ERRORS.has(error)) return 'NONE';

  let retrySeconds = marker.recovery && marker.recovery.retry_seconds;
  if (!Number.isSafeInteger(retrySeconds) || retrySeconds <= 0) retrySeconds = 1200;

  let baseSeconds;
  try {
    baseSeconds = Math.floor(fs.statSync(markerPath).mtimeMs / 1000);
  } catch (_) {
    return 'NONE';
  }

  const now = Math.floor(Date.now() / 1000);
  let target = baseSeconds + retrySeconds;
  if (error === 'rate_limit') {
    const reset = validRateLimitReset(marker.rate_limit_state, now);
    if (reset !== null) target = reset;
  }

  if (now >= target) return `READY ${error}`;
  return `WAIT ${Math.ceil(target - now)} ${error}`;
}

function removeMarkerForSession(markerPath, sessionId) {
  if (!sessionId || !fs.existsSync(markerPath)) return false;
  const marker = readMarker(markerPath);
  if (!marker || !marker.hook_input || marker.hook_input.session_id !== sessionId) return false;
  try {
    fs.unlinkSync(markerPath);
    return true;
  } catch (_) {
    return false;
  }
}

function readRateLimitState(statePath, report) {
  if (!fs.existsSync(statePath)) return null;
  try {
    return parseJsonObject(fs.readFileSync(statePath, 'utf8'), 'invalid cached rate-limit state');
  } catch (error) {
    report(`Ignoring malformed cached rate-limit state ${statePath}: ${error.message}`);
    return null;
  }
}

function atomicWriteJson(file, value) {
  const temporary = `${file}.tmp-${process.pid}-${Date.now()}`;
  fs.writeFileSync(temporary, `${JSON.stringify(value)}\n`, { mode: 0o600 });
  try {
    fs.renameSync(temporary, file);
  } catch (error) {
    try { fs.unlinkSync(temporary); } catch (_) {}
    throw error;
  }
}

function appendJsonLine(file, value) {
  fs.appendFileSync(file, `${JSON.stringify(value)}\n`);
}

function legacyTimestamp() {
  try {
    return execFileSync('date', ['+%Y-%m-%d %H:%M:%S %Z'], { encoding: 'utf8' }).trim();
  } catch (_) {
    return new Date().toISOString();
  }
}

function incidentToken(sessionId, errorType, incidentId) {
  const digest = crypto.createHash('sha256')
    .update(incidentId || `${sessionId || '<missing>'}\0${errorType || '<unknown>'}`)
    .digest('hex')
    .slice(0, 16);
  return `<!-- claude-code-stop-failure incident=${digest} -->`;
}

function failureDescription(errorType) {
  if (errorType === 'rate_limit') return 'a rate limit';
  if (errorType === 'overloaded') return 'an overloaded service';
  if (errorType === 'server_error') return 'a temporary server error';
  if (errorType) return `a non-retryable "${errorType}" error`;
  return 'an untyped API failure';
}

function appendHandoffNote(handoffPath, stamp, sessionId, errorType, enabled, incidentId) {
  if (!fs.existsSync(handoffPath)) return;
  const token = incidentToken(sessionId, errorType, incidentId);
  let text = '';
  try {
    text = fs.readFileSync(handoffPath, 'utf8');
  } catch (_) {
    return;
  }
  if (text.includes(token)) return;

  const recoveryLine = enabled
    ? 'Automatic recovery is enabled for this failure type.'
    : 'Automatic recovery is disabled for this failure type.';
  const note = [
    '',
    token,
    '',
    `Automatic note: Claude Code stopped with ${failureDescription(errorType)} at ${stamp}.`,
    'Raw hook input was saved to `.claude/stop-failure-events.jsonl`.',
    recoveryLine,
    'This hook cannot schedule a same-session resume by itself.',
    '',
  ].join('\n');

  try { fs.appendFileSync(handoffPath, note); } catch (_) {}
}

function runStopFailure(projectDir, rawInput, report = (message) => process.stderr.write(`${message}\n`)) {
  const claudeDir = path.join(projectDir, '.claude');
  const handoffPath = path.join(projectDir, 'HANDOFF.md');
  const logPath = path.join(claudeDir, 'stop-failure-events.jsonl');
  const markerPath = path.join(claudeDir, 'quota-blocked.json');
  const rateStatePath = path.join(claudeDir, 'rate-limit-state.json');
  const stamp = legacyTimestamp();

  fs.mkdirSync(claudeDir, { recursive: true });

  let hookInput = null;
  let inputError = null;
  try {
    hookInput = parseJsonObject(rawInput, 'invalid StopFailure JSON');
  } catch (error) {
    inputError = error;
  }

  let loaded = null;
  let configError = null;
  try {
    loaded = loadConfiguration(projectDir);
  } catch (error) {
    configError = error;
  }

  const logEntry = { logged_at: stamp, hook_input: hookInput };
  if (inputError) {
    logEntry.raw_input = rawInput;
    logEntry.input_error = inputError.message;
  }
  if (configError) logEntry.configuration_error = configError.message;
  try {
    appendJsonLine(logPath, logEntry);
  } catch (error) {
    report(`Could not append StopFailure log ${logPath}: ${error.message}`);
  }

  const sessionId = hookInput && typeof hookInput.session_id === 'string' && hookInput.session_id
    ? hookInput.session_id
    : null;
  const errorType = hookInput && typeof hookInput.error === 'string' ? hookInput.error : null;

  if (configError) {
    try { fs.unlinkSync(markerPath); } catch (_) {}
    report(`Invalid recovery configuration ${configError.message}`);
    if (hookInput) appendHandoffNote(handoffPath, stamp, sessionId, errorType, false);
    return { action: 'invalid_configuration' };
  }

  if (inputError) {
    report(inputError.message);
    return { action: 'logged_invalid_input' };
  }

  const enabled = SUPPORTED_ERRORS.has(errorType) && loaded.config.errors.includes(errorType);
  if (!enabled) {
    const removed = removeMarkerForSession(markerPath, sessionId);
    appendHandoffNote(handoffPath, stamp, sessionId, errorType, false);
    return { action: removed ? 'cancelled_existing_recovery' : 'logged_disabled_error' };
  }

  if (!sessionId) {
    report('StopFailure event has no session_id; recovery marker not created.');
    appendHandoffNote(handoffPath, stamp, null, errorType, false);
    return { action: 'missing_session_id' };
  }

  const rateLimitState = errorType === 'rate_limit'
    ? readRateLimitState(rateStatePath, report)
    : null;
  const previousMarker = readMarker(markerPath);
  const sameActiveIncident = Boolean(
    previousMarker &&
    previousMarker.hook_input &&
    previousMarker.hook_input.session_id === sessionId &&
    previousMarker.hook_input.error === errorType,
  );
  const incidentId = sameActiveIncident
    ? previousMarker.recovery && previousMarker.recovery.incident_id
      ? previousMarker.recovery.incident_id
      : `legacy:${previousMarker.logged_at || ''}:${sessionId}:${errorType}`
    : crypto.randomUUID();
  const marker = {
    logged_at: stamp,
    rate_limit_state: rateLimitState,
    hook_input: hookInput,
    recovery: {
      error: errorType,
      retry_minutes: loaded.config.retry_minutes,
      retry_seconds: loaded.config.retry_minutes * 60,
      configuration_source: loaded.source,
      incident_id: incidentId,
    },
  };

  atomicWriteJson(markerPath, marker);
  appendHandoffNote(handoffPath, stamp, sessionId, errorType, true, incidentId);
  return { action: 'recovery_marker_written', marker };
}

function main() {
  const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
  const mode = process.argv[2];

  if (mode === 'check') {
    process.stdout.write(`${checkMarker(projectDir)}\n`);
    return;
  }
  if (mode === 'clear') {
    clearMarker(projectDir);
    return;
  }

  let input = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (chunk) => { input += chunk; });
  process.stdin.on('end', () => {
    try {
      runStopFailure(projectDir, input);
    } catch (error) {
      process.stderr.write(`Session recovery hook failed: ${error.message}\n`);
    }
  });
}

if (require.main === module) main();

module.exports = {
  ConfigurationError,
  DEFAULT_CONFIG,
  MAX_RETRY_MINUTES,
  SUPPORTED_ERRORS,
  checkMarker,
  clearMarker,
  loadConfiguration,
  parseConfiguration,
  runStopFailure,
};
