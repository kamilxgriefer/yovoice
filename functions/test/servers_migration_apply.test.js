"use strict";

// The migration APPLY ENGINE against a real Firestore emulator.
//
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8085 \
//     node --test --test-concurrency=1 test/servers_migration_apply.test.js
//
// Write mode exists only to prove the engine; it refuses to run anywhere but a
// local emulator, and no CLI can reach it. Every fixture lives in a throwaway
// `demo-` project namespace.

const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { after, before, test } = require("node:test");

const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
const enabled = typeof emulatorHost === "string" && /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(emulatorHost);
const projectId = `demo-yovoice-apply-${randomUUID().slice(0, 8)}`;
let app;
let db;
let Timestamp;
if (enabled) {
  const adminApp = require("firebase-admin/app");
  const firestoreModule = require("firebase-admin/firestore");
  Timestamp = firestoreModule.Timestamp;
  app = adminApp.initializeApp({ projectId }, `apply-${randomUUID()}`);
  db = firestoreModule.getFirestore(app);
}

const { createLegacyMigrationCollector } = require("../servers/migration_collector");
const { CLIENT_GATE_PATH, CLIENT_PLATFORMS } = require("../servers/migration_gate");
const {
  DURABLE_MEMBER_SOURCES, FAMILY_RULES_BRANCHES, IMMUTABLE_MEMBER_FIELDS, IMMUTABLE_ROOT_FIELDS, LIVENESS_REASONS,
  RUN_COLLECTION, RUN_STEP_COLLECTION, V1_CLIENT_READ_PATHS, assertDurableMemberSource,
  assertPatchPreserves, channelPostImage, createLegacyMigrationApplyEngine, familyMigrationAllowed,
  reduceToChanges, rootPostImage, stampedPatch,
} = require("../servers/migration_apply");
const { readOwnerAllocations } = require("../servers/capacity");

const OWNER = "apply-owner-uid-7c31";
const MEMBER = "apply-member-uid-7c31";
const GUEST = "apply-guest-uid-7c31";
const BANNED = "apply-banned-uid-7c31";
const CROWD = "apply-transient-uid-7c31";
const ATTESTOR = "apply-attestor-uid-7c31";
const FAMILY_OWNER = "apply-family-uid-7c31";

const CLEAN = "club_clean";
const ARTWORK = "club_artwork";
const LIVE = "club_live";
const CROWDED = "club_crowded";
const HISTORY = "club_history";
const INVITED = "club_invited";
const PRIVATE_CHANNEL = "club_private_channel";
const FAMILY = `family_${FAMILY_OWNER}`;
const STANDALONE = "standalone_room_7c31";
// P1-1. Three roots whose bound rooms NO FORWARD POINTER NAMES, which is the
// state the engine used to be blind to. Each one is a shape this repository
// already asserts is real somewhere else:
//   ORPHAN        a voice channel was deleted with no cascade
//                 (firestore.rules lets a club manager do exactly that), so a
//                 live room still carries `clubId` and nothing points at it;
//   LAZY_LOUNGE   a club with a lounge and NO `loungeRoomId` and no voice
//                 channel at all — `clubs/deletion.js:205-212` asserts this is
//                 a real state, because lounges are created lazily;
//   STALE_POINTER the forward pointer is not merely absent but WRONG: the
//                 voice channel names a room that is gone, while the live
//                 history-bearing room is bound only by `clubId`.
const ORPHAN = "club_orphan_pointer";
const LAZY_LOUNGE = "club_lazy_lounge";
const STALE_POINTER = "club_stale_pointer";
const ORPHAN_ROOM = "room_orphan_live_7c31";
const STALE_ROOM = "room_stale_live_7c31";
const VANISHED_ROOM = "club_lounge_vanished_7c31";
const CLUB_IDS = [CLEAN, ARTWORK, LIVE, CROWDED, HISTORY, INVITED, PRIVATE_CHANNEL, FAMILY, ORPHAN];
const POINTER_BLIND_IDS = [ORPHAN, LAZY_LOUNGE, STALE_POINTER];
const ALL_ROOT_IDS = [...CLUB_IDS, LAZY_LOUNGE, STALE_POINTER];

const GATE_BUILD = 42;
const GATE_REVISION = 3;
const CENSUS_CLEAN = CLIENT_PLATFORMS.map((platform) => ({ platform, build: GATE_BUILD, sessions: 10 }));
const CENSUS_DIRTY = [...CENSUS_CLEAN, { platform: "android", build: GATE_BUILD - 1, sessions: 4 }];

const emulatorTest = (name, fn) =>
  test(name, { skip: enabled ? false : "Requires explicit localhost Firestore emulator." }, fn);
const at = (millis) => Timestamp.fromMillis(millis);
const clock = () => 1_800_000_000_000;

function clubRoot(id, changes = {}) {
  return {
    name: `Club ${id}`, description: "A real legacy club.", ownerId: OWNER, ownerName: OWNER,
    avatarUrl: null, bannerUrl: null, privacy: "public", type: "community", status: "active",
    defaultLanguage: "English", memberCount: 3, onlineCount: 7,
    defaultChatChannelId: "general", defaultVoiceChannelId: "lounge",
    announcementChannelId: "announcements", loungeRoomId: `club_lounge_${id}`,
    createdAt: at(1_700_000_000_000), updatedAt: at(1_700_000_000_000), ...changes,
  };
}

function legacyMember(uid, role, changes = {}) {
  return {
    userId: uid, displayName: uid, photoUrl: null, role, isOnline: true,
    joinedAt: at(1_700_000_000_000), invitedBy: null, ...changes,
  };
}

function legacyChannel(name, type, position, changes = {}) {
  return { name, type, position, isPrivate: false, createdBy: OWNER, createdAt: at(1_700_000_000_000), ...changes };
}

function loungeRoom(clubId, changes = {}) {
  return {
    hostId: OWNER, hostName: OWNER, hostPhotoUrl: null, name: `Club ${clubId} Lounge`,
    description: "Private voice lounge.", category: "club", visibility: "private", language: "English",
    maxParticipants: null, participantCount: 0, memberCount: 3, isLive: false, roomType: "community",
    status: "active", imageUrl: null, approvalRequired: false, slowModeSeconds: 0,
    autoMuteNewUsers: false, membersCanStartVoice: true, experience: "community", clubId,
    roomKind: "clubLounge", createdAt: at(1_700_000_000_000), updatedAt: at(1_700_000_000_000), ...changes,
  };
}

async function seed(entries) {
  for (const [path, value] of Object.entries(entries)) {
    if (value === null) await db.doc(path).delete();
    else await db.doc(path).set(value);
  }
}

function clubGraph(id, { root = {}, lounge = {}, members = null } = {}) {
  const roster = members ?? [[OWNER, "owner"], [MEMBER, "member"], [GUEST, "guest"]];
  const entries = {
    [`clubs/${id}`]: clubRoot(id, root),
    [`clubs/${id}/channels/general`]: legacyChannel("general", "chat", 0),
    [`clubs/${id}/channels/announcements`]: legacyChannel("announcements", "announcement", 1),
    [`clubs/${id}/channels/lounge`]: legacyChannel("Club Lounge", "voice", 2, { roomId: `club_lounge_${id}` }),
    [`rooms/club_lounge_${id}`]: loungeRoom(id, lounge),
  };
  for (const [uid, role] of roster) entries[`clubs/${id}/members/${uid}`] = legacyMember(uid, role);
  return entries;
}

async function collect() {
  const collector = createLegacyMigrationCollector({ firestore: db, projectId, emulator: true, clock });
  return collector.collect({ pageSize: 200, maxRoots: 200 });
}

function engine(mode) {
  return createLegacyMigrationApplyEngine({ firestore: db, Timestamp, projectId, emulator: true, mode, clock });
}

async function runEngine({ mode = "dryRun", runId = "run-1", census = CENSUS_CLEAN, gateRevision = GATE_REVISION, only = null } = {}) {
  const manifest = await collect();
  const mappings = only === null
    ? manifest.mappingReport.mappings
    : manifest.mappingReport.mappings.filter((mapping) => only.includes(mapping.sourcePath));
  return engine(mode).run({
    runId, mappings, planDigest: manifest.mappingReport.reportDigest,
    expectedGateRevision: gateRevision, clientCensus: census,
  });
}

const byPath = (report, path) => report.roots.find((root) => root.sourcePath === path);
let planBeforeApply = null;

async function publishGate(changes = {}) {
  await seed({
    [CLIENT_GATE_PATH]: {
      schemaVersion: 1, gateId: CLIENT_GATE_PATH.split("/")[1], minimumClientVersion: "1.9.0",
      minimumClientBuild: GATE_BUILD,
      platformMinimumBuild: Object.fromEntries(CLIENT_PLATFORMS.map((platform) => [platform, GATE_BUILD])),
      status: "satisfied", attestedBy: ATTESTOR, attestedAt: at(clock()),
      revision: GATE_REVISION, updatedAt: at(clock()), ...changes,
    },
  });
}

before(async () => {
  if (!enabled) return;
  // A banned member on the clean root: the ban must survive the migration
  // untouched and the person must still get an authorization row, because the
  // ban is read off the member document, not off its absence.
  for (const id of CLUB_IDS) {
    const overrides = id === FAMILY
      ? { root: { ownerId: FAMILY_OWNER, type: "family", privacy: "inviteOnly" },
        lounge: { hostId: FAMILY_OWNER },
        members: [[FAMILY_OWNER, "owner"], [MEMBER, "member"]] }
      : {};
    await seed(clubGraph(id, overrides));
  }
  // A paid, ordinary Club with artwork: its objects must survive untouched and
  // the migration must refuse while the Storage read branch is legacy-gated.
  await seed({ [`clubs/${ARTWORK}`]: clubRoot(ARTWORK, {
    avatarUrl: "https://storage.example.invalid/clubs/o/ARTWORK-AVATAR-OBJECT?generation=17",
    bannerUrl: "https://storage.example.invalid/clubs/o/ARTWORK-BANNER-OBJECT?generation=18",
  }) });
  await seed({ [`rooms/club_lounge_${LIVE}`]: loungeRoom(LIVE, { isLive: true, participantCount: 4 }) });
  await seed({ [`rooms/club_lounge_${CROWDED}/participants/${CROWD}`]: {
    userId: CROWD, displayName: CROWD, role: "speaker", isMuted: false, isSpeaker: true,
    isHandRaised: false, joinedAt: at(clock()), updatedAt: at(clock()),
  } });
  await seed({ [`rooms/club_lounge_${HISTORY}/messages/msg_0001`]: {
    senderId: MEMBER, text: "legacy room history", createdAt: at(1_700_000_100_000),
  } });
  await seed({ [`clubs/${INVITED}/invites/${BANNED}`]: {
    clubId: INVITED, inviteeId: BANNED, inviterId: OWNER, status: "pending", createdAt: at(1_700_000_200_000),
  } });
  await seed({
    [`clubs/${PRIVATE_CHANNEL}/channels/hr`]: legacyChannel("HR", "chat", 3, { isPrivate: true }),
  });
  await seed({ [`rooms/${STANDALONE}`]: {
    hostId: OWNER, hostName: OWNER, name: "Standalone", description: "", category: "social",
    visibility: "public", language: "English", participantCount: 0, memberCount: 1, isLive: false,
    roomType: "community", status: "active", imageUrl: null, experience: "community",
    createdAt: at(1_700_000_000_000), updatedAt: at(1_700_000_000_000),
  } });
  await seed({ [`rooms/${STANDALONE}/roomMembers/${OWNER}`]: { userId: OWNER, role: "host" } });
  await seed({ [`clubs/${CLEAN}/members/${BANNED}`]: legacyMember(BANNED, "member", { banned: true }) });

  // ---- P1-1: bound rooms that only the `clubId` back-pointer can find ----
  // ORPHAN keeps its ordinary, idle, discoverable lounge. The live room is the
  // SECOND one: named by no channel, not by `loungeRoomId`, carrying history.
  await seed({
    [`rooms/${ORPHAN_ROOM}`]: loungeRoom(ORPHAN, {
      name: "Orphaned voice room", roomKind: "clubVoice", isLive: true,
      participantCount: 7, voiceSessionId: "vs_orphan_live",
    }),
    [`rooms/${ORPHAN_ROOM}/messages/msg_0001`]: {
      senderId: MEMBER, text: "legacy room history", createdAt: at(1_700_000_100_000),
    },
  });
  // LAZY_LOUNGE has NO forward pointer of any kind: no `loungeRoomId`, no
  // voice channel. Its live lounge sits at the conventional id and carries a
  // cover, so it also proves the bound-room artwork refusal (F2) on a room the
  // old discovery set could not reach.
  await seed({
    [`clubs/${LAZY_LOUNGE}`]: clubRoot(LAZY_LOUNGE, { loungeRoomId: null, defaultVoiceChannelId: null }),
    [`clubs/${LAZY_LOUNGE}/channels/general`]: legacyChannel("general", "chat", 0),
    [`clubs/${LAZY_LOUNGE}/channels/announcements`]: legacyChannel("announcements", "announcement", 1),
    [`rooms/club_lounge_${LAZY_LOUNGE}`]: loungeRoom(LAZY_LOUNGE, {
      isLive: true, participantCount: 2,
      imageUrl: "https://storage.example.invalid/rooms/o/LAZY-LOUNGE-COVER?generation=21",
    }),
  });
  for (const [uid, role] of [[OWNER, "owner"], [MEMBER, "member"]]) {
    await seed({ [`clubs/${LAZY_LOUNGE}/members/${uid}`]: legacyMember(uid, role) });
  }
  // STALE_POINTER's voice channel names a room that no longer exists. The old
  // discovery set was therefore not empty — it was WRONG, and a wrong set
  // reads exactly as clean.
  await seed({
    [`clubs/${STALE_POINTER}`]: clubRoot(STALE_POINTER, { loungeRoomId: null }),
    [`clubs/${STALE_POINTER}/channels/general`]: legacyChannel("general", "chat", 0),
    [`clubs/${STALE_POINTER}/channels/announcements`]: legacyChannel("announcements", "announcement", 1),
    [`clubs/${STALE_POINTER}/channels/lounge`]: legacyChannel("Club Lounge", "voice", 2, { roomId: VANISHED_ROOM }),
    [`rooms/${STALE_ROOM}`]: loungeRoom(STALE_POINTER, {
      name: "Room the pointer lost", roomKind: "clubVoice", isLive: true,
      participantCount: 5, voiceSessionId: "vs_stale_live",
    }),
    [`rooms/${STALE_ROOM}/messages/msg_0001`]: {
      senderId: MEMBER, text: "legacy room history", createdAt: at(1_700_000_100_000),
    },
  });
  for (const [uid, role] of [[OWNER, "owner"], [MEMBER, "member"]]) {
    await seed({ [`clubs/${STALE_POINTER}/members/${uid}`]: legacyMember(uid, role) });
  }
  await publishGate();
});

after(async () => {
  if (!enabled) return;
  const { deleteApp } = require("firebase-admin/app");
  await deleteApp(app);
});

// ---------------------------------------------------------------- pure guards

test("a transient participation roster is not an accepted membership source", () => {
  assert.deepEqual([...DURABLE_MEMBER_SOURCES], ["members", "roomMembers", "owner"]);
  assert.equal(DURABLE_MEMBER_SOURCES.includes("participants"), false);
  assert.equal(assertDurableMemberSource("members"), "members");
  assert.throws(() => assertDurableMemberSource("participants"), (error) => error.code === "internal");
});

test("media identity and ownership are on the immutable list and a patch touching one fails", () => {
  for (const field of ["avatarUrl", "bannerUrl", "imageUrl", "ownerId", "name", "createdAt"]) {
    assert.ok(IMMUTABLE_ROOT_FIELDS.includes(field), field);
  }
  for (const field of ["banned", "role", "joinedAt", "userId"]) {
    assert.ok(IMMUTABLE_MEMBER_FIELDS.includes(field), field);
  }
  assert.throws(() => assertPatchPreserves({ avatarUrl: null }, IMMUTABLE_ROOT_FIELDS, "root"),
    (error) => error.code === "internal");
  assert.throws(() => assertPatchPreserves({ banned: false }, IMMUTABLE_MEMBER_FIELDS, "member"),
    (error) => error.code === "internal");
});

test("only liveness clears by waiting: LIVENESS_REASONS is exactly the two self-clearing refusals", () => {
  // The disposition rule reads this list with `every`, so a root is `deferred`
  // only when nothing but idleness blocks it (principal F9). The mixed case is
  // proven end to end by the P1-1 emulator tests below.
  assert.deepEqual([...LIVENESS_REASONS], ["active-session-must-not-be-migrated", "transient-participants-present"]);
  assert.equal(Object.isFrozen(LIVENESS_REASONS), true);
});

test("ADR-E is a computed flag over the three missing rules branches, not a comment", () => {
  assert.deepEqual([...FAMILY_RULES_BRANCHES], ["familyCheckIns", "familyMoments", "familyMomentsStorage"]);
  assert.equal(familyMigrationAllowed(), false);
  for (const branch of FAMILY_RULES_BRANCHES) assert.equal(V1_CLIENT_READ_PATHS[branch], false);
  // The refusal disappears on its own once the three branches exist.
  assert.equal(familyMigrationAllowed({ familyCheckIns: true, familyMoments: true, familyMomentsStorage: true }), true);
  assert.equal(familyMigrationAllowed({ familyCheckIns: true, familyMoments: true, familyMomentsStorage: false }), false);
});

test("a migrated Club's post-image classifies as the retained paid allocation", () => {
  const image = rootPostImage({ sourceKind: "club", sourceId: CLEAN, serverType: "community",
    entitlementPolicyId: "legacyCommunityPremiumV1", memberCount: 3, state: "complete" });
  assert.equal(image.entitlementPolicyId, "legacyCommunityPremiumV1");
  assert.equal(image.onlineCount, 0);
  assert.equal(image.serverActivationState, "held");
  assert.deepEqual(image.migration, { version: 1, sourceKind: "club", sourceId: CLEAN, state: "complete" });
  // A Club charged to the free allowance is a bug this refuses to write.
  assert.throws(() => rootPostImage({ sourceKind: "club", sourceId: CLEAN, serverType: "community",
    entitlementPolicyId: "freeServersV1", memberCount: 3, state: "complete" }),
  (error) => error.code === "internal");
  // An adopted room keeps its own room-scoped allocation identity.
  const room = rootPostImage({ sourceKind: "room", sourceId: STANDALONE, serverType: "community",
    entitlementPolicyId: "legacyRoomV1", memberCount: 1, state: "complete" });
  assert.deepEqual(room.migration, { version: 1, sourceKind: "room", sourceId: STANDALONE, state: "complete" });
});

test("a patch that changes nothing reduces to nothing, and is not given a fresh timestamp either", () => {
  assert.deepEqual(reduceToChanges({ a: 1, b: { c: [1, 2] } }, { a: 1, b: { c: [1, 2] } }), {});
  assert.deepEqual(reduceToChanges({ a: 1 }, { a: 2 }), { a: 2 });
  assert.deepEqual(reduceToChanges(undefined, { a: 1 }), { a: 1 });
  // `updatedAt` differs on every run by construction, so stamping it
  // unconditionally would make a re-run of an unfinished stage rewrite every
  // document it already wrote.
  assert.deepEqual(stampedPatch({ a: 1 }, { a: 1 }, "T"), {});
  assert.deepEqual(stampedPatch({ a: 1 }, { a: 2 }, "T"), { a: 2, updatedAt: "T" });
  const image = channelPostImage({
    serverId: "s", channel: { type: "chat", position: 0, isPrivate: false },
    historySource: { kind: "channelMessages" },
  }).desired;
  assert.equal(Object.hasOwn(image, "updatedAt"), false);
  assert.equal(Object.hasOwn(image, "liveness"), false);
  // An already-staged channel is re-stageable, an unsupported version is not.
  assert.deepEqual(channelPostImage({ serverId: "s", historySource: { kind: "channelMessages" },
    channel: { type: "chat", position: 0, isPrivate: false, serverSchemaVersion: 1 } }).reasons, []);
  assert.deepEqual(channelPostImage({ serverId: "s", historySource: { kind: "channelMessages" },
    channel: { type: "chat", position: 0, isPrivate: false, serverSchemaVersion: 2 } }).reasons,
  ["unsupported-channel-schema-version"]);
  for (const isPrivate of [undefined, null, 0, 1, "false", "true", {}, []]) {
    const channel = { type: "chat", position: 0 };
    if (isPrivate !== undefined) channel.isPrivate = isPrivate;
    assert.deepEqual(channelPostImage({ serverId: "s", historySource: { kind: "channelMessages" },
      channel }).reasons, ["channel-privacy-flag-missing-or-malformed"], JSON.stringify(isPrivate));
  }
  assert.deepEqual(channelPostImage({ serverId: "s", historySource: { kind: "channelMessages" },
    channel: { type: "chat", position: 0, isPrivate: true } }).reasons,
  ["restricted-legacy-channel-requires-access-mapping"]);
});

test("write mode refuses to exist outside an emulator", () => {
  assert.throws(() => createLegacyMigrationApplyEngine({
    firestore: { collection() {}, doc() {}, runTransaction() {} },
    Timestamp: { fromMillis: () => 0 }, projectId: "demo-x", emulator: false, mode: "apply",
  }), (error) => error.code === "failed-precondition");
});

// ------------------------------------------------------------------ emulator

emulatorTest("a dry run performs zero writes and leaves every root unversioned", async () => {
  const report = await runEngine({ mode: "dryRun" });
  assert.equal(report.dryRun, true);
  assert.equal(report.writeCount, 0);
  assert.equal(report.applyReady, false);
  assert.ok(report.plannedWrites > 0, "a dry run must still plan the writes it would make");
  for (const id of ALL_ROOT_IDS) {
    const root = await db.doc(`clubs/${id}`).get();
    assert.equal(root.data().serverSchemaVersion, undefined, id);
    assert.equal(root.data().migration, undefined, id);
  }
  const authorizations = await db.doc(`clubs/${CLEAN}`).collection("memberAuthorizations").get();
  assert.equal(authorizations.size, 0);
  assert.equal((await db.collection(RUN_COLLECTION).get()).size, 0);
});

emulatorTest("the dry run refuses exactly the roots whose data would lose its read path", async () => {
  const report = await runEngine({ mode: "dryRun" });
  const reasonsFor = (id) => byPath(report, `clubs/${id}`).reasons;
  assert.deepEqual(reasonsFor(ARTWORK), ["club-artwork-would-lose-its-read-path"]);
  assert.deepEqual(reasonsFor(HISTORY), ["bound-room-history-would-lose-its-read-path"]);
  assert.deepEqual(reasonsFor(INVITED), ["legacy-pending-invitation-has-no-v1-acceptance-path"]);
  assert.deepEqual(reasonsFor(FAMILY), ["family-migration-deferred-until-v1-rules-branches-exist"]);
  assert.deepEqual(reasonsFor(LIVE), ["active-session-must-not-be-migrated"]);
  assert.equal(byPath(report, `clubs/${LIVE}`).disposition, "deferred");
  assert.deepEqual(reasonsFor(CROWDED), ["transient-participants-present"]);
  assert.equal(byPath(report, `clubs/${CROWDED}`).disposition, "deferred");
  assert.deepEqual(reasonsFor(PRIVATE_CHANNEL), ["restricted-legacy-channel-requires-access-mapping"]);
  assert.equal(byPath(report, `rooms/${STANDALONE}`).reasons[0], "standalone-room-adoption-has-no-v1-client-read-path");
  assert.equal(byPath(report, `clubs/${CLEAN}`).disposition, "applied");
  assert.deepEqual(byPath(report, `clubs/${CLEAN}`).reasons, []);
});

emulatorTest("a bound room is migrated with its parent, never as a second root", async () => {
  const report = await runEngine({ mode: "dryRun" });
  const bound = byPath(report, `rooms/club_lounge_${CLEAN}`);
  assert.equal(bound.disposition, "covered");
  assert.deepEqual(bound.reasons, ["bound-room-is-migrated-with-its-parent-server"]);
  assert.equal(bound.writes, 0);
  assert.equal(bound.targetServerId, CLEAN);
});

emulatorTest("the client gate is enforced: unpublished, open, drifted and a live old cohort all refuse", async () => {
  const only = [`clubs/${CLEAN}`];
  await seed({ [CLIENT_GATE_PATH]: null });
  let report = await runEngine({ mode: "dryRun", only });
  assert.deepEqual(byPath(report, only[0]).reasons, ["client-compatibility-gate-not-satisfied"]);

  await publishGate({ status: "open", attestedBy: null, attestedAt: null });
  report = await runEngine({ mode: "dryRun", only });
  assert.deepEqual(byPath(report, only[0]).reasons, ["client-compatibility-gate-not-satisfied"]);

  await publishGate();
  report = await runEngine({ mode: "dryRun", only, gateRevision: GATE_REVISION + 1 });
  assert.deepEqual(byPath(report, only[0]).reasons, ["client-compatibility-gate-revision-mismatch"]);

  report = await runEngine({ mode: "dryRun", only, census: CENSUS_DIRTY });
  assert.deepEqual(byPath(report, only[0]).reasons, ["incompatible-client-cohort-observed"]);
  assert.equal(byPath(report, only[0]).gate.incompatibleSessions, 4);
  assert.deepEqual(byPath(report, only[0]).gate.incompatiblePlatforms, ["android"]);

  report = await runEngine({ mode: "dryRun", only, census: null });
  assert.deepEqual(byPath(report, only[0]).reasons, ["client-compatibility-census-not-supplied"]);

  // P1-2, through the ENGINE and not only through the pure gate function: a
  // census that observed nothing must refuse exactly as an absent one does.
  // `[]` used to satisfy the gate with zero observations, and a census of
  // all-zero rows — a complete statement that nothing was measured — did the
  // same. Both are now the unsupplied answer, and a census that never mentions
  // a platform the gate pins a build floor on says nothing about it.
  for (const census of [
    [],
    CLIENT_PLATFORMS.map((platform) => ({ platform, build: GATE_BUILD, sessions: 0 })),
    CLIENT_PLATFORMS.map((platform) => ({ platform, build: GATE_BUILD - 1, sessions: 0 })),
    CENSUS_CLEAN.slice(1),
  ]) {
    report = await runEngine({ mode: "dryRun", only, census });
    assert.deepEqual(byPath(report, only[0]).reasons, ["client-compatibility-census-not-supplied"],
      JSON.stringify(census));
    assert.equal(byPath(report, only[0]).gate.compatibleSessions, null);
    assert.equal(byPath(report, only[0]).disposition, "refused");
    assert.equal(report.writeCount, 0);
  }

  report = await runEngine({ mode: "dryRun", only });
  assert.equal(byPath(report, only[0]).disposition, "applied");
  assert.equal(report.openGates.includes("compatible-client-and-idle-session-cutover-gate"), false);
  assert.ok(report.openGates.includes("separate-production-migration-approval"));
});

emulatorTest("an apply run requires the reviewed gate revision before any stage or run-ledger write", async () => {
  const collected = await collect();
  const mappings = collected.mappingReport.mappings.filter((mapping) => mapping.sourcePath === `clubs/${CLEAN}`);
  for (const expectedGateRevision of [undefined, null, 0, -1, 1.5, "7"]) {
    await assert.rejects(engine("apply").run({
      runId: `missing-gate-${String(expectedGateRevision).replace(/[^A-Za-z0-9_-]/gu, "x")}`,
      mappings, planDigest: collected.mappingReport.reportDigest,
      expectedGateRevision, clientCensus: CENSUS_CLEAN,
    }), (error) => error.code === "invalid-argument");
  }
  assert.equal((await db.collection(RUN_COLLECTION).get()).size, 0);
  assert.equal((await db.doc(`clubs/${CLEAN}`).get()).data().serverSchemaVersion, undefined);
});

emulatorTest("an apply run re-reads the pinned gate in the root transaction and refuses revision drift", async () => {
  const collected = await collect();
  const mappings = collected.mappingReport.mappings.filter(
    (mapping) => mapping.sourcePath === `clubs/${CLEAN}`,
  );
  let transactions = 0;
  const driftingFirestore = new Proxy(db, {
    get(target, property) {
      if (property === "runTransaction") {
        return async (handler, options) => {
          transactions += 1;
          // One bounded member page, then channels, then the irreversible root
          // flip. The operator-reviewed gate changes in that exact window.
          if (transactions === 3) await publishGate({ revision: GATE_REVISION + 1 });
          return target.runTransaction(handler, options);
        };
      }
      const value = target[property];
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
  const report = await createLegacyMigrationApplyEngine({
    firestore: driftingFirestore, Timestamp, projectId, emulator: true,
    mode: "apply", clock,
  }).run({
    runId: "run-gate-toctou", mappings,
    planDigest: collected.mappingReport.reportDigest,
    expectedGateRevision: GATE_REVISION, clientCensus: CENSUS_CLEAN,
  });
  const entry = byPath(report, `clubs/${CLEAN}`);
  assert.equal(transactions, 3);
  assert.equal(entry.stage, "root");
  assert.equal(entry.disposition, "refused");
  assert.deepEqual(entry.reasons, ["client-compatibility-gate-revision-mismatch"]);
  assert.equal(entry.gate.revision, GATE_REVISION + 1);
  assert.equal((await db.doc(`clubs/${CLEAN}`).get()).data().serverSchemaVersion, undefined);
  await publishGate();
});

emulatorTest("apply writes the full V1 post-image and preserves identity, media and bans", async () => {
  // Captured BEFORE the write so the idempotence test below can replay a plan
  // that predates the migration — the case a fresh collection can never
  // reproduce, because the planner reports a migrated root as already-versioned.
  const collected = await collect();
  planBeforeApply = collected.mappingReport;
  const report = await engine("apply").run({
    runId: "run-apply",
    mappings: planBeforeApply.mappings.filter((mapping) => mapping.sourcePath === `clubs/${CLEAN}`),
    planDigest: planBeforeApply.reportDigest,
    expectedGateRevision: GATE_REVISION, clientCensus: CENSUS_CLEAN,
  });
  const entry = byPath(report, `clubs/${CLEAN}`);
  assert.equal(entry.disposition, "applied");
  assert.deepEqual(entry.stagesRun, ["members", "channels", "root"]);
  assert.equal(report.writeCount > 0, true);

  const root = (await db.doc(`clubs/${CLEAN}`).get()).data();
  assert.equal(root.serverSchemaVersion, 1);
  assert.equal(root.serverType, "community");
  assert.equal(root.templateVersion, 1);
  assert.equal(root.entitlementPolicyId, "legacyCommunityPremiumV1");
  assert.equal(root.serverActivationState, "held");
  assert.equal(root.status, "preparing");
  assert.equal(root.revision, 1);
  assert.deepEqual(root.migration, { version: 1, sourceKind: "club", sourceId: CLEAN, state: "complete" });
  // onlineCount is RESET, never carried: the fixture root carried 7.
  assert.equal(root.onlineCount, 0);
  // Recounted from the roster, not carried: the fixture root claimed 3 and the
  // roster holds 4, the fourth being the banned member.
  assert.equal(root.memberCount, 4);
  // Identity and media are byte-identical to the legacy document.
  const legacy = clubRoot(CLEAN);
  for (const field of ["name", "description", "ownerId", "ownerName", "privacy", "avatarUrl", "bannerUrl", "loungeRoomId"]) {
    assert.deepEqual(root[field], legacy[field], field);
  }
  assert.equal(root.createdAt.toMillis(), legacy.createdAt.toMillis());

  for (const [uid, role] of [[OWNER, "owner"], [MEMBER, "member"], [GUEST, "guest"], [BANNED, "member"]]) {
    const member = (await db.doc(`clubs/${CLEAN}/members/${uid}`).get()).data();
    assert.equal(member.role, role, uid);
    assert.equal(member.authorizationRevision, 1, uid);
    assert.equal(member.isOnline, false, uid);
    assert.equal(member.displayName, uid, uid);
    const authorization = (await db.doc(`clubs/${CLEAN}/memberAuthorizations/${uid}`).get()).data();
    assert.deepEqual(
      { schemaVersion: authorization.schemaVersion, userId: authorization.userId,
        revision: authorization.revision, status: authorization.status },
      { schemaVersion: 1, userId: uid, revision: 1, status: "member" },
    );
  }
  const authorizations = await db.collection(`clubs/${CLEAN}/memberAuthorizations`).get();
  assert.equal(authorizations.size, 4);
  // The ban survived untouched, and the banned person still carries an
  // authorization row: `canonicalMember` refuses them by reading `banned`.
  assert.equal((await db.doc(`clubs/${CLEAN}/members/${BANNED}`).get()).data().banned, true);

  const voice = (await db.doc(`clubs/${CLEAN}/channels/lounge`).get()).data();
  assert.equal(voice.serverSchemaVersion, 1);
  assert.equal(voice.serverId, CLEAN);
  assert.equal(voice.kind, "voice");
  assert.equal(voice.type, "voice");
  assert.equal(voice.accessMode, "members");
  assert.equal(voice.isPrivate, false);
  assert.deepEqual(voice.accessPolicy, { accessMode: "members", roleIds: [], userIds: [] });
  assert.equal(voice.experience, "community");
  assert.equal(voice.mediaMode, "audio");
  assert.equal(voice.roomId, `club_lounge_${CLEAN}`);
  assert.equal(voice.activeSessionId, null);
  assert.deepEqual(voice.liveness, { schemaVersion: 1, isLive: false, startedAt: null });
  assert.deepEqual(voice.historySource, { kind: "channelMessages" });
  assert.equal(voice.position, 2);
  assert.equal(voice.name, "Club Lounge");

  // The engine constructs no Storage client and writes no room document, so
  // every media pointer and anchor is byte-identical to the legacy graph.
  const room = (await db.doc(`rooms/club_lounge_${CLEAN}`).get()).data();
  const legacyRoom = loungeRoom(CLEAN);
  for (const field of ["hostId", "name", "imageUrl", "visibility", "roomKind", "clubId", "experience", "isLive", "participantCount"]) {
    assert.deepEqual(room[field], legacyRoom[field], field);
  }
  assert.equal(room.serverSchemaVersion, undefined);
  assert.equal(Object.keys(report.summary.plannedWritesByShape).some((shape) => shape.includes("rooms/")), false);

  const text = (await db.doc(`clubs/${CLEAN}/channels/general`).get()).data();
  assert.equal(text.kind, "text");
  assert.equal(text.type, "chat");
  assert.equal(text.roomId, null);
  assert.equal(text.experience, null);
  const announcements = (await db.doc(`clubs/${CLEAN}/channels/announcements`).get()).data();
  assert.equal(announcements.kind, "announcements");
  assert.equal(announcements.type, "announcement");
});

emulatorTest("no transient participant became a member of the migrated root", async () => {
  const members = await db.collection(`clubs/${CLEAN}/members`).get();
  assert.deepEqual(members.docs.map((doc) => doc.id).sort(), [BANNED, GUEST, MEMBER, OWNER].sort());
  assert.equal(members.docs.some((doc) => doc.id === CROWD), false);
  assert.equal((await db.doc(`clubs/${CLEAN}/members/${CROWD}`).get()).exists, false);
});

emulatorTest("a migrated paid Club never consumes one of the 20 free servers", async () => {
  const allocations = await db.runTransaction((transaction) =>
    readOwnerAllocations({ db, transaction, uid: OWNER }));
  assert.equal(allocations.counts.freeServersV1, 0);
  assert.equal(allocations.counts.familyFreeV1, 0);
  assert.equal(allocations.free.count < allocations.free.limit, true);
  const root = (await db.doc(`clubs/${CLEAN}`).get()).data();
  assert.equal(root.entitlementPolicyId, "legacyCommunityPremiumV1");
});

emulatorTest("re-running is a zero-write no-op at all three short-circuits", async () => {
  const stale = () => planBeforeApply.mappings.filter((mapping) => mapping.sourcePath === `clubs/${CLEAN}`);

  // 1. The RUN RECORD short-circuit: the same run id replaying the plan it was
  // started from. The step record says the root is complete, so no stage runs.
  const sameRun = await engine("apply").run({
    runId: "run-apply", mappings: stale(), planDigest: planBeforeApply.reportDigest,
    expectedGateRevision: GATE_REVISION, clientCensus: CENSUS_CLEAN,
  });
  const sameEntry = byPath(sameRun, `clubs/${CLEAN}`);
  assert.equal(sameEntry.disposition, "applied");
  assert.equal(sameEntry.resumed, true);
  assert.deepEqual(sameEntry.stagesRun, []);
  assert.equal(sameEntry.writes, 0);

  // 2. The ENGINE short-circuit: a FRESH run id replaying the pre-migration
  // plan, with no run record to lean on. It reaches the root inside the stage
  // transaction, sees the matching provenance, and writes nothing.
  const replay = await engine("apply").run({
    runId: "run-stale-replay", mappings: stale(), planDigest: planBeforeApply.reportDigest,
    expectedGateRevision: GATE_REVISION, clientCensus: CENSUS_CLEAN,
  });
  const replayEntry = byPath(replay, `clubs/${CLEAN}`);
  assert.equal(replayEntry.disposition, "already-applied");
  assert.equal(replayEntry.alreadyApplied, true);
  assert.deepEqual(replayEntry.reasons, ["already-migrated"]);
  assert.deepEqual(replayEntry.stagesRun, ["members"]);
  assert.equal(replayEntry.writes, 0);

  // 3. The PLANNER short-circuit: a fresh collection no longer plans the root
  // at all, because it now carries the version markers.
  const fresh = await runEngine({ mode: "apply", runId: "run-fresh", only: [`clubs/${CLEAN}`] });
  const freshEntry = byPath(fresh, `clubs/${CLEAN}`);
  assert.equal(freshEntry.disposition, "already-applied");
  assert.deepEqual(freshEntry.reasons, ["plan-already-versioned"]);
  assert.deepEqual(freshEntry.stagesRun, []);
  assert.equal(freshEntry.writes, 0);

  // Whichever way it was re-run, the migrated document is untouched.
  const root = (await db.doc(`clubs/${CLEAN}`).get()).data();
  assert.equal(root.revision, 1);
  assert.equal(root.memberCount, 4);
  assert.deepEqual(root.migration, { version: 1, sourceKind: "club", sourceId: CLEAN, state: "complete" });
});

emulatorTest("a run interrupted by an unsatisfied gate resumes at the stage it reached", async () => {
  const only = [`clubs/${INVITED}`];
  // Clear the blocker so this root is otherwise migratable.
  await seed({ [`clubs/${INVITED}/invites/${BANNED}`]: null });
  await publishGate({ status: "open", attestedBy: null, attestedAt: null });
  const blocked = await runEngine({ mode: "apply", runId: "run-resume", only });
  const blockedEntry = byPath(blocked, only[0]);
  assert.deepEqual(blockedEntry.stagesRun, ["members", "channels", "root"]);
  assert.deepEqual(blockedEntry.reasons, ["client-compatibility-gate-not-satisfied"]);
  assert.equal((await db.doc(`clubs/${INVITED}`).get()).data().serverSchemaVersion, undefined);
  // The staged halves DID land and are inert while the root is unversioned.
  assert.equal((await db.collection(`clubs/${INVITED}/memberAuthorizations`).get()).size, 3);
  assert.equal((await db.doc(`clubs/${INVITED}/channels/general`).get()).data().serverSchemaVersion, 1);
  const step = (await db.doc(`${RUN_COLLECTION}/run-resume/${RUN_STEP_COLLECTION}/club_${INVITED}`).get()).data();
  assert.equal(step.stage, "root");
  assert.equal(step.state, "channelsVersioned");
  assert.equal(step.memberCount, 3);
  assert.equal(step.ownerSeen, true);
  // The staged window must be INERT for the legacy rules. `liveness` is the
  // one staged field a legacy channel update is refused for carrying
  // (firestore.rules noClientChannelLiveness), so it is not written until the
  // root stage; until then a legacy manager can still rename or reorder.
  for (const channelId of ["general", "announcements", "lounge"]) {
    const channel = (await db.doc(`clubs/${INVITED}/channels/${channelId}`).get()).data();
    assert.equal(channel.serverSchemaVersion, 1, channelId);
    assert.equal(channel.liveness, undefined, channelId);
  }

  // A FRESH run id over the same partially staged root re-runs both staged
  // stages and writes nothing: staging is re-runnable, not one-shot.
  const restage = await runEngine({ mode: "apply", runId: "run-restage", only });
  const restageEntry = byPath(restage, only[0]);
  assert.deepEqual(restageEntry.stagesRun, ["members", "channels", "root"]);
  assert.deepEqual(restageEntry.reasons, ["client-compatibility-gate-not-satisfied"]);
  // Only the run-record write for the two staged stages; not one document of
  // the root's own graph was rewritten.
  assert.equal(restageEntry.writes, 2);

  await publishGate();
  const resumed = await runEngine({ mode: "apply", runId: "run-resume", only });
  const resumedEntry = byPath(resumed, only[0]);
  assert.equal(resumedEntry.resumed, true);
  // Members and channels are NOT re-run: resume starts at the unfinished stage.
  assert.deepEqual(resumedEntry.stagesRun, ["root"]);
  assert.equal(resumedEntry.disposition, "applied");
  assert.equal((await db.doc(`clubs/${INVITED}`).get()).data().serverSchemaVersion, 1);
  assert.equal((await db.doc(`clubs/${INVITED}`).get()).data().memberCount, 3);
  // The liveness projection lands with the root, idle, on every channel.
  for (const channelId of ["general", "announcements", "lounge"]) {
    const channel = (await db.doc(`clubs/${INVITED}/channels/${channelId}`).get()).data();
    assert.deepEqual(channel.liveness, { schemaVersion: 1, isLive: false, startedAt: null }, channelId);
  }
});

emulatorTest("a session that starts mid-run defers the root instead of racing the write", async () => {
  const only = [`clubs/${CROWDED}`];
  await seed({ [`rooms/club_lounge_${CROWDED}/participants/${CROWD}`]: null });
  await publishGate({ status: "open", attestedBy: null, attestedAt: null });
  const staged = await runEngine({ mode: "apply", runId: "run-race", only });
  assert.deepEqual(byPath(staged, only[0]).stagesRun, ["members", "channels", "root"]);
  assert.deepEqual(byPath(staged, only[0]).reasons, ["client-compatibility-gate-not-satisfied"]);

  await publishGate();
  await seed({ [`rooms/club_lounge_${CROWDED}`]: loungeRoom(CROWDED, { isLive: true, participantCount: 2 }) });
  const raced = await runEngine({ mode: "apply", runId: "run-race", only });
  assert.equal(byPath(raced, only[0]).disposition, "deferred");
  assert.deepEqual(byPath(raced, only[0]).reasons, ["active-session-must-not-be-migrated"]);
  assert.equal((await db.doc(`clubs/${CROWDED}`).get()).data().serverSchemaVersion, undefined);

  await seed({ [`rooms/club_lounge_${CROWDED}`]: loungeRoom(CROWDED) });
});

emulatorTest("a refusal inside a stage leaves nothing from that stage written", async () => {
  const only = [`clubs/${PRIVATE_CHANNEL}`];
  const report = await runEngine({ mode: "apply", runId: "run-partial", only });
  assert.deepEqual(byPath(report, only[0]).stagesRun, ["members", "channels"]);
  assert.deepEqual(byPath(report, only[0]).reasons, ["restricted-legacy-channel-requires-access-mapping"]);
  // Not one channel of that root was versioned, including the valid ones that
  // were validated before the restricted one.
  const channels = await db.collection(`clubs/${PRIVATE_CHANNEL}/channels`).get();
  assert.equal(channels.docs.some((doc) => doc.data().serverSchemaVersion !== undefined), false);
  assert.equal((await db.doc(`clubs/${PRIVATE_CHANNEL}`).get()).data().serverSchemaVersion, undefined);
});

emulatorTest("a root that moved since the plan was computed is refused, not written from a stale decision", async () => {
  const manifest = await collect();
  const mappings = manifest.mappingReport.mappings.filter((mapping) => mapping.sourcePath === `clubs/${ARTWORK}`);
  await db.doc(`clubs/${ARTWORK}`).update({ description: "changed after the plan" });
  const report = await engine("dryRun").run({
    runId: "run-stale", mappings, planDigest: manifest.mappingReport.reportDigest,
    expectedGateRevision: GATE_REVISION, clientCensus: CENSUS_CLEAN,
  });
  assert.deepEqual(byPath(report, `clubs/${ARTWORK}`).reasons, ["source-version-changed-since-plan"]);
});

emulatorTest("a refused root keeps its media pointers exactly as they were", async () => {
  const root = (await db.doc(`clubs/${ARTWORK}`).get()).data();
  assert.equal(root.serverSchemaVersion, undefined);
  assert.ok(root.avatarUrl.includes("generation=17"));
  assert.ok(root.bannerUrl.includes("generation=18"));
  assert.equal((await db.collection(`clubs/${ARTWORK}/memberAuthorizations`).get()).size, 0);
});

emulatorTest("the manifest never carries a display name, a description or a media URL", async () => {
  const report = await runEngine({ mode: "dryRun" });
  const text = JSON.stringify(report);
  for (const secret of ["generation=17", "generation=18", "A real legacy club", "Club Lounge", "storage.example.invalid"]) {
    assert.equal(text.includes(secret), false, secret);
  }
  assert.equal(report.applyReady, false);
});

// ------------------------------------------------- P1-1: back-pointer discovery
//
// The engine used to enumerate a Club's rooms by FORWARD POINTER only —
// `channel.roomId` plus `root.loungeRoomId`. `firestore.rules`
// (`isLegacyRoomData` reads `room.clubId`), `functions/clubs/deletion.js:278`
// and `functions/clubs/voice.js:29` all key on the BACK-pointer instead, so a
// room bound to the Club by `clubId` and named by nothing was invisible to
// `probeLiveness` and to the stranded-history probe at the same time: the root
// planned `applied` with every count reading zero while people were in the
// room. These three tests are the fixture the audit asked for — the pointer
// absent, the pointer missing entirely, and the pointer STALE — proven against
// a real emulator, because the fix is a transactional query and a source-text
// assertion does not prove a query runs (ADR-007).

async function forwardPointerRooms(clubId) {
  // The PRE-FIX discovery set, rebuilt from exactly the documents the engine
  // reads, so the fixture's blindness is measured rather than asserted.
  const root = await db.doc(`clubs/${clubId}`).get();
  const channels = await db.collection(`clubs/${clubId}/channels`).get();
  const ids = new Set();
  for (const doc of channels.docs) {
    const roomId = doc.data().roomId;
    if (typeof roomId === "string") ids.add(roomId);
  }
  const lounge = root.data().loungeRoomId;
  if (typeof lounge === "string") ids.add(lounge);
  return ids;
}

emulatorTest("the fixture is genuinely pointer-blind: forward-pointer discovery sees no live room and no history", async () => {
  const liveRoomOf = { [ORPHAN]: ORPHAN_ROOM, [LAZY_LOUNGE]: `club_lounge_${LAZY_LOUNGE}`, [STALE_POINTER]: STALE_ROOM };
  for (const id of POINTER_BLIND_IDS) {
    const pointers = await forwardPointerRooms(id);
    assert.equal(pointers.has(liveRoomOf[id]), false, `${id}: the live room must be unnamed by any pointer`);
    // And what the pointers DO name is harmless, so the old set would have
    // reported this root as clean: zero live rooms, zero stranded history.
    for (const roomId of pointers) {
      const room = await db.doc(`rooms/${roomId}`).get();
      if (!room.exists) continue;
      const data = room.data();
      assert.equal(data.isLive === true || data.participantCount > 0 ||
        typeof data.voiceSessionId === "string", false, `${id}: ${roomId} must be idle`);
      assert.equal((await db.collection(`rooms/${roomId}/messages`).limit(1).get()).size, 0, `${id}: ${roomId}`);
    }
  }
  // The stale pointer names a room that is gone; the live one is bound only by
  // `clubId`, exactly as `clubs/deletion.js` and the Rules enumerate it.
  assert.ok((await forwardPointerRooms(STALE_POINTER)).has(VANISHED_ROOM));
  assert.equal((await db.doc(`rooms/${VANISHED_ROOM}`).get()).exists, false);
  assert.equal((await db.doc(`rooms/${STALE_ROOM}`).get()).data().clubId, STALE_POINTER);
  // A pointer-blind club still has rooms — three separate implementations in
  // this repository find them the same way.
  for (const id of POINTER_BLIND_IDS) {
    const bound = await db.collection("rooms").where("clubId", "==", id).get();
    assert.ok(bound.size >= 1, id);
  }
});

emulatorTest("a live, history-bearing room bound only by clubId defers its root instead of migrating under people", async () => {
  const report = await runEngine({ mode: "dryRun" });
  const expected = {
    [ORPHAN]: ["active-session-must-not-be-migrated", "bound-room-history-would-lose-its-read-path"],
    [LAZY_LOUNGE]: ["active-session-must-not-be-migrated", "bound-room-artwork-would-lose-its-read-path"],
    [STALE_POINTER]: ["active-session-must-not-be-migrated", "bound-room-history-would-lose-its-read-path"],
  };
  for (const id of POINTER_BLIND_IDS) {
    const root = byPath(report, `clubs/${id}`);
    assert.deepEqual(root.reasons, expected[id], id);
    // Live AND stranded: waiting for the room to go idle will never clear the
    // second reason, so this is a refusal, not a deferral (principal F9).
    assert.equal(root.disposition, "refused", id);
    assert.equal(root.writes, 0, id);
    assert.equal(root.counts.liveRooms, 1, id);
    assert.equal(root.counts.transientParticipants, 0, id);
    assert.equal((await db.doc(`clubs/${id}`).get()).data().serverSchemaVersion, undefined, id);
  }
  // The counts are the operator's evidence, so they must mean what they say:
  // rooms that EXIST, never the ids that were probed. STALE_POINTER probes
  // three ids — a vanished channel anchor, the lazy lounge convention and the
  // back-pointer hit — and owns exactly one room.
  assert.equal(byPath(report, `clubs/${STALE_POINTER}`).counts.boundRooms, 1);
  assert.equal(byPath(report, `clubs/${ORPHAN}`).counts.boundRooms, 2);
  assert.equal(byPath(report, `clubs/${LAZY_LOUNGE}`).counts.boundRooms, 1);
  assert.equal(byPath(report, `clubs/${ORPHAN}`).counts.boundRoomMessages, 1);
  assert.equal(byPath(report, `clubs/${LAZY_LOUNGE}`).counts.boundRoomArtwork, 1);
});

emulatorTest("apply mode — the mode that can write — writes nothing for a pointer-blind root, and the room is untouched", async () => {
  const only = POINTER_BLIND_IDS.map((id) => `clubs/${id}`);
  const report = await runEngine({ mode: "apply", runId: "run-pointer-blind", only });
  // The only write is the durable run ledger. Every refused root reports zero
  // writes and remains byte-for-byte on its legacy schema.
  assert.equal(report.writeCount, 1);
  for (const id of POINTER_BLIND_IDS) {
    const entry = byPath(report, `clubs/${id}`);
    assert.equal(entry.disposition, "refused", id);
    assert.equal(entry.writes, 0, id);
    const root = (await db.doc(`clubs/${id}`).get()).data();
    assert.equal(root.serverSchemaVersion, undefined, id);
    assert.equal(root.migration, undefined, id);
    assert.equal((await db.collection(`clubs/${id}/memberAuthorizations`).get()).size, 0, id);
    for (const doc of (await db.collection(`clubs/${id}/channels`).get()).docs) {
      assert.equal(doc.data().serverSchemaVersion, undefined, `${id}/${doc.id}`);
    }
  }
  // The live rooms kept their session state and their history exactly.
  const orphan = (await db.doc(`rooms/${ORPHAN_ROOM}`).get()).data();
  assert.equal(orphan.isLive, true);
  assert.equal(orphan.participantCount, 7);
  assert.equal(orphan.clubId, ORPHAN);
  assert.equal((await db.collection(`rooms/${ORPHAN_ROOM}/messages`).get()).size, 1);
  assert.equal((await db.collection(`rooms/${STALE_ROOM}/messages`).get()).size, 1);
});

emulatorTest("an idle, history-free bound room found only by the back-pointer does not block its root", async () => {
  // The widened probe must be a refusal, not a wall: the same discovery path
  // that defers a live room has to let a quiet one through, or every Club with
  // a second room becomes unmigratable.
  await seed({
    [`rooms/${ORPHAN_ROOM}`]: loungeRoom(ORPHAN, { name: "Orphaned voice room", roomKind: "clubVoice" }),
    [`rooms/${ORPHAN_ROOM}/messages/msg_0001`]: null,
  });
  const report = await runEngine({ mode: "dryRun", only: [`clubs/${ORPHAN}`] });
  const root = byPath(report, `clubs/${ORPHAN}`);
  assert.deepEqual(root.reasons, []);
  assert.equal(root.disposition, "applied");
  assert.equal(root.counts.boundRooms, 2);
  assert.equal(root.counts.liveRooms, 0);
  assert.equal(root.counts.boundRoomMessages, 0);
  assert.equal(report.writeCount, 0);
  assert.equal(report.applyReady, false);
});
