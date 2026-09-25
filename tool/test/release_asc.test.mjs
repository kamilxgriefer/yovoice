// node --test tool/test/release_asc.test.mjs
//
// App Store Connect checks around the altool upload: the ES256 token, the
// duplicate-build refusal and the processing poll, against a mocked fetch.

import assert from 'node:assert/strict';
import { generateKeyPairSync, verify } from 'node:crypto';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { describe, test } from 'node:test';

import {
  ASC_AUDIENCE,
  ASC_TOKEN_LIFETIME_SECONDS,
  assertBuildFree,
  buildsUrl,
  main,
  makeAscToken,
  timeoutVerdict,
  waitValid,
} from '../release/asc.mjs';

const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
const PRIVATE_PEM = privateKey.export({ type: 'pkcs8', format: 'pem' });
const ISSUER = '69a6de7e-0000-47e3-e053-5b8c7c11a4d1';

const reply = (status, body) => ({
  status,
  ok: status >= 200 && status < 300,
  text: async () => JSON.stringify(body),
});
const builds = (...entries) =>
  reply(200, {
    data: entries.map(([id, version, processingState]) => ({ id, type: 'builds', attributes: { version, processingState } })),
  });

function ascServer(responses) {
  const calls = [];
  const queue = [...responses];
  const fetchImpl = async (url, options = {}) => {
    calls.push({ url, headers: options.headers ?? {} });
    const next = queue.length > 1 ? queue.shift() : queue[0];
    return typeof next === 'function' ? next(url) : next;
  };
  return { fetchImpl, calls };
}

let tokens = 0;
const tokenFactory = () => {
  tokens += 1;
  return `token-${tokens}`;
};

describe('makeAscToken', () => {
  test('signs an ES256 token Apple accepts: kid, issuer, audience, at most 20 minutes', () => {
    const token = makeAscToken({ privateKeyPem: PRIVATE_PEM, keyId: 'ABCDE12345', issuerId: ISSUER, now: () => 1_800_000_000_000 });
    const [header, payload, signature] = token.split('.');
    const decode = (part) => JSON.parse(Buffer.from(part, 'base64url').toString('utf8'));
    assert.deepEqual(decode(header), { kid: 'ABCDE12345', alg: 'ES256', typ: 'JWT' });
    const claims = decode(payload);
    assert.deepEqual(claims, { iss: ISSUER, iat: 1_800_000_000, exp: 1_800_001_200, aud: ASC_AUDIENCE });
    assert.ok(claims.exp - claims.iat <= 1200 && ASC_TOKEN_LIFETIME_SECONDS === 1200);
    const raw = Buffer.from(signature, 'base64url');
    assert.equal(raw.length, 64, 'JOSE ES256 signatures are raw r||s, not DER');
    assert.ok(verify('sha256', Buffer.from(`${header}.${payload}`), { key: publicKey, dsaEncoding: 'ieee-p1363' }, raw));
  });
});

test('buildsUrl filters by app and build number, and by version train when given', () => {
  const url = new URL(buildsUrl({ appId: '6801898909', buildNumber: 36, versionName: '3.0.0' }));
  assert.equal(url.origin + url.pathname, 'https://api.appstoreconnect.apple.com/v1/builds');
  assert.equal(url.searchParams.get('filter[app]'), '6801898909');
  assert.equal(url.searchParams.get('filter[version]'), '36');
  assert.equal(url.searchParams.get('filter[preReleaseVersion.version]'), '3.0.0');
  assert.equal(new URL(buildsUrl({ appId: '1', buildNumber: 2 })).searchParams.has('filter[preReleaseVersion.version]'), false);
});

describe('assertBuildFree', () => {
  test('passes when the number is unused, with a bearer token', async () => {
    const server = ascServer([builds()]);
    await assertBuildFree({ fetchImpl: server.fetchImpl, tokenFactory, appId: '6801898909', buildNumber: '36' });
    assert.match(server.calls[0].headers.Authorization, /^Bearer token-\d+$/u);
  });

  test('refuses a build number that already exists, in any state', async () => {
    for (const state of ['PROCESSING', 'VALID', 'INVALID']) {
      const server = ascServer([builds(['b1', '36', state])]);
      await assert.rejects(
        assertBuildFree({ fetchImpl: server.fetchImpl, tokenFactory, appId: '6801898909', buildNumber: '36' }),
        /already exists in App Store Connect/u,
      );
    }
  });

  test('fails closed when the API refuses the key', async () => {
    const server = ascServer([reply(401, { errors: [{ title: 'Authentication credentials are missing or invalid.' }] })]);
    await assert.rejects(
      assertBuildFree({ fetchImpl: server.fetchImpl, tokenFactory, appId: '6801898909', buildNumber: '36' }),
      /HTTP 401: Authentication credentials/u,
    );
  });
});

describe('waitValid', () => {
  const clock = () => {
    let time = 0;
    return { now: () => time, pause: async (ms) => { time += ms; } };
  };
  const options = (server, time, overrides = {}) => ({
    fetchImpl: server.fetchImpl,
    tokenFactory,
    appId: '6801898909',
    buildNumber: '36',
    versionName: '3.0.0',
    timeoutMs: 45 * 60_000,
    intervalMs: 60_000,
    now: time.now,
    pause: time.pause,
    ...overrides,
  });

  test('waits through not-visible and PROCESSING until VALID, with a fresh token per poll', async () => {
    const server = ascServer([builds(), builds(['b1', '36', 'PROCESSING']), builds(['b1', '36', 'VALID'])]);
    const before = tokens;
    const result = await waitValid(options(server, clock()));
    assert.deepEqual(result, { state: 'VALID', id: 'b1', attempts: 3 });
    assert.equal(tokens - before, 3);
  });

  test('fails on INVALID or FAILED processing', async () => {
    for (const state of ['INVALID', 'FAILED']) {
      const server = ascServer([builds(['b1', '36', state])]);
      await assert.rejects(waitValid(options(server, clock())), new RegExp(`ended ${state}`, 'u'));
    }
  });

  test('stops at the budget and reports a timeout instead of failing', async () => {
    const server = ascServer([builds(['b1', '36', 'PROCESSING'])]);
    const result = await waitValid(options(server, clock(), { timeoutMs: 5 * 60_000 }));
    assert.equal(result.state, 'TIMEOUT');
    assert.equal(result.lastSeen, 'PROCESSING');
    // Polls at 0, 1, 2, 3, 4 and 5 minutes; the next would pass the budget.
    assert.equal(result.attempts, 6);
  });

  test('a timeout remembers whether the build was ever visible', async () => {
    const processing = await waitValid(
      options(ascServer([builds(), builds(['b1', '36', 'PROCESSING'])]), clock(), { timeoutMs: 3 * 60_000 }),
    );
    assert.equal(processing.state, 'TIMEOUT');
    assert.equal(processing.seen, true);
    assert.equal(processing.id, 'b1');

    const never = await waitValid(options(ascServer([builds(['b0', '35', 'VALID'])]), clock(), { timeoutMs: 3 * 60_000 }));
    assert.equal(never.state, 'TIMEOUT');
    assert.equal(never.lastSeen, 'NOT_VISIBLE_YET');
    assert.equal(never.seen, false);
    assert.equal(never.id, null);
  });

  test('ignores builds with another number in the answer', async () => {
    const server = ascServer([builds(['b0', '35', 'VALID']), builds(['b1', '36', 'VALID'])]);
    const result = await waitValid(options(server, clock()));
    assert.equal(result.id, 'b1');
    assert.equal(result.attempts, 2);
  });
});

describe('timeoutVerdict', () => {
  const context = { buildNumber: '36', timeoutMinutes: 45 };

  test('VALID is neither a warning nor a failure', () => {
    assert.deepEqual(timeoutVerdict({ state: 'VALID', id: 'b1', attempts: 3 }, context), { fail: false, message: null });
  });

  test('a build seen processing at the deadline only warns: it is uploaded and its number is consumed', () => {
    const verdict = timeoutVerdict({ state: 'TIMEOUT', lastSeen: 'PROCESSING', id: 'b1', attempts: 46, seen: true }, context);
    assert.equal(verdict.fail, false);
    assert.match(verdict.message, /not VALID within 45 min \(last seen PROCESSING\)/u);
  });

  test('a build that never appeared fails the step, so the release is not tagged', () => {
    const verdict = timeoutVerdict(
      { state: 'TIMEOUT', lastSeen: 'NOT_VISIBLE_YET', id: null, attempts: 46, seen: false },
      context,
    );
    assert.equal(verdict.fail, true);
    assert.match(verdict.message, /never appeared in App Store Connect/u);
    assert.match(verdict.message, /not tagged/u);
    assert.match(verdict.message, /never re-upload blindly/u);
  });
});

describe('wait-valid command', () => {
  test('fails the step when the build never appeared, after writing the summary', async () => {
    const scratch = mkdtempSync(path.join(tmpdir(), 'yovoice-asc-test-'));
    const savedSummary = process.env.GITHUB_STEP_SUMMARY;
    process.env.GITHUB_STEP_SUMMARY = path.join(scratch, 'summary.md');
    try {
      const keyFile = path.join(scratch, 'AuthKey_ABCDE12345.p8');
      writeFileSync(keyFile, PRIVATE_PEM);
      const server = ascServer([builds()]);
      // An interval longer than the budget: exactly one poll, then the deadline.
      await assert.rejects(
        main(
          [
            'wait-valid',
            '--key-file', keyFile,
            '--key-id', 'ABCDE12345',
            '--issuer-id', ISSUER,
            '--app-id', '6801898909',
            '--build-number', '36',
            '--version-name', '3.0.0',
            '--timeout-minutes', '1',
            '--interval-seconds', '120',
          ],
          { fetchImpl: server.fetchImpl },
        ),
        /never appeared in App Store Connect/u,
      );
      assert.equal(server.calls.length, 1);
      assert.match(readFileSync(process.env.GITHUB_STEP_SUMMARY, 'utf8'), /NEVER SEEN in App Store Connect/u);
    } finally {
      if (savedSummary === undefined) delete process.env.GITHUB_STEP_SUMMARY;
      else process.env.GITHUB_STEP_SUMMARY = savedSummary;
      rmSync(scratch, { recursive: true, force: true });
    }
  });
});
