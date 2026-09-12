// The per-room versioned-anchor boundary on the legacy Club room loops
// (principal-review.md P3-3, s3-reaudit.md F1).
//
// Five loops iterate `rooms where clubId == clubId` and act on
// `roomDocument.id`. Against a versioned (V1) anchor that id is the WRONG
// LiveKit namespace — the live room is the generation's immutable `srv_`
// name — so `endRoom`/`revokeParticipant` there is reported as
// `alreadyAbsent`: a silent success that leaves the identity connected,
// while the anchor's mirrors and roster belong to the V1 teardown.
//
// DEFENCE IN DEPTH, NOT A LIVE FIX. Every entry point asserts
// `assertLegacyClubData` first, and a canonical V1 anchor's `clubId` equals
// its `serverId` — always a versioned club root — so none of this is
// reachable without tampered data. The rooms seeded below ARE that tampered
// shape: a versioned anchor carrying a LEGACY club's id, which is the only
// way the query can return one.
//
// Two of the five loops live in modules with their own suites and are
// covered there: clubs/deletion.js in test/club_self_deletion.test.js and
// clubs/members.js in test/club_membership_security.test.js. This file
// covers the remaining three — admin/clubs.js twice and clubs/voice.js,
// which has no suite of its own.
//
//   firebase emulators:start --only auth,firestore,storage
//   node --test --test-concurrency=1 test/servers_legacy_club_anchor_guard.test.js

const assert = require("node:assert/strict");
const { after, afterEach, beforeEach, describe, test } = require("node:test");

// Refuse to run against production, even when a developer has ADC enabled.
if (!/^127\.0\.0\.1:\d+$/u.test(process.env.FIRESTORE_EMULATOR_HOST ?? "")) {
  throw new Error("An explicit loopback FIRESTORE_EMULATOR_HOST is required.");
}

// ITS OWN FIRESTORE NAMESPACE, like server_legacy_boundary.test.js and for
// the same reason: `seed()` below clears the whole database, and the rooms
// this file creates are live, club-bound rooms that neighbouring suites list
// globally.
process.env.GCLOUD_PROJECT = "demo-yovoice-legacy-anchor-guard";

const { initializeApp, deleteApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

const app = initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = getFirestore(app);

const {
  adminDeleteClub,
  setClubModerationStatus,
  setClubLiveKitControlForTests,
  setClubStorageBucketForTests,
} = require("../admin/clubs");
const { revokeClubMemberVoice } = require("../clubs/voice");
const { setProtectedOwnerUidForTests } = require("../utils/roles");

const P = "lag-";
const OWNER = `${P}owner`;
const MEMBER = `${P}member`;
const STAFF = `${P}staff`;
const CLUB = `${P}club`;
const LEGACY_ROOM = `${P}room-a-legacy`;
const ANCHOR_ROOM = `${P}room-b-anchor`;
const SERVER = `${P}server`;
const CHANNEL = `${P}channel`;
const SESSION = `${P}session`;
const SRV_NAME = `srv_${"a".repeat(40)}`;

const invoke = (callable, value) => (callable.run ?? callable)(value);
const staff = (data) => ({
  auth: {
    uid: STAFF,
    token: {
      role: "superAdmin",
      email_verified: true,
      auth_time: Math.floor(Date.now() / 1000),
    },
  },
  data,
});

function mirrorReference(uid, roomId) {
  return db.collection("activeVoiceSessions").doc(uid)
    .collection("rooms").doc(roomId);
}

function fakeControl() {
  const calls = [];
  return {
    calls,
    async endRoom(roomId) {
      calls.push(["endRoom", roomId]);
    },
    async revokeParticipant(roomId, uid) {
      calls.push(["revokeParticipant", roomId, uid]);
    },
  };
}

function fakeBucket() {
  const prefixDeletes = [];
  const fileDeletes = [];
  return {
    prefixDeletes,
    fileDeletes,
    name: "yovoice-test.firebasestorage.app",
    async deleteFiles(options) {
      prefixDeletes.push(options.prefix);
    },
    file(objectPath) {
      return {
        async delete() {
          fileDeletes.push(objectPath);
        },
      };
    },
  };
}

// A legacy club with two rooms bound to it by the `clubId` FIELD — the same
// authority every loop under test uses. One is an ordinary legacy room; the
// other is a versioned anchor that should never be addressed by id.
async function seed() {
  for (const collection of await db.listCollections()) {
    await db.recursiveDelete(collection);
  }
  await Promise.all([
    db.doc(`users/${OWNER}`).set({ displayName: OWNER, banned: false, disabled: false }),
    db.doc(`users/${MEMBER}`).set({ displayName: MEMBER, banned: false, disabled: false }),
    db.doc(`users/${STAFF}`).set({ role: "superAdmin", banned: false, disabled: false }),
    db.doc(`clubs/${CLUB}`).set({
      name: "Legacy Club",
      ownerId: OWNER,
      ownerName: "Owner",
      type: "community",
      status: "active",
      privacy: "private",
      memberCount: 2,
      onlineCount: 1,
    }),
  ]);
  await Promise.all([
    db.doc(`clubs/${CLUB}/members/${OWNER}`).set({ userId: OWNER, role: "owner" }),
    db.doc(`clubs/${CLUB}/members/${MEMBER}`).set({ userId: MEMBER, role: "member" }),
    db.doc(`rooms/${LEGACY_ROOM}`).set({
      hostId: OWNER,
      clubId: CLUB,
      name: "Legacy club room",
      roomKind: "clubRoom",
      status: "active",
      visibility: "private",
      isLive: true,
      participantCount: 1,
    }),
    db.doc(`rooms/${LEGACY_ROOM}/participants/${MEMBER}`).set({
      userId: MEMBER,
      role: "listener",
    }),
    mirrorReference(MEMBER, LEGACY_ROOM).set({
      userId: MEMBER,
      roomId: LEGACY_ROOM,
      participantIdentity: MEMBER,
      expiresAt: Timestamp.fromMillis(Date.now() + 300_000),
    }),
    // THE TAMPERED ANCHOR. `clubId` names a legacy club (a canonical anchor's
    // clubId is its own versioned serverId), which is what puts it in the
    // query at all; `serverSchemaVersion`/`serverId` are what make it a
    // versioned boundary for isVersionedAnchor().
    db.doc(`rooms/${ANCHOR_ROOM}`).set({
      serverSchemaVersion: 1,
      serverId: SERVER,
      channelId: CHANNEL,
      clubId: CLUB,
      hostId: OWNER,
      name: "V1 media anchor",
      status: "active",
      visibility: "public",
      isLive: true,
      participantCount: 1,
      roomType: "community",
      experience: "community",
      livekitRoomName: SRV_NAME,
      voiceSessionId: SESSION,
    }),
    db.doc(`rooms/${ANCHOR_ROOM}/participants/${MEMBER}`).set({
      userId: MEMBER,
      role: "speaker",
    }),
    mirrorReference(MEMBER, ANCHOR_ROOM).set({
      serverSchemaVersion: 1,
      serverId: SERVER,
      channelId: CHANNEL,
      roomId: ANCHOR_ROOM,
      sessionId: SESSION,
      userId: MEMBER,
      participantIdentity: MEMBER,
      livekitRoomName: SRV_NAME,
      expiresAt: Timestamp.fromMillis(Date.now() + 300_000),
    }),
  ]);
}

async function anchorState() {
  const [room, mirror, participant] = await Promise.all([
    db.doc(`rooms/${ANCHOR_ROOM}`).get(),
    mirrorReference(MEMBER, ANCHOR_ROOM).get(),
    db.doc(`rooms/${ANCHOR_ROOM}/participants/${MEMBER}`).get(),
  ]);
  return {
    room: room.data() ?? null,
    mirror: mirror.data() ?? null,
    participant: participant.data() ?? null,
  };
}

beforeEach(seed);

afterEach(() => {
  setClubLiveKitControlForTests(null);
  setClubStorageBucketForTests(null);
  setProtectedOwnerUidForTests(null);
});

after(async () => {
  await db.terminate();
  await deleteApp(app);
});

describe("admin/clubs.js setClubModerationStatus", () => {
  test("suspension ends the legacy room only and never addresses the anchor id", async () => {
    const control = fakeControl();
    setClubLiveKitControlForTests(control);
    const before = await anchorState();

    await invoke(setClubModerationStatus, staff({
      clubId: CLUB,
      suspended: true,
      reason: "versioned anchor boundary regression",
    }));

    // The legacy room is ended, its mirrors swept and its roster cleared —
    // byte-for-byte the behaviour that shipped before the guard.
    assert.deepEqual(control.calls, [["endRoom", LEGACY_ROOM]]);
    assert.equal((await mirrorReference(MEMBER, LEGACY_ROOM).get()).exists, false);
    assert.equal(
      (await db.collection(`rooms/${LEGACY_ROOM}/participants`).get()).empty,
      true,
    );
    const legacy = (await db.doc(`rooms/${LEGACY_ROOM}`).get()).data();
    assert.equal(legacy.isLive, false);
    assert.equal(legacy.status, "suspended");
    assert.equal(legacy.moderationReason, "versioned anchor boundary regression");
    assert.equal(legacy.moderatedBy, STAFF);
    assert.equal(legacy.participantCount, 0);
    assert.ok(legacy.moderatedAt, "the legacy room is stamped by the moderation batch");

    // The anchor gets no provider call, keeps its live generation's mirror
    // and keeps its roster row.
    const after = await anchorState();
    assert.deepEqual(after.mirror, before.mirror);
    assert.deepEqual(after.participant, before.participant);

    // BYTE-IDENTICAL, `isLive` included. The moderation BATCH is guarded
    // too, so a versioned anchor is not moderated, not dated and above all
    // not dropped to `isLive: false` — the liveness of a V1 anchor belongs
    // to its channelSession generation, never to a club moderation verdict.
    assert.deepEqual(after.room, before.room);
    assert.equal(after.room.isLive, true);
    assert.equal(after.room.status, "active");
  });

  test("restoring a suspended club runs no room teardown at all", async () => {
    const control = fakeControl();
    setClubLiveKitControlForTests(control);
    await db.doc(`clubs/${CLUB}`).update({ status: "suspended" });
    const before = await anchorState();

    await invoke(setClubModerationStatus, staff({ clubId: CLUB, suspended: false }));

    assert.deepEqual(control.calls, []);
    const after = await anchorState();
    assert.deepEqual(after.room, before.room);
    assert.deepEqual(after.mirror, before.mirror);
    assert.deepEqual(after.participant, before.participant);
    // ...while the legacy room is restored by the same batch, as before.
    const legacy = (await db.doc(`rooms/${LEGACY_ROOM}`).get()).data();
    assert.equal(legacy.status, "active");
    assert.equal(legacy.isLive, true);
  });
});

describe("admin/clubs.js adminDeleteClub", () => {
  test("deletes the legacy room and leaves the versioned anchor byte-identical", async () => {
    const control = fakeControl();
    const bucket = fakeBucket();
    setProtectedOwnerUidForTests(STAFF);
    setClubLiveKitControlForTests(control);
    setClubStorageBucketForTests(bucket);
    const before = await anchorState();

    const result = await invoke(adminDeleteClub, staff({
      clubId: CLUB,
      confirmation: CLUB,
      reason: "versioned anchor boundary regression",
    }));

    assert.equal(result.success, true);
    // Legacy: ended, media swept, document recursively deleted.
    assert.deepEqual(control.calls, [["endRoom", LEGACY_ROOM]]);
    assert.deepEqual(bucket.prefixDeletes, [`room_images/${LEGACY_ROOM}/`]);
    assert.equal((await db.doc(`rooms/${LEGACY_ROOM}`).get()).exists, false);
    assert.equal((await mirrorReference(MEMBER, LEGACY_ROOM).get()).exists, false);
    assert.equal((await db.doc(`clubs/${CLUB}`).get()).exists, false);

    // Anchor: no provider call, no media sweep, no mirror delete, and the
    // document itself survives the club deletion untouched.
    const after = await anchorState();
    assert.deepEqual(after.room, before.room);
    assert.deepEqual(after.mirror, before.mirror);
    assert.deepEqual(after.participant, before.participant);
  });
});

describe("clubs/voice.js revokeClubMemberVoice", () => {
  test("revokes the legacy room and never revokes against the anchor id", async () => {
    // The anchor KEEPS its roster row for this identity. The guard is at the
    // top of the loop now, so neither the roster transaction nor the provider
    // call runs for a versioned anchor: no participant delete, no
    // participantCount write, no revoke and no mirror delete.
    const control = fakeControl();
    const before = await anchorState();

    const scanned = await revokeClubMemberVoice({
      clubId: CLUB,
      userId: MEMBER,
      control,
    });

    // The query result is unchanged: both rooms are still scanned.
    assert.equal(scanned, 2);
    assert.deepEqual(control.calls, [["revokeParticipant", LEGACY_ROOM, MEMBER]]);
    assert.equal((await mirrorReference(MEMBER, LEGACY_ROOM).get()).exists, false);
    assert.equal(
      (await db.doc(`rooms/${LEGACY_ROOM}/participants/${MEMBER}`).get()).exists,
      false,
    );
    assert.equal(
      (await db.doc(`rooms/${LEGACY_ROOM}`).get()).data().participantCount,
      0,
    );

    const after = await anchorState();
    assert.deepEqual(after.room, before.room);
    assert.deepEqual(after.mirror, before.mirror);
    assert.deepEqual(after.participant, before.participant);
    assert.equal(
      (await db.doc(`rooms/${ANCHOR_ROOM}/participants/${MEMBER}`).get()).exists,
      true,
      "the V1 generation's roster row is not touched by a legacy Club path",
    );
  });

  test("a club whose rooms are all legacy is revoked exactly as before", async () => {
    await db.recursiveDelete(db.doc(`rooms/${ANCHOR_ROOM}`));
    const control = fakeControl();

    const scanned = await revokeClubMemberVoice({
      clubId: CLUB,
      userId: MEMBER,
      control,
    });

    assert.equal(scanned, 1);
    assert.deepEqual(control.calls, [["revokeParticipant", LEGACY_ROOM, MEMBER]]);
    assert.equal((await mirrorReference(MEMBER, LEGACY_ROOM).get()).exists, false);
  });
});
