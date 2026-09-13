"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execFileSync, spawnSync } = require("node:child_process");
const { after, test } = require("node:test");

const {
  COMPATIBILITY_EXPORTS,
  INFRASTRUCTURE_COMPATIBILITY_EXPORTS,
  PHASE_FILES,
  buildActivationPackage,
  inspectServersSource,
  phasePlan,
  preparePackageDependencies,
  verifyPackage,
} = require("../servers_activation_package");
const registration = require("../../functions/servers/registration");

const temporaryRoots = [];
const EXPECTED_COMPATIBILITY_EXPORTS = Object.freeze([
  "createCommunityClub",
  "createRoom",
  "finalizeClubMedia",
  "transferClubOwnershipSelf",
  "removeClubMemberSelf",
  "deleteClubSelf",
  "sendClubMessage",
  "sendRoomMessage",
  "startRoomVoice",
  "createLiveKitToken",
  "sendClubInvite",
  "moderateClubMessage",
  "createContentReport",
  "removeRoomParticipantSelf",
  "setOwnRoomParticipantMute",
  "moderateRoomParticipantSelf",
  "setRoomStatusSelf",
  "setRoomVisibilitySelf",
  "endRoomVoiceSelf",
  "leaveRoomSelf",
  "deleteRoomSelf",
  "reserveRoomCoverUpload",
  "finalizeRoomCoverUpload",
  "getRoomCoverMediaAccess",
  "expireRoomCoverUploadReservationsSchedule",
  "setClubModerationStatus",
  "removeClubMember",
  "setClubMemberBan",
  "adminDeleteClub",
  "transferClubOwnership",
  "setRoomModerationStatus",
  "forceEndRoom",
  "removeRoomParticipant",
  "setParticipantMute",
  "adminDeleteRoom",
  "adminDeleteMessage",
  "sweepStrandedLiveRoomsSchedule",
  "onModerationVoiceEnforcementCreated",
  "receiveLiveKitAchievementWebhook",
  "publishPublicShowcaseSchedule",
  "onClubInviteCreated",
  "onClubMemberCreated",
]);
const EXPECTED_INFRASTRUCTURE_EXPORTS = Object.freeze([
  "onServerInviteWritten",
  "sweepExpiredServerInvitesSchedule",
  "onServerControlOutboxCreated",
  "processPendingServerControlOutboxSchedule",
  "sweepStaleServerChannelSessionsSchedule",
  "sweepServerFamilyMemoryMaintenanceSchedule",
  "sweepServerCompanyFileMaintenanceSchedule",
]);

after(() => {
  for (const root of temporaryRoots) fs.rmSync(root, { recursive: true, force: true });
});

function write(file, contents) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, contents);
}

function git(source, args) {
  return execFileSync("git", ["-C", source, ...args], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  }).trim();
}

function canonicalInventory() {
  const podcast = new Set(registration.PODCAST_RECORDING_EXPORTS);
  return {
    baseNames: registration.SERVERS_V1_EXPORT_NAMES.filter((name) => !podcast.has(name)),
    callableNames: Object.keys(registration.SERVER_CALLABLE_METHODS),
    dispatcherNames: [...registration.DISPATCHER_EXPORTS],
    podcastNames: [...registration.PODCAST_RECORDING_EXPORTS],
    sweepNames: [...registration.SWEEP_EXPORTS],
  };
}

function fixture() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "yovoice-servers-activation-test-"));
  temporaryRoots.push(root);
  const source = path.join(root, "source");
  fs.mkdirSync(source);
  const inventory = canonicalInventory();
  write(path.join(source, ".gitignore"), "functions/node_modules/\n");
  const runtimePackage = {
    name: "activation-fixture-runtime",
    version: "1.0.0",
    main: "index.js",
  };
  const fixturePackage = {
    name: "activation-fixture",
    version: "1.0.0",
    private: true,
    main: "index.js",
    dependencies: {
      "activation-fixture-runtime": "file:vendor/activation-fixture-runtime",
    },
  };
  const fixtureLock = {
    name: fixturePackage.name,
    version: fixturePackage.version,
    lockfileVersion: 3,
    requires: true,
    packages: {
      "": {
        name: fixturePackage.name,
        version: fixturePackage.version,
        dependencies: fixturePackage.dependencies,
      },
      "node_modules/activation-fixture-runtime": {
        version: runtimePackage.version,
        resolved: "file:vendor/activation-fixture-runtime",
      },
      "vendor/activation-fixture-runtime": {
        name: runtimePackage.name,
        version: runtimePackage.version,
      },
    },
  };
  write(path.join(source, "functions", "servers", "registration.js"), [
    `const SERVER_CALLABLE_METHODS = Object.freeze(${JSON.stringify(registration.SERVER_CALLABLE_METHODS)});`,
    `const DISPATCHER_EXPORTS = Object.freeze(${JSON.stringify(inventory.dispatcherNames)});`,
    `const SWEEP_EXPORTS = Object.freeze(${JSON.stringify(inventory.sweepNames)});`,
    `const PODCAST_RECORDING_EXPORTS = Object.freeze(${JSON.stringify(inventory.podcastNames)});`,
    `const SERVERS_V1_EXPORT_NAMES = Object.freeze(${JSON.stringify(registration.SERVERS_V1_EXPORT_NAMES)});`,
    "module.exports = { SERVER_CALLABLE_METHODS, DISPATCHER_EXPORTS, SWEEP_EXPORTS, PODCAST_RECORDING_EXPORTS, SERVERS_V1_EXPORT_NAMES };",
    "",
  ].join("\n"));
  write(path.join(source, "functions", "index.js"), [
    "require('activation-fixture-runtime');",
    "const registration = require('./servers/registration');",
    "const podcast = new Set(registration.PODCAST_RECORDING_EXPORTS);",
    "for (const name of registration.SERVERS_V1_EXPORT_NAMES) if (!podcast.has(name)) exports[name] = () => name;",
    `for (const name of ${JSON.stringify([...COMPATIBILITY_EXPORTS, ...INFRASTRUCTURE_COMPATIBILITY_EXPORTS])}) exports[name] = () => name;`,
    "",
  ].join("\n"));
  write(path.join(source, "functions", "package.json"), `${JSON.stringify(fixturePackage, null, 2)}\n`);
  write(path.join(source, "functions", "package-lock.json"), `${JSON.stringify(fixtureLock, null, 2)}\n`);
  write(
    path.join(source, "functions", "vendor", "activation-fixture-runtime", "package.json"),
    `${JSON.stringify(runtimePackage, null, 2)}\n`,
  );
  write(
    path.join(source, "functions", "vendor", "activation-fixture-runtime", "index.js"),
    "module.exports = Object.freeze({ ready: true });\n",
  );
  write(path.join(source, "firestore.rules"), "rules_version = '2';\nservice cloud.firestore { match /databases/{database}/documents { match /{document=**} { allow read, write: if false; } } }\n");
  write(path.join(source, "firestore.indexes.json"), "{\"indexes\":[],\"fieldOverrides\":[]}\n");
  write(path.join(source, "storage.rules"), "rules_version = '2';\nservice firebase.storage { match /b/{bucket}/o { match /{object=**} { allow read, write: if false; } } }\n");
  write(
    path.join(source, "functions", "node_modules", "activation-fixture-runtime", "package.json"),
    `${JSON.stringify(runtimePackage, null, 2)}\n`,
  );
  write(
    path.join(source, "functions", "node_modules", "activation-fixture-runtime", "index.js"),
    "module.exports = Object.freeze({ ready: true });\n",
  );
  execFileSync("git", ["init", "-q", source]);
  git(source, ["config", "user.email", "activation-test@yovoice.invalid"]);
  git(source, ["config", "user.name", "YO Voice Activation Test"]);
  git(source, ["add", "."]);
  git(source, ["commit", "-q", "-m", "fixture"]);
  const sha = git(source, ["rev-parse", "HEAD"]);
  return { root, source, sha, output: path.join(root, "package"), inventory };
}

function sha256(file) {
  return crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
}

function refreshRecordedChecksums(packageRoot, relativeNames) {
  const names = new Set(relativeNames);
  const checksumPath = path.join(packageRoot, "SHA256SUMS");
  const lines = fs.readFileSync(checksumPath, "utf8").trimEnd().split("\n").map((line) => {
    const separator = line.indexOf("  ");
    const name = line.slice(separator + 2);
    if (!names.has(name)) return line;
    names.delete(name);
    return `${sha256(path.join(packageRoot, ...name.split("/")))}  ${name}`;
  });
  assert.equal(names.size, 0);
  fs.writeFileSync(checksumPath, `${lines.join("\n")}\n`);
  return sha256(checksumPath);
}

function runtimeEnvironment() {
  const environment = { ...process.env };
  delete environment.NODE_OPTIONS;
  delete environment.NODE_PATH;
  return environment;
}

function selectorNames(file) {
  const text = fs.readFileSync(file, "utf8");
  assert.equal(text.endsWith("\n"), true);
  assert.equal(text.trim().includes(" "), false);
  return text.trim().split(",").map((target) => {
    assert.match(target, /^functions:[A-Za-z][A-Za-z0-9]*$/u);
    return target.slice("functions:".length);
  });
}

test("phase plan partitions all 53 source-static Server exports exactly once", () => {
  const inventory = canonicalInventory();
  const phases = phasePlan(inventory);
  const podcast = new Set(inventory.podcastNames);
  const selected = Object.values(phases).flat();
  const selectedBase = selected.filter((name) => inventory.baseNames.includes(name));

  assert.equal(inventory.baseNames.length, 53);
  assert.equal(selectedBase.length, 53);
  assert.equal(new Set(selectedBase).size, 53);
  assert.deepEqual(new Set(selectedBase), new Set(inventory.baseNames));
  assert.deepEqual(phases.phase0CompatibilityGuards, EXPECTED_COMPATIBILITY_EXPORTS);
  assert.deepEqual(phases.phase1Infrastructure, EXPECTED_INFRASTRUCTURE_EXPORTS);
  assert.equal(phases.phase1Infrastructure.filter((name) => inventory.baseNames.includes(name)).length, 5);
  assert.equal(phases.phase0CompatibilityGuards.some((name) => inventory.baseNames.includes(name)), false);
  assert.equal(phases.phase1Infrastructure.slice(0, 2).some((name) => inventory.baseNames.includes(name)), false);
  assert.equal(phases.phase2NonCreationCallables.length, 47);
  assert.deepEqual(phases.phase3CreationBlocked, ["createServerV1"]);
  assert.equal(selected.some((name) => podcast.has(name)), false);
  assert.equal(new Set(selected).size, selected.length);
});

test("clean exact-SHA generation creates a self-contained, checksummed package", () => {
  const value = fixture();
  const result = buildActivationPackage({
    source: value.source,
    expectedSha: value.sha,
    output: value.output,
  });
  assert.equal(result.sha, value.sha);
  assert.equal(result.output, path.join(fs.realpathSync(value.root), "package"));
  assert.equal(git(value.source, ["status", "--porcelain=v1", "--untracked-files=all"]), "");

  const generated = path.join(result.output, "generated");
  const config = JSON.parse(fs.readFileSync(path.join(generated, "firebase.activation.json"), "utf8"));
  const sourceRoot = path.join(result.output, "source");
  for (const target of [
    config.functions[0].source,
    config.firestore.rules,
    config.firestore.indexes,
    config.storage.rules,
  ]) {
    assert.equal(path.isAbsolute(target), true);
    assert.equal(path.relative(sourceRoot, target).startsWith(".."), false);
    assert.equal(fs.existsSync(target), true);
  }
  assert.equal(fs.readFileSync(path.join(generated, "SOURCE_COMMIT.txt"), "utf8"), `${value.sha}\n`);

  const phases = Object.fromEntries(Object.entries(PHASE_FILES).map(([phase, filename]) => [
    phase,
    selectorNames(path.join(generated, filename)),
  ]));
  assert.deepEqual(phases, result.phases);
  const allSelectors = Object.values(phases).flat();
  for (const name of value.inventory.podcastNames) assert.equal(allSelectors.includes(name), false, name);
  assert.equal(fs.existsSync(path.join(result.output, "SHA256SUMS")), true);
  assert.match(result.manifestSha256, /^[0-9a-f]{64}$/u);
  assert.deepEqual(verifyPackage(result.output, {
    expectedSha: value.sha,
    expectedManifestSha256: result.manifestSha256,
  }), {
    fileCount: result.fileCount,
    manifestSha256: result.manifestSha256,
    sha: value.sha,
  });
  assert.throws(() => verifyPackage(result.output), /requires one trusted lowercase 40-character/u);
  const standardVerification = spawnSync("shasum", ["-a", "256", "-c", "SHA256SUMS"], {
    cwd: result.output,
    encoding: "utf8",
  });
  assert.equal(standardVerification.status, 0, standardVerification.stderr);
});

test("source inspection proves environment-independent registration and no Podcast exports", () => {
  const value = fixture();
  const inspected = inspectServersSource(value.source);
  assert.deepEqual(inspected.baseNames, value.inventory.baseNames);
  assert.deepEqual(inspected.podcastNames, value.inventory.podcastNames);
  assert.equal(inspected.baseNames.length, 53);
});

test("generation fails closed on a mismatched SHA, malformed SHA, dirty tree, and in-tree output", () => {
  const value = fixture();
  assert.throws(() => buildActivationPackage({
    source: value.source,
    expectedSha: "0".repeat(40),
    output: value.output,
  }), /does not match expected SHA/u);
  assert.throws(() => buildActivationPackage({
    source: value.source,
    expectedSha: value.sha.toUpperCase(),
    output: value.output,
  }), /exact lowercase 40-character/u);

  write(path.join(value.source, "untracked.txt"), "dirty\n");
  assert.throws(() => buildActivationPackage({
    source: value.source,
    expectedSha: value.sha,
    output: value.output,
  }), /worktree is dirty/u);
  fs.rmSync(path.join(value.source, "untracked.txt"));

  assert.throws(() => buildActivationPackage({
    source: value.source,
    expectedSha: value.sha,
    output: path.join(value.source, "activation-package"),
  }), /outside the source worktree/u);
  assert.equal(fs.existsSync(value.output), false);
});

test("checksum verification detects content tampering and unlisted files", () => {
  const altered = fixture();
  const alteredResult = buildActivationPackage({
    source: altered.source,
    expectedSha: altered.sha,
    output: altered.output,
  });
  const selector = path.join(altered.output, "generated", PHASE_FILES.phase3CreationBlocked);
  fs.appendFileSync(selector, "functions:publishServerPodcastEpisodeV1\n");
  assert.throws(() => verifyPackage(altered.output, {
    expectedSha: altered.sha,
    expectedManifestSha256: alteredResult.manifestSha256,
  }), /Checksum mismatch/u);
  const standardVerification = spawnSync("shasum", ["-a", "256", "-c", "SHA256SUMS"], {
    cwd: altered.output,
    encoding: "utf8",
  });
  assert.notEqual(standardVerification.status, 0);

  const added = fixture();
  const addedResult = buildActivationPackage({ source: added.source, expectedSha: added.sha, output: added.output });
  write(path.join(added.output, "unlisted.txt"), "tamper\n");
  assert.throws(() => verifyPackage(added.output, {
    expectedSha: added.sha,
    expectedManifestSha256: addedResult.manifestSha256,
  }), /does not cover every activation-package file/u);
});

test("trusted external anchors reject a fully recomputed in-package checksum manifest", () => {
  const value = fixture();
  const result = buildActivationPackage({ source: value.source, expectedSha: value.sha, output: value.output });
  const selectorName = `generated/${PHASE_FILES.phase3CreationBlocked}`;
  const markerName = "generated/SOURCE_COMMIT.txt";
  write(path.join(value.output, ...selectorName.split("/")), "functions:updateServerV1\n");
  write(path.join(value.output, ...markerName.split("/")), `${"1".repeat(40)}\n`);
  const attackerManifestSha256 = refreshRecordedChecksums(value.output, [selectorName, markerName]);

  assert.throws(() => verifyPackage(value.output, {
    expectedSha: value.sha,
    expectedManifestSha256: result.manifestSha256,
  }), /does not match the trusted external digest/u);
  assert.throws(() => verifyPackage(value.output, {
    expectedSha: value.sha,
    expectedManifestSha256: attackerManifestSha256,
  }), /does not match the trusted expected SHA/u);
});

test("inspection and package bytes come from the exact commit rather than a hidden worktree edit", () => {
  const value = fixture();
  const registrationPath = "functions/servers/registration.js";
  git(value.source, ["update-index", "--assume-unchanged", registrationPath]);
  write(path.join(value.source, ...registrationPath.split("/")), "throw new Error('mutable worktree was inspected');\n");
  assert.equal(git(value.source, ["status", "--porcelain=v1", "--untracked-files=all"]), "");

  try {
    const result = buildActivationPackage({ source: value.source, expectedSha: value.sha, output: value.output });
    const committed = execFileSync("git", ["-C", value.source, "show", `${value.sha}:${registrationPath}`]);
    assert.deepEqual(fs.readFileSync(path.join(result.output, "source", ...registrationPath.split("/"))), committed);
  } finally {
    git(value.source, ["update-index", "--no-assume-unchanged", registrationPath]);
  }
});

test("the output path is reserved before inspection and cannot be replaced", () => {
  const value = fixture();
  let reservationObserved = false;
  buildActivationPackage({
    source: value.source,
    expectedSha: value.sha,
    output: value.output,
    inspect: () => {
      reservationObserved = fs.statSync(value.output).isDirectory();
      assert.throws(() => fs.mkdirSync(value.output), { code: "EEXIST" });
      return canonicalInventory();
    },
  });
  assert.equal(reservationObserved, true);
});

test("moving a path-bound package blocks the anchored deployment preflight", () => {
  const value = fixture();
  const result = buildActivationPackage({ source: value.source, expectedSha: value.sha, output: value.output });
  const moved = path.join(value.root, "moved-package");
  fs.renameSync(value.output, moved);
  const standardVerification = spawnSync("shasum", ["-a", "256", "-c", "SHA256SUMS"], {
    cwd: moved,
    encoding: "utf8",
  });
  assert.equal(standardVerification.status, 0, standardVerification.stderr);
  assert.throws(() => verifyPackage(moved, {
    expectedSha: value.sha,
    expectedManifestSha256: result.manifestSha256,
  }), /path escapes package\/source/u);
});

test("locked dependency preparation makes the packaged Functions index locally loadable", () => {
  const value = fixture();
  const result = buildActivationPackage({ source: value.source, expectedSha: value.sha, output: value.output });
  const packagedSource = path.join(value.output, "source");
  const loadArguments = ["-e", "require('./functions/index.js')"];
  const before = spawnSync(process.execPath, loadArguments, {
    cwd: packagedSource,
    encoding: "utf8",
    env: runtimeEnvironment(),
  });
  assert.notEqual(before.status, 0, "fixture unexpectedly loaded without package-local dependencies");

  const prepared = preparePackageDependencies(value.output, {
    expectedSha: value.sha,
    expectedManifestSha256: result.manifestSha256,
  });
  assert.equal(prepared.dependenciesPrepared, true);
  assert.equal(prepared.manifestSha256, result.manifestSha256);
  const afterPrepare = spawnSync(process.execPath, loadArguments, {
    cwd: packagedSource,
    encoding: "utf8",
    env: runtimeEnvironment(),
  });
  assert.equal(afterPrepare.status, 0, afterPrepare.stderr);
  assert.equal(
    fs.readFileSync(path.join(value.output, "SHA256SUMS"), "utf8").includes("source/functions/node_modules/"),
    false,
  );

  write(path.join(packagedSource, "functions", "node_modules", "operational-cache.txt"), "ignored\n");
  assert.equal(verifyPackage(value.output, {
    expectedSha: value.sha,
    expectedManifestSha256: result.manifestSha256,
  }).manifestSha256, result.manifestSha256);
});

test("locked dependency preparation rejects a stale generation-time selector plan", () => {
  const value = fixture();
  const compromisedInventory = canonicalInventory();
  const first = compromisedInventory.callableNames.indexOf("updateServerV1");
  const second = compromisedInventory.callableNames.indexOf("deleteServerV1");
  [compromisedInventory.callableNames[first], compromisedInventory.callableNames[second]] = [
    compromisedInventory.callableNames[second],
    compromisedInventory.callableNames[first],
  ];
  const result = buildActivationPackage({
    source: value.source,
    expectedSha: value.sha,
    output: value.output,
    inspect: () => compromisedInventory,
  });
  assert.throws(() => preparePackageDependencies(value.output, {
    expectedSha: value.sha,
    expectedManifestSha256: result.manifestSha256,
  }), /does not match the locked-dependency source plan/u);
});

test("generation refuses to overwrite an existing package", () => {
  const value = fixture();
  fs.mkdirSync(value.output);
  assert.throws(() => buildActivationPackage({
    source: value.source,
    expectedSha: value.sha,
    output: value.output,
  }), /refusing to overwrite/u);
});
