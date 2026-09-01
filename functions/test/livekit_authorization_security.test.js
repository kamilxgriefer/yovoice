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
  createLiveKitTokenHandler,
  deriveVoiceGrant,
  recordAuthorizedVoiceSession,
  restrictionIsActive,
  VOICE_TOKEN_ATTEMPT_LIMIT,
  VOICE_TOKEN_RATE_LIMIT,
  VOICE_TOKEN_TTL,
  voiceTokenAttemptRateReference,
} = require("../livekit/token");

const db = getFirestore();
const P = "lka-";
const UID = `${P}user`;
const HOST = `${P}host`;
const CLUB = `${P}club`;

function auth(uid = UID) {
  return { uid, token: {} };
}

function callable(data, uid = UID) {
  return { auth: auth(uid), data };
}

function tokenHarness() {
  const state = { constructed: 0, signed: 0, grants: [] };
  class FakeAccessToken {
    constructor() {
      state.constructed += 1;
    }

    addGrant(grant) {
      state.grants.push(grant);
    }

    async toJwt() {
      state.signed += 1;
      return `room-test-jwt-${state.signed}`;
    }
  }
  return { state, AccessTokenClass: FakeAccessToken };
}

function tokenOptions(harness, nowMs = Date.UTC(2026, 8, 1, 10, 0, 0)) {
  return {
    AccessTokenClass: harness.AccessTokenClass,
    apiKey: () => "test-key",
    apiSecret: () => "test-secret-long-enough",
    serverUrl: () => "wss://rtc.example.test",
    clock: () => nowMs,
  };
}

async function recursiveDelete(reference) {
  if (typeof db.recursiveDelete === "function") {
    await db.recursiveDelete(reference);
  } else {
    await reference.delete();
  }
}

async function wipeOwn() {
  const [rooms, clubs, operationLedgers, rateLimits] = await Promise.all([
    db.collection("rooms").get(),
    db.collection("clubs").get(),
    db.collection("integrityOperationLedgers").where("ownerId", "==", UID).get(),
    db.collection("privateRateLimits").where("ownerId", "==", UID).get(),
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
    ...operationLedgers.docs.map((document) => document.ref.delete()),
    ...rateLimits.docs.map((document) => document.ref.delete()),
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

  test("a Club guest cannot enter voice even with a participant row", async () => {
    const roomId = `${P}club-guest`;
    await seedRoom(roomId, { visibility: "private", clubId: CLUB });
    await Promise.all([
      db.collection("clubs").doc(CLUB).set({ status: "active" }),
      db.collection("clubs").doc(CLUB).collection("members").doc(UID).set({
        userId: UID,
        role: "guest",
        banned: false,
      }),
      seedParticipant(roomId),
    ]);
    await assert.rejects(
      () => authorizeRoomVoiceAccess(roomId, auth()),
      (error) => error?.code === "permission-denied",
    );
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

  test("100 random missing-room token retries stop at N before JWT", async () => {
    const roomId = `${P}missing-cost-target`;
    const harness = tokenHarness();
    const options = tokenOptions(harness);
    const limit = VOICE_TOKEN_ATTEMPT_LIMIT.maxEvents;
    for (let index = 0; index < 100; index += 1) {
      await assert.rejects(
        createLiveKitTokenHandler(callable({ roomId }), options),
        (error) => index < limit
          ? error?.code === "not-found"
          : error?.code === "resource-exhausted",
      );
    }
    assert.equal(harness.state.constructed, 0);
    assert.equal(harness.state.signed, 0);
    assert.equal(
      (await voiceTokenAttemptRateReference(UID).get()).data().count,
      limit,
    );

    // Even after the target becomes valid, the next attempt is refused by
    // the committed actor bucket and cannot reach participant/profile reads
    // or the injected JWT constructor.
    await seedRoom(roomId);
    await seedParticipant(roomId);
    await assert.rejects(
      createLiveKitTokenHandler(callable({ roomId }), options),
      (error) => error?.code === "resource-exhausted",
    );
    assert.equal(harness.state.constructed, 0);
  });

  test("private-room denials consume the same actor-wide token budget", async () => {
    const roomId = `${P}private-cost-target`;
    await seedRoom(roomId, { visibility: "private" });
    await seedParticipant(roomId);
    const harness = tokenHarness();
    const options = tokenOptions(harness);
    const limit = VOICE_TOKEN_ATTEMPT_LIMIT.maxEvents;
    for (let index = 0; index < limit; index += 1) {
      await assert.rejects(
        createLiveKitTokenHandler(callable({ roomId }), options),
        (error) => error?.code === "permission-denied",
      );
    }
    await db.doc(`rooms/${roomId}/participants/${UID}`).update({
      admittedBy: HOST,
    });
    for (let index = limit; index < 100; index += 1) {
      await assert.rejects(
        createLiveKitTokenHandler(callable({ roomId }), options),
        (error) => error?.code === "resource-exhausted",
      );
    }
    assert.equal(harness.state.constructed, 0);
    assert.equal(harness.state.signed, 0);
  });

  test("completed room-token requestId replay is free and signs once", async () => {
    const roomId = `${P}token-replay`;
    await seedRoom(roomId);
    await seedParticipant(roomId);
    const harness = tokenHarness();
    const options = tokenOptions(harness);
    const tokenRequest = callable({
      roomId,
      requestId: "room-token-replay-0001",
    });
    const first = await createLiveKitTokenHandler(tokenRequest, options);
    const replay = await createLiveKitTokenHandler(tokenRequest, options);
    assert.deepEqual(replay, first);
    assert.equal(harness.state.constructed, 1);
    assert.equal(harness.state.signed, 1);
    assert.equal(
      (await voiceTokenAttemptRateReference(UID).get()).data().count,
      1,
    );
    const conflictingToken = () => createLiveKitTokenHandler(callable({
        roomId: `${P}different-room`,
        requestId: "room-token-replay-0001",
      }), options);
    await assert.rejects(
      conflictingToken,
      (error) => error?.code === "already-exists",
    );
    const limit = VOICE_TOKEN_ATTEMPT_LIMIT.maxEvents;
    assert.equal(
      (await voiceTokenAttemptRateReference(UID).get()).data().count,
      2,
    );
    for (let charged = 2; charged < limit; charged += 1) {
      await assert.rejects(
        conflictingToken,
        (error) => error?.code === "already-exists",
      );
      assert.equal(
        (await voiceTokenAttemptRateReference(UID).get()).data().count,
        charged + 1,
      );
    }
    await assert.rejects(
      conflictingToken,
      (error) => error?.code === "resource-exhausted",
    );
    assert.equal(
      (await voiceTokenAttemptRateReference(UID).get()).data().count,
      limit,
    );
    assert.equal(harness.state.signed, 1);
    const session = await db.doc(
      `activeVoiceSessions/${UID}/rooms/${roomId}`,
    ).get();
    assert.equal(session.data().tokenIssueCount, 1);
  });

  test("concurrent room-token retries converge on one ledger result", async () => {
    const roomId = `${P}token-race`;
    await seedRoom(roomId);
    await seedParticipant(roomId);
    const harness = tokenHarness();
    const options = tokenOptions(harness);
    const tokenRequest = callable({
      roomId,
      requestId: "room-token-race-0001",
    });
    const responses = await Promise.all([
      createLiveKitTokenHandler(tokenRequest, options),
      createLiveKitTokenHandler(tokenRequest, options),
    ]);
    assert.deepEqual(responses[1], responses[0]);
    assert.ok(harness.state.signed >= 1 && harness.state.signed <= 2);
    const charged = (await voiceTokenAttemptRateReference(UID).get()).data().count;
    assert.ok(charged >= 1 && charged <= 2);
    const session = await db.doc(
      `activeVoiceSessions/${UID}/rooms/${roomId}`,
    ).get();
    assert.equal(session.data().tokenIssueCount, 1);
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
        photoUrl: null,
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

  test("voice token issuance is transactionally rate limited per room and user", async () => {
    const roomId = `${P}token-rate-limit`;
    await seedRoom(roomId);
    await seedParticipant(roomId);
    const expectedGrant = deriveVoiceGrant(
      await authorizeRoomVoiceAccess(roomId, auth()),
      auth(),
    );
    const nowMs = Date.UTC(2026, 7, 31, 12, 0, 0);
    for (let index = 0; index < VOICE_TOKEN_RATE_LIMIT; index += 1) {
      await recordAuthorizedVoiceSession({
        roomId,
        authenticatedUser: auth(),
        expectedGrant,
        expiresAt: Timestamp.fromMillis(nowMs + 300_000),
        nowMs,
      });
    }
    await assert.rejects(
      recordAuthorizedVoiceSession({
        roomId,
        authenticatedUser: auth(),
        expectedGrant,
        expiresAt: Timestamp.fromMillis(nowMs + 300_000),
        nowMs,
      }),
      (error) => error?.code === "resource-exhausted",
    );

    const session = await db.collection("activeVoiceSessions").doc(UID)
      .collection("rooms").doc(roomId).get();
    assert.equal(session.data().tokenIssueCount, VOICE_TOKEN_RATE_LIMIT);
  });
});

// THE MICROPHONE PERMISSION ITSELF. Until 2026-08-20 nothing here exercised
// `deriveVoiceGrant`'s publish decision, which is how a defect this visible
// reached production: muting yourself revoked `canPublish`, the client read
// the missing permission as "you are audience", replaced the mute toggle with
// a Listening label — and left no control to unmute with. The flag persisted
// in Firestore, so re-entering the room reproduced it from the fresh token.
describe("publish permission", () => {
  const actor = { uid: `${P}speaker-uid` };

  function grantFor({
    role = "listener",
    experience = "community",
    hostId = `${P}someone-else`,
    isMuted = false,
    hostMuted = false,
    serverMuted = false,
    communicationMuted = false,
  } = {}) {
    return deriveVoiceGrant(
      {
        room: { hostId, experience },
        participant: {
          userId: actor.uid,
          displayName: "Speaker",
          role,
          isMuted,
          hostMuted,
          serverMuted,
        },
        profile: { displayName: "Speaker" },
        communicationMuted,
      },
      actor,
    );
  }

  test("muting YOURSELF never costs you the right to speak again", () => {
    assert.equal(grantFor({ isMuted: true }).permissions.canPublish, true);
    assert.equal(
      grantFor({ role: "host", hostId: actor.uid, isMuted: true })
        .permissions.canPublish,
      true,
      "a host who muted themselves must still be able to unmute",
    );
  });

  test("a moderator mute, a server mute and a sanction all DO revoke it", () => {
    assert.equal(grantFor({ hostMuted: true }).permissions.canPublish, false);
    assert.equal(grantFor({ serverMuted: true }).permissions.canPublish, false);
    assert.equal(
      grantFor({ communicationMuted: true }).permissions.canPublish,
      false,
    );
  });

  test("a moderator mute outranks the participant's own unmuted state", () => {
    assert.equal(
      grantFor({ isMuted: false, hostMuted: true }).permissions.canPublish,
      false,
    );
  });

  // Self-service joins are pinned to `role: 'listener'` by firestore.rules,
  // so gating publish on the role alone made every non-host in a Family or
  // Community room a permanent audience member.
  test("in a community room a plain listener may speak", () => {
    assert.equal(grantFor({ role: "listener" }).permissions.canPublish, true);
  });

  test("a room with NO experience field is a community room", () => {
    const grant = deriveVoiceGrant(
      {
        room: { hostId: `${P}other` },
        participant: { userId: actor.uid, displayName: "S", role: "listener" },
        profile: { displayName: "S" },
        communicationMuted: false,
      },
      actor,
    );
    assert.equal(
      grant.permissions.canPublish,
      true,
      "27 of 45 production rooms carry no experience field",
    );
  });

  test("a BROADCAST room still has an audience that must be promoted", () => {
    assert.equal(
      grantFor({ role: "listener", experience: "broadcast" })
        .permissions.canPublish,
      false,
    );
    assert.equal(
      grantFor({ role: "listener", experience: "podcast" })
        .permissions.canPublish,
      false,
      "the legacy 'podcast' value is a broadcast room",
    );
    assert.equal(
      grantFor({ role: "speaker", experience: "broadcast" })
        .permissions.canPublish,
      true,
      "a promoted speaker publishes",
    );
    assert.equal(
      grantFor({ role: "host", hostId: actor.uid, experience: "broadcast" })
        .permissions.canPublish,
      true,
    );
  });

  test("canSubscribe is never taken away — a muted person still hears the room", () => {
    assert.equal(grantFor({ hostMuted: true }).permissions.canSubscribe, true);
    assert.equal(
      grantFor({ communicationMuted: true }).permissions.canSubscribe,
      true,
    );
  });
});
