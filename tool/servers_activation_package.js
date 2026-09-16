#!/usr/bin/env node

"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

const EXACT_SHA = /^[0-9a-f]{40}$/u;
const SHA256 = /^[0-9a-f]{64}$/u;
const CHECKSUM = /^([0-9a-f]{64})  ([^\r\n]+)$/u;
const INSPECTION_MARKER = "YOVOICE_SERVERS_ACTIVATION_INSPECTION=";
const OPERATIONAL_DEPENDENCY_ROOT = "source/functions/node_modules";

const PHASE_FILES = Object.freeze({
  phase0CompatibilityGuards: "phase0CompatibilityGuards.firebase-only.txt",
  phase1Infrastructure: "phase1Infrastructure.firebase-only.txt",
  phase2NonCreationCallables: "phase2NonCreationCallables.firebase-only.txt",
  phase3CreationBlocked: "phase3CreationBlocked.firebase-only.txt",
});

// Existing functions that must precede the source-static Servers surface.
// They are deliberately outside the 54-name Servers V1 base manifest.
const COMPATIBILITY_EXPORTS = Object.freeze([
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

const INFRASTRUCTURE_COMPATIBILITY_EXPORTS = Object.freeze([
  "onServerInviteWritten",
  "sweepExpiredServerInvitesSchedule",
]);

const REQUIRED_SOURCE_PATHS = Object.freeze([
  "functions",
  "firestore.indexes.json",
  "firestore.rules",
  "storage.rules",
]);

function fail(message) {
  throw new Error(message);
}

function runGit(source, args, options = {}) {
  return execFileSync("git", ["-C", source, ...args], {
    encoding: options.encoding === undefined ? "utf8" : options.encoding,
    maxBuffer: options.maxBuffer ?? 64 * 1024 * 1024,
    stdio: ["ignore", "pipe", "pipe"],
  });
}

function exactSourceIdentity(source, expectedSha) {
  if (!EXACT_SHA.test(expectedSha)) {
    fail("--expected-sha must be one exact lowercase 40-character commit SHA.");
  }
  const sourceReal = fs.realpathSync(source);
  const topLevel = fs.realpathSync(runGit(sourceReal, ["rev-parse", "--show-toplevel"]).trim());
  if (sourceReal !== topLevel) {
    fail(`--source must name the Git worktree root exactly: ${topLevel}`);
  }
  const head = runGit(sourceReal, ["rev-parse", "HEAD"]).trim();
  if (head !== expectedSha) {
    fail(`Source HEAD ${head} does not match expected SHA ${expectedSha}.`);
  }
  const commit = runGit(sourceReal, ["rev-parse", `${expectedSha}^{commit}`]).trim();
  if (commit !== expectedSha) {
    fail(`Expected SHA does not resolve to the exact source commit: ${expectedSha}.`);
  }
  const status = runGit(sourceReal, ["status", "--porcelain=v1", "--untracked-files=all"]);
  if (status !== "") {
    fail("Source worktree is dirty; refusing to create an activation package.");
  }
  return Object.freeze({ source: sourceReal, sha: head });
}

function outputIdentity(source, output) {
  const absolute = path.resolve(output);
  const parent = fs.realpathSync(path.dirname(absolute));
  const resolved = path.join(parent, path.basename(absolute));
  const relativeToSource = path.relative(source, resolved);
  if (relativeToSource === "" || (!relativeToSource.startsWith(`..${path.sep}`) && relativeToSource !== "..")) {
    fail("--output must be outside the source worktree so generation cannot dirty the exact source.");
  }
  if (fs.existsSync(resolved)) {
    fail(`Output already exists; refusing to overwrite it: ${resolved}`);
  }
  return resolved;
}

function inspectionEnvironment(overrides = {}, nodePath) {
  const environment = { ...process.env };
  for (const name of Object.keys(environment)) {
    if (name.startsWith("YOVOICE_") || name === "STRIPE_BILLING_EXPORTS" ||
        name === "K_SERVICE" || name === "FUNCTION_TARGET" ||
        name === "FIREBASE_CONFIG" || name === "GCLOUD_PROJECT" ||
        name === "NODE_OPTIONS" || name === "NODE_PATH") {
      delete environment[name];
    }
  }
  environment.GCLOUD_PROJECT = "yovoice-activation-inspection";
  environment.FIREBASE_CONFIG = JSON.stringify({
    projectId: environment.GCLOUD_PROJECT,
    storageBucket: `${environment.GCLOUD_PROJECT}.firebasestorage.app`,
  });
  if (nodePath !== undefined) environment.NODE_PATH = path.resolve(nodePath);
  return { ...environment, ...overrides };
}

function inspectOnce(source, overrides, options) {
  const script = [
    "const registration = require('./servers/registration.js');",
    "const root = require('./index.js');",
    "const result = {",
    "  callableNames: Object.keys(registration.ALL_SERVER_CALLABLE_METHODS),",
    "  dispatcherNames: [...registration.DISPATCHER_EXPORTS],",
    "  sweepNames: [...registration.SWEEP_EXPORTS],",
    "  allServerNames: [...registration.SERVERS_V1_EXPORT_NAMES],",
    "  podcastNames: [...registration.PODCAST_RECORDING_EXPORTS],",
    "  rootExportNames: Object.keys(root),",
    "  rootFunctionNames: Object.keys(root).filter((name) => typeof root[name] === 'function'),",
    "};",
    `process.stdout.write('\\n${INSPECTION_MARKER}' + JSON.stringify(result));`,
  ].join("\n");
  let output;
  try {
    output = execFileSync(process.execPath, ["-e", script], {
      cwd: path.join(source, "functions"),
      encoding: "utf8",
      env: inspectionEnvironment(overrides, options.nodePath),
      maxBuffer: 64 * 1024 * 1024,
      stdio: ["ignore", "pipe", "pipe"],
    });
  } catch (error) {
    const detail = String(error.stderr ?? error.message ?? error).trim();
    fail(`Unable to inspect the Functions export map: ${detail}`);
  }
  const markerAt = output.lastIndexOf(INSPECTION_MARKER);
  if (markerAt < 0) fail("Functions inspection produced no parseable export manifest.");
  try {
    return JSON.parse(output.slice(markerAt + INSPECTION_MARKER.length));
  } catch {
    fail("Functions inspection produced malformed export metadata.");
  }
}

function uniqueNames(value, label) {
  if (!Array.isArray(value) || value.some((name) => typeof name !== "string" || !/^[A-Za-z][A-Za-z0-9]*$/u.test(name))) {
    fail(`${label} is not a valid export-name list.`);
  }
  if (new Set(value).size !== value.length) fail(`${label} contains duplicate names.`);
  return value;
}

function inspectServersSource(source, options = {}) {
  const baseline = inspectOnce(source, {}, options);
  const hostileEnvironment = inspectOnce(source, {
    YOVOICE_SERVERS_V1: "enabled",
    YOVOICE_PODCAST_RECORDING_ENABLED: "true",
  }, options);
  for (const [label, value] of Object.entries(baseline)) uniqueNames(value, label);
  for (const [label, value] of Object.entries(hostileEnvironment)) uniqueNames(value, `hostile ${label}`);
  for (const label of Object.keys(baseline)) {
    if (JSON.stringify(baseline[label]) !== JSON.stringify(hostileEnvironment[label])) {
      fail(`A late environment value changes the source-static Functions manifest: ${label}.`);
    }
  }

  const allServerNames = baseline.allServerNames;
  const podcastNames = baseline.podcastNames;
  const podcast = new Set(podcastNames);
  const baseNames = allServerNames.filter((name) => !podcast.has(name));
  const hostileBase = hostileEnvironment.allServerNames.filter(
    (name) => !new Set(hostileEnvironment.podcastNames).has(name),
  );
  if (allServerNames.length !== 61 || baseline.callableNames.length !== 55 || podcastNames.length !== 7 || baseNames.length !== 54) {
    fail("Servers registration is not the reviewed 61-total/55-callable/7-Podcast/54-base manifest.");
  }
  if (JSON.stringify(baseNames) !== JSON.stringify(hostileBase)) {
    fail("A late environment value changes the source-static Servers base manifest.");
  }
  const root = new Set(baseline.rootExportNames);
  const rootFunctions = new Set(baseline.rootFunctionNames);
  for (const name of baseNames) {
    if (!root.has(name) || !rootFunctions.has(name)) fail(`Source-static Server function is absent from functions/index.js: ${name}.`);
  }
  for (const name of podcastNames) {
    if (root.has(name)) fail(`Podcast recording export must remain source-disabled: ${name}.`);
  }
  for (const name of [...COMPATIBILITY_EXPORTS, ...INFRASTRUCTURE_COMPATIBILITY_EXPORTS]) {
    if (!root.has(name) || !rootFunctions.has(name)) fail(`Required compatibility function is absent: ${name}.`);
  }
  return Object.freeze({
    baseNames: Object.freeze([...baseNames]),
    callableNames: Object.freeze([...baseline.callableNames]),
    dispatcherNames: Object.freeze([...baseline.dispatcherNames]),
    podcastNames: Object.freeze([...podcastNames]),
    sweepNames: Object.freeze([...baseline.sweepNames]),
  });
}

function phasePlan(inventory) {
  const podcast = new Set(uniqueNames([...inventory.podcastNames], "podcastNames"));
  const baseNames = uniqueNames([...inventory.baseNames], "baseNames");
  const callables = uniqueNames([...inventory.callableNames], "callableNames");
  const infrastructureBase = [
    ...uniqueNames([...inventory.dispatcherNames], "dispatcherNames"),
    ...uniqueNames([...inventory.sweepNames], "sweepNames"),
  ].filter((name) => !podcast.has(name));
  if (infrastructureBase.length !== 5 || new Set(infrastructureBase).size !== 5) {
    fail("The reviewed base infrastructure intersection must contain exactly five exports.");
  }
  if (!baseNames.includes("createServerV1")) fail("The reviewed creation export is missing.");
  const nonCreation = callables.filter((name) => !podcast.has(name) && name !== "createServerV1");
  if (nonCreation.length !== 48) fail("The reviewed non-creation callable phase must contain exactly 48 exports.");

  const plan = {
    phase0CompatibilityGuards: [...COMPATIBILITY_EXPORTS],
    phase1Infrastructure: [...INFRASTRUCTURE_COMPATIBILITY_EXPORTS, ...infrastructureBase],
    phase2NonCreationCallables: nonCreation,
    phase3CreationBlocked: ["createServerV1"],
  };
  const selectedBase = Object.values(plan).flat().filter((name) => baseNames.includes(name));
  if (selectedBase.length !== 54 || new Set(selectedBase).size !== 54 ||
      baseNames.some((name) => !selectedBase.includes(name))) {
    fail("Phase selectors do not cover every source-static Server export exactly once.");
  }
  const allSelected = Object.values(plan).flat();
  if (allSelected.some((name) => podcast.has(name))) fail("A Podcast recording export entered an activation phase.");
  if (new Set(allSelected).size !== allSelected.length) fail("An export occurs in more than one activation phase.");
  return Object.freeze(Object.fromEntries(
    Object.entries(plan).map(([key, names]) => [key, Object.freeze(names)]),
  ));
}

function trackedEntries(source, sha) {
  const raw = runGit(source, ["ls-tree", "-rz", "--full-tree", sha, "--", ...REQUIRED_SOURCE_PATHS], {
    encoding: null,
  });
  const entries = raw.toString("utf8").split("\0").filter(Boolean).map((line) => {
    const match = /^(\d{6}) (\S+) ([0-9a-f]+)\t(.+)$/u.exec(line);
    if (!match) fail("Git returned a malformed tree entry.");
    return { mode: match[1], type: match[2], oid: match[3], name: match[4] };
  });
  if (entries.length === 0) fail("The exact source commit contains no deployable files.");
  for (const required of REQUIRED_SOURCE_PATHS.slice(1)) {
    if (!entries.some((entry) => entry.name === required)) fail(`Exact source commit is missing ${required}.`);
  }
  if (!entries.some((entry) => entry.name === "functions/index.js") ||
      !entries.some((entry) => entry.name === "functions/package.json")) {
    fail("Exact source commit is missing the Functions deployment entrypoints.");
  }
  if (entries.some((entry) => entry.name === "functions/node_modules" ||
      entry.name.startsWith("functions/node_modules/"))) {
    fail("The exact source commit must not track functions/node_modules.");
  }
  return entries;
}

function safeRelativeFile(name) {
  if (name.includes("\0") || name.includes("\n") || name.includes("\r") || path.isAbsolute(name)) {
    fail(`Unsafe source path: ${JSON.stringify(name)}.`);
  }
  const normalized = path.posix.normalize(name);
  if (normalized !== name || normalized === ".." || normalized.startsWith("../")) {
    fail(`Source path escapes the package: ${JSON.stringify(name)}.`);
  }
  return normalized;
}

function copyExactSource(source, sha, destination) {
  const entries = trackedEntries(source, sha);
  for (const entry of entries) {
    if (entry.type !== "blob" || !["100644", "100755"].includes(entry.mode)) {
      fail(`Unsupported exact-source entry ${entry.name} (${entry.mode} ${entry.type}).`);
    }
    const relative = safeRelativeFile(entry.name);
    const output = path.join(destination, ...relative.split("/"));
    fs.mkdirSync(path.dirname(output), { recursive: true });
    const contents = runGit(source, ["cat-file", "blob", entry.oid], { encoding: null });
    fs.writeFileSync(output, contents, { mode: entry.mode === "100755" ? 0o755 : 0o644 });
  }
}

function selectorText(names) {
  return `${names.map((name) => `functions:${name}`).join(",")}\n`;
}

function parseSelectorText(contents, label) {
  if (typeof contents !== "string" || contents.length === 0 || !contents.endsWith("\n") ||
      contents.slice(0, -1).includes("\n") || contents.includes("\r")) {
    fail(`${label} is not one canonical Firebase selector line.`);
  }
  const names = contents.slice(0, -1).split(",").map((target) => {
    const match = /^functions:([A-Za-z][A-Za-z0-9]*)$/u.exec(target);
    if (!match) fail(`${label} contains an invalid Firebase function target.`);
    return match[1];
  });
  return uniqueNames(names, label);
}

function validateGeneratedSelectors(packageRoot, plan) {
  for (const [phase, filename] of Object.entries(PHASE_FILES)) {
    const label = `generated/${filename}`;
    const contents = fs.readFileSync(path.join(packageRoot, "generated", filename), "utf8");
    const names = parseSelectorText(contents, label);
    if (contents !== selectorText(plan[phase]) || JSON.stringify(names) !== JSON.stringify(plan[phase])) {
      fail(`${label} does not match the locked-dependency source plan.`);
    }
  }
}

function firebaseConfig(finalOutput) {
  const source = path.join(finalOutput, "source");
  return {
    functions: [{
      source: path.join(source, "functions"),
      codebase: "default",
      ignore: ["node_modules", ".git", "firebase-debug.log", "firebase-debug.*.log"],
    }],
    firestore: {
      rules: path.join(source, "firestore.rules"),
      indexes: path.join(source, "firestore.indexes.json"),
    },
    storage: { rules: path.join(source, "storage.rules") },
  };
}

function walkFiles(root, relative = "") {
  const here = path.join(root, relative);
  const files = [];
  for (const entry of fs.readdirSync(here, { withFileTypes: true }).sort(
    (a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0,
  )) {
    const child = relative === "" ? entry.name : `${relative}/${entry.name}`;
    if (entry.isDirectory() && child === OPERATIONAL_DEPENDENCY_ROOT) continue;
    if (entry.isDirectory()) files.push(...walkFiles(root, child));
    else if (entry.isFile()) files.push(child);
    else fail(`Activation package contains unsupported filesystem entry: ${child}.`);
  }
  return files;
}

function sha256(file) {
  return crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
}

function writeChecksums(root) {
  const files = walkFiles(root).filter((name) => name !== "SHA256SUMS");
  const body = files.map((name) => `${sha256(path.join(root, name))}  ${name}`).join("\n");
  const checksumPath = path.join(root, "SHA256SUMS");
  fs.writeFileSync(checksumPath, `${body}\n`, { mode: 0o644 });
  return sha256(checksumPath);
}

function inside(parent, candidate) {
  const relative = path.relative(parent, candidate);
  return relative === "" || (!relative.startsWith(`..${path.sep}`) && relative !== "..");
}

function validateConfigPaths(packageRoot, config) {
  const sourceRoot = path.join(packageRoot, "source");
  const paths = [
    config?.functions?.[0]?.source,
    config?.firestore?.rules,
    config?.firestore?.indexes,
    config?.storage?.rules,
  ];
  if (paths.some((value) => typeof value !== "string" || !path.isAbsolute(value))) {
    fail("Firebase activation config must contain absolute package-source paths.");
  }
  for (const target of paths) {
    if (!inside(sourceRoot, target)) fail(`Firebase activation path escapes package/source: ${target}.`);
    if (!fs.existsSync(target)) fail(`Firebase activation path does not resolve: ${target}.`);
  }
}

function verifyPackage(packageRoot, { expectedSha, expectedManifestSha256 } = {}) {
  if (!EXACT_SHA.test(expectedSha ?? "")) {
    fail("Package verification requires one trusted lowercase 40-character expected SHA.");
  }
  if (!SHA256.test(expectedManifestSha256 ?? "")) {
    fail("Package verification requires one trusted lowercase SHA256SUMS digest.");
  }
  const root = fs.realpathSync(packageRoot);
  const checksumPath = path.join(root, "SHA256SUMS");
  const actualManifestSha256 = sha256(checksumPath);
  if (!crypto.timingSafeEqual(
    Buffer.from(actualManifestSha256, "hex"),
    Buffer.from(expectedManifestSha256, "hex"),
  )) {
    fail("SHA256SUMS does not match the trusted external digest.");
  }
  const lines = fs.readFileSync(checksumPath, "utf8").split("\n").filter(Boolean);
  const recorded = new Map();
  for (const line of lines) {
    const match = CHECKSUM.exec(line);
    if (!match) fail(`Malformed checksum line: ${line}.`);
    const name = safeRelativeFile(match[2]);
    if (name === "SHA256SUMS" || recorded.has(name)) fail(`Invalid duplicate checksum entry: ${name}.`);
    const file = path.join(root, ...name.split("/"));
    if (!inside(root, file) || !fs.statSync(file).isFile()) fail(`Checksum target is not a package file: ${name}.`);
    const actual = sha256(file);
    if (actual !== match[1]) fail(`Checksum mismatch: ${name}.`);
    recorded.set(name, match[1]);
  }
  const actualFiles = walkFiles(root).filter((name) => name !== "SHA256SUMS");
  if (recorded.size !== actualFiles.length || actualFiles.some((name) => !recorded.has(name))) {
    fail("SHA256SUMS does not cover every activation-package file exactly once.");
  }
  const commit = fs.readFileSync(path.join(root, "generated", "SOURCE_COMMIT.txt"), "utf8");
  if (!EXACT_SHA.test(commit.trim()) || commit !== `${commit.trim()}\n`) fail("Package source commit marker is malformed.");
  if (commit.trim() !== expectedSha) fail("Package source commit does not match the trusted expected SHA.");
  const config = JSON.parse(fs.readFileSync(path.join(root, "generated", "firebase.activation.json"), "utf8"));
  validateConfigPaths(root, config);
  return Object.freeze({
    fileCount: actualFiles.length,
    manifestSha256: actualManifestSha256,
    sha: commit.trim(),
  });
}

function buildActivationPackage({ source, expectedSha, output, inspect = inspectServersSource }) {
  const identity = exactSourceIdentity(source, expectedSha);
  const finalOutput = outputIdentity(identity.source, output);
  try {
    fs.mkdirSync(finalOutput, { mode: 0o700 });
  } catch (error) {
    if (error.code === "EEXIST") fail(`Output already exists; refusing to overwrite it: ${finalOutput}`);
    throw error;
  }
  try {
    const inspectionSource = path.join(finalOutput, ".inspection-source");
    copyExactSource(identity.source, identity.sha, inspectionSource);
    const nodeModules = fs.realpathSync(path.join(identity.source, "functions", "node_modules"));
    if (!fs.statSync(nodeModules).isDirectory()) fail("Source Functions dependencies are not an installed directory.");
    const inventory = inspect(inspectionSource, { nodePath: nodeModules });
    const phases = phasePlan(inventory);
    fs.rmSync(inspectionSource, { recursive: true, force: true });

    // Both inspection and deploy input now come from immutable blobs at the
    // expected commit. A final identity check keeps the operator worktree
    // policy fail-closed without making it the source of packaged bytes.
    copyExactSource(identity.source, identity.sha, path.join(finalOutput, "source"));
    exactSourceIdentity(identity.source, expectedSha);

    const generated = path.join(finalOutput, "generated");
    fs.mkdirSync(generated, { recursive: true });
    fs.writeFileSync(path.join(generated, "SOURCE_COMMIT.txt"), `${identity.sha}\n`, { mode: 0o644 });
    const config = firebaseConfig(finalOutput);
    fs.writeFileSync(
      path.join(generated, "firebase.activation.json"),
      `${JSON.stringify(config, null, 2)}\n`,
      { mode: 0o644 },
    );
    for (const [phase, filename] of Object.entries(PHASE_FILES)) {
      fs.writeFileSync(path.join(generated, filename), selectorText(phases[phase]), { mode: 0o644 });
    }
    validateConfigPaths(finalOutput, config);
    const manifestSha256 = writeChecksums(finalOutput);
    const verified = verifyPackage(finalOutput, {
      expectedSha,
      expectedManifestSha256: manifestSha256,
    });
    fs.chmodSync(finalOutput, 0o755);
    return Object.freeze({ output: finalOutput, phases, ...verified });
  } catch (error) {
    fs.rmSync(finalOutput, { recursive: true, force: true });
    throw error;
  }
}

function preparePackageDependencies(packageRoot, {
  expectedSha,
  expectedManifestSha256,
  npmCommand = "npm",
  inspect = inspectServersSource,
} = {}) {
  const verifiedBefore = verifyPackage(packageRoot, { expectedSha, expectedManifestSha256 });
  const root = fs.realpathSync(packageRoot);
  const functionsRoot = path.join(root, "source", "functions");
  const packageJson = path.join(functionsRoot, "package.json");
  const packageLock = path.join(functionsRoot, "package-lock.json");
  if (!fs.statSync(packageJson).isFile() || !fs.statSync(packageLock).isFile()) {
    fail("Dependency preparation requires package.json and package-lock.json in package/source/functions.");
  }
  try {
    execFileSync(npmCommand, [
      "ci",
      "--omit=dev",
      "--ignore-scripts",
      "--no-audit",
      "--no-fund",
    ], {
      cwd: functionsRoot,
      encoding: "utf8",
      env: inspectionEnvironment(),
      maxBuffer: 64 * 1024 * 1024,
      stdio: ["ignore", "pipe", "pipe"],
    });
  } catch (error) {
    const detail = String(error.stderr ?? error.message ?? error).trim();
    fail(`Locked Functions dependency installation failed: ${detail}`);
  }
  const verifiedAfter = verifyPackage(root, { expectedSha, expectedManifestSha256 });
  if (JSON.stringify(verifiedAfter) !== JSON.stringify(verifiedBefore)) {
    fail("Dependency preparation changed the anchored activation package.");
  }
  const inventory = inspect(path.join(root, "source"));
  const lockedDependencyPlan = phasePlan(inventory);
  validateGeneratedSelectors(root, lockedDependencyPlan);
  return Object.freeze({ ...verifiedAfter, dependenciesPrepared: true });
}

function parseArguments(argv) {
  const options = {};
  for (let index = 0; index < argv.length; index += 1) {
    const name = argv[index];
    if (name === "--verify") {
      if (options.verify !== undefined || index + 1 >= argv.length) fail("--verify requires exactly one package path.");
      options.verify = argv[++index];
      continue;
    }
    if (name === "--prepare-dependencies") {
      if (options.prepareDependencies !== undefined || index + 1 >= argv.length) {
        fail("--prepare-dependencies requires exactly one package path.");
      }
      options.prepareDependencies = argv[++index];
      continue;
    }
    if (!["--source", "--expected-sha", "--expected-manifest-sha256", "--output"].includes(name) ||
        index + 1 >= argv.length) {
      fail(`Unknown or incomplete argument: ${name}.`);
    }
    const key = name.slice(2).replace(/-([a-z])/gu, (_match, letter) => letter.toUpperCase());
    if (options[key] !== undefined) fail(`Duplicate argument: ${name}.`);
    options[key] = argv[++index];
  }
  if (options.verify !== undefined || options.prepareDependencies !== undefined) {
    if (options.verify !== undefined && options.prepareDependencies !== undefined) {
      fail("Choose exactly one of --verify or --prepare-dependencies.");
    }
    if (options.source !== undefined || options.output !== undefined) {
      fail("Package verification/preparation cannot be combined with --source or --output.");
    }
    for (const key of ["expectedSha", "expectedManifestSha256"]) {
      if (options[key] === undefined) {
        fail("Usage: servers_activation_package.js (--verify|--prepare-dependencies) PATH --expected-sha SHA --expected-manifest-sha256 SHA256");
      }
    }
    return options;
  }
  if (options.expectedManifestSha256 !== undefined) {
    fail("--expected-manifest-sha256 is valid only with --verify or --prepare-dependencies.");
  }
  for (const key of ["source", "expectedSha", "output"]) {
    if (options[key] === undefined) fail("Usage: servers_activation_package.js --source PATH --expected-sha SHA --output PATH");
  }
  return options;
}

function main(argv) {
  const options = parseArguments(argv);
  let result;
  if (options.verify !== undefined) {
    result = verifyPackage(options.verify, {
      expectedSha: options.expectedSha,
      expectedManifestSha256: options.expectedManifestSha256,
    });
  } else if (options.prepareDependencies !== undefined) {
    result = preparePackageDependencies(options.prepareDependencies, {
      expectedSha: options.expectedSha,
      expectedManifestSha256: options.expectedManifestSha256,
    });
  } else {
    result = buildActivationPackage(options);
  }
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

if (require.main === module) {
  try {
    main(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`servers-activation-package: ${error.message}\n`);
    process.exitCode = 1;
  }
}

module.exports = {
  COMPATIBILITY_EXPORTS,
  INFRASTRUCTURE_COMPATIBILITY_EXPORTS,
  PHASE_FILES,
  REQUIRED_SOURCE_PATHS,
  buildActivationPackage,
  exactSourceIdentity,
  inspectServersSource,
  main,
  phasePlan,
  preparePackageDependencies,
  verifyPackage,
};
