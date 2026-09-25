// Uploads one signed Android App Bundle to a Google Play testing track through
// the Play Developer API (androidpublisher v3), with no third-party code.
//
//   node play.mjs upload --service-account FILE --package app.yovoice \
//     --aab FILE --version-code 36 --version-name 3.0.0 --track internal --status draft
//
// Order, and why:
//   1. edits.insert
//   2. bundles.list — refuse if this versionCode is already in Play
//      (versionCodes are never reusable, so a duplicate is always a mistake);
//   3. bundles.upload — ONE attempt, never retried; Play's answer must carry
//      the expected versionCode and the SHA-256 of the local file;
//   4. tracks.update — only the internal track is allowed from CI;
//   5. edits.commit — retried once with changesNotSentForReview=true only when
//      Play says that parameter is required (the edit is still uncommitted);
//   6. read back in a fresh edit that is then deleted.
// Any failure before the commit deletes the edit, so nothing reaches the track.

import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

import {
  ReleaseError,
  apiErrorMessage,
  appendSummary,
  parseArgs,
  requestJson,
  requireArg,
  runCli,
  signJwt,
} from './lib.mjs';

export const GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token';
export const PLAY_SCOPE = 'https://www.googleapis.com/auth/androidpublisher';
export const PLAY_API = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications';
export const PLAY_UPLOAD_API = 'https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications';
// Production and the other testing tracks are deliberately not reachable from CI.
export const ALLOWED_TRACKS = Object.freeze(['internal']);
export const ALLOWED_STATUSES = Object.freeze(['draft', 'completed']);

export function parseServiceAccount(text) {
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    throw new ReleaseError('PLAY_SERVICE_ACCOUNT_JSON is not valid JSON');
  }
  if (json?.type !== 'service_account' || !json.client_email || !json.private_key) {
    throw new ReleaseError('PLAY_SERVICE_ACCOUNT_JSON is not a service-account key');
  }
  // The assertion is only ever sent to Google's token endpoint, whatever the
  // file says, so a tampered key file cannot redirect it.
  if (json.token_uri && json.token_uri !== GOOGLE_TOKEN_URL) {
    throw new ReleaseError('PLAY_SERVICE_ACCOUNT_JSON has an unexpected token_uri');
  }
  return {
    clientEmail: String(json.client_email),
    privateKey: String(json.private_key),
    privateKeyId: json.private_key_id ? String(json.private_key_id) : undefined,
  };
}

export async function getAccessToken({ fetchImpl, serviceAccount, now = () => Date.now() }) {
  const issuedAt = Math.floor(now() / 1000);
  const assertion = signJwt({
    alg: 'RS256',
    header: serviceAccount.privateKeyId ? { kid: serviceAccount.privateKeyId } : {},
    payload: {
      iss: serviceAccount.clientEmail,
      scope: PLAY_SCOPE,
      aud: GOOGLE_TOKEN_URL,
      iat: issuedAt,
      exp: issuedAt + 3600,
    },
    privateKeyPem: serviceAccount.privateKey,
  });
  const result = await requestJson(fetchImpl, GOOGLE_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }).toString(),
  });
  if (!result.ok || typeof result.json?.access_token !== 'string') {
    throw new ReleaseError(`Google token exchange failed: ${apiErrorMessage(result)}`);
  }
  return result.json.access_token;
}

function needsNoReviewCommit(result) {
  return (result.status === 400 || result.status === 403) && /changesNotSentForReview/u.test(result.text ?? '');
}

export async function publishBundle({
  fetchImpl,
  accessToken,
  packageName,
  aabBytes,
  versionCode,
  versionName,
  track,
  status,
  log = () => {},
}) {
  if (!ALLOWED_TRACKS.includes(track)) throw new ReleaseError(`Track "${track}" is not allowed from CI`);
  if (!ALLOWED_STATUSES.includes(status)) throw new ReleaseError(`Release status "${status}" is not allowed`);
  const code = String(versionCode);
  const localSha256 = createHash('sha256').update(aabBytes).digest('hex');
  const base = `${PLAY_API}/${encodeURIComponent(packageName)}/edits`;
  const auth = { Authorization: `Bearer ${accessToken}` };
  const jsonHeaders = { ...auth, 'Content-Type': 'application/json' };

  const insert = await requestJson(fetchImpl, base, { method: 'POST', headers: jsonHeaders, body: '{}' });
  if (!insert.ok || typeof insert.json?.id !== 'string') {
    throw new ReleaseError(`Play edits.insert failed: ${apiErrorMessage(insert)}`);
  }
  const editId = insert.json.id;
  const edit = `${base}/${encodeURIComponent(editId)}`;
  log(`Play edit ${editId} opened`);

  let committed = false;
  let sentForReview = true;
  try {
    const list = await requestJson(fetchImpl, `${edit}/bundles`, { headers: auth });
    if (!list.ok) throw new ReleaseError(`Play bundles.list failed: ${apiErrorMessage(list)}`);
    const existing = (list.json?.bundles ?? []).some((bundle) => String(bundle.versionCode) === code);
    if (existing) {
      throw new ReleaseError(`versionCode ${code} is already in Play. Build numbers are never reusable; cut the next one.`);
    }

    log(`Uploading ${aabBytes.length} bytes (sha256 ${localSha256}); a failed upload is not retried`);
    const upload = await requestJson(
      fetchImpl,
      `${PLAY_UPLOAD_API}/${encodeURIComponent(packageName)}/edits/${encodeURIComponent(editId)}/bundles?uploadType=media`,
      { method: 'POST', headers: { ...auth, 'Content-Type': 'application/octet-stream' }, body: aabBytes },
    );
    if (!upload.ok) throw new ReleaseError(`Play bundles.upload failed: ${apiErrorMessage(upload)}`);
    const uploadedCode = String(upload.json?.versionCode ?? '');
    const uploadedSha256 = String(upload.json?.sha256 ?? '').toLowerCase();
    if (uploadedCode !== code) {
      throw new ReleaseError(`Play parsed versionCode ${uploadedCode || '(none)'} from the bundle, expected ${code}`);
    }
    if (uploadedSha256 !== localSha256) {
      throw new ReleaseError('Play reports a different SHA-256 than the local bundle; refusing to release it');
    }
    log(`Play accepted bundle ${uploadedCode}, sha256 matches`);

    const trackBody = {
      track,
      releases: [{ name: `${code} (${versionName})`, versionCodes: [code], status }],
    };
    const trackUpdate = await requestJson(fetchImpl, `${edit}/tracks/${encodeURIComponent(track)}`, {
      method: 'PUT',
      headers: jsonHeaders,
      body: JSON.stringify(trackBody),
    });
    if (!trackUpdate.ok) throw new ReleaseError(`Play tracks.update failed: ${apiErrorMessage(trackUpdate)}`);

    let commit = await requestJson(fetchImpl, `${edit}:commit`, { method: 'POST', headers: auth });
    if (needsNoReviewCommit(commit)) {
      log('Play asks for changesNotSentForReview=true; committing once more with it (the edit is still uncommitted)');
      sentForReview = false;
      commit = await requestJson(fetchImpl, `${edit}:commit?changesNotSentForReview=true`, {
        method: 'POST',
        headers: auth,
      });
    }
    if (!commit.ok) throw new ReleaseError(`Play edits.commit failed: ${apiErrorMessage(commit)}`);
    committed = true;
    log(`Play edit ${editId} committed`);
  } finally {
    if (!committed) {
      const removal = await requestJson(fetchImpl, edit, { method: 'DELETE', headers: auth }).catch(() => null);
      log(`Play edit ${editId} ${removal?.ok ? 'deleted' : 'could not be deleted (it expires on its own)'}; nothing was released`);
    }
  }

  // Read back from a fresh edit, which is deleted afterwards.
  const readInsert = await requestJson(fetchImpl, base, { method: 'POST', headers: jsonHeaders, body: '{}' });
  if (!readInsert.ok || typeof readInsert.json?.id !== 'string') {
    throw new ReleaseError(`Committed, but the read-back edit could not be opened: ${apiErrorMessage(readInsert)}`);
  }
  const readEdit = `${base}/${encodeURIComponent(readInsert.json.id)}`;
  try {
    const readTrack = await requestJson(fetchImpl, `${readEdit}/tracks/${encodeURIComponent(track)}`, { headers: auth });
    if (!readTrack.ok) {
      throw new ReleaseError(`Committed, but the ${track} track could not be read back: ${apiErrorMessage(readTrack)}`);
    }
    const release = (readTrack.json?.releases ?? []).find((entry) =>
      (entry.versionCodes ?? []).map(String).includes(code),
    );
    if (!release) {
      throw new ReleaseError(`Committed, but versionCode ${code} is not on the ${track} track when read back. Check Play Console.`);
    }
    return { editId, versionCode: code, sha256: localSha256, track, status: release.status, sentForReview };
  } finally {
    await requestJson(fetchImpl, readEdit, { method: 'DELETE', headers: auth }).catch(() => null);
  }
}

export async function main(argv, { fetchImpl = globalThis.fetch } = {}) {
  const args = parseArgs(argv);
  const [command] = args._;
  if (command !== 'upload') throw new ReleaseError('Usage: play.mjs upload --service-account FILE ...');
  const serviceAccount = parseServiceAccount(readFileSync(requireArg(args, 'service-account'), 'utf8'));
  const packageName = requireArg(args, 'package', /^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$/u);
  const versionCode = requireArg(args, 'version-code', /^[1-9][0-9]{0,9}$/u);
  const versionName = requireArg(args, 'version-name', /^[0-9]+\.[0-9]+\.[0-9]+$/u);
  const track = requireArg(args, 'track');
  const status = requireArg(args, 'status');
  const aabBytes = readFileSync(requireArg(args, 'aab'));
  const log = (line) => process.stdout.write(`${line}\n`);

  const accessToken = await getAccessToken({ fetchImpl, serviceAccount });
  const result = await publishBundle({
    fetchImpl,
    accessToken,
    packageName,
    aabBytes,
    versionCode,
    versionName,
    track,
    status,
    log,
  });
  appendSummary(
    [
      '### Google Play',
      '',
      '| | |',
      '| --- | --- |',
      `| Package | ${packageName} |`,
      `| Track | ${result.track} |`,
      `| Release | ${versionCode} (${versionName}), status read back: ${result.status} |`,
      `| AAB sha256 | \`${result.sha256}\` |`,
      `| Edit | ${result.editId} |`,
      `| Sent for review | ${result.sentForReview ? 'yes (Play default)' : 'no: send the changes for review in Play Console'} |`,
    ].join('\n'),
  );
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  await runCli(main);
}
