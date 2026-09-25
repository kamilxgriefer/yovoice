// node --test tool/test/release_preflight.test.mjs
//
// The store-release preflight: input validation, the pubspec match, the
// baseline choice and every release-order gate, plus an end-to-end run
// against a throwaway git repository with a mocked GitHub API.

import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { after, before, describe, test } from 'node:test';

import {
  BACKEND_PATHS,
  configurationCacheEnabled,
  decide,
  main,
  parsePubspecVersion,
  pickBaselineTag,
  readInputs,
  summarizeCheckRun,
  trustedSuiteIds,
} from '../release/preflight.mjs';

const SHA_A = 'a'.repeat(40);
const SHA_B = 'b'.repeat(40);

function validEnv(overrides = {}) {
  return {
    RELEASE_REF: SHA_A,
    RELEASE_BUILD_NUMBER: '36',
    RELEASE_PLATFORMS: 'both',
    RELEASE_DRY_RUN: 'true',
    RELEASE_PLAY_STATUS: 'draft',
    RELEASE_BACKEND_CONFIRMED: 'false',
    RELEASE_WEB_CONFIRMED: 'false',
    RELEASE_SINCE_REF: '',
    ...overrides,
  };
}

// Keep the real job summary and outputs clean when these tests run inside the
// preflight job itself.
const scratch = mkdtempSync(path.join(tmpdir(), 'yovoice-preflight-test-'));
const savedSummary = process.env.GITHUB_STEP_SUMMARY;
const savedOutput = process.env.GITHUB_OUTPUT;
before(() => {
  process.env.GITHUB_STEP_SUMMARY = path.join(scratch, 'summary.md');
  process.env.GITHUB_OUTPUT = path.join(scratch, 'output.txt');
});
after(() => {
  if (savedSummary === undefined) delete process.env.GITHUB_STEP_SUMMARY;
  else process.env.GITHUB_STEP_SUMMARY = savedSummary;
  if (savedOutput === undefined) delete process.env.GITHUB_OUTPUT;
  else process.env.GITHUB_OUTPUT = savedOutput;
  rmSync(scratch, { recursive: true, force: true });
});

describe('readInputs', () => {
  test('accepts a well-formed dispatch', () => {
    const inputs = readInputs(validEnv());
    assert.equal(inputs.ref, SHA_A);
    assert.equal(inputs.buildNumber, 36);
    assert.equal(inputs.dryRun, true);
    assert.equal(inputs.sinceRef, '');
  });

  for (const [name, overrides] of [
    ['a short SHA', { RELEASE_REF: 'abc1234' }],
    ['an uppercase SHA', { RELEASE_REF: 'A'.repeat(40) }],
    ['shell metacharacters in ref', { RELEASE_REF: `${SHA_A}; curl evil` }],
    ['a branch name', { RELEASE_REF: 'main' }],
    ['a zero build number', { RELEASE_BUILD_NUMBER: '0' }],
    ['a padded build number', { RELEASE_BUILD_NUMBER: '036' }],
    ['a build number above the Play ceiling', { RELEASE_BUILD_NUMBER: '2100000001' }],
    ['a build number with text', { RELEASE_BUILD_NUMBER: '36$(id)' }],
    ['an unknown platform', { RELEASE_PLATFORMS: 'web' }],
    ['a production Play status', { RELEASE_PLAY_STATUS: 'inProgress' }],
    ['a non-boolean dry_run', { RELEASE_DRY_RUN: 'yes' }],
    ['a missing dry_run', { RELEASE_DRY_RUN: undefined }],
    ['a malformed since_ref', { RELEASE_SINCE_REF: 'HEAD~3' }],
  ]) {
    test(`refuses ${name}`, () => {
      assert.throws(() => readInputs(validEnv(overrides)), /Invalid inputs/u);
    });
  }
});

describe('parsePubspecVersion', () => {
  test('reads the repository pubspec', () => {
    const text = readFileSync(new URL('../../pubspec.yaml', import.meta.url), 'utf8');
    const version = parsePubspecVersion(text);
    assert.match(version.buildName, /^\d+\.\d+\.\d+$/u);
    assert.ok(Number.isSafeInteger(version.buildNumber) && version.buildNumber > 0);
  });

  test('reads name and number, ignoring a trailing comment', () => {
    assert.deepEqual(parsePubspecVersion('name: x\nversion: 3.0.0+36 # next\n'), {
      buildName: '3.0.0',
      buildNumber: 36,
    });
  });

  test('refuses a pubspec without a build number', () => {
    assert.throws(() => parsePubspecVersion('version: 3.0.0\n'), /version/u);
  });
});

test('configurationCacheEnabled spots both spellings and ignores the current file', () => {
  assert.equal(configurationCacheEnabled('org.gradle.configuration-cache=true\n'), true);
  assert.equal(configurationCacheEnabled('org.gradle.unsafe.configuration-cache = true\n'), true);
  assert.equal(configurationCacheEnabled('org.gradle.configuration-cache=false\n'), false);
  assert.equal(configurationCacheEnabled('# org.gradle.configuration-cache=true\n'), false);
  const current = readFileSync(new URL('../../android/gradle.properties', import.meta.url), 'utf8');
  assert.equal(configurationCacheEnabled(current), false);
});

describe('pickBaselineTag', () => {
  const tags = [
    { name: 'store-build-34', sha: SHA_A },
    { name: 'store-build-35', sha: SHA_B },
    { name: 'store-build-36', sha: 'c'.repeat(40) },
    { name: 'slim-p7-ready', sha: 'd'.repeat(40) },
    { name: 'store-build-x', sha: 'e'.repeat(40) },
  ];

  test('takes the highest ancestor tag below the requested build', () => {
    assert.equal(pickBaselineTag(tags, 36, () => true).name, 'store-build-35');
  });

  test('never uses the tag of the build being released', () => {
    assert.equal(pickBaselineTag(tags, 37, () => true).name, 'store-build-36');
    assert.equal(pickBaselineTag(tags, 36, () => true).number, 35);
  });

  test('skips tags that are not ancestors of ref', () => {
    assert.equal(pickBaselineTag(tags, 36, (sha) => sha === SHA_A).name, 'store-build-34');
  });

  test('returns null when nothing qualifies (fail closed upstream)', () => {
    assert.equal(pickBaselineTag(tags, 34, () => true), null);
    assert.equal(pickBaselineTag([], 36, () => true), null);
  });
});

describe('summarizeCheckRun', () => {
  const run = (id, overrides = {}) => ({
    id,
    name: 'verify_and_build',
    status: 'completed',
    conclusion: 'success',
    app: { slug: 'github-actions' },
    html_url: `https://example.invalid/${id}`,
    ...overrides,
  });

  test('uses the newest run', () => {
    assert.equal(summarizeCheckRun([run(1), run(2, { conclusion: 'failure' })], 'verify_and_build').state, 'failed');
    assert.equal(summarizeCheckRun([run(2, { conclusion: 'failure' }), run(3)], 'verify_and_build').state, 'success');
  });

  test('ignores runs from other apps with the same name', () => {
    assert.equal(
      summarizeCheckRun([run(9, { app: { slug: 'someone-else' } })], 'verify_and_build').state,
      'missing',
    );
  });

  test('reports pending and cancelled runs as not green', () => {
    assert.equal(summarizeCheckRun([run(1, { status: 'in_progress', conclusion: null })], 'verify_and_build').state, 'pending');
    const cancelled = summarizeCheckRun([run(1, { conclusion: 'cancelled' })], 'verify_and_build');
    assert.equal(cancelled.state, 'failed');
    assert.equal(cancelled.conclusion, 'cancelled');
  });
});

describe('trustedSuiteIds', () => {
  const workflowRun = (suite, overrides = {}) => ({
    id: suite,
    event: 'push',
    head_branch: 'main',
    head_sha: SHA_A,
    check_suite_id: suite,
    ...overrides,
  });
  const runs = [
    workflowRun(1),
    workflowRun(2, { event: 'workflow_dispatch' }),
    workflowRun(3, { event: 'pull_request' }),
    workflowRun(4, { event: 'pull_request', head_branch: 'feature' }),
    workflowRun(5, { head_branch: 'feature' }),
    workflowRun(6, { head_sha: SHA_B }),
    workflowRun(7, { check_suite_id: null }),
  ];

  test('keeps only runs on main, on exactly the SHA, for the given events', () => {
    assert.deepEqual([...trustedSuiteIds(runs, { sha: SHA_A, events: ['push', 'workflow_dispatch'] })].sort(), [1, 2]);
    assert.deepEqual([...trustedSuiteIds(runs, { sha: SHA_A, events: ['workflow_dispatch'] })], [2]);
    assert.equal(trustedSuiteIds(undefined, { sha: SHA_A, events: ['push'] }).size, 0);
  });

  test('a pull_request run whose head branch is called main still does not count', () => {
    const forkMain = [workflowRun(8, { event: 'pull_request', head_branch: 'main' })];
    assert.equal(trustedSuiteIds(forkMain, { sha: SHA_A, events: ['push', 'workflow_dispatch'] }).size, 0);
  });

  test('summarizeCheckRun counts only check runs in trusted suites when given them', () => {
    const checkRun = (id, suite, conclusion) => ({
      id,
      name: 'verify_and_build',
      status: 'completed',
      conclusion,
      app: { slug: 'github-actions' },
      check_suite: { id: suite },
    });
    // A newer green pull_request run must not turn a red push run green.
    const checkRuns = [checkRun(10, 1, 'failure'), checkRun(11, 3, 'success')];
    const trusted = trustedSuiteIds(runs, { sha: SHA_A, events: ['push', 'workflow_dispatch'] });
    assert.equal(summarizeCheckRun(checkRuns, 'verify_and_build', trusted).state, 'failed');
    assert.equal(summarizeCheckRun([checkRun(11, 3, 'success')], 'verify_and_build', trusted).state, 'missing');
    assert.equal(summarizeCheckRun([checkRun(12, 2, 'success')], 'verify_and_build', trusted).state, 'success');
  });
});

describe('decide', () => {
  const green = [
    { name: 'verify_and_build', state: 'success' },
    { name: 'Playwright against release web build', state: 'success' },
  ];
  const baseline = { sha: SHA_B, label: 'store-build-35' };
  const clean = {
    ci: green,
    backend: { baseline, changed: [], confirmed: false },
    web: { state: 'success', confirmed: false },
    tagConflict: null,
  };

  test('a clean real release passes', () => {
    assert.deepEqual(decide({ ...clean, dryRun: false }), { failures: [], warnings: [] });
  });

  test('a real release refuses red CI, a backend diff, missing web and a missing baseline', () => {
    const cases = [
      { ci: [{ name: 'verify_and_build', state: 'failed', conclusion: 'cancelled' }, green[1]] },
      { backend: { baseline, changed: ['functions/index.js'], confirmed: false } },
      { web: { state: 'missing', confirmed: false } },
      { backend: { baseline: null, changed: [], confirmed: true } },
      { tagConflict: { name: 'store-build-36', sha: SHA_B } },
    ];
    for (const overrides of cases) {
      const outcome = decide({ ...clean, ...overrides, dryRun: false });
      assert.equal(outcome.failures.length, 1, JSON.stringify(overrides));
      assert.equal(outcome.warnings.length, 0);
    }
  });

  test('the confirmations clear only their own gate', () => {
    const outcome = decide({
      ...clean,
      dryRun: false,
      backend: { baseline, changed: ['firestore.rules'], confirmed: true },
      web: { state: 'missing', confirmed: true },
    });
    assert.deepEqual(outcome.failures, []);
    const stillRed = decide({
      ...clean,
      dryRun: false,
      ci: [{ name: 'verify_and_build', state: 'missing' }, green[1]],
      backend: { baseline, changed: ['firestore.rules'], confirmed: true },
      web: { state: 'missing', confirmed: true },
    });
    assert.equal(stillRed.failures.length, 1);
  });

  test('a dry run turns release-order gates into warnings', () => {
    const outcome = decide({
      dryRun: true,
      ci: [{ name: 'verify_and_build', state: 'missing' }, green[1]],
      backend: { baseline: null, changed: [], confirmed: false },
      web: { state: 'missing', confirmed: false },
      tagConflict: null,
    });
    assert.equal(outcome.failures.length, 0);
    assert.equal(outcome.warnings.length, 3);
  });
});

test('BACKEND_PATHS covers exactly the manually deployed backend surfaces', () => {
  assert.deepEqual([...BACKEND_PATHS], ['functions', 'firestore.rules', 'firestore.indexes.json', 'storage.rules']);
});

// ---------------------------------------------------------------------------
// End to end against a real git repository.

describe('main against a throwaway repository', () => {
  const repo = mkdtempSync(path.join(tmpdir(), 'yovoice-preflight-repo-'));
  const cwd = process.cwd();
  const shas = {};

  const git = (...args) =>
    execFileSync('git', ['-c', 'user.name=CI Test', '-c', 'user.email=ci@example.invalid', ...args], {
      cwd: repo,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    }).trim();
  const write = (file, content) => {
    mkdirSync(path.dirname(path.join(repo, file)), { recursive: true });
    writeFileSync(path.join(repo, file), content);
  };
  const commit = (message) => {
    git('add', '-A');
    git('commit', '-q', '-m', message);
    return git('rev-parse', 'HEAD');
  };

  before(() => {
    git('init', '-q', '-b', 'main');
    write('pubspec.yaml', 'name: yovoice\nversion: 3.0.0+35\n');
    write('android/gradle.properties', 'android.useAndroidX=true\n');
    write('functions/index.js', 'exports.a = 1;\n');
    shas.released = commit('3.0.0+35');
    git('tag', 'store-build-35', shas.released);
    write('lib/app.dart', 'void main() {}\n');
    write('pubspec.yaml', 'name: yovoice\nversion: 3.0.0+36\n');
    shas.clientOnly = commit('client change, 3.0.0+36');
    write('functions/index.js', 'exports.a = 2;\n');
    shas.backend = commit('backend change');
    git('update-ref', 'refs/remotes/origin/main', shas.backend);
    git('checkout', '-q', '-b', 'feature');
    write('lib/other.dart', '// off main\n');
    shas.offMain = commit('not on main');
    git('checkout', '-q', 'main');
    process.chdir(repo);
  });

  after(() => {
    process.chdir(cwd);
    rmSync(repo, { recursive: true, force: true });
  });

  // Check suite 100 is the push run on main, 200 the Hosting dispatch on main,
  // 300 a pull_request run on the same head SHA (it tests a merge commit).
  // ciEvent moves the CI check runs into another run's suite.
  function fakeGitHub({ ci = 'success', web = 'success', ciEvent = 'push' } = {}) {
    const calls = [];
    const suiteFor = { push: 100, workflow_dispatch: 200, pull_request: 300 };
    const fetchImpl = async (url, options) => {
      calls.push({ url, options });
      const parsed = new URL(url);
      if (parsed.pathname.endsWith('/actions/runs')) {
        const sha = parsed.searchParams.get('head_sha');
        const workflowRuns = Object.entries(suiteFor).map(([event, suite]) => ({
          id: suite,
          event,
          head_branch: 'main',
          head_sha: sha,
          check_suite_id: suite,
        }));
        const body = JSON.stringify({ total_count: workflowRuns.length, workflow_runs: workflowRuns });
        return { status: 200, ok: true, text: async () => body };
      }
      const name = parsed.searchParams.get('check_name');
      const conclusion = name === 'deploy_hosting' ? web : ci;
      const suite = name === 'deploy_hosting' ? suiteFor.workflow_dispatch : suiteFor[ciEvent];
      const runs =
        conclusion === 'missing'
          ? []
          : [
              {
                id: 1,
                name,
                status: 'completed',
                conclusion,
                app: { slug: 'github-actions' },
                check_suite: { id: suite },
                html_url: null,
              },
            ];
      const body = JSON.stringify({ check_runs: runs });
      return { status: 200, ok: true, text: async () => body };
    };
    return { fetchImpl, calls };
  }

  const run = (overrides, github = fakeGitHub(), warnings = []) =>
    main([], {
      env: {
        ...validEnv(overrides),
        GITHUB_REPOSITORY: 'owner/repo',
        GITHUB_TOKEN: 'test-token',
        GITHUB_REF: 'refs/heads/main',
        GITHUB_SHA: shas.backend,
      },
      fetchImpl: github.fetchImpl,
      warnImpl: (message) => warnings.push(message),
    });

  test('passes a client-only real release and writes the outputs', async () => {
    writeFileSync(process.env.GITHUB_OUTPUT, '');
    await run({ RELEASE_REF: shas.clientOnly, RELEASE_DRY_RUN: 'false' });
    const outputs = readFileSync(process.env.GITHUB_OUTPUT, 'utf8');
    assert.match(outputs, new RegExp(`^sha=${shas.clientOnly}$`, 'mu'));
    assert.match(outputs, /^build_name=3\.0\.0$/mu);
    assert.match(outputs, /^build_number=36$/mu);
  });

  test('sends the token only to the GitHub API', async () => {
    const github = fakeGitHub();
    await run({ RELEASE_REF: shas.clientOnly, RELEASE_DRY_RUN: 'false' }, github);
    // One workflow-runs read (to learn which check suites are trusted) plus
    // one check-runs read per gate.
    assert.equal(github.calls.length, 4);
    for (const call of github.calls) {
      assert.ok(
        call.url.startsWith('https://api.github.com/repos/owner/repo/commits/') ||
          call.url.startsWith(`https://api.github.com/repos/owner/repo/actions/runs?head_sha=${shas.clientOnly}&`),
        call.url,
      );
      assert.equal(call.options.headers.Authorization, 'Bearer test-token');
    }
  });

  test('refuses a backend change without backend_confirmed, accepts it with', async () => {
    await assert.rejects(run({ RELEASE_REF: shas.backend, RELEASE_DRY_RUN: 'false' }), /backend file/u);
    await run({ RELEASE_REF: shas.backend, RELEASE_DRY_RUN: 'false', RELEASE_BACKEND_CONFIRMED: 'true' });
  });

  test('an explicit since_ref moves the baseline', async () => {
    // The default baseline (store-build-35) sees the Functions change...
    await assert.rejects(run({ RELEASE_REF: shas.backend, RELEASE_DRY_RUN: 'false' }), /backend file/u);
    // ...a baseline after it does not, and a baseline before it still does.
    await run({ RELEASE_REF: shas.backend, RELEASE_DRY_RUN: 'false', RELEASE_SINCE_REF: shas.backend });
    await assert.rejects(
      run({ RELEASE_REF: shas.backend, RELEASE_DRY_RUN: 'false', RELEASE_SINCE_REF: shas.clientOnly }),
      /backend file/u,
    );
    await assert.rejects(
      run({ RELEASE_REF: shas.clientOnly, RELEASE_DRY_RUN: 'false', RELEASE_SINCE_REF: shas.backend }),
      /not an ancestor/u,
    );
  });

  test('refuses a build number that does not match the pubspec', async () => {
    await assert.rejects(run({ RELEASE_REF: shas.released, RELEASE_BUILD_NUMBER: '36' }), /does not match pubspec/u);
  });

  test('refuses a commit that is not on main, in both modes', async () => {
    await assert.rejects(run({ RELEASE_REF: shas.offMain }), /not on main/u);
    await assert.rejects(run({ RELEASE_REF: shas.offMain, RELEASE_DRY_RUN: 'false' }), /not on main/u);
  });

  test('refuses a real release dispatched from another branch', async () => {
    await assert.rejects(
      main([], {
        env: {
          ...validEnv({ RELEASE_REF: shas.clientOnly, RELEASE_DRY_RUN: 'false' }),
          GITHUB_REPOSITORY: 'owner/repo',
          GITHUB_TOKEN: 't',
          GITHUB_REF: 'refs/heads/feature',
        },
        fetchImpl: fakeGitHub().fetchImpl,
        warnImpl: () => {},
      }),
      /dispatched from main/u,
    );
  });

  test('refuses red CI and a missing web deploy on a real run, warns on a dry run', async () => {
    await assert.rejects(
      run({ RELEASE_REF: shas.clientOnly, RELEASE_DRY_RUN: 'false' }, fakeGitHub({ ci: 'cancelled' })),
      /CI check/u,
    );
    await assert.rejects(
      run({ RELEASE_REF: shas.clientOnly, RELEASE_DRY_RUN: 'false' }, fakeGitHub({ web: 'missing' })),
      /deploy_hosting/u,
    );
    await run(
      { RELEASE_REF: shas.clientOnly, RELEASE_DRY_RUN: 'false', RELEASE_WEB_CONFIRMED: 'true' },
      fakeGitHub({ web: 'missing' }),
    );
    const warnings = [];
    await run({ RELEASE_REF: shas.backend }, fakeGitHub({ ci: 'missing', web: 'missing' }), warnings);
    assert.equal(warnings.length, 4);
  });

  test('green CI from a pull_request run does not satisfy a real release; a dispatch run on main does', async () => {
    await assert.rejects(
      run({ RELEASE_REF: shas.clientOnly, RELEASE_DRY_RUN: 'false' }, fakeGitHub({ ciEvent: 'pull_request' })),
      /CI check "verify_and_build" is missing/u,
    );
    await run({ RELEASE_REF: shas.clientOnly, RELEASE_DRY_RUN: 'false' }, fakeGitHub({ ciEvent: 'workflow_dispatch' }));
  });

  test('fails closed with no baseline at all', async () => {
    git('tag', '-d', 'store-build-35');
    try {
      await assert.rejects(run({ RELEASE_REF: shas.clientOnly, RELEASE_DRY_RUN: 'false' }), /No store-release baseline/u);
    } finally {
      git('tag', 'store-build-35', shas.released);
    }
  });

  test('refuses a build number already tagged on another commit', async () => {
    git('tag', 'store-build-36', shas.released);
    try {
      await assert.rejects(
        run({ RELEASE_REF: shas.clientOnly, RELEASE_DRY_RUN: 'false' }),
        /already tagged store-build-36/u,
      );
    } finally {
      git('tag', '-d', 'store-build-36');
    }
  });

  test('refuses a tree that turns the Gradle configuration cache on', async () => {
    write('android/gradle.properties', 'org.gradle.configuration-cache=true\n');
    const sha = commit('config cache on');
    git('update-ref', 'refs/remotes/origin/main', sha);
    try {
      await assert.rejects(run({ RELEASE_REF: sha }), /configuration cache/u);
    } finally {
      git('update-ref', 'refs/remotes/origin/main', shas.backend);
    }
  });
});
