// node --test tool/test/release_workflow.test.mjs
//
// Structural guarantees of .github/workflows/store-release.yml that a later
// edit must not quietly lose. The repository is public, so each of these is a
// leak or an injection if it regresses. Text-based on purpose: the check has
// to run with zero dependencies inside the preflight job.

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const workflow = readFileSync(new URL('../../.github/workflows/store-release.yml', import.meta.url), 'utf8');
const releaseDoc = readFileSync(new URL('../../docs/RELEASE_CI.md', import.meta.url), 'utf8');
const lines = workflow.split('\n');
const codeLines = lines.filter((line) => !/^\s*#/u.test(line));

const EXPECTED_SECRETS = [
  'ANDROID_UPLOAD_KEYSTORE_BASE64',
  'ANDROID_UPLOAD_KEY_PASSWORD',
  'PLAY_SERVICE_ACCOUNT_JSON',
  'ASC_KEY_ID',
  'ASC_ISSUER_ID',
  'ASC_PRIVATE_KEY_P8',
  'IOS_DIST_CERT_P12_BASE64',
  'IOS_DIST_CERT_P12_PASSWORD',
  'IOS_APPSTORE_PROFILE_BASE64',
];

const indentOf = (line) => line.length - line.trimStart().length;

// Every run: script body, block or inline.
function runBlocks() {
  const blocks = [];
  for (let index = 0; index < lines.length; index += 1) {
    const match = /^(\s*)(- )?run:(.*)$/u.exec(lines[index]);
    if (!match) continue;
    const keyIndent = match[1].length + (match[2] ? 2 : 0);
    const rest = match[3].trim();
    if (!/^[|>][-+]?$/u.test(rest)) {
      blocks.push({ line: index + 1, text: rest });
      continue;
    }
    const body = [];
    let cursor = index + 1;
    while (cursor < lines.length && (lines[cursor].trim() === '' || indentOf(lines[cursor]) > keyIndent)) {
      body.push(lines[cursor]);
      cursor += 1;
    }
    blocks.push({ line: index + 1, text: body.join('\n') });
  }
  return blocks;
}

function jobs() {
  const start = lines.findIndex((line) => line === 'jobs:');
  const result = new Map();
  let current = null;
  for (const line of lines.slice(start + 1)) {
    const match = /^ {2}([A-Za-z0-9_-]+):\s*$/u.exec(line);
    if (match) {
      current = match[1];
      result.set(current, []);
    } else if (current && !/^\s*#/u.test(line)) {
      result.get(current).push(line);
    }
  }
  return new Map([...result].map(([name, body]) => [name, body.join('\n')]));
}

test('it is dispatch-only', () => {
  const start = lines.indexOf('on:');
  const triggers = [];
  for (const line of lines.slice(start + 1)) {
    if (/^\S/u.test(line)) break;
    const match = /^ {2}([a-z_]+):/u.exec(line);
    if (match) triggers.push(match[1]);
  }
  assert.deepEqual(triggers, ['workflow_dispatch']);
});

test('no ${{ }} expression is interpolated into any run: script', () => {
  const blocks = runBlocks();
  assert.ok(blocks.length > 20, 'the run: parser found the scripts');
  for (const block of blocks) {
    assert.doesNotMatch(block.text, /\$\{\{/u, `run: at line ${block.line} interpolates an expression`);
  }
});

test('scripts never trace, never pass defines, never use the upload export options', () => {
  for (const block of runBlocks()) {
    assert.doesNotMatch(block.text, /\bset -[a-z]*x/u, `line ${block.line}`);
    assert.doesNotMatch(block.text, /--dart-define/u, `line ${block.line}`);
    assert.doesNotMatch(block.text, /ExportOptionsUpload/u, `line ${block.line}`);
    for (const line of block.text.split('\n')) {
      const touchesSecretValue = /\$\{?(?:KEYSTORE_BASE64|UPLOAD_KEY_PASSWORD|YOVOICE_UPLOAD_KEY_PASSWORD|PLAY_SERVICE_ACCOUNT_JSON|P12_BASE64|P12_PASSWORD|PROFILE_BASE64|ASC_PRIVATE_KEY_P8)\b/u.test(line);
      const persists = /GITHUB_(?:ENV|OUTPUT|STEP_SUMMARY)/u.test(line);
      assert.ok(!(touchesSecretValue && persists), `line ${block.line} writes a secret to a runner file: ${line.trim()}`);
    }
  }
});

test('every action is pinned to a full commit SHA', () => {
  const uses = codeLines.map((line) => /uses:\s*(\S+)/u.exec(line)).filter(Boolean);
  assert.ok(uses.length > 0);
  for (const [, reference] of uses) {
    assert.match(reference, /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_./-]+@[0-9a-f]{40}$/u, reference);
  }
});

test('no cache, no artifact, no third-party upload action', () => {
  const code = codeLines.join('\n');
  for (const forbidden of ['upload-artifact', 'download-artifact', 'actions/cache', 'setup-gradle', 'cache: true']) {
    assert.ok(!code.includes(forbidden), forbidden);
  }
  for (const line of codeLines.filter((entry) => /^\s*cache:/u.test(entry))) {
    assert.match(line.trim(), /^cache: false$/u);
  }
  const setupNode = codeLines.filter((line) => line.includes('actions/setup-node@')).length;
  const noPackageCache = codeLines.filter((line) => line.trim() === 'package-manager-cache: false').length;
  assert.equal(noPackageCache, setupNode);
  const checkouts = codeLines.filter((line) => line.includes('actions/checkout@')).length;
  const noCredentials = codeLines.filter((line) => line.trim() === 'persist-credentials: false').length;
  assert.equal(noCredentials, checkouts);
});

test('permissions default to none and only the tag job can write', () => {
  assert.ok(lines.includes('permissions: {}'));
  const all = jobs();
  for (const [name, body] of all) {
    assert.match(body, /\n {4}permissions:\n/u, `${name} declares its permissions`);
    if (name === 'record') {
      assert.match(body, /contents: write/u);
      assert.ok(!body.includes('secrets.'), 'the tag job holds no secret');
      assert.ok(!body.includes('actions/checkout'), 'the tag job runs no repository code');
    } else {
      assert.ok(!/: write/u.test(body), `${name} must not write`);
    }
  }
});

test('dry-run jobs reference no secret and no environment', () => {
  const all = jobs();
  for (const name of ['android_dry_run', 'ios_dry_run']) {
    const body = all.get(name);
    assert.ok(body, name);
    assert.ok(!body.includes('secrets.'), `${name} references a secret`);
    assert.ok(!body.includes('environment:'), `${name} names an environment`);
    assert.match(body, /if: \$\{\{ inputs\.dry_run && /u);
  }
});

test('secrets appear only in the two store-release jobs, which run only for real releases from main', () => {
  const all = jobs();
  const used = new Set();
  for (const [name, body] of all) {
    for (const match of body.matchAll(/secrets\.([A-Z0-9_]+)/gu)) used.add(match[1]);
    if (!body.includes('secrets.')) continue;
    assert.ok(['android', 'ios'].includes(name), `${name} uses a secret`);
    assert.match(body, /\n {4}environment: store-release\n/u);
    assert.match(body, /!inputs\.dry_run && github\.ref == 'refs\/heads\/main'/u);
  }
  assert.deepEqual([...used].sort(), [...EXPECTED_SECRETS].sort());
});

test('release tooling runs from the workflow commit, the app from ref', () => {
  const all = jobs();
  for (const name of ['android', 'ios', 'android_dry_run']) {
    const body = all.get(name);
    assert.match(body, /path: tooling\n\s+sparse-checkout: tool\/release/u, name);
    assert.match(body, /ref: \$\{\{ needs\.preflight\.outputs\.sha \}\}\n\s+path: app/u, name);
    assert.ok(!/node app\//u.test(body), `${name} runs tooling from the app checkout`);
  }
});

test('every secret the workflow reads is documented with its exact name', () => {
  for (const name of EXPECTED_SECRETS) {
    assert.ok(releaseDoc.includes(`\`${name}\``), `docs/RELEASE_CI.md documents ${name}`);
  }
  assert.ok(releaseDoc.includes('store-release'));
});
