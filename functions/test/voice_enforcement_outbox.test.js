// Durable voice enforcement for bans and platform communication mutes.
// The sanction is committed atomically with an outbox event; the retrying
// trigger must revoke the identity from every Firestore/LiveKit session and
// must never mark a partially failed pass as completed.

const assert = require("node:assert/strict");
const { test, beforeEach, afterEach, describe } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST =
  process.env.FIREBASE_AUTH_EMULATOR_HOST ?? "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");

if (getApps().length === 0) initializeApp();

const { applySanction } = require("../staff/sanctions");
const { setUserBan } = require("../admin/users");
const {
  EVENT_COLLECTION,
  EVENT_TYPES,
  executeVoiceEnforcementEvent,
  onModerationVoiceEnforcementCreated,
} = require("../staff/voice_enforcement");
const { setProtectedOwnerUidForTests } = require("../utils/roles");

const db = getFirestore();
const adminAuth = getAuth();
const run = (callable) => callable.run ?? callable;

const P = "voice-outbox-";
const OWNER = `${P}owner`;
const MOD = `${P}moderator`;
const TARGET = `${P}target`;
const ROOM_A = `${P}room-a`;
const ROOM_B = `${P}room-b`;
const INDEXED_ROOM = `${P}indexed-room`;
const GHOST_ROOM = `${P}ghost-livekit-room`;

function request(uid, role, data, token = {}) {
  return {
    auth: {
      uid,
      token: {
        role,
        auth_time: Math.floor(Date.now() / 1000),
        ...token,
      },
    },
    data,
  };
}

async function deleteAuthUser(uid) {
  try {
    await adminAuth.deleteUser(uid);
  } catch (error) {
    if (error?.code !== "auth/user-not-found") throw error;
  }
}

async function wipe() {
  const events = await db
    .collection(EVENT_COLLECTION)
    .where("targetUid", "==", TARGET)
    .get();
  const audits = await db
    .collection("adminAuditLogs")
    .where("targetId", "==", TARGET)
    .get();
  await Promise.all([
    ...events.docs.map((document) => document.ref.delete()),
    ...audits.docs.map((document) => document.ref.delete()),
    db.collection("restrictions").doc(TARGET).delete(),
    db.collection("users").doc(TARGET).delete(),
    db.collection("users").doc(MOD).delete(),
    db.collection("users").doc(OWNER).delete(),
    db.collection("rooms").doc(ROOM_A)
      .collection("participants").doc(TARGET).delete(),
    db.collection("rooms").doc(ROOM_B)
      .collection("participants").doc(TARGET).delete(),
    db.collection("rooms").doc(ROOM_A).delete(),
    db.collection("rooms").doc(ROOM_B).delete(),
    db.collection("activeVoiceSessions").doc(TARGET)
      .collection("rooms").doc(INDEXED_ROOM).delete(),
    deleteAuthUser(TARGET),
  ]);
}

async function seed() {
  await Promise.all([
    db.collection("users").doc(OWNER).set({ role: "superAdmin" }),
    db.collection("users").doc(MOD).set({ role: "moderator" }),
    db.collection("users").doc(TARGET).set({ role: "user" }),
    db.collection("rooms").doc(ROOM_A).set({
      status: "active",
      isLive: true,
    }),
    db.collection("rooms").doc(ROOM_B).set({
      status: "active",
      isLive: true,
    }),
    db.collection("rooms").doc(ROOM_A)
      .collection("participants").doc(TARGET).set({ userId: TARGET }),
    db.collection("rooms").doc(ROOM_B)
      .collection("participants").doc(TARGET).set({ userId: TARGET }),
  ]);
}

async function onlyEvent() {
  const snapshot = await db
    .collection(EVENT_COLLECTION)
    .where("targetUid", "==", TARGET)
    .get();
  assert.equal(snapshot.size, 1);
  return snapshot.docs[0];
}

beforeEach(async () => {
  setProtectedOwnerUidForTests(OWNER);
  await wipe();
  await seed();
});

afterEach(() => setProtectedOwnerUidForTests(null));

describe("voice enforcement outbox", () => {
  test("the Firestore trigger retries and binds LiveKit credentials", () => {
    assert.equal(
      onModerationVoiceEnforcementCreated.__endpoint.eventTrigger.retry,
      true,
    );
    const secrets =
      onModerationVoiceEnforcementCreated.__endpoint
        .secretEnvironmentVariables.map((secret) => secret.key);
    assert.ok(secrets.includes("LIVEKIT_API_KEY"));
    assert.ok(secrets.includes("LIVEKIT_API_SECRET"));
  });

  test("communication mute atomically queues revocation and retries all rooms",
    async () => {
      const result = await run(applySanction)(request(MOD, "moderator", {
        action: "communicationMute",
        uid: TARGET,
        reason: "credible platform abuse",
        durationHours: 1,
      }));
      assert.equal(result.outcome, "muted");
      assert.equal(result.voiceEnforcement.status, "queued");

      const [restriction, eventDocument] = await Promise.all([
        db.collection("restrictions").doc(TARGET).get(),
        onlyEvent(),
      ]);
      assert.equal(restriction.data().type, "communicationMute");
      assert.equal(eventDocument.data().type, EVENT_TYPES.COMMUNICATION_MUTE);
      assert.equal(eventDocument.id, result.voiceEnforcement.eventId);
      assert.equal(
        restriction.data().voiceEnforcementEventId,
        eventDocument.id,
      );

      await db.collection("activeVoiceSessions").doc(TARGET)
        .collection("rooms").doc(INDEXED_ROOM).set({
          userId: TARGET,
          roomId: INDEXED_ROOM,
          participantIdentity: TARGET,
        });

      const firstCalls = [];
      let failedOnce = false;
      const firstControl = {
        async findParticipantRooms(identity) {
          assert.equal(identity, TARGET);
          // GHOST_ROOM deliberately has no Firestore participant row: active
          // LiveKit discovery must still close that self-delete bypass.
          return [ROOM_B, GHOST_ROOM];
        },
        async revokeParticipant(roomId, identity) {
          firstCalls.push([roomId, identity]);
          if (roomId === ROOM_B && !failedOnce) {
            failedOnce = true;
            throw Object.assign(new Error("controlled outage"), {
              code: "unavailable",
            });
          }
        },
      };
      await assert.rejects(
        () => executeVoiceEnforcementEvent(eventDocument, firstControl),
        /controlled outage/,
      );
      assert.deepEqual(
        new Set(firstCalls.map(([roomId]) => roomId)),
        new Set([ROOM_A, ROOM_B, INDEXED_ROOM, GHOST_ROOM]),
      );
      const retrying = (await eventDocument.ref.get()).data();
      assert.equal(retrying.status, "retrying");
      assert.equal(retrying.attemptCount, 1);
      assert.equal(retrying.roomsDiscovered, 4);
      assert.equal(retrying.roomsRevoked, 3);
      assert.equal(
        (await db.collection("activeVoiceSessions").doc(TARGET)
          .collection("rooms").doc(INDEXED_ROOM).get()).exists,
        false,
        "a successfully revoked session must not leave an active mirror",
      );

      const retryCalls = [];
      const retryControl = {
        async findParticipantRooms() {
          return [GHOST_ROOM];
        },
        async revokeParticipant(roomId, identity) {
          retryCalls.push([roomId, identity]);
        },
      };
      const completed = await executeVoiceEnforcementEvent(
        eventDocument,
        retryControl,
      );
      assert.equal(completed.completed, true);
      assert.equal(
        completed.roomsDiscovered,
        3,
        "the cleaned index-only session must not be rediscovered",
      );
      assert.deepEqual(
        new Set(retryCalls.map(([roomId]) => roomId)),
        new Set([ROOM_A, ROOM_B, GHOST_ROOM]),
        "the retry must not rediscover a cleaned index-only session",
      );
      const finalEvent = (await eventDocument.ref.get()).data();
      assert.equal(finalEvent.status, "completed");
      assert.equal(finalEvent.attemptCount, 2);
      assert.equal(finalEvent.lastErrorCode, null);

      let replayCalls = 0;
      const replay = await executeVoiceEnforcementEvent(eventDocument, {
        async findParticipantRooms() {
          replayCalls += 1;
          return [];
        },
        async revokeParticipant() {
          replayCalls += 1;
        },
      });
      assert.equal(replay.skipped, true);
      assert.equal(replayCalls, 0, "completed events are idempotent");
    });

  test("a ban commits server state and a queued full-session revocation",
    async () => {
      await adminAuth.createUser({
        uid: TARGET,
        email: `${TARGET}@test.invalid`,
      });

      const result = await run(setUserBan)(request(MOD, "moderator", {
        uid: TARGET,
        banned: true,
        durationHours: 1,
        reason: "active account takeover",
      }));
      assert.equal(result.banned, true);
      assert.equal(result.voiceEnforcement.status, "queued");

      const [profile, authUser, eventDocument] = await Promise.all([
        db.collection("users").doc(TARGET).get(),
        adminAuth.getUser(TARGET),
        onlyEvent(),
      ]);
      assert.equal(profile.data().banned, true);
      assert.equal(profile.data().banEnforcementEventId, eventDocument.id);
      assert.equal(authUser.disabled, true);
      assert.equal(eventDocument.data().type, EVENT_TYPES.BAN);
      assert.equal(eventDocument.id, result.voiceEnforcement.eventId);
      assert.equal(eventDocument.data().status, "pending");
    });

  test("a lifted mute supersedes its queued event without revoking",
    async () => {
      await db.collection("users").doc(MOD).set({ role: "superModerator" });
      await run(applySanction)(request(MOD, "superModerator", {
        action: "communicationMute",
        uid: TARGET,
        reason: "temporary investigation",
        durationHours: 1,
      }));
      const eventDocument = await onlyEvent();

      await run(applySanction)(request(MOD, "superModerator", {
        action: "liftMute",
        uid: TARGET,
        reason: "investigation cleared",
      }));

      let controlCalls = 0;
      const outcome = await executeVoiceEnforcementEvent(eventDocument, {
        async findParticipantRooms() {
          controlCalls += 1;
          return [];
        },
        async revokeParticipant() {
          controlCalls += 1;
        },
      });
      assert.deepEqual(outcome, { skipped: true, reason: "superseded" });
      assert.equal(controlCalls, 0);
      assert.equal((await eventDocument.ref.get()).data().status, "superseded");
    });
});
