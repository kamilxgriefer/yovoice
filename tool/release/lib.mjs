// Shared helpers for the store-release tooling (.github/workflows/store-release.yml).
//
// Zero dependencies on purpose: these scripts run in jobs that hold the
// Android upload key, the Play service account and the App Store Connect key,
// so nothing from npm is allowed next to them. Node's built-in crypto signs
// the JWTs and the built-in fetch talks to the store APIs.
//
// Nothing in this file may print a credential, a token or a signed assertion.
// Errors carry the HTTP status and the API's own error message only.

import { appendFileSync } from 'node:fs';
import { createPrivateKey, sign } from 'node:crypto';

export class ReleaseError extends Error {
  constructor(message) {
    super(message);
    this.name = 'ReleaseError';
  }
}

export function base64url(input) {
  const buffer = Buffer.isBuffer(input) ? input : Buffer.from(input);
  return buffer.toString('base64').replace(/=+$/u, '').replace(/\+/gu, '-').replace(/\//gu, '_');
}

// alg is RS256 (Google service account) or ES256 (App Store Connect .p8).
export function signJwt({ header, payload, privateKeyPem, alg }) {
  if (alg !== 'RS256' && alg !== 'ES256') {
    throw new ReleaseError(`Unsupported JWT algorithm ${alg}`);
  }
  const fullHeader = { ...header, alg, typ: 'JWT' };
  const signingInput = `${base64url(JSON.stringify(fullHeader))}.${base64url(JSON.stringify(payload))}`;
  const key = createPrivateKey(privateKeyPem);
  const signature =
    alg === 'ES256'
      ? sign('sha256', Buffer.from(signingInput), { key, dsaEncoding: 'ieee-p1363' })
      : sign('sha256', Buffer.from(signingInput), key);
  return `${signingInput}.${base64url(signature)}`;
}

// --name value pairs only; positional words go to `_`. A flag without a value
// is an error rather than a silent `true`, because every flag here carries data.
export function parseArgs(argv) {
  const result = { _: [] };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith('--')) {
      result._.push(token);
      continue;
    }
    const name = token.slice(2);
    const value = argv[index + 1];
    if (!name || value === undefined || value.startsWith('--')) {
      throw new ReleaseError(`Flag --${name} needs a value`);
    }
    result[name] = value;
    index += 1;
  }
  return result;
}

export function requireArg(args, name, pattern) {
  const value = args[name];
  if (value === undefined || value === '') {
    throw new ReleaseError(`Missing --${name}`);
  }
  if (pattern && !pattern.test(value)) {
    throw new ReleaseError(`--${name} has an unexpected format`);
  }
  return value;
}

// Reads a JSON (or empty) response. Never echoes request headers or bodies.
export async function requestJson(fetchImpl, url, { method = 'GET', headers = {}, body } = {}) {
  const response = await fetchImpl(url, { method, headers, body });
  const text = await response.text();
  let json = null;
  if (text) {
    try {
      json = JSON.parse(text);
    } catch {
      json = null;
    }
  }
  return { status: response.status, ok: response.ok, json, text };
}

export function apiErrorMessage(result) {
  const message =
    result.json?.error?.message ??
    result.json?.errors?.map((entry) => entry.detail ?? entry.title).join('; ') ??
    result.json?.error_description ??
    '';
  // Cap the length so a surprising HTML error page cannot flood a public log.
  return `HTTP ${result.status}${message ? `: ${String(message).slice(0, 500)}` : ''}`;
}

export function appendSummary(markdown) {
  const target = process.env.GITHUB_STEP_SUMMARY;
  if (target) {
    appendFileSync(target, `${markdown}\n`);
  } else {
    process.stdout.write(`${markdown}\n`);
  }
}

// Only for values already validated against a strict pattern: a newline in a
// value would let it forge a second output line.
export function setOutput(name, value) {
  const text = String(value);
  if (/[\r\n]/u.test(text)) {
    throw new ReleaseError(`Refusing to write a multi-line output for ${name}`);
  }
  const target = process.env.GITHUB_OUTPUT;
  if (target) {
    appendFileSync(target, `${name}=${text}\n`);
  }
}

// Workflow-command data escaping (::error:: / ::warning::), as the runner expects.
export function escapeCommandData(text) {
  return String(text).replace(/%/gu, '%25').replace(/\r/gu, '%0D').replace(/\n/gu, '%0A');
}

export function warn(message) {
  process.stdout.write(`::warning::${escapeCommandData(message)}\n`);
}

export function sleep(milliseconds) {
  return new Promise((resolve) => {
    setTimeout(resolve, milliseconds);
  });
}

export async function runCli(main) {
  try {
    await main(process.argv.slice(2));
  } catch (error) {
    const message = error instanceof ReleaseError ? error.message : `Unexpected failure: ${error?.message ?? error}`;
    process.stderr.write(`::error::${escapeCommandData(message)}\n`);
    process.exitCode = 1;
  }
}
