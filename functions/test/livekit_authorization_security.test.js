// Voice admission security: Firestore participant existence is not authority.

const assert = require("node:assert/strict");
const { test, beforeEach, describe } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  authorizeRoomVoiceAccess,
  buildParticipantMetadata,
  buildParticipantName,
  deriveVoiceGrant,
  recordAuthorizedVoiceSession,
  restrictionIsActive,
  VOICE_TOKEN_TTL,
} = require("../livekit/token");

const db = getFirestore();
const P = "lka-";
const UID = `${P}user`;
const HOST = `${P}host`;
const CLUB = `${P}club`;

function auth(uid = UID) {
  return { uid, token: {} };
}

async function recursiveDelete(reference) {
  if (typeof db.recursiveDelete === "function") {
    await db.recursiveDelete(reference);
  } else {
    await reference.delete();
  }
}

async function wipeOwn() {
  const [rooms, clubs] = await Promise.all([
    db.collection("rooms").get(),
    db.collection("clubs").get(),
  ]);
  await Promise.all([
    ...rooms.docs
      .filter((doc) => doc.id.startsWith(P))
      .map((doc) => recursiveDelete(doc.ref)),
    ...clubs.docs
      .filter((doc) => doc.id.startsWith(P))
      .map((doc) => recursiveDelete(doc.ref)),
    db.collection("users").doc(UID).delete(),
    db.collection("users").doc(HOST).delete(),
    db.collection("restrictions").doc(UID).delete(),
    recursiveDelete(db.collection("activeVoiceSessions").doc(UID)),
  ]);
}

async function seedRoom(
  roomId,
  { visibility = "public", clubId = null, status = "active", isLive = true } = {},
) {
  await db.collection("rooms").doc(roomId).set({
    hostId: HOST,
    visibility,
    status,
    isLive,
    ...(clubId ? { clubId, roomKind: "clubLounge" } : {}),
  });
}

async function seedParticipant(roomId, overrides = {}) {
  await db
    .collection("rooms")
    .doc(roomId)
    .collection("participants")
    .doc(UID)
    .set({
      userId: UID,
      role: "listener",
      isMuted: true,
      ...overrides,
    });
}

beforeEach(async () => {
  await wipeOwn();
  await db.collection("users").doc(UID).set({
    displayName: "Canonical profile",
    photoUrl: "https://example.com/canonical.png",
    banned: false,
  });
});

describe("authorizeRoomVoiceAccess", () => {
  test("allows an active public-room participant", async () => {
    const roomId = `${P}public`;
    await seedRoom(roomId);
    await seedParticipant(roomId);
    const result = await authorizeRoomVoiceAccess(roomId, auth());
    assert.equal(result.room.visibility, "public");
    assert.equal(result.participant.userId, UID);
  });

  test("denies a self-forged participant in a private room", async () => {
    const roomId = `${P}private-forged`;
    await seedRoom(roomId, { visibility: "private" });
    await seedParticipant(roomId);
    await assert.rejects(
      () => authorizeRoomVoiceAccess(roomId, auth()),
      (error) => error?.code === "permission-denied",
    );
  });

  test("allows an explicitly host-admitted private participant", async () => {
    const roomId = `${P}private-admitted`;
    await seedRoom(roomId, { visibility: "private" });
    await seedParticipant(roomId, { admittedBy: HOST });
    const result = await authorizeRoomVoiceAccess(roomId, auth());
    assert.equal(result.participant.admittedBy, HOST);
  });

  test("a forged Club Lounge participant is denied without membership", async () => {
    const roomId = `${P}club-forged`;
    await seedRoom(roomId, { visibility: "private", clubId: CLUB });
    await db.collection("clubs").doc(CLUB).set({ status: "active" });
    await seedParticipant(roomId);
    await assert.rejects(
      () => authorizeRoomVoiceAccess(roomId, auth()),
      (error) => error?.code === "permission-denied",
    );
  });

  test("an active canonical Club member may enter the lounge", async () => {
    const roomId = `${P}club-member`;
    await seedRoom(roomId, { visibility: "private", clubId: CLUB });
    await Promise.all([
      db.collection("clubs").doc(CLUB).set({ status: "active" }),
      db.collection("clubs").doc(CLUB).collection("members").doc(UID).set({
        userId: UID,
        role: "member",
        banned: false,
      }),
      seedParticipant(roomId),
    ]);
    const result = await authorizeRoomVoiceAccess(roomId, auth());
    assert.equal(result.room.clubId, CLUB);
  });

  test("suspended Club, banned member, and banned account all fail closed", async () => {
    const roomId = `${P}club-blocked`;
    await seedRoom(roomId, { visibility: "private", clubId: CLUB });
    await seedParticipant(roomId);
    const clubRef = db.collection("clubs").doc(CLUB);
    const memberRef = clubRef.collection("members").doc(UID);
    await Promise.all([
      clubRef.set({ status: "suspended" }),
      memberRef.set({ userId: UID, role: "member", banned: false }),
    ]);
    await assert.rejects(
      () => authorizeRoomVoiceAccess(roomId, auth()),
      (error) => error?.code === "permission-denied",
    );

    await clubRef.set({ status: "active" });
    await memberRef.update({ banned: true });
    await assert.rejects(
      () => authorizeRoomVoiceAccess(roomId, auth()),
      (error) => error?.code === "permission-denied",
    );

    await memberRef.update({ banned: false });
    await db.collection("users").doc(UID).set({ banned: true });
    await assert.rejects(
      () => authorizeRoomVoiceAccess(roomId, auth()),
      (error) => error?.code === "permission-denied",
    );
  });

  test("missing or disabled canonical account state fails closed", async () => {
    const roomId = `${P}account-state`;
    await seedRoom(roomId);
    await seedParticipant(roomId);
    await db.collection("users").doc(UID).delete();
    await assert.rejects(
      () => authorizeRoomVoiceAccess(roomId, auth()),
      (error) => error?.code === "permission-denied",
    );

    await db.collection("users").doc(UID).set({ disabled: true });
    await assert.rejects(
      () => authorizeRoomVoiceAccess(roomId, auth()),
      (error) => error?.code === "permission-denied",
    );
  });

  test("every non-active or missing Club status fails closed", async () => {
    const roomId = `${P}club-status`;
    await seedRoom(roomId, { visibility: "private", clubId: CLUB });
    await seedParticipant(roomId);
    await db.collection("clubs").doc(CLUB).collection("members").doc(UID).set({
      userId: UID,
      role: "member",
      banned: false,
    });
    for (const status of [undefined, "archived", "quarantined", "deleted"]) {
      await db.collection("clubs").doc(CLUB).set(
        status == null ? {} : { status },
      );
      await assert.rejects(
        () => authorizeRoomVoiceAccess(roomId, auth()),
        (error) => error?.code === "permission-denied",
      );
    }
    await db.collection("clubs").doc(CLUB).set({
      status: "active",
      deletionInProgress: true,
    });
    await assert.rejects(
      () => authorizeRoomVoiceAccess(roomId, auth()),
      (error) => error?.code === "permission-denied",
    );
  });

  test("ended or suspended rooms cannot issue voice access", async () => {
    const roomId = `${P}ended`;
    await seedRoom(roomId, { isLive: false });
    await seedParticipant(roomId);
    await assert.rejects(
      () => authorizeRoomVoiceAccess(roomId, auth()),
      (error) => error?.code === "failed-precondition",
    );
  });

  test("document-path input cannot escape the rooms collection", async () => {
    await assert.rejects(
      () => authorizeRoomVoiceAccess("../users/victim", auth()),
      (error) => error?.code === "invalid-argument",
    );
  });

  test("communication mute is derived from live server restriction state", async () => {
    const roomId = `${P}muted`;
    await seedRoom(roomId);
    await seedParticipant(roomId);
    await db.collection("restrictions").doc(UID).set({
      type: "communicationMute",
      expiresAt: null,
    });
    const result = await authorizeRoomVoiceAccess(roomId, auth());
    assert.equal(result.communicationMuted, true);

    assert.equal(
      restrictionIsActive({
        type: "communicationMute",
        expiresAt: new Date(Date.now() - 1000),
      }),
      false,
    );
  });

  test("participant name ignores client input and uses canonical identity", () => {
    assert.equal(
      buildParticipantName(
        { displayName: "Roster name" },
        { displayName: "Canonical profile" },
        { uid: UID, token: { name: "Token name" } },
      ),
      "Canonical profile",
    );
    assert.equal(VOICE_TOKEN_TTL, "5m");
    assert.deepEqual(
      JSON.parse(buildParticipantMetadata(
        {
          role: "speaker",
          displayName: "Forged roster name",
          photoUrl: "https://evil.example/forged.png",
        },
        {
          displayName: "Canonical profile",
          photoUrl: "https://example.com/canonical.png",
        },
        auth(),
      )),
      {
        uid: UID,
        role: "speaker",
        username: "Canonical profile",
        photoUrl: "https://example.com/canonical.png",
      },
    );
  });

  test("final authority transaction writes a canonical session mirror", async () => {
    const roomId = `${P}session-mirror`;
    await seedRoom(roomId);
    await seedParticipant(roomId);
    const expectedGrant = deriveVoiceGrant(
      await authorizeRoomVoiceAccess(roomId, auth()),
      auth(),
    );
    const expiresAt = Timestamp.fromMillis(Date.now() + 300_000);
    await recordAuthorizedVoiceSession({
      roomId,
      authenticatedUser: auth(),
      expectedGrant,
      expiresAt,
    });
    const session = await db.collection("activeVoiceSessions").doc(UID)
      .collection("rooms").doc(roomId).get();
    assert.equal(session.data().userId, UID);
    assert.equal(session.data().roomId, roomId);
    assert.equal(session.data().participantIdentity, UID);
    assert.equal(session.data().expiresAt.toMillis(), expiresAt.toMillis());
  });

  test("final authority transaction rejects a stale pre-signed grant", async () => {
    const roomId = `${P}session-race`;
    await seedRoom(roomId);
    await seedParticipant(roomId);
    const staleGrant = deriveVoiceGrant(
      await authorizeRoomVoiceAccess(roomId, auth()),
      auth(),
    );
    await db.collection("rooms").doc(roomId)
      .collection("participants").doc(UID).update({
        role: "speaker",
        isMuted: false,
      });
    await assert.rejects(
      recordAuthorizedVoiceSession({
        roomId,
        authenticatedUser: auth(),
        expectedGrant: staleGrant,
        expiresAt: Timestamp.fromMillis(Date.now() + 300_000),
      }),
      (error) => error?.code === "aborted",
    );
    assert.equal(
      (await db.collection("activeVoiceSessions").doc(UID)
        .collection("rooms").doc(roomId).get()).exists,
      false,
    );
  });
});
