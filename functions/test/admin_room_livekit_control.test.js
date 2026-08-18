// LiveKit enforcement for administrative room actions.
//
// Firestore is updated first to block new token issuance. The callable must
// still fail visibly when LiveKit cannot revoke an already-issued session,
// while preserving that secure Firestore state so a retry can converge.
//
//   firebase emulators:start --only firestore --project yovoice-fn-test
//   npm test

const assert = require("node:assert/strict");
const { test, beforeEach, afterEach, describe } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  LiveKitControlError,
  createLiveKitControl,
} = require("../livekit/control");
const {
  setRoomModerationStatus,
  forceEndRoom,
  removeRoomParticipant,
  setParticipantMute,
  adminDeleteRoom,
  setRoomLiveKitControlForTests,
  setRoomStorageBucketForTests,
} = require("../admin/rooms");
const { setProtectedOwnerUidForTests } = require("../utils/roles");

const db = getFirestore();
const run = (callable) => callable.run ?? callable;

const P = "room-lkc-";
const OWNER = `${P}owner`;
const SUPERMOD = `${P}supermod`;
const MOD = `${P}mod`;
const SPEAKER = `${P}speaker`;
const ROOM = `${P}room`;

function request(uid, role, data) {
  return { auth: { uid, token: { role } }, data };
}

async function expectCode(promise, code) {
  await assert.rejects(promise, (error) => {
    assert.equal(error.code, code, `expected ${code}, got ${error.code}`);
    return true;
  });
}

async function seedRoom() {
  const roomReference = db.collection("rooms").doc(ROOM);
  await Promise.all([
    db.collection("users").doc(OWNER).set({ role: "superAdmin" }),
    db.collection("users").doc(SUPERMOD).set({ role: "superModerator" }),
    db.collection("users").doc(MOD).set({ role: "moderator" }),
    roomReference.set({
      name: "Control plane room",
      hostId: OWNER,
      visibility: "public",
      status: "active",
      isLive: true,
      participantCount: 1,
      updatedAt: Timestamp.now(),
    }),
    roomReference.collection("participants").doc(SPEAKER).set({
      userId: SPEAKER,
      displayName: "Speaker",
      role: "speaker",
      isMuted: false,
    }),
    db.collection("activeVoiceSessions").doc(SPEAKER)
      .collection("rooms").doc(ROOM).set({
        userId: SPEAKER,
        roomId: ROOM,
        participantIdentity: SPEAKER,
        expiresAt: Timestamp.fromMillis(Date.now() + 300_000),
      }),
  ]);
}

async function wipe() {
  const roomReference = db.collection("rooms").doc(ROOM);
  const participants = await roomReference.collection("participants").get();
  await Promise.all([
    ...participants.docs.map((document) => document.ref.delete()),
    roomReference.delete(),
    db.collection("users").doc(OWNER).delete(),
    db.collection("users").doc(SUPERMOD).delete(),
    db.collection("users").doc(MOD).delete(),
    db.collection("restrictions").doc(SPEAKER).delete(),
    db.collection("activeVoiceSessions").doc(SPEAKER)
      .collection("rooms").doc(ROOM).delete(),
  ]);

  const audit = await db.collection("adminAuditLogs").get();
  await Promise.all(
    audit.docs
      .filter((document) => {
        const data = document.data() ?? {};
        return data.targetId === ROOM ||
          String(data.actorId ?? "").startsWith(P);
      })
      .map((document) => document.ref.delete()),
  );
}

beforeEach(async () => {
  setProtectedOwnerUidForTests(OWNER);
  setRoomLiveKitControlForTests(null);
  setRoomStorageBucketForTests({
    name: "yovoice-test.firebasestorage.app",
    async deleteFiles() {},
  });
  await wipe();
  await seedRoom();
});

afterEach(() => {
  setProtectedOwnerUidForTests(null);
  setRoomLiveKitControlForTests(null);
  setRoomStorageBucketForTests(null);
});

describe("LiveKit control helper", () => {
  test("every admin voice mutation binds both LiveKit secrets", () => {
    for (const callable of [
      setRoomModerationStatus,
      forceEndRoom,
      removeRoomParticipant,
      setParticipantMute,
      adminDeleteRoom,
    ]) {
      const keys = (callable.__endpoint?.secretEnvironmentVariables ?? [])
        .map((secret) => secret.key);
      assert.ok(keys.includes("LIVEKIT_API_KEY"));
      assert.ok(keys.includes("LIVEKIT_API_SECRET"));
    }
  });

  test("participant removal retries once and carries token revocation time",
    async () => {
      const calls = [];
      const client = {
        async removeParticipant(roomId, identity, options) {
          calls.push({ roomId, identity, options });
          if (calls.length === 1) throw Object.assign(new Error("retry"), {
            code: "unavailable",
          });
        },
      };
      const control = createLiveKitControl({
        client,
        sleep: async () => {},
        now: () => 10_000,
      });

      const result = await control.revokeParticipant("room", "user");
      assert.equal(result.attempts, 2);
      assert.equal(calls.length, 2);
      assert.equal(calls[0].options.revokeTokenTs, 11n);
    });

  test("not-found is idempotent success, while persistent failure is typed",
    async () => {
      const absent = createLiveKitControl({
        client: {
          async removeParticipant() {
            throw Object.assign(new Error("gone"), {
              status: 404,
              code: "not_found",
            });
          },
        },
        sleep: async () => {},
      });
      const absentResult = await absent.revokeParticipant("room", "user");
      assert.equal(absentResult.alreadyAbsent, true);

      const failed = createLiveKitControl({
        client: {
          async removeParticipant() {
            throw Object.assign(new Error("down"), { code: "unavailable" });
          },
        },
        sleep: async () => {},
      });
      await assert.rejects(
        () => failed.revokeParticipant("room", "user"),
        (error) => error instanceof LiveKitControlError &&
          error.operation === "removeParticipant",
      );
    });

  test("permission changes preserve every unrelated LiveKit permission",
    async () => {
      let update;
      const control = createLiveKitControl({
        client: {
          async getParticipant() {
            return {
              permission: {
                canSubscribe: true,
                canPublishData: true,
                hidden: false,
              },
            };
          },
          async updateParticipant(roomId, identity, options) {
            update = { roomId, identity, options };
            return {};
          },
        },
        sleep: async () => {},
      });

      await control.setParticipantPermissions("room", "user", {
        canPublish: false,
        canPublishData: false,
      });
      assert.deepEqual(update, {
        roomId: "room",
        identity: "user",
        options: {
          permission: {
            canSubscribe: true,
            hidden: false,
            canPublish: false,
            canPublishData: false,
          },
        },
      });
    });

  test("identity discovery scans active LiveKit rooms and fails closed",
    async () => {
      const control = createLiveKitControl({
        client: {
          async listRooms() {
            return [{ name: "one" }, { name: "two" }];
          },
          async getParticipant(roomId) {
            if (roomId === "two") {
              throw Object.assign(new Error("absent"), {
                status: 404,
                code: "not_found",
              });
            }
            return { identity: "user" };
          },
        },
        sleep: async () => {},
      });
      assert.deepEqual(await control.findParticipantRooms("user"), ["one"]);

      const failed = createLiveKitControl({
        client: {
          async listRooms() {
            throw Object.assign(new Error("down"), { code: "unavailable" });
          },
        },
        sleep: async () => {},
      });
      await assert.rejects(
        () => failed.findParticipantRooms("user"),
        (error) => error instanceof LiveKitControlError &&
          error.operation === "listRooms",
      );

      let lookups = 0;
      const bounded = createLiveKitControl({
        client: {
          async listRooms() {
            return [{ name: "one" }, { name: "two" }];
          },
          async getParticipant() {
            lookups += 1;
            return { identity: "user" };
          },
        },
        maxRoomScan: 1,
        sleep: async () => {},
      });
      await assert.rejects(
        () => bounded.findParticipantRooms("user"),
        (error) => error instanceof LiveKitControlError &&
          error.operation === "participantRoomScanBound" &&
          error.cause.code === "resource_exhausted",
      );
      assert.equal(lookups, 0, "an oversized legacy scan fails before fan-out");
    });

  test("room deletion is attempted even if one token revocation fails",
    async () => {
      let deleted = 0;
      const control = createLiveKitControl({
        client: {
          async listParticipants() {
            return [{ identity: "a" }, { identity: "b" }];
          },
          async removeParticipant(_room, identity) {
            if (identity === "a") {
              throw Object.assign(new Error("down"), { code: "unavailable" });
            }
          },
          async deleteRoom() {
            deleted += 1;
          },
        },
        sleep: async () => {},
      });

      await assert.rejects(
        () => control.endRoom("room"),
        (error) => error instanceof LiveKitControlError,
      );
      assert.equal(deleted, 1, "deleteRoom must still stop the active room");
    });
});

describe("callable convergence", () => {
  test("force-end keeps Firestore closed on LiveKit failure, then retries",
    async () => {
      let attempts = 0;
      setRoomLiveKitControlForTests({
        async endRoom() {
          attempts += 1;
          throw new Error("LiveKit unavailable");
        },
      });

      await assert.rejects(
        () => run(forceEndRoom)(request(SUPERMOD, "superModerator", {
          roomId: ROOM,
          reason: "credible threat",
        })),
        (error) => {
          assert.equal(error.code, "unavailable");
          assert.equal(error.details.stateApplied, true);
          assert.equal(error.details.liveKitApplied, false);
          return true;
        },
      );

      const secured = await db.collection("rooms").doc(ROOM).get();
      assert.equal(secured.data().isLive, false);
      assert.equal(secured.data().participantCount, 0);
      assert.equal(
        (await secured.ref.collection("participants").doc(SPEAKER).get()).exists,
        true,
        "cleanup waits so a retry can still identify durable participants",
      );
      assert.equal(
        (await db.collection("activeVoiceSessions").doc(SPEAKER)
          .collection("rooms").doc(ROOM).get()).exists,
        true,
        "the session mirror remains retryable until LiveKit is stopped",
      );

      setRoomLiveKitControlForTests({
        async endRoom() {
          attempts += 1;
          return {};
        },
      });
      const result = await run(forceEndRoom)(
        request(SUPERMOD, "superModerator", {
          roomId: ROOM,
          reason: "credible threat",
        }),
      );
      assert.equal(result.success, true);
      assert.equal(attempts, 2);
      assert.equal(
        (await secured.ref.collection("participants").doc(SPEAKER).get()).exists,
        false,
      );
      assert.equal(
        (await db.collection("activeVoiceSessions").doc(SPEAKER)
          .collection("rooms").doc(ROOM).get()).exists,
        false,
      );
    });

  test("participant removal remains retryable after its Firestore row is gone",
    async () => {
      let revocations = 0;
      setRoomLiveKitControlForTests({
        async revokeParticipant() {
          revocations += 1;
          throw new Error("LiveKit unavailable");
        },
      });

      await expectCode(
        run(removeRoomParticipant)(request(MOD, "moderator", {
          roomId: ROOM,
          userId: SPEAKER,
          reason: "abuse",
        })),
        "unavailable",
      );
      const room = await db.collection("rooms").doc(ROOM).get();
      assert.equal(room.data().participantCount, 0);
      assert.equal(
        (await room.ref.collection("participants").doc(SPEAKER).get()).exists,
        false,
      );
      assert.equal(
        (await db.collection("activeVoiceSessions").doc(SPEAKER)
          .collection("rooms").doc(ROOM).get()).exists,
        false,
        "roster removal and its session mirror are one transaction",
      );

      setRoomLiveKitControlForTests({
        async revokeParticipant() {
          revocations += 1;
          return {};
        },
      });
      const retried = await run(removeRoomParticipant)(
        request(MOD, "moderator", {
          roomId: ROOM,
          userId: SPEAKER,
          reason: "abuse",
        }),
      );
      assert.equal(retried.alreadyRemoved, true);
      assert.equal(revocations, 2);
      assert.equal((await room.ref.get()).data().participantCount, 0);
    });

  test("mute persists denial before LiveKit and unmute restores speakers only",
    async () => {
      const decisions = [];
      setRoomLiveKitControlForTests({
        async setPublishingAllowed(_roomId, _userId, canPublish) {
          decisions.push(canPublish);
          throw new Error("LiveKit unavailable");
        },
      });
      await expectCode(
        run(setParticipantMute)(request(MOD, "moderator", {
          roomId: ROOM,
          userId: SPEAKER,
          muted: true,
        })),
        "unavailable",
      );
      const participant = db
        .collection("rooms")
        .doc(ROOM)
        .collection("participants")
        .doc(SPEAKER);
      const mutedState = (await participant.get()).data();
      assert.equal(mutedState.serverMuted, true);
      assert.equal(mutedState.isMuted, false, "self mute state must survive");
      assert.deepEqual(decisions, [false]);

      setRoomLiveKitControlForTests({
        async setPublishingAllowed(_roomId, _userId, canPublish) {
          decisions.push(canPublish);
          return {};
        },
      });
      const result = await run(setParticipantMute)(
        request(MOD, "moderator", {
          roomId: ROOM,
          userId: SPEAKER,
          muted: false,
        }),
      );
      assert.equal(result.success, true);
      assert.deepEqual(decisions, [false, true]);
      const unmutedState = (await participant.get()).data();
      assert.equal(unmutedState.serverMuted, false);
      assert.equal(unmutedState.isMuted, false);
    });

  test("staff unmute never overrides the participant's own mute",
    async () => {
      const participant = db
        .collection("rooms")
        .doc(ROOM)
        .collection("participants")
        .doc(SPEAKER);
      await participant.set({ isMuted: true, serverMuted: true }, { merge: true });

      let canPublish;
      setRoomLiveKitControlForTests({
        async setPublishingAllowed(_roomId, _userId, allowed) {
          canPublish = allowed;
          return {};
        },
      });
      await run(setParticipantMute)(request(MOD, "moderator", {
        roomId: ROOM,
        userId: SPEAKER,
        muted: false,
      }));

      const data = (await participant.get()).data();
      assert.equal(data.serverMuted, false);
      assert.equal(data.isMuted, true);
      assert.equal(canPublish, false);
    });

  test("staff unmute cannot bypass host or platform communication mutes",
    async () => {
      const participant = db
        .collection("rooms")
        .doc(ROOM)
        .collection("participants")
        .doc(SPEAKER);
      const restriction = db.collection("restrictions").doc(SPEAKER);
      await Promise.all([
        participant.set({
          isMuted: false,
          hostMuted: true,
          serverMuted: true,
        }, { merge: true }),
        restriction.set({
          type: "communicationMute",
          expiresAt: Timestamp.fromMillis(Date.now() + 60_000),
        }),
      ]);

      const decisions = [];
      setRoomLiveKitControlForTests({
        async setPublishingAllowed(_roomId, _userId, allowed) {
          decisions.push(allowed);
          return {};
        },
      });
      await run(setParticipantMute)(request(MOD, "moderator", {
        roomId: ROOM,
        userId: SPEAKER,
        muted: false,
      }));

      const data = (await participant.get()).data();
      assert.equal(data.serverMuted, false);
      assert.equal(data.hostMuted, true);
      assert.equal(data.isMuted, false);
      assert.deepEqual(decisions, [false]);

      await Promise.all([
        participant.set({ hostMuted: false, serverMuted: true }, { merge: true }),
        restriction.set({
          type: "communicationMute",
          expiresAt: Timestamp.fromMillis(Date.now() - 60_000),
        }),
      ]);
      await run(setParticipantMute)(request(MOD, "moderator", {
        roomId: ROOM,
        userId: SPEAKER,
        muted: false,
      }));
      assert.deepEqual(decisions, [false, true]);
    });

  test("staff unmute cannot restore publishing in a closed room", async () => {
    const room = db.collection("rooms").doc(ROOM);
    const participant = room.collection("participants").doc(SPEAKER);
    await Promise.all([
      room.set({ isLive: false, status: "suspended" }, { merge: true }),
      participant.set({
        isMuted: false,
        hostMuted: false,
        serverMuted: true,
      }, { merge: true }),
    ]);

    let canPublish;
    setRoomLiveKitControlForTests({
      async setPublishingAllowed(_roomId, _userId, allowed) {
        canPublish = allowed;
        return {};
      },
    });
    await run(setParticipantMute)(request(MOD, "moderator", {
      roomId: ROOM,
      userId: SPEAKER,
      muted: false,
    }));
    assert.equal(canPublish, false);
    assert.equal((await participant.get()).data().serverMuted, false);
  });

  test("mute cannot recreate a participant that already left", async () => {
    const participant = db
      .collection("rooms")
      .doc(ROOM)
      .collection("participants")
      .doc(SPEAKER);
    await participant.delete();
    setRoomLiveKitControlForTests({
      async setPublishingAllowed() {
        throw new Error("must not reach LiveKit");
      },
    });

    await expectCode(
      run(setParticipantMute)(request(MOD, "moderator", {
        roomId: ROOM,
        userId: SPEAKER,
        muted: true,
      })),
      "not-found",
    );
    assert.equal((await participant.get()).exists, false);
  });

  test("the Flutter quarantined status aliases to a real suspension",
    async () => {
      let ended = 0;
      setRoomLiveKitControlForTests({
        async endRoom() {
          ended += 1;
          return {};
        },
      });
      const result = await run(setRoomModerationStatus)(
        request(SUPERMOD, "superModerator", {
          roomId: ROOM,
          status: "quarantined",
          reason: "investigation",
        }),
      );
      assert.equal(result.status, "suspended");
      assert.equal((await db.collection("rooms").doc(ROOM).get()).data().status,
        "suspended");
      assert.equal(ended, 1);
    });

  test("permanent delete leaves a tombstone on control failure and converges",
    async () => {
      setRoomLiveKitControlForTests({
        async endRoom() {
          throw new Error("LiveKit unavailable");
        },
      });
      const data = {
        roomId: ROOM,
        reason: "owner deletion",
        confirmation: ROOM,
      };
      await expectCode(
        run(adminDeleteRoom)(request(OWNER, "superAdmin", data)),
        "unavailable",
      );
      const tombstone = await db.collection("rooms").doc(ROOM).get();
      assert.equal(tombstone.exists, true);
      assert.equal(tombstone.data().status, "deleted");
      assert.equal(tombstone.data().isLive, false);
      assert.equal(
        (await db.collection("activeVoiceSessions").doc(SPEAKER)
          .collection("rooms").doc(ROOM).get()).exists,
        true,
      );

      await expectCode(
        run(setRoomModerationStatus)(request(SUPERMOD, "superModerator", {
          roomId: ROOM,
          status: "active",
        })),
        "failed-precondition",
      );
      assert.equal((await tombstone.ref.get()).data().status, "deleted");

      setRoomLiveKitControlForTests({
        async endRoom() {
          return {};
        },
      });
      setRoomStorageBucketForTests({
        name: "yovoice-test.firebasestorage.app",
        async deleteFiles() {
          const error = new Error("Storage unavailable");
          error.code = "storage-unavailable";
          throw error;
        },
      });
      await expectCode(
        run(adminDeleteRoom)(request(OWNER, "superAdmin", data)),
        "unavailable",
      );
      assert.equal((await tombstone.ref.get()).exists, true);

      const storageCalls = [];
      setRoomStorageBucketForTests({
        name: "yovoice-test.firebasestorage.app",
        async deleteFiles(options) {
          storageCalls.push(options);
        },
      });
      const result = await run(adminDeleteRoom)(
        request(OWNER, "superAdmin", data),
      );
      assert.equal(result.success, true);
      assert.deepEqual(storageCalls, [
        { prefix: `room_images/${ROOM}/`, force: true },
      ]);
      assert.equal((await tombstone.ref.get()).exists, false);
      assert.equal(
        (await db.collection("activeVoiceSessions").doc(SPEAKER)
          .collection("rooms").doc(ROOM).get()).exists,
        false,
      );
      assert.equal(
        (await db.collection("adminAuditLogs")
          .doc(`delete_room_${ROOM}`).get()).exists,
        true,
      );
    });

  test("global deletion allows a super moderator and refuses a regular "
      + "moderator", async () => {
    const data = {
      roomId: ROOM,
      reason: "confirmed policy violation",
      confirmation: ROOM,
    };
    await expectCode(
      run(adminDeleteRoom)(request(MOD, "moderator", data)),
      "permission-denied",
    );
    assert.equal((await db.collection("rooms").doc(ROOM).get()).exists, true);

    setRoomLiveKitControlForTests({
      async endRoom() {
        return {};
      },
    });
    setRoomStorageBucketForTests({
      name: "yovoice-test.firebasestorage.app",
      async deleteFiles() {},
    });
    const result = await run(adminDeleteRoom)(
      request(SUPERMOD, "superModerator", data),
    );
    assert.equal(result.success, true);
    assert.equal((await db.collection("rooms").doc(ROOM).get()).exists, false);
  });
});
