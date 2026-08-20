// Owner-initiated Club deletion (deleteClubSelf) must tear down the club
// document tree, its lounge room, LiveKit state, active-session mirrors,
// private users/{uid}/clubs projections and Storage media — and refuse
// everyone who is not the club document's current owner. This is the "Club
// lifecycle" that executeDeleteRoom's lounge refusal routes to; that
// refusal itself stays pinned by room_host_control_security.test.js.

const assert = require("node:assert/strict");
const { test, beforeEach, describe } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

// ITS OWN FIRESTORE NAMESPACE, like room_liveness_sweeper.test.js and for
// the same reason, mirrored: `node --test test/*.test.js` runs suites in
// parallel against one shared emulator database per project id, and several
// neighbouring suites (legacy_identity_scrub, achievement_migration,
// direct_integrity) page over WHOLE collections — `users` above all. This
// suite seeds `users/csd-*` documents and projections while they scan, which
// made their exact counters read whatever the scheduler did that run
// (verified: 734/734 green without this file, 4 cross-suite failures with it
// in the shared namespace). A derived project id isolates both directions.
const BASE_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";
const CLUB_DELETION_PROJECT = `${BASE_PROJECT}-club-deletion`;
process.env.GCLOUD_PROJECT = CLUB_DELETION_PROJECT;

if (getApps().length === 0) {
  initializeApp({ projectId: CLUB_DELETION_PROJECT });
}

const { executeDeleteClubSelf } = require("../clubs/deletion");

const db = getFirestore();
const P = "csd-";
const OWNER = `${P}owner`;
const MODERATOR = `${P}moderator`;
const MEMBER = `${P}member`;
const PREVIOUS = `${P}previous`;
const CLUB = `${P}club`;
const LOUNGE = `club_lounge_${CLUB}`;
const CHANNEL = `${P}general`;
const BUCKET_NAME = "yovoice-test.firebasestorage.app";
const AVATAR_PATH = `clubs/${OWNER}/${CLUB}/avatar`;
const AVATAR_URL =
  `https://firebasestorage.googleapis.com/v0/b/${BUCKET_NAME}` +
  `/o/${encodeURIComponent(AVATAR_PATH)}?alt=media&token=test-token`;

function request(uid, data) {
  return { auth: { uid, token: {} }, data };
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

function fakeBucket({ failPrefixes = false } = {}) {
  const prefixDeletes = [];
  const fileDeletes = [];
  return {
    name: BUCKET_NAME,
    prefixDeletes,
    fileDeletes,
    async deleteFiles(options) {
      prefixDeletes.push(options.prefix);
      if (failPrefixes) {
        const error = new Error("Storage unavailable");
        error.code = "storage-unavailable";
        throw error;
      }
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

async function wipeOwn() {
  await Promise.all([
    db.recursiveDelete(db.collection("clubs").doc(CLUB)),
    db.recursiveDelete(db.collection("rooms").doc(LOUNGE)),
    db.recursiveDelete(db.collection("users").doc(OWNER)),
    db.recursiveDelete(db.collection("users").doc(MODERATOR)),
    db.recursiveDelete(db.collection("users").doc(MEMBER)),
    db.recursiveDelete(db.collection("users").doc(PREVIOUS)),
    db.recursiveDelete(db.collection("activeVoiceSessions").doc(OWNER)),
    db.recursiveDelete(db.collection("activeVoiceSessions").doc(MEMBER)),
    db.collection("clubMarketingConsents").doc(CLUB).delete(),
    db.collection("clubOwnershipGuards").doc(OWNER).delete(),
    db.collection("adminAuditLogs").doc(`delete_club_self_${CLUB}`).delete(),
  ]);
}

async function seedClub(overrides = {}) {
  const clubReference = db.collection("clubs").doc(CLUB);
  await clubReference.set({
    name: "family",
    description: "The family space",
    ownerId: OWNER,
    ownerName: "Owner",
    avatarUrl: AVATAR_URL,
    bannerUrl: null,
    privacy: "private",
    type: "community",
    status: "active",
    defaultLanguage: "English",
    memberCount: 3,
    onlineCount: 1,
    loungeRoomId: LOUNGE,
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
    ...overrides,
  });
  await Promise.all([
    clubReference.collection("members").doc(OWNER).set({
      userId: OWNER,
      role: "owner",
      joinedAt: Timestamp.now(),
    }),
    clubReference.collection("members").doc(MODERATOR).set({
      userId: MODERATOR,
      role: "moderator",
      joinedAt: Timestamp.now(),
    }),
    clubReference.collection("members").doc(MEMBER).set({
      userId: MEMBER,
      role: "member",
      joinedAt: Timestamp.now(),
    }),
    clubReference.collection("invites").doc(`${P}invitee`).set({
      inviterId: OWNER,
      clubId: CLUB,
      createdAt: Timestamp.now(),
    }),
    clubReference.collection("channels").doc(CHANNEL).set({
      name: "general",
      type: "chat",
      createdBy: OWNER,
    }),
    clubReference.collection("checkIns").doc(`${P}checkin`).set({
      userId: MEMBER,
      clubId: CLUB,
      status: "home",
      createdAt: Timestamp.now(),
    }),
    clubReference.collection("moments").doc(`${P}moment`).set({
      authorId: MEMBER,
      clubId: CLUB,
      createdAt: Timestamp.now(),
    }),
    db.collection("clubMarketingConsents").doc(CLUB).set({
      grantedBy: OWNER,
    }),
    ...[OWNER, MODERATOR, MEMBER].map((uid) =>
      db.collection("users").doc(uid).collection("clubs").doc(CLUB).set({
        clubId: CLUB,
        name: "family",
        role: uid === OWNER ? "owner" : "member",
      }),
    ),
  ]);
  await clubReference
    .collection("channels")
    .doc(CHANNEL)
    .collection("messages")
    .doc(`${P}message`)
    .set({
      senderId: MEMBER,
      clubId: CLUB,
      channelId: CHANNEL,
      text: "hello",
    });
}

async function seedLounge(overrides = {}) {
  await db.collection("rooms").doc(LOUNGE).set({
    hostId: OWNER,
    name: "family Lounge",
    clubId: CLUB,
    roomKind: "clubLounge",
    visibility: "private",
    status: "active",
    isLive: false,
    participantCount: 0,
    membersCanStartVoice: true,
    ...overrides,
  });
}

async function seedLoungeParticipant(uid) {
  await db
    .collection("rooms")
    .doc(LOUNGE)
    .collection("participants")
    .doc(uid)
    .set({ userId: uid, role: uid === OWNER ? "host" : "listener" });
}

async function seedSession(uid) {
  await db
    .collection("activeVoiceSessions")
    .doc(uid)
    .collection("rooms")
    .doc(LOUNGE)
    .set({
      userId: uid,
      roomId: LOUNGE,
      participantIdentity: uid,
      expiresAt: Timestamp.fromMillis(Date.now() + 300_000),
    });
}

async function clubGraphIsGone() {
  const [
    club,
    lounge,
    loungeParticipants,
    members,
    invites,
    messages,
    checkIns,
    moments,
    consent,
    ...projections
  ] = await Promise.all([
    db.collection("clubs").doc(CLUB).get(),
    db.collection("rooms").doc(LOUNGE).get(),
    db.collection("rooms").doc(LOUNGE).collection("participants").get(),
    db.collection("clubs").doc(CLUB).collection("members").get(),
    db.collection("clubs").doc(CLUB).collection("invites").get(),
    db
      .collection("clubs")
      .doc(CLUB)
      .collection("channels")
      .doc(CHANNEL)
      .collection("messages")
      .get(),
    db.collection("clubs").doc(CLUB).collection("checkIns").get(),
    db.collection("clubs").doc(CLUB).collection("moments").get(),
    db.collection("clubMarketingConsents").doc(CLUB).get(),
    ...[OWNER, MODERATOR, MEMBER].map((uid) =>
      db.collection("users").doc(uid).collection("clubs").doc(CLUB).get(),
    ),
  ]);
  return (
    !club.exists &&
    !lounge.exists &&
    loungeParticipants.empty &&
    members.empty &&
    invites.empty &&
    messages.empty &&
    checkIns.empty &&
    moments.empty &&
    !consent.exists &&
    projections.every((snapshot) => !snapshot.exists)
  );
}

beforeEach(async () => {
  await wipeOwn();
  await Promise.all(
    [OWNER, MODERATOR, MEMBER, PREVIOUS].map((uid) =>
      db.collection("users").doc(uid).set({ banned: false }),
    ),
  );
});

describe("club self deletion", () => {
  // ACCOUNT STATUS GATES THE OWNER TOO. requireActiveCaller mirrors the
  // participants.js pattern, but until these three cases existed that was an
  // inspection claim, not a pinned one — and the destructive call of the
  // product is the last place a claim should stand in for a test.
  for (const [label, profile] of [
    ["a BANNED owner", { banned: true }],
    ["a DISABLED owner", { disabled: true }],
    ["an owner with NO profile document", null],
  ]) {
    test(`${label} is refused and nothing is deleted`, async () => {
      const control = fakeControl();
      const bucket = fakeBucket();
      await seedClub();
      await seedLounge();
      if (profile === null) {
        await db.collection("users").doc(OWNER).delete();
      } else {
        await db.collection("users").doc(OWNER).set(profile);
      }

      await assert.rejects(
        () => executeDeleteClubSelf(request(OWNER, { clubId: CLUB }), control, bucket),
        (error) => error.code === "permission-denied",
      );
      const club = await db.collection("clubs").doc(CLUB).get();
      assert.equal(club.exists, true);
      assert.notEqual(club.data().deletionInProgress, true);
      const loungeDoc = await db.collection("rooms").doc(`club_lounge_${CLUB}`).get();
      assert.equal(loungeDoc.exists, true);
      assert.deepEqual(control.calls, []);
    });
  }

  test("the owner deletes the whole club: tree, lounge, sessions, projections, LiveKit and media", async () => {
    const control = fakeControl();
    const bucket = fakeBucket();
    await seedClub();
    await seedLounge();
    await seedLoungeParticipant(MEMBER);
    await seedSession(MEMBER);

    const result = await executeDeleteClubSelf(
      request(OWNER, { clubId: CLUB }),
      control,
      bucket,
    );

    assert.deepEqual(result, { success: true, clubId: CLUB });
    assert.equal(await clubGraphIsGone(), true);
    assert.equal(
      (
        await db
          .collection("activeVoiceSessions")
          .doc(MEMBER)
          .collection("rooms")
          .doc(LOUNGE)
          .get()
      ).exists,
      false,
    );
    assert.deepEqual(control.calls, [["endRoom", LOUNGE]]);
    assert.deepEqual(bucket.prefixDeletes, [`room_images/${LOUNGE}/`]);
    assert.deepEqual(bucket.fileDeletes, [AVATAR_PATH]);
    const audit = await db
      .collection("adminAuditLogs")
      .doc(`delete_club_self_${CLUB}`)
      .get();
    assert.equal(audit.exists, true);
    assert.equal(audit.data().action, "delete_club_self");
    assert.equal(audit.data().targetId, CLUB);
    assert.equal(audit.data().actorId, OWNER);
  });

  test("a non-owner — even a club moderator or member — is refused and nothing is deleted", async () => {
    const control = fakeControl();
    const bucket = fakeBucket();
    await seedClub();
    await seedLounge();
    await seedLoungeParticipant(MEMBER);

    for (const caller of [MODERATOR, MEMBER]) {
      await assert.rejects(
        executeDeleteClubSelf(request(caller, { clubId: CLUB }), control, bucket),
        (error) => error?.code === "permission-denied",
      );
    }

    const [club, lounge, membersSnapshot, participant] = await Promise.all([
      db.collection("clubs").doc(CLUB).get(),
      db.collection("rooms").doc(LOUNGE).get(),
      db.collection("clubs").doc(CLUB).collection("members").get(),
      db
        .collection("rooms")
        .doc(LOUNGE)
        .collection("participants")
        .doc(MEMBER)
        .get(),
    ]);
    assert.equal(club.exists, true);
    assert.notEqual(club.data().deletionInProgress, true);
    assert.equal(lounge.exists, true);
    assert.equal(lounge.data().status, "active");
    assert.equal(membersSnapshot.size, 3);
    assert.equal(participant.exists, true);
    assert.deepEqual(control.calls, []);
    assert.deepEqual(bucket.prefixDeletes, []);
    assert.deepEqual(bucket.fileDeletes, []);
  });

  test("unknown, invalid and unauthenticated callers get the contract errors", async () => {
    const control = fakeControl();
    const bucket = fakeBucket();
    await assert.rejects(
      executeDeleteClubSelf(
        request(OWNER, { clubId: `${P}missing` }),
        control,
        bucket,
      ),
      (error) => error?.code === "not-found",
    );
    await assert.rejects(
      executeDeleteClubSelf(
        request(OWNER, { clubId: "not/a/document-id" }),
        control,
        bucket,
      ),
      (error) => error?.code === "invalid-argument",
    );
    await assert.rejects(
      executeDeleteClubSelf({ auth: null, data: { clubId: CLUB } }, control, bucket),
      (error) => error?.code === "unauthenticated",
    );
    assert.deepEqual(control.calls, []);
  });

  test("a club whose lounge was never created (lazy ensureClubLounge) deletes cleanly", async () => {
    const control = fakeControl();
    const bucket = fakeBucket();
    await seedClub();

    const result = await executeDeleteClubSelf(
      request(OWNER, { clubId: CLUB }),
      control,
      bucket,
    );

    assert.deepEqual(result, { success: true, clubId: CLUB });
    assert.equal(await clubGraphIsGone(), true);
    // No room document exists, so there is no LiveKit room to end and no
    // room-media prefix to sweep; the club's own media is still cleaned.
    assert.deepEqual(control.calls, []);
    assert.deepEqual(bucket.prefixDeletes, []);
    assert.deepEqual(bucket.fileDeletes, [AVATAR_PATH]);
  });

  test("PINNED SEMANTICS: a half-failed deletion resumes on repeat; a completed one is not-found", async () => {
    const control = fakeControl();
    await seedClub();
    await seedLounge();
    await seedLoungeParticipant(MEMBER);

    // First attempt: Storage is down, so the sweep dies AFTER the marking
    // transaction. The club must stay marked and retryable, never wedged.
    await assert.rejects(
      executeDeleteClubSelf(
        request(OWNER, { clubId: CLUB }),
        control,
        fakeBucket({ failPrefixes: true }),
      ),
      (error) => error?.code === "unavailable",
    );
    const [markedClub, closedLounge, projection] = await Promise.all([
      db.collection("clubs").doc(CLUB).get(),
      db.collection("rooms").doc(LOUNGE).get(),
      db.collection("users").doc(OWNER).collection("clubs").doc(CLUB).get(),
    ]);
    assert.equal(markedClub.exists, true);
    assert.equal(markedClub.data().deletionInProgress, true);
    assert.equal(closedLounge.exists, true);
    assert.equal(closedLounge.data().status, "closed");
    assert.equal(closedLounge.data().isLive, false);
    assert.equal(closedLounge.data().participantCount, 0);
    assert.equal(closedLounge.data().deletionInProgress, true);
    // Projections are removed only after media cleanup succeeds, so the
    // membership index is still intact on the failed attempt.
    assert.equal(projection.exists, true);

    // Repeat call on the deletionInProgress club: SUCCEEDS and finishes.
    const retryBucket = fakeBucket();
    const result = await executeDeleteClubSelf(
      request(OWNER, { clubId: CLUB }),
      control,
      retryBucket,
    );
    assert.deepEqual(result, { success: true, clubId: CLUB });
    assert.equal(await clubGraphIsGone(), true);

    // After completion the club document no longer exists: not-found.
    await assert.rejects(
      executeDeleteClubSelf(request(OWNER, { clubId: CLUB }), control, fakeBucket()),
      (error) => error?.code === "not-found",
    );
  });

  test("a live lounge with participants is ended: LiveKit endRoom and session mirrors cleared", async () => {
    const control = fakeControl();
    const bucket = fakeBucket();
    await seedClub();
    await seedLounge({ isLive: true, participantCount: 2 });
    await seedLoungeParticipant(OWNER);
    await seedLoungeParticipant(MEMBER);
    await seedSession(OWNER);
    await seedSession(MEMBER);

    const result = await executeDeleteClubSelf(
      request(OWNER, { clubId: CLUB }),
      control,
      bucket,
    );

    assert.deepEqual(result, { success: true, clubId: CLUB });
    assert.deepEqual(control.calls, [["endRoom", LOUNGE]]);
    assert.equal(await clubGraphIsGone(), true);
    for (const uid of [OWNER, MEMBER]) {
      assert.equal(
        (
          await db
            .collection("activeVoiceSessions")
            .doc(uid)
            .collection("rooms")
            .doc(LOUNGE)
            .get()
        ).exists,
        false,
      );
    }
  });

  test("a moderated (suspended) club cannot be deleted by its owner", async () => {
    const control = fakeControl();
    const bucket = fakeBucket();
    await seedClub({ status: "suspended" });
    await seedLounge({ status: "suspended", isLive: false });

    await assert.rejects(
      executeDeleteClubSelf(request(OWNER, { clubId: CLUB }), control, bucket),
      (error) => error?.code === "failed-precondition",
    );
    const club = await db.collection("clubs").doc(CLUB).get();
    assert.equal(club.exists, true);
    assert.notEqual(club.data().deletionInProgress, true);
    assert.deepEqual(control.calls, []);
  });

  test("pending ownership transfer: the recipient deletes, the previous owner is refused", async () => {
    const control = fakeControl();
    const bucket = fakeBucket();
    await seedClub({
      ownershipVoiceResetPending: true,
      ownershipTransferredFrom: PREVIOUS,
    });
    await seedLounge();

    await assert.rejects(
      executeDeleteClubSelf(request(PREVIOUS, { clubId: CLUB }), control, bucket),
      (error) => error?.code === "permission-denied",
    );
    assert.equal((await db.collection("clubs").doc(CLUB).get()).exists, true);
    assert.deepEqual(control.calls, []);

    const result = await executeDeleteClubSelf(
      request(OWNER, { clubId: CLUB }),
      control,
      bucket,
    );
    assert.deepEqual(result, { success: true, clubId: CLUB });
    assert.equal(await clubGraphIsGone(), true);
  });

  test("a family club also sweeps the family moments media prefix", async () => {
    const control = fakeControl();
    const bucket = fakeBucket();
    await seedClub({ type: "family", privacy: "inviteOnly" });
    await seedLounge();

    const result = await executeDeleteClubSelf(
      request(OWNER, { clubId: CLUB }),
      control,
      bucket,
    );

    assert.deepEqual(result, { success: true, clubId: CLUB });
    assert.equal(await clubGraphIsGone(), true);
    assert.deepEqual(bucket.prefixDeletes, [
      `room_images/${LOUNGE}/`,
      `family_moments/${CLUB}/`,
    ]);
  });
});
