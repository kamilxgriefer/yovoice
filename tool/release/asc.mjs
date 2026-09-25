// App Store Connect API checks around the altool upload, with no third-party
// code. The .p8 key is read from a file the workflow writes under
// ~/.appstoreconnect/private_keys and removes in an always() step.
//
//   node asc.mjs assert-build-free --key-file F --key-id ID --issuer-id ISS \
//     --app-id 6801898909 --build-number 36
//   node asc.mjs wait-valid --key-file F --key-id ID --issuer-id ISS \
//     --app-id 6801898909 --build-number 36 --version-name 3.0.0 \
//     --timeout-minutes 45 --interval-seconds 60
//
// assert-build-free refuses when the build number already exists in App Store
// Connect under any version: numbers are never reusable, and a blind re-upload
// ends in "Redundant Binary Upload" (docs/DEPLOYMENT.md).
// wait-valid polls until processing is VALID, fails on INVALID or FAILED, and
// warns (without failing) when the budget runs out, because by then the binary
// is uploaded and the build number is consumed either way.
//
// External TestFlight distribution (What to Test, the external group, beta
// review) is deliberately NOT done here; it stays the documented manual step.

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
  sleep,
  warn,
} from './lib.mjs';

export const ASC_API = 'https://api.appstoreconnect.apple.com/v1';
export const ASC_AUDIENCE = 'appstoreconnect-v1';
// Apple rejects tokens that live longer than 20 minutes.
export const ASC_TOKEN_LIFETIME_SECONDS = 1200;

export function makeAscToken({ privateKeyPem, keyId, issuerId, now = () => Date.now() }) {
  const issuedAt = Math.floor(now() / 1000);
  return signJwt({
    alg: 'ES256',
    header: { kid: keyId },
    payload: { iss: issuerId, iat: issuedAt, exp: issuedAt + ASC_TOKEN_LIFETIME_SECONDS, aud: ASC_AUDIENCE },
    privateKeyPem,
  });
}

export function buildsUrl({ appId, buildNumber, versionName }) {
  const params = new URLSearchParams({
    'filter[app]': appId,
    'filter[version]': String(buildNumber),
    'fields[builds]': 'version,processingState,uploadedDate,expired',
    limit: '20',
  });
  if (versionName) params.set('filter[preReleaseVersion.version]', versionName);
  return `${ASC_API}/builds?${params.toString()}`;
}

export async function findBuilds({ fetchImpl, tokenFactory, appId, buildNumber, versionName }) {
  const result = await requestJson(fetchImpl, buildsUrl({ appId, buildNumber, versionName }), {
    headers: { Authorization: `Bearer ${tokenFactory()}` },
  });
  if (!result.ok) throw new ReleaseError(`App Store Connect builds query failed: ${apiErrorMessage(result)}`);
  return (result.json?.data ?? []).map((build) => ({
    id: String(build.id),
    version: String(build.attributes?.version ?? ''),
    processingState: String(build.attributes?.processingState ?? ''),
  }));
}

export async function assertBuildFree({ fetchImpl, tokenFactory, appId, buildNumber }) {
  const builds = await findBuilds({ fetchImpl, tokenFactory, appId, buildNumber });
  const clash = builds.find((build) => build.version === String(buildNumber));
  if (clash) {
    throw new ReleaseError(
      `Build ${buildNumber} already exists in App Store Connect (${clash.id}, ${clash.processingState}). ` +
        'Do not re-upload; build numbers are never reusable.',
    );
  }
}

export async function waitValid({
  fetchImpl,
  tokenFactory,
  appId,
  buildNumber,
  versionName,
  timeoutMs,
  intervalMs,
  now = () => Date.now(),
  pause = sleep,
  log = () => {},
}) {
  const deadline = now() + timeoutMs;
  let attempt = 0;
  for (;;) {
    attempt += 1;
    const builds = await findBuilds({ fetchImpl, tokenFactory, appId, buildNumber, versionName });
    const build = builds.find((entry) => entry.version === String(buildNumber));
    const state = build?.processingState ?? 'NOT_VISIBLE_YET';
    log(`Poll ${attempt}: build ${buildNumber} ${state}`);
    if (state === 'VALID') return { state, id: build.id, attempts: attempt };
    if (state === 'INVALID' || state === 'FAILED') {
      throw new ReleaseError(`App Store Connect processing ended ${state} for build ${buildNumber} (${build.id})`);
    }
    if (now() + intervalMs > deadline) return { state: 'TIMEOUT', lastSeen: state, id: build?.id ?? null, attempts: attempt };
    await pause(intervalMs);
  }
}

export async function main(argv, { fetchImpl = globalThis.fetch } = {}) {
  const args = parseArgs(argv);
  const [command] = args._;
  const privateKeyPem = readFileSync(requireArg(args, 'key-file'), 'utf8');
  const keyId = requireArg(args, 'key-id', /^[A-Z0-9]{10}$/u);
  const issuerId = requireArg(args, 'issuer-id', /^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$/u);
  const appId = requireArg(args, 'app-id', /^[0-9]{6,12}$/u);
  const buildNumber = requireArg(args, 'build-number', /^[1-9][0-9]{0,9}$/u);
  const tokenFactory = () => makeAscToken({ privateKeyPem, keyId, issuerId });
  const log = (line) => process.stdout.write(`${line}\n`);

  if (command === 'assert-build-free') {
    await assertBuildFree({ fetchImpl, tokenFactory, appId, buildNumber });
    log(`Build ${buildNumber} is not in App Store Connect yet`);
    return;
  }
  if (command === 'wait-valid') {
    const versionName = requireArg(args, 'version-name', /^[0-9]+\.[0-9]+\.[0-9]+$/u);
    const timeoutMinutes = Number(requireArg(args, 'timeout-minutes', /^[1-9][0-9]{0,2}$/u));
    const intervalSeconds = Number(requireArg(args, 'interval-seconds', /^[1-9][0-9]{0,3}$/u));
    const result = await waitValid({
      fetchImpl,
      tokenFactory,
      appId,
      buildNumber,
      versionName,
      timeoutMs: timeoutMinutes * 60_000,
      intervalMs: intervalSeconds * 1000,
      log,
    });
    if (result.state === 'TIMEOUT') {
      warn(
        `Build ${buildNumber} was uploaded but processing was not VALID within ${timeoutMinutes} min ` +
          `(last seen ${result.lastSeen}). Check TestFlight; do not re-upload.`,
      );
    }
    appendSummary(
      [
        '### App Store Connect',
        '',
        '| | |',
        '| --- | --- |',
        `| Build | ${versionName} (${buildNumber}) |`,
        `| Processing | ${result.state === 'TIMEOUT' ? `not confirmed (last seen ${result.lastSeen})` : result.state} |`,
        `| ASC build id | ${result.id ?? 'unknown'} |`,
        '| External TestFlight group | not touched: manual step (docs/RELEASE_CI.md) |',
      ].join('\n'),
    );
    return;
  }
  throw new ReleaseError('Usage: asc.mjs assert-build-free|wait-valid ...');
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  await runCli(main);
}
