// ponytail — OpenCode plugin (self-contained)
// Injects the ponytail frugality ladder into every chat's system prompt
// and persists /ponytail mode switches. No external dependencies.
// OpenCode loads this as a server plugin:
//   { "plugin": ["./.opencode/plugins/ponytail.mjs"] }
import path from 'node:path';
import fs from 'node:fs';
import os from 'node:os';

// ── Intensity Modes ──
// off   = disabled
// lite  = brief reminder (1-rung: YAGNI check)
// full  = full 6-rung ladder + rules (default)
// ultra = full ladder + strict enforcement + perfectionism check

const VALID_MODES = new Set(['off', 'lite', 'full', 'ultra']);
const DEFAULT_MODE = 'full';

function getDefaultMode() {
  return DEFAULT_MODE;
}

function normalizePersistedMode(mode) {
  if (mode && VALID_MODES.has(mode.toLowerCase())) {
    return mode.toLowerCase();
  }
  return DEFAULT_MODE;
}

function getPonytailInstructions(mode) {
  const ladder = [
    '1. Does this need to exist?       → skip it (YAGNI)',
    '2. Standard library does it?      → use it',
    '3. Native platform feature?       → use it',
    '4. Already-installed dependency?  → use it',
    '5. Can this be one line?          → one line',
    '6. Only then: minimum code that works',
  ].join('\n');

  const rules = [
    'No unsolicited abstractions.',
    'No new dependencies unless unavoidable.',
    'Deletion > addition. Boring > clever. Fewest files possible.',
    'Mark intentional shortcuts with ponytail: comments (ceiling + upgrade path).',
    'Not sacrificed: input validation, data-loss error handling, security, accessibility.',
    'Non-trivial logic leaves ONE runnable check (assert-based, no test framework).',
  ].map(r => `- ${r}`).join('\n');

  if (mode === 'lite') {
    return [
      '## Ponytail (lite)',
      'Before writing code, ask: does this need to exist? Could existing code do it?',
      '',
    ].join('\n');
  }
  if (mode === 'ultra') {
    return [
      '## Ponytail (ultra)',
      '### 6-Rung Frugality Ladder',
      ladder,
      '',
      '### Rules (strict)',
      rules,
      '',
      '### Pre-commit checklist',
      '- Can any file be eliminated entirely?',
      '- Is every abstraction justified?',
      '- Could any dependency be removed?',
      '- Is there a simpler design I rejected? Why?',
      '',
      'Perfectionism check: would this be "good enough" in prod 3 months from now?',
      '',
    ].join('\n');
  }
  // full (default)
  return [
    '## Ponytail (frugality)',
    '### 6-Rung Frugality Ladder',
    'Run this ladder before writing ANY code:',
    '',
    '```',
    ladder,
    '```',
    '',
    '### Rules',
    rules,
    '',
  ].join('\n');
}

// ── Plugin State ──
const statePath = path.join(
  process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config'),
  '.ponytail-active'
);

function readMode() {
  try {
    const raw = fs.readFileSync(statePath, 'utf8').trim();
    return normalizePersistedMode(raw);
  } catch {
    return getDefaultMode();
  }
}

function writeMode(mode) {
  fs.mkdirSync(path.dirname(statePath), { recursive: true });
  fs.writeFileSync(statePath, mode);
}

// ── Plugin Export ──
export default async ({ client } = {}) => {
  const log = (level, msg) => {
    try {
      if (client?.app?.log) {
        client.app.log({ body: { service: 'ponytail', level, msg } });
      }
    } catch { /* ignore */ }
  };

  // Track active mode (starts from persisted state)
  let activeMode = readMode();

  return {
    // Inject ponytail ruleset into system prompt every turn
    'experimental.chat.system.transform': async (_input, output) => {
      if (activeMode === 'off') return;
      output.system.push(getPonytailInstructions(activeMode));
    },

    // Handle /ponytail <mode> persistence
    'cmd.execute.before': async (input) => {
      if (!input || input.cmd !== 'ponytail') return;
      const arg = (input.arguments || '').trim();
      const mode = normalizePersistedMode(arg);
      activeMode = mode;
      writeMode(mode);
      log('info', 'ponytail mode set to ' + mode);
    },
  };
};
//
