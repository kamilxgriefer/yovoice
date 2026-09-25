// Preflight for .github/workflows/store-release.yml. Runs with no secret and a
// read-only token, before anyone is asked to approve the store-release
// environment. Everything it decides is written to the job summary, which is
// what the approver reads.
//
// Hard failures in every mode (the build would be meaningless or unsafe):
//   - an input with the wrong shape;
//   - a real run dispatched from anything but main;
//   - `ref` not a commit that is already on main;
//   - `build_number` not equal to the +N in pubspec.yaml at `ref`;
//   - the Gradle configuration cache switched on at `ref` (it would serialise
//     the upload-key password into the build tree).
//
// Release-order gates (hard failures on a real run, warnings on a dry run):
//   - CI: `verify_and_build` and `Playwright against release web build`
//     concluded success on exactly `ref`, counted only from workflow runs on
//     main started by a push or a dispatch (a pull_request run attaches its
//     check runs to the head SHA but tests a merge commit, so it never counts);
//   - backend: functions/, firestore.rules, firestore.indexes.json and
//     storage.rules are unchanged since the last store release, unless
//     backend_confirmed is true (docs/DEPLOYMENT.md, "4. The app — only after
//     1-3 are read back");
//   - web: a `deploy_hosting` job concluded success on exactly `ref` in a
//     workflow_dispatch run on main, unless web_confirmed is true, so Hosting
//     and the stores ship the same SHA;
//   - the build number has not already been tagged for a different SHA.
//
// The baseline for the backend gate is `since_ref` when given, otherwise the
// highest `store-build-<N>` tag that is an ancestor of `ref` with N below the
// requested build. With neither, a real run refuses (fail closed): an empty
// baseline would make `git diff` compare nothing and pass silently.

import { execFileSync, spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

import {
  ReleaseError,
  apiErrorMessage,
  appendSummary,
  requestJson,
  runCli,
  setOutput,
  warn,
} from './lib.mjs';

export const SHA_PATTERN = /^[0-9a-f]{40}$/u;
export const BUILD_NUMBER_PATTERN = /^[1-9][0-9]{0,9}$/u;
// Google Play's hard ceiling for versionCode.
export const MAX_BUILD_NUMBER = 2100000000;
export const BACKEND_PATHS = Object.freeze([
  'functions',
  'firestore.rules',
  'firestore.indexes.json',
  'storage.rules',
]);
// Paths whose code runs next to the signing secrets, or decides what is
// signed. Listed for the approver, never used as a gate on their own.
export const SIGNING_SENSITIVE_APP_PATHS = Object.freeze([
  'android',
  'ios',
  'pubspec.yaml',
  'pubspec.lock',
  'tool/generate_ui_sounds.py',
]);
export const RELEASE_TOOLING_PATHS = Object.freeze([
  'tool/release',
  '.github/workflows/store-release.yml',
]);
export const CI_CHECK_NAMES = Object.freeze([
  'verify_and_build',
  'Playwright against release web build',
]);
export const WEB_DEPLOY_CHECK_NAME = 'deploy_hosting';
// Workflow-run events whose check runs may satisfy a gate. Both CI workflows
// also run on pull_request, which tests refs/pull/N/merge, not the head SHA.
export const CI_TRUSTED_EVENTS = Object.freeze(['push', 'workflow_dispatch']);
export const WEB_DEPLOY_TRUSTED_EVENTS = Object.freeze(['workflow_dispatch']);
export const MAIN_BRANCH = 'main';
export const STORE_TAG_PREFIX = 'store-build-';
export const MAIN_REF = 'refs/heads/main';
export const MAIN_REMOTE_REF = 'refs/remotes/origin/main';

function parseBoolean(value, name, errors) {
  if (value === 'true') return true;
  if (value === 'false') return false;
  errors.push(`${name} must be true or false`);
  return false;
}

export function readInputs(env) {
  const errors = [];
  const ref = env.RELEASE_REF ?? '';
  if (!SHA_PATTERN.test(ref)) {
    errors.push('ref must be a full 40-character lowercase commit SHA');
  }
  const buildNumberText = env.RELEASE_BUILD_NUMBER ?? '';
  const buildNumber = BUILD_NUMBER_PATTERN.test(buildNumberText) ? Number(buildNumberText) : Number.NaN;
  if (!Number.isSafeInteger(buildNumber) || buildNumber > MAX_BUILD_NUMBER) {
    errors.push(`build_number must be a whole number from 1 to ${MAX_BUILD_NUMBER}`);
  }
  const platforms = env.RELEASE_PLATFORMS ?? '';
  if (!['both', 'android', 'ios'].includes(platforms)) {
    errors.push('platforms must be both, android or ios');
  }
  const playReleaseStatus = env.RELEASE_PLAY_STATUS ?? '';
  if (!['draft', 'completed'].includes(playReleaseStatus)) {
    errors.push('play_release_status must be draft or completed');
  }
  const sinceRef = env.RELEASE_SINCE_REF ?? '';
  if (sinceRef !== '' && !SHA_PATTERN.test(sinceRef)) {
    errors.push('since_ref must be empty or a full 40-character lowercase commit SHA');
  }
  const dryRun = parseBoolean(env.RELEASE_DRY_RUN, 'dry_run', errors);
  const backendConfirmed = parseBoolean(env.RELEASE_BACKEND_CONFIRMED, 'backend_confirmed', errors);
  const webConfirmed = parseBoolean(env.RELEASE_WEB_CONFIRMED, 'web_confirmed', errors);
  if (errors.length > 0) {
    throw new ReleaseError(`Invalid inputs: ${errors.join('; ')}`);
  }
  return {
    ref,
    buildNumber,
    platforms,
    playReleaseStatus,
    sinceRef,
    dryRun,
    backendConfirmed,
    webConfirmed,
  };
}

export function parsePubspecVersion(text) {
  const match = /^version:[ \t]*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)[ \t]*(?:#.*)?$/mu.exec(text);
  if (!match) {
    throw new ReleaseError('pubspec.yaml at ref has no "version: X.Y.Z+N" line');
  }
  return { buildName: match[1], buildNumber: Number(match[2]) };
}

export function configurationCacheEnabled(gradlePropertiesText) {
  return /^[ \t]*org\.gradle\.(?:unsafe\.)?configuration-cache[ \t]*[=:][ \t]*true[ \t]*$/imu.test(
    gradlePropertiesText,
  );
}

// tags: [{ name, sha }] with sha already peeled to the commit.
export function pickBaselineTag(tags, buildNumber, isAncestorOfRef) {
  const candidates = tags
    .map((tag) => {
      const match = /^store-build-([1-9][0-9]*)$/u.exec(tag.name);
      return match ? { ...tag, number: Number(match[1]) } : null;
    })
    .filter((tag) => tag !== null && tag.number < buildNumber && SHA_PATTERN.test(tag.sha))
    .sort((left, right) => right.number - left.number);
  for (const candidate of candidates) {
    if (isAncestorOfRef(candidate.sha)) {
      return candidate;
    }
  }
  return null;
}

// Check suites of the workflow runs that tested exactly `sha` on main for one
// of `events`. Workflow runs come from GET /repos/{o}/{r}/actions/runs.
export function trustedSuiteIds(workflowRuns, { sha, events }) {
  return new Set(
    (workflowRuns ?? [])
      .filter(
        (run) =>
          run?.head_sha === sha &&
          run?.head_branch === MAIN_BRANCH &&
          events.includes(run?.event) &&
          run?.check_suite_id !== undefined &&
          run?.check_suite_id !== null,
      )
      .map((run) => run.check_suite_id),
  );
}

// Picks the newest run of `name` created by GitHub Actions itself, so a
// check run another app happens to name the same cannot satisfy the gate.
// With `suiteIds`, only check runs in those check suites count (see
// trustedSuiteIds); the release gates always pass it.
export function summarizeCheckRun(checkRuns, name, suiteIds = null) {
  const matching = (checkRuns ?? []).filter(
    (run) =>
      run?.name === name &&
      run?.app?.slug === 'github-actions' &&
      (suiteIds === null || suiteIds.has(run?.check_suite?.id)),
  );
  if (matching.length === 0) {
    return { name, state: 'missing', conclusion: null, url: null };
  }
  const latest = matching.reduce((newest, run) => (run.id > newest.id ? run : newest));
  let state = 'failed';
  if (latest.status !== 'completed') state = 'pending';
  else if (latest.conclusion === 'success') state = 'success';
  return { name, state, conclusion: latest.conclusion ?? latest.status, url: latest.html_url ?? null };
}

export function decide({ dryRun, ci, backend, web, tagConflict }) {
  const failures = [];
  const warnings = [];
  const gate = (message) => (dryRun ? warnings : failures).push(message);

  for (const check of ci) {
    if (check.state !== 'success') {
      gate(
        `CI check "${check.name}" is ${check.state}${check.conclusion ? ` (${check.conclusion})` : ''} on this SHA. ` +
          'Only a SHA whose own push (or dispatch) run on main finished green can ship; pull_request runs do not ' +
          'count, and a run cancelled by a newer push never turns green, so release the newer SHA instead.',
      );
    }
  }
  if (backend.baseline === null) {
    gate(
      'No store-release baseline: pass since_ref, or tag the last store release as store-build-<N> ' +
        '(docs/RELEASE_CI.md, "Baseline tags").',
    );
  } else if (backend.changed.length > 0 && !backend.confirmed) {
    gate(
      `${backend.changed.length} backend file(s) changed since ${backend.baseline.label}. ` +
        'Deploy and read back indexes, rules and Functions first (docs/DEPLOYMENT.md), then re-run with backend_confirmed=true.',
    );
  }
  if (web.state !== 'success' && !web.confirmed) {
    gate(
      `No successful deploy_hosting job on this SHA (${web.state}). Deploy Hosting from this SHA first ` +
        '(firebase-hosting-merge.yml with deploy_hosting=true while main is at this SHA), or re-run with ' +
        'web_confirmed=true if Hosting was deployed from this SHA by hand or the skew is deliberate.',
    );
  }
  if (tagConflict) {
    gate(`Build number is already tagged ${tagConflict.name} on a different commit (${tagConflict.sha}). Use the next number.`);
  }
  return { failures, warnings };
}

// ---------------------------------------------------------------------------
// Side-effecting helpers (git and the GitHub REST API). Kept thin so the
// decisions above stay unit-testable without a repository or a network.

function git(args) {
  return execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
}

function gitOptional(args) {
  const result = spawnSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  return result.status === 0 ? result.stdout : null;
}

function isAncestor(ancestor, descendant) {
  const result = spawnSync('git', ['merge-base', '--is-ancestor', ancestor, descendant], { stdio: 'ignore' });
  if (result.status === 0) return true;
  if (result.status === 1) return false;
  throw new ReleaseError(`git merge-base failed for ${ancestor} and ${descendant}`);
}

function commitExists(sha) {
  return gitOptional(['cat-file', '-e', `${sha}^{commit}`]) !== null;
}

function listStoreTags() {
  const output = git([
    'for-each-ref',
    '--format=%(refname:strip=2) %(objectname) %(*objectname)',
    `refs/tags/${STORE_TAG_PREFIX}*`,
  ]);
  return output
    .split('\n')
    .filter(Boolean)
    .map((line) => {
      const [name, objectSha, peeledSha] = line.trim().split(/\s+/u);
      return { name, sha: peeledSha || objectSha };
    });
}

function githubHeaders(token) {
  return {
    Accept: 'application/vnd.github+json',
    Authorization: `Bearer ${token}`,
    'X-GitHub-Api-Version': '2022-11-28',
  };
}

// Every workflow run on `sha`. More than 100 runs on one commit would only
// hide trusted runs, which makes the gates refuse (fail closed).
async function fetchWorkflowRuns(fetchImpl, { apiUrl, repository, token, sha }) {
  const url = `${apiUrl}/repos/${repository}/actions/runs?head_sha=${sha}&per_page=100`;
  const result = await requestJson(fetchImpl, url, { headers: githubHeaders(token) });
  if (!result.ok) {
    throw new ReleaseError(`Could not read workflow runs for ${sha}: ${apiErrorMessage(result)}`);
  }
  return result.json?.workflow_runs ?? [];
}

async function fetchCheckRuns(fetchImpl, { apiUrl, repository, token, sha, name, suiteIds }) {
  const url =
    `${apiUrl}/repos/${repository}/commits/${sha}/check-runs` +
    `?check_name=${encodeURIComponent(name)}&filter=all&per_page=100`;
  const result = await requestJson(fetchImpl, url, { headers: githubHeaders(token) });
  if (!result.ok) {
    throw new ReleaseError(`Could not read check runs for "${name}": ${apiErrorMessage(result)}`);
  }
  return summarizeCheckRun(result.json?.check_runs, name, suiteIds);
}

function fence(lines) {
  const safe = lines.map((line) => line.replace(/`{3,}/gu, "'''"));
  return ['```text', ...(safe.length ? safe : ['(none)']), '```'].join('\n');
}

function capped(lines, limit) {
  if (lines.length <= limit) return lines;
  return [...lines.slice(0, limit), `... and ${lines.length - limit} more`];
}

export async function main(_argv, { env = process.env, fetchImpl = globalThis.fetch, warnImpl = warn } = {}) {
  const inputs = readInputs(env);
  const repository = env.GITHUB_REPOSITORY ?? '';
  const token = env.GITHUB_TOKEN ?? '';
  const apiUrl = env.GITHUB_API_URL || 'https://api.github.com';
  const workflowRef = env.GITHUB_REF ?? '';
  const toolingSha = env.GITHUB_SHA ?? '';
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/u.test(repository) || !token) {
    throw new ReleaseError('GITHUB_REPOSITORY and GITHUB_TOKEN must be set');
  }

  if (!inputs.dryRun && workflowRef !== MAIN_REF) {
    throw new ReleaseError(`A real store release must be dispatched from main, not ${workflowRef || '(unknown)'}`);
  }
  if (!commitExists(inputs.ref)) {
    throw new ReleaseError(`ref ${inputs.ref} is not a commit in this repository`);
  }
  if (gitOptional(['rev-parse', '--verify', '--quiet', MAIN_REMOTE_REF]) === null) {
    throw new ReleaseError('origin/main is not available; the checkout needs fetch-depth: 0');
  }
  if (!isAncestor(inputs.ref, MAIN_REMOTE_REF)) {
    throw new ReleaseError(`ref ${inputs.ref} is not on main`);
  }

  const pubspec = parsePubspecVersion(git(['show', `${inputs.ref}:pubspec.yaml`]));
  if (pubspec.buildNumber !== inputs.buildNumber) {
    throw new ReleaseError(
      `build_number ${inputs.buildNumber} does not match pubspec.yaml at ref (${pubspec.buildName}+${pubspec.buildNumber}). ` +
        'Bump the pubspec on main first; store build numbers are never reusable.',
    );
  }
  const gradleProperties = gitOptional(['show', `${inputs.ref}:android/gradle.properties`]) ?? '';
  if (configurationCacheEnabled(gradleProperties)) {
    throw new ReleaseError(
      'android/gradle.properties enables the Gradle configuration cache, which would serialise the upload-key password. Refusing.',
    );
  }

  const tags = listStoreTags();
  const sameNumberTag = tags.find((tag) => tag.name === `${STORE_TAG_PREFIX}${inputs.buildNumber}`) ?? null;
  const tagConflict = sameNumberTag && sameNumberTag.sha !== inputs.ref ? sameNumberTag : null;

  let baseline = null;
  if (inputs.sinceRef) {
    if (!commitExists(inputs.sinceRef)) {
      throw new ReleaseError(`since_ref ${inputs.sinceRef} is not a commit in this repository`);
    }
    if (!isAncestor(inputs.sinceRef, inputs.ref)) {
      throw new ReleaseError(`since_ref ${inputs.sinceRef} is not an ancestor of ref`);
    }
    baseline = { sha: inputs.sinceRef, label: `since_ref ${inputs.sinceRef.slice(0, 12)}` };
  } else {
    const tag = pickBaselineTag(tags, inputs.buildNumber, (sha) => isAncestor(sha, inputs.ref));
    if (tag) baseline = { sha: tag.sha, label: `${tag.name} (${tag.sha.slice(0, 12)})` };
  }

  const changedBackend = baseline
    ? git(['diff', '--name-only', baseline.sha, inputs.ref, '--', ...BACKEND_PATHS]).split('\n').filter(Boolean)
    : [];
  const commits = baseline
    ? git(['log', '--oneline', '--no-decorate', `${baseline.sha}..${inputs.ref}`]).split('\n').filter(Boolean)
    : [];
  const changedSensitive = baseline
    ? git(['diff', '--stat', baseline.sha, inputs.ref, '--', ...SIGNING_SENSITIVE_APP_PATHS]).split('\n').filter(Boolean)
    : [];
  const toolingChanges =
    baseline && SHA_PATTERN.test(toolingSha) && commitExists(toolingSha)
      ? git(['diff', '--stat', baseline.sha, toolingSha, '--', ...RELEASE_TOOLING_PATHS]).split('\n').filter(Boolean)
      : [];

  const workflowRuns = await fetchWorkflowRuns(fetchImpl, { apiUrl, repository, token, sha: inputs.ref });
  const ciSuites = trustedSuiteIds(workflowRuns, { sha: inputs.ref, events: CI_TRUSTED_EVENTS });
  const webSuites = trustedSuiteIds(workflowRuns, { sha: inputs.ref, events: WEB_DEPLOY_TRUSTED_EVENTS });
  const ci = [];
  for (const name of CI_CHECK_NAMES) {
    ci.push(await fetchCheckRuns(fetchImpl, { apiUrl, repository, token, sha: inputs.ref, name, suiteIds: ciSuites }));
  }
  const webRun = await fetchCheckRuns(fetchImpl, {
    apiUrl,
    repository,
    token,
    sha: inputs.ref,
    name: WEB_DEPLOY_CHECK_NAME,
    suiteIds: webSuites,
  });

  const { failures, warnings } = decide({
    dryRun: inputs.dryRun,
    ci,
    backend: { baseline, changed: changedBackend, confirmed: inputs.backendConfirmed },
    web: { state: webRun.state, confirmed: inputs.webConfirmed },
    tagConflict,
  });

  const mode = inputs.dryRun ? 'DRY RUN (unsigned, no secrets, no upload)' : 'REAL RELEASE (signed, uploads to stores)';
  appendSummary(
    [
      `## Store release preflight: ${failures.length ? 'REFUSED' : 'passed'}`,
      '',
      '| | |',
      '| --- | --- |',
      `| Mode | ${mode} |`,
      `| App commit (ref) | \`${inputs.ref}\` |`,
      `| Release tooling commit (workflow) | \`${toolingSha || 'unknown'}\` |`,
      `| Version | ${pubspec.buildName} (${inputs.buildNumber}) |`,
      `| Platforms | ${inputs.platforms} |`,
      `| Play track / status | internal / ${inputs.playReleaseStatus} |`,
      `| Backend baseline | ${baseline ? baseline.label : 'none'} |`,
      `| Backend files changed | ${baseline ? changedBackend.length : 'unknown'}${inputs.backendConfirmed ? ' (backend_confirmed=true)' : ''} |`,
      ...ci.map(
        (check) =>
          `| CI: ${check.name} (push or dispatch on main) | ${check.state}${check.url ? ` ([run](${check.url}))` : ''} |`,
      ),
      `| Web: deploy_hosting on this SHA (dispatch on main) | ${webRun.state}${inputs.webConfirmed ? ' (web_confirmed=true)' : ''} |`,
      `| Tag for this build number | ${sameNumberTag ? `${sameNumberTag.name} -> ${sameNumberTag.sha.slice(0, 12)}` : 'none yet'} |`,
      '',
      failures.length ? `### Refused\n\n${failures.map((line) => `- ${line}`).join('\n')}` : '',
      warnings.length ? `### Warnings (dry run: would refuse a real release)\n\n${warnings.map((line) => `- ${line}`).join('\n')}` : '',
      '### Commits since the baseline',
      fence(capped(commits, 200)),
      '### Backend files changed since the baseline',
      fence(capped(changedBackend, 200)),
      '### Review before approving: code that runs next to the signing secrets',
      'App-side (android/, ios/, pubspec, sound generator) since the baseline:',
      fence(capped(changedSensitive, 60)),
      'Release tooling (tool/release, this workflow) since the baseline:',
      fence(capped(toolingChanges, 60)),
    ]
      .filter((line) => line !== '')
      .join('\n'),
  );

  for (const message of warnings) warnImpl(message);
  if (failures.length > 0) {
    throw new ReleaseError(`Preflight refused the release: ${failures.join(' | ')}`);
  }

  setOutput('sha', inputs.ref);
  setOutput('build_name', pubspec.buildName);
  setOutput('build_number', String(inputs.buildNumber));
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  await runCli(main);
}
