// node --test tool/test/release_play.test.mjs
//
// The Play Developer API upload, against a mocked fetch: the call order, the
// refusals that must stop a release before the commit, the single upload
// attempt, and that no credential reaches a log line.

import assert from 'node:assert/strict';
import { createHash, generateKeyPairSync, verify } from 'node:crypto';
import { describe, test } from 'node:test';

import {
  GOOGLE_TOKEN_URL,
  PLAY_SCOPE,
  getAccessToken,
  parseServiceAccount,
  publishBundle,
} from '../release/play.mjs';

const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const PRIVATE_PEM = privateKey.export({ type: 'pkcs8', format: 'pem' });
const ACCESS_TOKEN = 'ya29.test-access-token';
const AAB = Buffer.from('pretend this is a signed app bundle');
const AAB_SHA256 = createHash('sha256').update(AAB).digest('hex');

const serviceAccountJson = (overrides = {}) =>
  JSON.stringify({
    type: 'service_account',
    client_email: 'yovoice-play-release@example.iam.gserviceaccount.com',
    private_key: PRIVATE_PEM,
    private_key_id: 'key-1',
    token_uri: GOOGLE_TOKEN_URL,
    ...overrides,
  });

const reply = (status, body) => ({
  status,
  ok: status >= 200 && status < 300,
  text: async () => (body === undefined ? '' : JSON.stringify(body)),
});

function classify(url, method) {
  if (url === GOOGLE_TOKEN_URL) return 'token';
  if (method === 'DELETE') return 'delete';
  if (url.includes('/upload/')) return 'upload';
  if (url.includes(':commit')) return 'commit';
  if (url.includes('/tracks/')) return method === 'PUT' ? 'trackUpdate' : 'trackGet';
  if (url.endsWith('/bundles')) return 'list';
  if (url.endsWith('/edits') && method === 'POST') return 'insert';
  return 'unknown';
}

function playServer(overrides = {}) {
  const calls = [];
  let edits = 0;
  const handlers = {
    token: () => reply(200, { access_token: ACCESS_TOKEN, expires_in: 3600 }),
    insert: () => reply(200, { id: `edit-${(edits += 1)}` }),
    list: () => reply(200, { bundles: [{ versionCode: 34 }, { versionCode: 35 }] }),
    upload: () => reply(200, { versionCode: 36, sha256: AAB_SHA256, sha1: 'x' }),
    trackUpdate: (call) => reply(200, JSON.parse(call.body)),
    commit: () => reply(200, { id: 'edit-1' }),
    trackGet: () => reply(200, { track: 'internal', releases: [{ versionCodes: ['36'], status: 'draft' }] }),
    delete: () => reply(204),
    ...overrides,
  };
  const fetchImpl = async (url, options = {}) => {
    const method = options.method ?? 'GET';
    const call = { kind: classify(url, method), url, method, headers: options.headers ?? {}, body: options.body };
    calls.push(call);
    const handler = handlers[call.kind];
    if (!handler) throw new Error(`Unexpected request ${method} ${url}`);
    return handler(call, calls);
  };
  return { fetchImpl, calls, kinds: () => calls.map((call) => call.kind) };
}

const publish = (server, overrides = {}, logs = []) =>
  publishBundle({
    fetchImpl: server.fetchImpl,
    accessToken: ACCESS_TOKEN,
    packageName: 'app.yovoice',
    aabBytes: AAB,
    versionCode: '36',
    versionName: '3.0.0',
    track: 'internal',
    status: 'draft',
    log: (line) => logs.push(line),
    ...overrides,
  });

describe('service account and token', () => {
  test('parseServiceAccount refuses anything but a Google service-account key', () => {
    assert.throws(() => parseServiceAccount('not json'), /not valid JSON/u);
    assert.throws(() => parseServiceAccount(serviceAccountJson({ type: 'authorized_user' })), /not a service-account/u);
    assert.throws(
      () => parseServiceAccount(serviceAccountJson({ token_uri: 'https://evil.example/token' })),
      /unexpected token_uri/u,
    );
    assert.equal(parseServiceAccount(serviceAccountJson()).privateKeyId, 'key-1');
  });

  test('exchanges a correctly signed RS256 assertion for the androidpublisher scope', async () => {
    const server = playServer();
    const token = await getAccessToken({
      fetchImpl: server.fetchImpl,
      serviceAccount: parseServiceAccount(serviceAccountJson()),
      now: () => 1_800_000_000_000,
    });
    assert.equal(token, ACCESS_TOKEN);
    assert.equal(server.calls.length, 1);
    const [call] = server.calls;
    assert.equal(call.method, 'POST');
    const form = new URLSearchParams(call.body);
    assert.equal(form.get('grant_type'), 'urn:ietf:params:oauth:grant-type:jwt-bearer');
    const [header, payload, signature] = form.get('assertion').split('.');
    const decode = (part) => JSON.parse(Buffer.from(part, 'base64url').toString('utf8'));
    assert.deepEqual(decode(header), { kid: 'key-1', alg: 'RS256', typ: 'JWT' });
    assert.deepEqual(decode(payload), {
      iss: 'yovoice-play-release@example.iam.gserviceaccount.com',
      scope: PLAY_SCOPE,
      aud: GOOGLE_TOKEN_URL,
      iat: 1_800_000_000,
      exp: 1_800_003_600,
    });
    assert.ok(verify('sha256', Buffer.from(`${header}.${payload}`), publicKey, Buffer.from(signature, 'base64url')));
  });

  test('a failed exchange reports the status without the assertion', async () => {
    const server = playServer({ token: () => reply(400, { error: 'invalid_grant', error_description: 'Invalid JWT' }) });
    await assert.rejects(
      getAccessToken({ fetchImpl: server.fetchImpl, serviceAccount: parseServiceAccount(serviceAccountJson()) }),
      (error) => {
        assert.match(error.message, /HTTP 400: Invalid JWT/u);
        assert.doesNotMatch(error.message, /eyJ/u);
        return true;
      },
    );
  });
});

describe('publishBundle', () => {
  test('uploads, assigns the internal track, commits and reads back, in that order', async () => {
    const server = playServer();
    const logs = [];
    const result = await publish(server, {}, logs);
    assert.deepEqual(server.kinds(), ['insert', 'list', 'upload', 'trackUpdate', 'commit', 'insert', 'trackGet', 'delete']);
    const upload = server.calls[2];
    assert.equal(upload.headers['Content-Type'], 'application/octet-stream');
    assert.match(upload.url, /\/upload\/androidpublisher\/v3\/applications\/app\.yovoice\/edits\/edit-1\/bundles\?uploadType=media$/u);
    assert.equal(upload.body, AAB);
    assert.deepEqual(JSON.parse(server.calls[3].body), {
      track: 'internal',
      releases: [{ name: '36 (3.0.0)', versionCodes: ['36'], status: 'draft' }],
    });
    assert.match(server.calls[3].url, /\/edits\/edit-1\/tracks\/internal$/u);
    assert.match(server.calls[4].url, /\/edits\/edit-1:commit$/u);
    assert.match(server.calls[7].url, /\/edits\/edit-2$/u);
    for (const call of server.calls) assert.equal(call.headers.Authorization, `Bearer ${ACCESS_TOKEN}`);
    assert.deepEqual(result, {
      editId: 'edit-1',
      versionCode: '36',
      sha256: AAB_SHA256,
      track: 'internal',
      status: 'draft',
      sentForReview: true,
    });
    assert.ok(logs.every((line) => !line.includes(ACCESS_TOKEN)));
  });

  test('refuses a versionCode Play already has, before uploading anything', async () => {
    const server = playServer({ list: () => reply(200, { bundles: [{ versionCode: 36 }] }) });
    await assert.rejects(publish(server), /already in Play/u);
    assert.deepEqual(server.kinds(), ['insert', 'list', 'delete']);
  });

  test('never retries a failed upload and deletes the edit', async () => {
    const server = playServer({ upload: () => reply(500, { error: { message: 'Backend Error' } }) });
    await assert.rejects(publish(server), /bundles\.upload failed: HTTP 500: Backend Error/u);
    assert.deepEqual(server.kinds(), ['insert', 'list', 'upload', 'delete']);
  });

  test('refuses when Play parsed a different versionCode or hash', async () => {
    const wrongCode = playServer({ upload: () => reply(200, { versionCode: 35, sha256: AAB_SHA256 }) });
    await assert.rejects(publish(wrongCode), /parsed versionCode 35/u);
    assert.deepEqual(wrongCode.kinds(), ['insert', 'list', 'upload', 'delete']);

    const wrongHash = playServer({ upload: () => reply(200, { versionCode: 36, sha256: 'f'.repeat(64) }) });
    await assert.rejects(publish(wrongHash), /different SHA-256/u);
    assert.deepEqual(wrongHash.kinds(), ['insert', 'list', 'upload', 'delete']);
  });

  test('commits once more with changesNotSentForReview only when Play asks for it', async () => {
    const server = playServer({
      commit: (call) =>
        call.url.includes('changesNotSentForReview=true')
          ? reply(200, { id: 'edit-1' })
          : reply(400, {
              error: {
                message:
                  'Changes cannot be sent for review automatically. Please set the query parameter changesNotSentForReview to true.',
              },
            }),
    });
    const result = await publish(server);
    assert.equal(result.sentForReview, false);
    assert.deepEqual(server.kinds(), [
      'insert',
      'list',
      'upload',
      'trackUpdate',
      'commit',
      'commit',
      'insert',
      'trackGet',
      'delete',
    ]);
  });

  test('any other commit failure is final and deletes the edit', async () => {
    const server = playServer({ commit: () => reply(403, { error: { message: 'The caller does not have permission' } }) });
    await assert.rejects(publish(server), /edits\.commit failed: HTTP 403/u);
    assert.deepEqual(server.kinds(), ['insert', 'list', 'upload', 'trackUpdate', 'commit', 'delete']);
  });

  test('a commit that does not read back is reported, and the read edit is still deleted', async () => {
    const server = playServer({ trackGet: () => reply(200, { track: 'internal', releases: [{ versionCodes: ['35'] }] }) });
    await assert.rejects(publish(server), /Committed, but versionCode 36 is not on the internal track/u);
    assert.equal(server.kinds().at(-1), 'delete');
  });

  test('only the internal track and the draft/completed statuses are reachable', async () => {
    for (const track of ['production', 'alpha', 'beta']) {
      const server = playServer();
      await assert.rejects(publish(server, { track }), /not allowed from CI/u);
      assert.equal(server.calls.length, 0);
    }
    for (const status of ['inProgress', 'halted', '']) {
      const server = playServer();
      await assert.rejects(publish(server, { status }), /not allowed/u);
      assert.equal(server.calls.length, 0);
    }
  });
});
