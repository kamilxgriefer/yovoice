const fs = require("fs");
const path = require("path");
const assert = require("node:assert/strict");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
const {
  addDoc,
  doc,
  getDoc,
  getDocs,
  deleteDoc,
  deleteField,
  collection,
  collectionGroup,
  documentId,
  query,
  where,
  setDoc,
  updateDoc,
  writeBatch,
  runTransaction,
  serverTimestamp,
  Timestamp,
  orderBy,
  limit,
} = require("firebase/firestore");

const RULES_PATH = path.resolve(__dirname, "../firestore.rules");

// The emulator's default port is 8080 and firebase.json still declares it, but
// a developer machine frequently already has something on it — including a
// long-running emulator started for the app. Hardcoding the port made the
// suite unrunnable in that situation, which is the wrong failure for the one
// gate that stands between a rule change and production. Set
// FIRESTORE_EMULATOR_PORT to match `emulators:start --only firestore
// --project demo-yovoice` on any other port.
const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_ADDRESS ?? "127.0.0.1";
const EMULATOR_PORT = Number(process.env.FIRESTORE_EMULATOR_PORT ?? 8080);
if (!Number.isInteger(EMULATOR_PORT) || EMULATOR_PORT <= 0) {
  throw new Error(
    `FIRESTORE_EMULATOR_PORT is not a port: ${process.env.FIRESTORE_EMULATOR_PORT}`,
  );
}

let passed = 0;
let failed = 0;

async function check(name, fn) {
  try {
    await fn();
    passed += 1;
    console.log(`  OK  ${name}`);
  } catch (error) {
    failed += 1;
    console.log(`FAIL  ${name}`);
    console.log(`      ${error.message.split("\n")[0]}`);
  }
}

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: "demo-yovoice",
    firestore: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      host: EMULATOR_HOST,
      port: EMULATOR_PORT,
    },
  });

  // email_verified: true on every regular test context — isVerified()
  // gates most create rules now, and these contexts stand in for normal,
  // already-onboarded users throughout the rest of this file. The
  // dedicated `unverified` context further down is what actually
  // exercises the gate itself.
  // The suite seeds documents as it goes and was only deterministic on a
  // brand-new emulator; running it twice against the same instance made
  // unrelated cases fail on leftover state (blocked pairs, existing
  // conversations). Clearing up front makes every run start identical.
  await testEnv.clearFirestore();

  const host = testEnv.authenticatedContext("host-uid", {
    email_verified: true,
  });
  const attacker = testEnv.authenticatedContext("attacker-uid", {
    email_verified: true,
  });
  const invitee = testEnv.authenticatedContext("invitee-uid", {
    email_verified: true,
  });
  const unverified = testEnv.authenticatedContext("unverified-uid", {
    email_verified: false,
  });

  // These are established app accounts. Communication rules intentionally
  // require the authoritative profile so a server-side ban takes effect even
  // while an old Firebase Auth token is still valid. Dedicated bootstrap
  // cases below use separate fresh identities.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await Promise.all([
      setDoc(doc(db, "users/host-uid"), {
        displayName: "Host",
        banned: false,
      }),
      setDoc(doc(db, "users/attacker-uid"), {
        displayName: "Attacker",
        banned: false,
      }),
      setDoc(doc(db, "users/invitee-uid"), {
        displayName: "Invitee",
        banned: false,
      }),
      setDoc(doc(db, "users/unverified-uid"), {
        displayName: "Unverified",
        banned: false,
      }),
    ]);
  });

  // --- Room creation + host's own participant doc (batch/getAfter path) ---
  function createHostRoomBatch(
    db,
    roomId,
    {
      hostName = "Host",
      participantName = "Host",
      imageUrl = undefined,
    } = {},
  ) {
    const batch = writeBatch(db);
    const room = {
      hostId: "host-uid",
      hostName,
      name: "Test room",
      description: "",
      category: "talk",
      visibility: "public",
      language: "English",
      maxParticipants: 25,
      participantCount: 1,
      memberCount: 0,
      isLive: true,
      roomType: "temporary",
      status: "active",
      approvalRequired: false,
      slowModeSeconds: 0,
      autoMuteNewUsers: true,
      membersCanStartVoice: false,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    };
    if (imageUrl !== undefined) room.imageUrl = imageUrl;
    batch.set(doc(db, `rooms/${roomId}`), room);
    batch.set(doc(db, `rooms/${roomId}/participants/host-uid`), {
      userId: "host-uid",
      displayName: participantName,
      photoUrl: null,
      role: "host",
      isMuted: false,
      isSpeaker: true,
      isHandRaised: false,
      joinedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    return batch;
  }

  await check(
    "SECURITY: room root and initial participant cannot use Auth or arbitrary display names",
    async () => {
      const db = host.firestore();
      await assertFails(
        createHostRoomBatch(db, "forged-root-name", {
          hostName: "Bypass Auth Name",
        }).commit(),
      );
      await assertFails(
        createHostRoomBatch(db, "forged-host-participant", {
          participantName: "Arbitrary Participant Name",
        }).commit(),
      );
    },
  );

  const managedRoomCover = (roomId, bucket =
    "yovoice-ec54a.firebasestorage.app") =>
    `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/` +
    `room_images%2F${roomId}%2Fhost-uid_123.jpg?alt=media&token=test`;
  const managedClubAvatar = (ownerId, clubId, bucket =
    "yovoice-ec54a.firebasestorage.app") =>
    `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/` +
    `clubs%2F${ownerId}%2F${clubId}%2Favatar` +
    "?alt=media&generation=123&token=test";

  await check(
    "SECURITY ROOMS: create rejects malformed, oversized and external cover pointers",
    async () => {
      const db = host.firestore();
      for (const [roomId, imageUrl] of [
        ["cover-object-create", {}],
        ["cover-external-create", "https://tracker.example/cover.jpg"],
        ["cover-oversized-create", `https://${"a".repeat(2050)}`],
        [
          "cover-sibling-create",
          managedRoomCover("different-room"),
        ],
      ]) {
        await assertFails(
          createHostRoomBatch(db, roomId, { imageUrl }).commit(),
        );
      }
      await assertFails(
        createHostRoomBatch(db, ".*", {
          imageUrl: managedRoomCover("victim-room"),
        }).commit(),
      );
    },
  );

  await check(
    "SECURITY ROOMS: create is pointerless until server cover finalization",
    async () => {
      const db = host.firestore();
      await assertFails(
        createHostRoomBatch(db, "managed-cover-create", {
          imageUrl: managedRoomCover("managed-cover-create"),
        }).commit(),
      );
      await assertFails(
        createHostRoomBatch(db, "legacy-cover-create", {
          imageUrl: managedRoomCover(
            "legacy-cover-create",
            "yovoice-ec54a.appspot.com",
          ).replace(".jpg", ".png"),
        }).commit(),
      );
      await assertFails(
        createHostRoomBatch(db, "pointerless-cover-create", {
          imageUrl: null,
        }).commit(),
      );
    },
  );

  await check(
    "SECURITY ROOMS: upload reservations, leases and byte budgets are server-only",
    async () => {
      const db = host.firestore();
      for (const path of [
        `roomCoverUploadReservations/${"a".repeat(40)}`,
        "roomCoverUploadLeases/host-uid",
        "roomCoverUploadBudgets/host-uid_2030-01-01",
      ]) {
        const reference = doc(db, path);
        await assertFails(getDoc(reference));
        await assertFails(setDoc(reference, { ownerId: "host-uid" }));
      }
    },
  );

  await check(
    "SECURITY: ordinary room creation is callable-only, even with canonical roster",
    async () => {
      const db = host.firestore();
      await assertFails(createHostRoomBatch(db, "room1").commit());
    },
  );

  // seed the room as an already-existing document for the rest of the tests
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "rooms/room1"), {
      hostId: "host-uid",
      hostName: "Host",
      name: "Test room",
      description: "",
      category: "talk",
      visibility: "public",
      language: "English",
      maxParticipants: 25,
      participantCount: 1,
      memberCount: 0,
      isLive: true,
      roomType: "temporary",
      status: "active",
      approvalRequired: false,
      slowModeSeconds: 0,
      autoMuteNewUsers: true,
      membersCanStartVoice: false,
    });
  });

  await check(
    "SECURITY: a self-joining participant cannot forge displayName",
    async () => {
      const db = attacker.firestore();
      const batch = writeBatch(db);
      batch.set(doc(db, "rooms/room1/participants/attacker-uid"), {
        userId: "attacker-uid",
        displayName: "Bypass Auth Name",
        photoUrl: null,
        role: "speaker",
        isMuted: false,
        isSpeaker: true,
        isHandRaised: false,
        joinedAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
      batch.update(doc(db, "rooms/room1"), {
        participantCount: 2,
        updatedAt: serverTimestamp(),
      });
      await assertFails(batch.commit());
    },
  );

  await check(
    "non-host joins a Community room as a normal speaker",
    async () => {
      const db = attacker.firestore();
      const ref = doc(db, "rooms/room1/participants/attacker-uid");
      const batch = writeBatch(db);
      batch.set(ref, {
        userId: "attacker-uid",
        displayName: "Attacker",
        photoUrl: null,
        role: "speaker",
        isMuted: false,
        isSpeaker: true,
        isHandRaised: false,
        joinedAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
      batch.update(doc(db, "rooms/room1"), {
        participantCount: 2,
        updatedAt: serverTimestamp(),
      });
      await assertSucceeds(
        batch.commit(),
      );
    },
  );

  await check(
    "Broadcast keeps self-service joins in the listener audience",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "rooms/broadcast-join"), {
          hostId: "host-uid",
          hostName: "Host",
          name: "Broadcast",
          description: "",
          category: "talk",
          visibility: "public",
          language: "English",
          maxParticipants: 25,
          participantCount: 0,
          memberCount: 0,
          isLive: true,
          roomType: "temporary",
          experience: "broadcast",
          status: "active",
          approvalRequired: false,
          slowModeSeconds: 0,
          autoMuteNewUsers: true,
          membersCanStartVoice: false,
        });
      });
      const db = attacker.firestore();
      const batch = writeBatch(db);
      batch.set(
        doc(db, "rooms/broadcast-join/participants/attacker-uid"),
        {
          userId: "attacker-uid",
          displayName: "Attacker",
          photoUrl: null,
          role: "listener",
          isMuted: true,
          isSpeaker: false,
          isHandRaised: false,
          joinedAt: serverTimestamp(),
          updatedAt: serverTimestamp(),
        },
      );
      batch.update(doc(db, "rooms/broadcast-join"), {
        participantCount: 1,
        updatedAt: serverTimestamp(),
      });
      await assertSucceeds(batch.commit());
    },
  );

  await check("REGRESSION CHECK: non-host cannot self-create as host", async () => {
    const db = attacker.firestore();
    const ref = doc(db, "rooms/room1/participants/attacker-uid-2");
    await assertFails(
      setDoc(ref, {
        userId: "attacker-uid",
        displayName: "Attacker",
        role: "host",
        isMuted: false,
        isSpeaker: true,
        isHandRaised: false,
      }),
    );
  });

  await check("SECURITY: non-host cannot self-promote to speaker via update", async () => {
    const db = attacker.firestore();
    const ref = doc(db, "rooms/room1/participants/attacker-uid");
    await assertFails(updateDoc(ref, { role: "speaker", isSpeaker: true }));
  });

  await check("regression: participant can mute/unmute themselves", async () => {
    const db = attacker.firestore();
    const ref = doc(db, "rooms/room1/participants/attacker-uid");
    await assertSucceeds(
      updateDoc(ref, { isMuted: false, updatedAt: serverTimestamp() }),
    );
  });

  await check("SECURITY: a Community speaker cannot forge a stage request", async () => {
    const db = attacker.firestore();
    const ref = doc(db, "rooms/room1/participants/attacker-uid");
    await assertFails(
      updateDoc(ref, { isHandRaised: true, updatedAt: serverTimestamp() }),
    );
  });

  await check("regression: a podcast listener can request the stage", async () => {
    const db = attacker.firestore();
    const ref = doc(
      db,
      "rooms/broadcast-join/participants/attacker-uid",
    );
    await assertSucceeds(
      updateDoc(ref, { isHandRaised: true, updatedAt: serverTimestamp() }),
    );
  });

  await check(
    "PODCAST SECURITY: a listener can lower a request after the host closes the queue",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await updateDoc(doc(ctx.firestore(), "rooms/broadcast-join"), {
          handRaisingEnabled: false,
        });
      });
      const db = attacker.firestore();
      const ref = doc(
        db,
        "rooms/broadcast-join/participants/attacker-uid",
      );
      await assertSucceeds(
        updateDoc(ref, {
          isHandRaised: false,
          updatedAt: serverTimestamp(),
        }),
      );
      await assertFails(
        updateDoc(ref, {
          isHandRaised: true,
          updatedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check("SECURITY: host moderation bypasses direct writes and uses callable", async () => {
    const db = host.firestore();
    const ref = doc(db, "rooms/room1/participants/attacker-uid");
    await assertFails(
      updateDoc(ref, { hostMuted: true, updatedAt: serverTimestamp() }),
    );
  });

  await check("SECURITY: non-host cannot hijack the room (rename it)", async () => {
    const db = attacker.firestore();
    const ref = doc(db, "rooms/room1");
    await assertFails(updateDoc(ref, { name: "Hijacked room" }));
  });

  await check("SECURITY: non-host cannot reassign hostId to themselves", async () => {
    const db = attacker.firestore();
    const ref = doc(db, "rooms/room1");
    await assertFails(updateDoc(ref, { hostId: "attacker-uid" }));
  });

  await check(
    "SECURITY: host cannot reassign hostId either (must go through a function)",
    async () => {
      const db = host.firestore();
      const ref = doc(db, "rooms/room1");
      await assertFails(updateDoc(ref, { hostId: "someone-else" }));
    },
  );

  await check("SECURITY: a participant cannot bump participantCount without a join", async () => {
    const db = attacker.firestore();
    const ref = doc(db, "rooms/room1");
    await assertFails(updateDoc(ref, { participantCount: 3 }));
  });

  await check("regression: host can update room name/description/etc", async () => {
    const db = host.firestore();
    const ref = doc(db, "rooms/room1");
    await assertSucceeds(
      updateDoc(ref, {
        name: "Renamed by host",
        updatedAt: serverTimestamp(),
      }),
    );
  });

  await check(
    "SECURITY ROOMS: host update cannot poison public imageUrl",
    async () => {
      const ref = doc(host.firestore(), "rooms/room1");
      for (const imageUrl of [
        {},
        "https://tracker.example/cover.jpg",
        `https://${"a".repeat(2050)}`,
        managedRoomCover("different-room"),
        managedRoomCover("room1").replace(
          "room_images%2F",
          "room_images%2F..%2F",
        ),
      ]) {
        await assertFails(
          updateDoc(ref, { imageUrl, updatedAt: serverTimestamp() }),
        );
      }
      await assertFails(
        updateDoc(ref, {
          imageUrl: managedRoomCover("room1"),
          updatedAt: serverTimestamp(),
        }),
      );
      await assertFails(
        updateDoc(ref, {
          visibility: "private",
          updatedAt: serverTimestamp(),
        }),
      );
      await assertFails(
        createHostRoomBatch(host.firestore(), "[a-z]+").commit(),
      );
      await assertFails(
        updateDoc(doc(host.firestore(), "rooms/[a-z]+"), {
          imageUrl: managedRoomCover("victim-room"),
          updatedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "ROOMS: Club Lounge rejects denormalized cover URLs",
    async () => {
      const clubId = "cover-club";
      const roomId = `club_lounge_${clubId}`;
      const avatarUrl = managedClubAvatar("host-uid", clubId);
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, `clubs/${clubId}`), {
          ownerId: "host-uid",
          name: "Cover Club",
          type: "community",
          status: "active",
          avatarUrl,
          loungeRoomId: roomId,
        });
        await setDoc(doc(db, `rooms/${roomId}`), {
          hostId: "host-uid",
          hostName: "Host",
          name: "Cover Club Lounge",
          description: "Private voice lounge for Cover Club members.",
          category: "club",
          visibility: "private",
          language: "English",
          maxParticipants: null,
          participantCount: 0,
          memberCount: 1,
          isLive: false,
          roomType: "community",
          status: "active",
          imageUrl: null,
          approvalRequired: false,
          slowModeSeconds: 0,
          autoMuteNewUsers: false,
          membersCanStartVoice: true,
          experience: "community",
          clubId,
          roomKind: "clubLounge",
          createdAt: new Date(),
          updatedAt: new Date(),
        });
      });

      const ref = doc(host.firestore(), `rooms/${roomId}`);
      await assertFails(
        updateDoc(ref, { imageUrl: avatarUrl, updatedAt: serverTimestamp() }),
      );
      for (const imageUrl of [
        managedClubAvatar("victim-owner", "victim-club"),
        managedClubAvatar("different-owner", clubId),
      ]) {
        await assertFails(
          updateDoc(ref, { imageUrl, updatedAt: serverTimestamp() }),
        );
      }
      await assertFails(
        updateDoc(doc(host.firestore(), "rooms/room1"), {
          imageUrl: avatarUrl,
          updatedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "SECURITY ROOMS: a private-room participant row cannot be self-forged",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "rooms/private-voice"), {
          hostId: "host-uid",
          hostName: "Host",
          name: "Private voice",
          description: "",
          category: "talk",
          visibility: "private",
          language: "English",
          maxParticipants: 25,
          participantCount: 0,
          memberCount: 0,
          isLive: true,
          roomType: "temporary",
          status: "active",
          approvalRequired: false,
          slowModeSeconds: 0,
          autoMuteNewUsers: true,
          membersCanStartVoice: false,
        });
      });
      const db = attacker.firestore();
      const participant = doc(
        db,
        "rooms/private-voice/participants/attacker-uid",
      );
      await assertFails(
        setDoc(participant, {
          userId: "attacker-uid",
          displayName: "Attacker",
          role: "listener",
          isMuted: true,
          isSpeaker: false,
          isHandRaised: false,
        }),
      );

      const batch = writeBatch(db);
      batch.set(participant, {
        userId: "attacker-uid",
        displayName: "Attacker",
        role: "listener",
        isMuted: true,
        isSpeaker: false,
        isHandRaised: false,
        joinedAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
      batch.update(doc(db, "rooms/private-voice"), {
        participantCount: 1,
        updatedAt: serverTimestamp(),
      });
      await assertFails(batch.commit());
    },
  );

  await check(
    "ROOMS: a host can explicitly admit a private-room participant",
    async () => {
      await assertFails(
        setDoc(
          doc(host.firestore(), "rooms/private-voice/participants/invitee-uid"),
          {
            userId: "invitee-uid",
            displayName: "Arbitrary Invitee Name",
            role: "speaker",
            isMuted: true,
            isSpeaker: true,
            isHandRaised: false,
            admittedBy: "host-uid",
            updatedAt: serverTimestamp(),
          },
        ),
      );
      await assertSucceeds(
        setDoc(
          doc(host.firestore(), "rooms/private-voice/participants/invitee-uid"),
          {
            userId: "invitee-uid",
            displayName: "Invitee",
            role: "speaker",
            isMuted: true,
            isSpeaker: true,
            isHandRaised: false,
            admittedBy: "host-uid",
            updatedAt: serverTimestamp(),
          },
        ),
      );
      await assertSucceeds(
        getDoc(doc(invitee.firestore(), "rooms/private-voice")),
      );
      await assertFails(
        getDoc(doc(attacker.firestore(), "rooms/private-voice")),
      );
    },
  );

  await check(
    "SECURITY ROOMS: Club Lounge join requires active canonical membership",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, "clubs/voice-access-club"), {
          ownerId: "host-uid",
          status: "active",
          type: "community",
        });
        await setDoc(
          doc(db, "clubs/voice-access-club/members/invitee-uid"),
          { userId: "invitee-uid", role: "member", banned: false },
        );
        await setDoc(doc(db, "rooms/club-lounge-security"), {
          hostId: "host-uid",
          hostName: "Host",
          name: "Club Lounge",
          description: "",
          category: "club",
          visibility: "private",
          language: "English",
          maxParticipants: null,
          participantCount: 0,
          memberCount: 1,
          isLive: true,
          roomType: "community",
          status: "active",
          approvalRequired: false,
          slowModeSeconds: 0,
          autoMuteNewUsers: false,
          membersCanStartVoice: true,
          clubId: "voice-access-club",
          roomKind: "clubLounge",
        });
      });

      function loungeJoinBatch(db, uid, displayName) {
        const batch = writeBatch(db);
        batch.set(
          doc(db, `rooms/club-lounge-security/participants/${uid}`),
          {
            userId: uid,
            displayName,
            photoUrl: null,
            role: "speaker",
            isMuted: false,
            isSpeaker: true,
            isHandRaised: false,
            joinedAt: serverTimestamp(),
            updatedAt: serverTimestamp(),
          },
        );
        batch.update(doc(db, "rooms/club-lounge-security"), {
          participantCount: 1,
          updatedAt: serverTimestamp(),
        });
        return batch;
      }

      await assertFails(
        loungeJoinBatch(
          attacker.firestore(),
          "attacker-uid",
          "Attacker",
        ).commit(),
      );
      await assertSucceeds(
        loungeJoinBatch(
          invitee.firestore(),
          "invitee-uid",
          "Invitee",
        ).commit(),
      );
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await updateDoc(doc(ctx.firestore(), "clubs/voice-access-club"), {
          deletionInProgress: true,
        });
      });
      await assertFails(
        getDoc(doc(invitee.firestore(), "rooms/club-lounge-security")),
      );
    },
  );

  await check(
    "SECURITY ROOMS: participant leave is callable-only, even with a counter batch",
    async () => {
      const db = attacker.firestore();
      const batch = writeBatch(db);
      batch.delete(doc(db, "rooms/room1/participants/attacker-uid"));
      batch.update(doc(db, "rooms/room1"), {
        participantCount: 1,
        updatedAt: serverTimestamp(),
      });
      await assertFails(batch.commit());
    },
  );

  await check(
    "SECURITY VOICE: active session mirrors are invisible and server-only",
    async () => {
      const path = "activeVoiceSessions/attacker-uid/rooms/room1";
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), path), {
          userId: "attacker-uid",
          roomId: "room1",
          participantIdentity: "attacker-uid",
          expiresAt: Timestamp.fromMillis(Date.now() + 300000),
        });
      });
      const reference = doc(attacker.firestore(), path);
      await assertFails(getDoc(reference));
      await assertFails(updateDoc(reference, { roomId: "other-room" }));
      await assertFails(deleteDoc(reference));
      await assertFails(
        setDoc(
          doc(host.firestore(), "activeVoiceSessions/host-uid/rooms/room1"),
          {
            userId: "host-uid",
            roomId: "room1",
            participantIdentity: "host-uid",
          },
        ),
      );
    },
  );

  await check(
    "ROOMS: watchOwnedRooms can list the host's private rooms only",
    async () => {
      await assertSucceeds(
        getDocs(
          query(
            collection(host.firestore(), "rooms"),
            where("hostId", "==", "host-uid"),
          ),
        ),
      );
      await assertFails(
        getDocs(
          query(
            collection(attacker.firestore(), "rooms"),
            where("hostId", "==", "host-uid"),
          ),
        ),
      );
    },
  );

  await check(
    "SECURITY ROOMS: self-join cannot forge host admission or authority fields",
    async () => {
      const db = attacker.firestore();
      const participant = doc(db, "rooms/room1/participants/attacker-uid");
      const batch = writeBatch(db);
      batch.set(participant, {
        userId: "attacker-uid",
        displayName: "Attacker",
        photoUrl: null,
        role: "listener",
        isMuted: true,
        isSpeaker: false,
        isHandRaised: false,
        admittedBy: "host-uid",
        joinedAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
      batch.update(doc(db, "rooms/room1"), {
        participantCount: 2,
        updatedAt: serverTimestamp(),
      });
      await assertFails(batch.commit());
    },
  );

  await check(
    "SECURITY ROOMS: self update cannot clear host/staff moderation mute",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), "rooms/room1/participants/attacker-uid"),
          {
            userId: "attacker-uid",
            role: "speaker",
            isMuted: true,
            isSpeaker: true,
            isHandRaised: false,
            hostMuted: true,
            serverMuted: true,
          },
        );
      });
      await assertFails(
        updateDoc(
          doc(
            attacker.firestore(),
            "rooms/room1/participants/attacker-uid",
          ),
          {
            isMuted: false,
            hostMuted: false,
            serverMuted: false,
            updatedAt: serverTimestamp(),
          },
        ),
      );
    },
  );

  await check(
    "SECURITY ROOMS: host cannot restore moderation status or close outside callable",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "rooms/moderated-room"), {
          hostId: "host-uid",
          name: "Moderated",
          visibility: "public",
          status: "suspended",
          isLive: false,
          participantCount: 0,
        });
      });
      await assertFails(
        updateDoc(doc(host.firestore(), "rooms/moderated-room"), {
          status: "active",
          updatedAt: serverTimestamp(),
        }),
      );
      await assertFails(
        updateDoc(doc(host.firestore(), "rooms/room1"), {
          status: "closed",
          isLive: false,
          participantCount: 0,
          updatedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "SECURITY ROOMS: ordinary room create cannot forge Club Lounge authority",
    async () => {
      await assertFails(
        setDoc(doc(host.firestore(), "rooms/forged-lounge"), {
          hostId: "host-uid",
          hostName: "Host",
          name: "Forged lounge",
          visibility: "private",
          status: "active",
          isLive: false,
          participantCount: 0,
          roomType: "community",
          clubId: "victim-club",
          roomKind: "clubLounge",
        }),
      );
    },
  );

  // --- Club ownership hijack (#2) ---
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "clubs/club1"), {
      ownerId: "host-uid",
      name: "Test club",
      status: "active",
      memberCount: 1,
    });
    await setDoc(doc(ctx.firestore(), "clubs/club1/invites/invitee-uid"), {
      inviteeId: "invitee-uid",
      inviterId: "host-uid",
      status: "pending",
    });
  });

  await check("SECURITY: random user cannot self-appoint as club owner", async () => {
    const db = attacker.firestore();
    const ref = doc(db, "clubs/club1/members/attacker-uid");
    await assertFails(
      setDoc(ref, {
        userId: "attacker-uid",
        displayName: "Attacker",
        photoUrl: null,
        role: "owner",
        isOnline: true,
        joinedAt: serverTimestamp(),
        invitedBy: null,
      }),
    );
  });

  await check(
    "SECURITY: an existing Club root cannot be reused to self-appoint an owner",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "clubs/club2"), {
          ownerId: "host-uid",
          name: "Second club",
          status: "active",
          memberCount: 0,
        });
      });
      const db = host.firestore();
      const ref = doc(db, "clubs/club2/members/host-uid");
      await assertFails(
        setDoc(ref, {
          userId: "host-uid",
          displayName: "Host",
          photoUrl: null,
          role: "owner",
          isOnline: true,
          joinedAt: serverTimestamp(),
          invitedBy: null,
        }),
      );
    },
  );

  await check(
    "SECURITY: an invitee cannot create membership outside the acceptance batch",
    async () => {
      const db = invitee.firestore();
      const ref = doc(db, "clubs/club1/members/invitee-uid");
      await assertFails(
        setDoc(ref, {
          userId: "invitee-uid",
          displayName: "Invitee",
          photoUrl: null,
          role: "member",
          isOnline: true,
          joinedAt: serverTimestamp(),
          invitedBy: "host-uid",
        }),
      );
    },
  );

  // --- /users/{userId} field validation (#6) ---
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users/host-uid"), {
      displayName: "Host",
      friendCount: 0,
      followerCount: 0,
    });
    await setDoc(doc(ctx.firestore(), "users/attacker-uid"), {
      displayName: "Attacker",
      friendCount: 0,
      followerCount: 0,
    });
  });

  await check("regression: user can update their own non-name profile fields", async () => {
    const db = host.firestore();
    const ref = doc(db, "users/host-uid");
    await assertSucceeds(updateDoc(ref, { bio: "A real profile update" }));
  });

  await check(
    "SECURITY: an established display name is server-authoritative",
    async () => {
      const db = host.firestore();
      const ref = doc(db, "users/host-uid");
      await assertFails(updateDoc(ref, { displayName: "Host renamed" }));
      // Existing clients always send displayName in their merged profile
      // payload. Keeping the same value must not break unrelated edits.
      await assertSucceeds(
        updateDoc(ref, {
          displayName: "Host",
          website: "https://example.com",
        }),
      );
    },
  );

  await check(
    "regression: a partial user document can bootstrap displayName exactly once",
    async () => {
      const uid = "display-name-bootstrap-uid";
      const profile = testEnv.authenticatedContext(uid, {
        email_verified: true,
      });
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), `users/${uid}`), {
          uid,
          isOnline: true,
        });
      });
      const ref = doc(profile.firestore(), `users/${uid}`);
      // The social-auth provisioner must treat a presence-first document as
      // an update. `createdAt` is deliberately create-only, so the old blind
      // merge was denied and deleted the freshly authenticated Google user.
      await assertFails(
        updateDoc(ref, {
          uid,
          email: "bootstrap@example.com",
          displayName: "Bootstrap Voice",
          username: "Bootstrap Voice",
          createdAt: serverTimestamp(),
        }),
      );
      await assertSucceeds(
        updateDoc(ref, {
          uid,
          email: "bootstrap@example.com",
          displayName: "Bootstrap Voice",
          username: "Bootstrap Voice",
          lastSeen: serverTimestamp(),
        }),
      );
      await assertFails(
        updateDoc(ref, { displayName: "Second Bootstrap" }),
      );
    },
  );

  await check(
    "SECURITY: clients cannot forge or clear displayNameChangedAt",
    async () => {
      const ref = doc(host.firestore(), "users/host-uid");
      await assertFails(
        updateDoc(ref, { displayNameChangedAt: serverTimestamp() }),
      );
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await updateDoc(doc(ctx.firestore(), "users/host-uid"), {
          displayNameChangedAt: Timestamp.fromMillis(Date.now()),
        });
      });
      await assertFails(updateDoc(ref, { displayNameChangedAt: deleteField() }));
    },
  );

  await check(
    "regression: achievement progress can atomically persist unlock timestamps",
    async () => {
      const db = host.firestore();
      const ref = doc(db, "users/host-uid");
      await assertSucceeds(
        updateDoc(ref, {
          roomCount: 1,
          unlockedTitleIds: ["rooms_1"],
          "unlockedTitleTimestamps.rooms_1": serverTimestamp(),
          selectedTitleId: "rooms_1",
          achievementsUpdatedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "SECURITY: user cannot write an out-of-allowlist field to their own doc",
    async () => {
      const db = host.firestore();
      const ref = doc(db, "users/host-uid");
      await assertFails(updateDoc(ref, { role: "superAdmin" }));
    },
  );

  await check("SECURITY: user cannot edit someone else's profile fields", async () => {
    const db = attacker.firestore();
    const ref = doc(db, "users/host-uid");
    await assertFails(updateDoc(ref, { displayName: "Hijacked" }));
  });

  await check(
    "SECURITY: clients cannot change another user's followerCount",
    async () => {
      const db = attacker.firestore();
      const ref = doc(db, "users/host-uid");
      await assertFails(updateDoc(ref, { followerCount: 1 }));
    },
  );

  await check(
    "SECURITY: clients cannot forge their own social counters",
    async () => {
      const db = host.firestore();
      const ref = doc(db, "users/host-uid");
      await assertFails(updateDoc(ref, { friendCount: 999 }));
      await assertFails(updateDoc(ref, { followerCount: 999 }));
      await assertFails(updateDoc(ref, { followingCount: 999 }));
    },
  );

  await check(
    "SECURITY: non-owner touching followerCount cannot sneak in another field",
    async () => {
      const db = attacker.firestore();
      const ref = doc(db, "users/host-uid");
      await assertFails(updateDoc(ref, { followerCount: 2, displayName: "Hijacked" }));
    },
  );

  // --- sentFriendRequests (#10) ---
  await check("SECURITY: sentFriendRequests are server-write-only", async () => {
    const db = attacker.firestore();
    const ref = doc(db, "users/attacker-uid/sentFriendRequests/host-uid");
    await assertFails(setDoc(ref, { receiverId: "host-uid", createdAt: null }));
  });

  await check(
    "SECURITY: user cannot create a sentFriendRequests entry for someone else",
    async () => {
      const db = attacker.firestore();
      const ref = doc(db, "users/host-uid/sentFriendRequests/attacker-uid");
      await assertFails(setDoc(ref, { receiverId: "attacker-uid", createdAt: null }));
    },
  );

  // --- forced friendship (#8) ---
  await check("SECURITY: cannot create a friends doc without a matching request", async () => {
    const db = attacker.firestore();
    const ref = doc(db, "users/host-uid/friends/attacker-uid");
    await assertFails(setDoc(ref, { userId: "attacker-uid", createdAt: null }));
  });

  await check("SECURITY: even a real request cannot be accepted by direct client writes", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "users/host-uid/friendRequests/attacker-uid"), {
        senderId: "attacker-uid",
        createdAt: null,
      });
    });
    const db = host.firestore();
    const ref = doc(db, "users/host-uid/friends/attacker-uid");
    await assertFails(setDoc(ref, { userId: "attacker-uid", createdAt: null }));
  });

  // --- following/followers (#10) ---
  await check("SECURITY: following edges are server-write-only", async () => {
    const db = attacker.firestore();
    const ref = doc(db, "users/attacker-uid/following/host-uid");
    await assertFails(setDoc(ref, { uid: "host-uid", followedAt: null }));
  });

  await check(
    "SECURITY: user cannot create a following entry on someone else's list",
    async () => {
      const db = attacker.firestore();
      const ref = doc(db, "users/host-uid/following/attacker-uid");
      await assertFails(setDoc(ref, { uid: "attacker-uid", followedAt: null }));
    },
  );

  await check(
    "SECURITY: followers edges are server-write-only",
    async () => {
      const db = attacker.firestore();
      const ref = doc(db, "users/host-uid/followers/attacker-uid");
      await assertFails(setDoc(ref, { uid: "attacker-uid", followedAt: null }));
    },
  );

  await check(
    "SECURITY: server follow-generation pointers remain readable but immutable",
    async () => {
      const path = "users/attacker-uid/following/host-uid";
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await setDoc(doc(context.firestore(), path), {
          uid: "host-uid",
          followedAt: Timestamp.now(),
          notificationId: "follow_attacker-uid_generation",
        });
      });
      await assertSucceeds(getDoc(doc(attacker.firestore(), path)));
      await assertFails(
        updateDoc(doc(attacker.firestore(), path), {
          notificationId: "follow_attacker-uid_forged",
        }),
      );
    },
  );

  await check(
    "following and followers queries accept legacy and generation edges",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        await Promise.all([
          setDoc(doc(db, "users/attacker-uid/following/host-uid"), {
            uid: "host-uid",
            followedAt: Timestamp.fromMillis(2),
          }),
          setDoc(doc(db, "users/attacker-uid/following/invitee-uid"), {
            uid: "invitee-uid",
            followedAt: Timestamp.fromMillis(1),
            notificationId: "follow_attacker-uid_generation",
          }),
          setDoc(doc(db, "users/attacker-uid/followers/host-uid"), {
            uid: "host-uid",
            followedAt: Timestamp.fromMillis(2),
          }),
          setDoc(doc(db, "users/attacker-uid/followers/invitee-uid"), {
            uid: "invitee-uid",
            followedAt: Timestamp.fromMillis(1),
            notificationId: "follow_invitee-uid_generation",
          }),
        ]);
      });
      const db = attacker.firestore();
      for (const collectionName of ["following", "followers"]) {
        const result = await assertSucceeds(
          getDocs(
            query(
              collection(db, `users/attacker-uid/${collectionName}`),
              orderBy("followedAt", "desc"),
              limit(100),
            ),
          ),
        );
        assert.equal(result.size, 2, collectionName);
      }
    },
  );

  await check(
    "SECURITY: point reads reject malformed follow pointers and list access is bounded",
    async () => {
      const path = "users/attacker-uid/following/host-uid";
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await updateDoc(doc(context.firestore(), path), {
          notificationId: "x".repeat(321),
        });
      });
      await assertFails(getDoc(doc(attacker.firestore(), path)));
      // Firestore cannot prove per-document schema predicates for an
      // unconstrained collection query. These rows are Admin-only, so list
      // disclosure is instead capped to the exact production access pattern.
      await assertSucceeds(
        getDocs(
          query(
            collection(attacker.firestore(), "users/attacker-uid/following"),
            orderBy("followedAt", "desc"),
            limit(100),
          ),
        ),
      );
      await assertFails(
        getDocs(
          query(
            collection(attacker.firestore(), "users/attacker-uid/following"),
            orderBy("followedAt", "desc"),
            limit(101),
          ),
        ),
      );
    },
  );

  await check(
    "PRIVACY: follow lists inherit profile visibility and block boundaries",
    async () => {
      const ownerId = "follow-privacy-owner";
      const readerId = "follow-privacy-reader";
      const endpointId = "follow-privacy-endpoint";
      const owner = testEnv.authenticatedContext(ownerId, {
        email_verified: true,
      });
      const reader = testEnv.authenticatedContext(readerId, {
        email_verified: true,
      });
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        await Promise.all([
          setDoc(doc(db, `users/${ownerId}`), {
            displayName: "Owner",
            banned: false,
            profileVisibility: "public",
          }),
          setDoc(doc(db, `users/${readerId}`), {
            displayName: "Reader",
            banned: false,
          }),
          setDoc(doc(db, `users/${endpointId}`), {
            displayName: "Endpoint",
            banned: false,
          }),
          setDoc(doc(db, `users/${ownerId}/following/${endpointId}`), {
            uid: endpointId,
            followedAt: Timestamp.now(),
          }),
        ]);
      });

      const listFor = (context) =>
        getDocs(
          query(
            collection(context.firestore(), `users/${ownerId}/following`),
            orderBy("followedAt", "desc"),
            limit(100),
          ),
        );
      const endpointFor = (context) =>
        getDoc(
          doc(context.firestore(), `users/${ownerId}/following/${endpointId}`),
        );

      await assertSucceeds(listFor(reader));
      await assertSucceeds(endpointFor(reader));

      await testEnv.withSecurityRulesDisabled(async (context) => {
        await updateDoc(doc(context.firestore(), `users/${ownerId}`), {
          profileVisibility: "private",
        });
      });
      await assertSucceeds(listFor(owner));
      await assertFails(listFor(reader));
      await assertFails(endpointFor(reader));

      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        await updateDoc(doc(db, `users/${ownerId}`), {
          profileVisibility: "friends",
        });
      });
      await assertFails(listFor(reader));

      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        for (const [guardOwner, friend] of [
          [ownerId, readerId],
          [readerId, ownerId],
        ]) {
          await setDoc(
            doc(db, `friendshipGuards/${guardOwner}/friends/${friend}`),
            {
              ownerId: guardOwner,
              friendId: friend,
              schemaVersion: 1,
              establishedAt: Timestamp.now(),
            },
          );
        }
      });
      await assertSucceeds(listFor(reader));

      await testEnv.withSecurityRulesDisabled(async (context) => {
        await setDoc(
          doc(
            context.firestore(),
            `users/${ownerId}/blocked/${readerId}`,
          ),
          { userId: readerId, createdAt: Timestamp.now() },
        );
      });
      await assertFails(listFor(reader));
      await assertFails(endpointFor(reader));
    },
  );

  // --- legacy handRequests compatibility (#10) ---
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "rooms/broadcastRoom"), {
      hostId: "host-uid",
      experience: "broadcast",
      visibility: "public",
      status: "active",
      isLive: true,
      handRaisingEnabled: true,
    });
    await setDoc(
      doc(ctx.firestore(), "rooms/broadcastRoom/participants/attacker-uid"),
      { userId: "attacker-uid", role: "listener" },
    );
    await setDoc(doc(ctx.firestore(), "rooms/communityRoom"), {
      hostId: "host-uid",
      experience: "community",
    });
    await setDoc(doc(ctx.firestore(), "rooms/privateBroadcastRoom"), {
      hostId: "host-uid",
      experience: "broadcast",
      visibility: "private",
      status: "active",
      isLive: true,
      handRaisingEnabled: true,
    });
  });

  await check("compatibility: a legacy broadcast hand request still works", async () => {
    const db = attacker.firestore();
    const ref = doc(db, "rooms/broadcastRoom/handRequests/attacker-uid");
    await assertSucceeds(
      setDoc(ref, {
        displayName: "Attacker",
        photoUrl: null,
        createdAt: serverTimestamp(),
      }),
    );
  });

  await check(
    "SECURITY: a legacy hand request name is bound to the canonical profile",
    async () => {
      const db = attacker.firestore();
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await deleteDoc(
          doc(
            ctx.firestore(),
            "rooms/broadcastRoom/handRequests/attacker-uid",
          ),
        );
        await updateDoc(doc(ctx.firestore(), "users/attacker-uid"), {
          displayName: "Renamed Attacker",
        });
      });
      await assertFails(
        setDoc(
          doc(db, "rooms/broadcastRoom/handRequests/attacker-uid"),
          {
            displayName: "Attacker",
            photoUrl: null,
            createdAt: serverTimestamp(),
          },
        ),
      );
      await assertSucceeds(
        setDoc(
          doc(db, "rooms/broadcastRoom/handRequests/attacker-uid"),
          {
            displayName: "Renamed Attacker",
            photoUrl: null,
            createdAt: serverTimestamp(),
          },
        ),
      );
    },
  );

  await check("SECURITY: legacy hand request is podcast-only", async () => {
    const db = attacker.firestore();
    const ref = doc(db, "rooms/communityRoom/handRequests/attacker-uid");
    await assertFails(setDoc(ref, { displayName: "Attacker", createdAt: null }));
  });

  await check(
    "SECURITY: outsider cannot reach a private legacy hand queue",
    async () => {
      const db = attacker.firestore();
      await assertFails(
        setDoc(
          doc(
            db,
            "rooms/privateBroadcastRoom/handRequests/attacker-uid",
          ),
          {
            displayName: "Attacker",
            photoUrl: null,
            createdAt: serverTimestamp(),
          },
        ),
      );
      await assertFails(
        getDocs(collection(db, "rooms/privateBroadcastRoom/handRequests")),
      );
    },
  );

  // --- voiceMoments likes/comments (#7) ---
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "voiceMoments/moment1"), {
      authorId: "host-uid",
      isPublished: true,
      likeCount: 0,
      commentCount: 0,
    });
    await setDoc(doc(ctx.firestore(), "voiceMoments/moment-private"), {
      authorId: "host-uid",
      isPublished: false,
      status: "uploading",
      likeCount: 0,
      commentCount: 0,
    });
    await setDoc(
      doc(ctx.firestore(), "voiceMoments/moment1/likes/published-like"),
      { userId: "host-uid", createdAt: serverTimestamp() },
    );
    await setDoc(
      doc(ctx.firestore(), "voiceMoments/moment1/comments/existing-comment"),
      {
        type: "text",
        authorId: "attacker-uid",
        text: "Existing comment",
        createdAt: serverTimestamp(),
      },
    );
    await setDoc(
      doc(ctx.firestore(), "voiceMoments/moment-private/likes/private-like"),
      { userId: "host-uid", createdAt: serverTimestamp() },
    );
    await setDoc(
      doc(
        ctx.firestore(),
        "voiceMoments/moment-private/comments/private-comment",
      ),
      {
        type: "text",
        authorId: "host-uid",
        text: "Private comment",
        createdAt: serverTimestamp(),
      },
    );
  });

  await check("SECURITY: likes and root counters are callable-only", async () => {
    const db = attacker.firestore();
    const likeRef = doc(db, "voiceMoments/moment1/likes/attacker-uid");
    await assertFails(setDoc(likeRef, {
      userId: "attacker-uid",
      createdAt: serverTimestamp(),
    }));

    const batch = writeBatch(db);
    batch.set(likeRef, {
      userId: "attacker-uid",
      createdAt: serverTimestamp(),
    });
    batch.update(doc(db, "voiceMoments/moment1"), { likeCount: 1 });
    await assertFails(batch.commit());

    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), "voiceMoments/moment1/likes/attacker-uid"),
        { userId: "attacker-uid", createdAt: serverTimestamp() },
      );
    });
    await assertFails(updateDoc(likeRef, { createdAt: serverTimestamp() }));
    await assertFails(deleteDoc(likeRef));
  });

  await check("SECURITY: no client can mutate either engagement counter", async () => {
    const db = attacker.firestore();
    const ref = doc(db, "voiceMoments/moment1");
    await assertFails(updateDoc(ref, { likeCount: 9999 }));
    await assertFails(updateDoc(ref, { likeCount: -1 }));
    await assertFails(updateDoc(ref, { commentCount: 1 }));
  });

  await check("SECURITY: text and forged comments are callable-only", async () => {
    await assertFails(setDoc(
      doc(attacker.firestore(), "voiceMoments/moment1/comments/comment-1"),
      {
        type: "text",
        authorId: "attacker-uid",
        text: "Canonical comment",
      },
    ));
    await assertFails(setDoc(
      doc(attacker.firestore(), "voiceMoments/moment1/comments/forged"),
      {
        type: "text",
        authorId: "attacker-uid",
        text: "Forged comment",
        createdAt: "not-a-timestamp",
        admin: true,
      },
    ));
    const existing = doc(
      attacker.firestore(),
      "voiceMoments/moment1/comments/existing-comment",
    );
    await assertFails(updateDoc(existing, { text: "Attacker edit" }));
    await assertFails(deleteDoc(existing));
  });

  await check(
    "SECURITY: even the owner cannot directly edit root content or identity",
    async () => {
      const ref = doc(host.firestore(), "voiceMoments/moment1");
      await assertFails(updateDoc(ref, { caption: "Owner edit" }));
      await assertFails(updateDoc(ref, { authorId: "attacker-uid" }));
    },
  );

  await check("SECURITY: draft roots are author-private while published roots are readable", async () => {
    await assertSucceeds(getDoc(doc(host.firestore(), "voiceMoments/moment-private")));
    await assertFails(getDoc(doc(attacker.firestore(), "voiceMoments/moment-private")));
    await assertSucceeds(getDoc(doc(attacker.firestore(), "voiceMoments/moment1")));
  });

  await check(
    "SECURITY: Moment engagement reads inherit the parent visibility boundary",
    async () => {
      const privateLike = "voiceMoments/moment-private/likes/private-like";
      const privateComment =
        "voiceMoments/moment-private/comments/private-comment";
      const publishedLike = "voiceMoments/moment1/likes/published-like";
      const publishedComment =
        "voiceMoments/moment1/comments/existing-comment";

      await assertSucceeds(getDoc(doc(host.firestore(), privateLike)));
      await assertSucceeds(getDoc(doc(host.firestore(), privateComment)));
      await assertFails(getDoc(doc(attacker.firestore(), privateLike)));
      await assertFails(getDoc(doc(attacker.firestore(), privateComment)));
      await assertSucceeds(getDoc(doc(attacker.firestore(), publishedLike)));
      await assertSucceeds(getDoc(doc(attacker.firestore(), publishedComment)));

      const anonymous = testEnv.unauthenticatedContext().firestore();
      await assertFails(getDoc(doc(anonymous, publishedLike)));
      await assertFails(getDoc(doc(anonymous, publishedComment)));
    },
  );

  // --- voiceMoments 24h expiry pinning + momentViews (story chains) ---
  //
  // expiresAt is server authority: finalizeMomentDraft stamps it
  // createdAt + 24h and the scheduled sweep retires the Moment when it
  // passes. If the author could write either timestamp, they could extend
  // their own story past 24 hours (or re-order a chain), so both must be
  // immutable on update and expiresAt unforgeable on create.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "voiceMoments/moment-expiry"), {
      authorId: "host-uid",
      caption: "Expiring story",
      isPublished: true,
      status: "published",
      likeCount: 0,
      commentCount: 0,
      createdAt: Timestamp.fromMillis(1_820_000_000_000),
      expiresAt: Timestamp.fromMillis(1_820_000_000_000 + 86_400_000),
    });
  });

  await check("SECURITY: the author cannot extend their own Moment's expiresAt", async () => {
    const ref = doc(host.firestore(), "voiceMoments/moment-expiry");
    await assertFails(updateDoc(ref, {
      expiresAt: Timestamp.fromMillis(1_820_000_000_000 + 10 * 86_400_000),
    }));
  });

  await check("SECURITY: the author cannot rewrite createdAt to re-order a chain", async () => {
    const ref = doc(host.firestore(), "voiceMoments/moment-expiry");
    await assertFails(updateDoc(ref, {
      createdAt: Timestamp.fromMillis(1_820_000_500_000),
    }));
  });

  await check("SECURITY: the author cannot attach expiresAt to a Moment that has none", async () => {
    const ref = doc(host.firestore(), "voiceMoments/moment1");
    await assertFails(updateDoc(ref, {
      expiresAt: Timestamp.fromMillis(2_000_000_000_000),
    }));
  });

  await check("SECURITY: the author cannot strip expiresAt to make a story permanent", async () => {
    // Operator-chosen availability (2026-08) makes a MISSING expiresAt mean
    // "permanent — published until deleted", so deleting the field is now the
    // exact same attack as extending it: a self-granted upgrade from a
    // 24-hour story to a forever one. `affectedKeys()` counts a removed key
    // as affected, which is what refuses this; the pin keeps it that way.
    const ref = doc(host.firestore(), "voiceMoments/moment-expiry");
    await assertFails(updateDoc(ref, { expiresAt: deleteField() }));
  });

  await check("SECURITY: the author cannot edit the caption on an expiring Moment", async () => {
    const ref = doc(host.firestore(), "voiceMoments/moment-expiry");
    await assertFails(updateDoc(ref, { caption: "Owner edit before expiry" }));
  });

  await check("SECURITY: a client-created Moment cannot carry its own expiresAt", async () => {
    await assertFails(setDoc(doc(host.firestore(), "voiceMoments/forged-expiry-create"), {
      authorId: "host-uid",
      caption: "Forged deadline",
      isPublished: true,
      likeCount: 0,
      commentCount: 0,
      expiresAt: Timestamp.fromMillis(3_000_000_000_000),
    }));
  });

  await check("SECURITY: legacy-style client root creation is also rejected", async () => {
    await assertFails(setDoc(doc(host.firestore(), "voiceMoments/legacy-client-create"), {
      authorId: "host-uid",
      caption: "Legacy create",
      isPublished: true,
      likeCount: 0,
      commentCount: 0,
    }));
  });

  await check("SECURITY: root deletion is callable-only, including for the author", async () => {
    await assertFails(deleteDoc(doc(host.firestore(), "voiceMoments/moment1")));
  });

  await check("SECURITY: capacity mutex ledgers are invisible and server-only", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "momentCapacityLedgers/host-uid"), {
        schemaVersion: 1,
        ownerId: "host-uid",
        revision: 1,
        updatedAt: serverTimestamp(),
      });
    });
    const ref = doc(host.firestore(), "momentCapacityLedgers/host-uid");
    await assertFails(getDoc(ref));
    await assertFails(updateDoc(ref, { revision: 2 }));
    await assertFails(deleteDoc(ref));
  });

  // Viewed state for story chains lives at users/{uid}/momentViews/{momentId}
  // with the exact shape { viewedAt: request.time }. Owner-only in both
  // directions — who watched whose story is private — and rows never carry
  // anything beyond the server-stamped watch time. No delete: "unviewed"
  // cannot be re-armed by clearing history, and there is deliberately no
  // global view counter anywhere for it to feed.
  await check("regression: the owner records their own Moment view with server time", async () => {
    const ref = doc(host.firestore(), "users/host-uid/momentViews/moment1");
    await assertSucceeds(setDoc(ref, { viewedAt: serverTimestamp() }));
  });

  await check("regression: re-viewing updates the same row with server time", async () => {
    const ref = doc(host.firestore(), "users/host-uid/momentViews/moment1");
    await assertSucceeds(updateDoc(ref, { viewedAt: serverTimestamp() }));
  });

  await check("regression: the owner can read and list their own Moment views", async () => {
    const db = host.firestore();
    await assertSucceeds(getDoc(doc(db, "users/host-uid/momentViews/moment1")));
    await assertSucceeds(getDocs(collection(db, "users/host-uid/momentViews")));
  });

  await check("SECURITY: nobody can write a Moment view into someone else's history", async () => {
    const ref = doc(attacker.firestore(), "users/host-uid/momentViews/moment1");
    await assertFails(setDoc(ref, { viewedAt: serverTimestamp() }));
  });

  await check("SECURITY: nobody can read someone else's Moment view history", async () => {
    const db = attacker.firestore();
    await assertFails(getDoc(doc(db, "users/host-uid/momentViews/moment1")));
    await assertFails(getDocs(collection(db, "users/host-uid/momentViews")));
  });

  await check("SECURITY: a Moment view cannot carry a forged or extra payload", async () => {
    const db = host.firestore();
    await assertFails(setDoc(doc(db, "users/host-uid/momentViews/forged-time"), {
      viewedAt: Timestamp.fromMillis(1_000_000_000_000),
    }));
    await assertFails(setDoc(doc(db, "users/host-uid/momentViews/extra-keys"), {
      viewedAt: serverTimestamp(),
      count: 9999,
    }));
  });

  await check("SECURITY: Moment views cannot be deleted to re-arm unviewed rings", async () => {
    const ref = doc(host.firestore(), "users/host-uid/momentViews/moment1");
    await assertFails(deleteDoc(ref));
  });

  // --- room messages visibility (#9) ---
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "rooms/publicRoom"), {
      hostId: "host-uid",
      visibility: "public",
    });
    await setDoc(doc(ctx.firestore(), "rooms/privateRoom"), {
      hostId: "host-uid",
      visibility: "private",
    });
    await setDoc(doc(ctx.firestore(), "rooms/privateRoom/participants/host-uid"), {
      userId: "host-uid",
    });
  });

  await check("regression: anyone can read a PUBLIC room's chat without joining", async () => {
    const db = attacker.firestore();
    await assertSucceeds(getDocs(collection(db, "rooms/publicRoom/messages")));
  });

  await check("SECURITY: a non-participant cannot read a PRIVATE room's chat", async () => {
    const db = attacker.firestore();
    await assertFails(getDocs(collection(db, "rooms/privateRoom/messages")));
  });

  await check("regression: an actual participant CAN read a PRIVATE room's chat", async () => {
    const db = host.firestore();
    await assertSucceeds(getDocs(collection(db, "rooms/privateRoom/messages")));
  });

  // --- friendRequests cross-read for getRelationshipStatus() ---
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users/host-uid/friendRequests/attacker-uid"), {
      senderId: "attacker-uid",
      createdAt: null,
    });
  });

  await check(
    "regression: the SENDER can read their own outgoing request under the recipient's doc",
    async () => {
      const db = attacker.firestore();
      const ref = doc(db, "users/host-uid/friendRequests/attacker-uid");
      await assertSucceeds(getDoc(ref));
    },
  );

  await check(
    "regression: the RECIPIENT can still read their own incoming request list",
    async () => {
      const db = host.firestore();
      const ref = doc(db, "users/host-uid/friendRequests/attacker-uid");
      await assertSucceeds(getDoc(ref));
    },
  );

  await check(
    "SECURITY: an unrelated third party cannot read someone else's friendRequest",
    async () => {
      const db = invitee.firestore();
      const ref = doc(db, "users/host-uid/friendRequests/attacker-uid");
      await assertFails(getDoc(ref));
    },
  );

  // --- the actual LIST queries the product runs (2026-08-18 regression) ---
  // watchFriendRequests()/watchFriends() run collection LIST queries. The
  // old single-`read` rules called accountIsActive(<wildcard>) per candidate
  // row, which fails a list wholesale — the Notifications screen lost every
  // accept/decline control and the Friends counter read 0 in production.
  // These tests execute the real queries; getDoc() coverage is not enough.
  await check(
    "regression: the RECIPIENT can LIST their own incoming friendRequests",
    async () => {
      const db = host.firestore();
      await assertSucceeds(
        getDocs(collection(db, "users/host-uid/friendRequests")),
      );
    },
  );

  await check(
    "SECURITY: a third party cannot LIST someone else's friendRequests",
    async () => {
      const db = invitee.firestore();
      await assertFails(
        getDocs(collection(db, "users/host-uid/friendRequests")),
      );
    },
  );

  await check(
    "SECURITY: the sender cannot LIST the recipient's friendRequests",
    async () => {
      const db = attacker.firestore();
      await assertFails(
        getDocs(collection(db, "users/host-uid/friendRequests")),
      );
    },
  );

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users/host-uid/friends/friend-1"), {
      friendId: "friend-1",
      displayName: "First friend",
    });
    await setDoc(
      doc(ctx.firestore(), "users/host-uid/sentFriendRequests/invitee-uid"),
      { receiverId: "invitee-uid", createdAt: null },
    );
  });

  await check("regression: the owner can LIST their own friends mirror", async () => {
    const db = host.firestore();
    await assertSucceeds(getDocs(collection(db, "users/host-uid/friends")));
  });

  await check("SECURITY: a third party cannot LIST someone else's friends", async () => {
    const db = invitee.firestore();
    await assertFails(getDocs(collection(db, "users/host-uid/friends")));
  });

  await check(
    "regression: the owner can LIST their own sentFriendRequests",
    async () => {
      const db = host.firestore();
      await assertSucceeds(
        getDocs(collection(db, "users/host-uid/sentFriendRequests")),
      );
    },
  );

  await check(
    "SECURITY: a third party cannot LIST someone else's sentFriendRequests",
    async () => {
      const db = invitee.firestore();
      await assertFails(
        getDocs(collection(db, "users/host-uid/sentFriendRequests")),
      );
    },
  );

  // --- clubs/{clubId}/members collectionGroup compatibility ---
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "clubs/club3"), {
      ownerId: "host-uid",
      name: "Third club",
      status: "active",
      memberCount: 1,
    });
    await setDoc(doc(ctx.firestore(), "clubs/club3/members/attacker-uid"), {
      userId: "attacker-uid",
      role: "member",
    });
    await setDoc(doc(ctx.firestore(), "clubs/club3/members/host-uid"), {
      userId: "host-uid",
      role: "owner",
    });
  });

  await check("regression: a user can always read their OWN club membership record", async () => {
    const db = attacker.firestore();
    const ref = doc(db, "clubs/club3/members/attacker-uid");
    await assertSucceeds(getDoc(ref));
  });

  await check(
    "SECURITY: a non-member cannot read someone ELSE's club membership record",
    async () => {
      const db = invitee.firestore();
      const ref = doc(db, "clubs/club3/members/attacker-uid");
      await assertFails(getDoc(ref));
    },
  );

  await check("regression: an actual club member can still browse the member list", async () => {
    const db = host.firestore(); // host is the club owner -> a member
    const ref = doc(db, "clubs/club3/members/attacker-uid");
    await assertSucceeds(getDoc(ref));
  });

  await check(
    "SECURITY CLUBS: banned members, inactive Clubs, deletion and global bans deny all Club content",
    async () => {
      const clubId = "content-gate-club";
      const clubPath = `clubs/${clubId}`;
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, clubPath), {
          ownerId: "host-uid",
          type: "community",
          status: "active",
          deletionInProgress: false,
        });
        await setDoc(doc(db, `${clubPath}/members/attacker-uid`), {
          userId: "attacker-uid",
          role: "member",
          banned: false,
        });
        await setDoc(doc(db, `${clubPath}/members/host-uid`), {
          userId: "host-uid",
          role: "owner",
          banned: false,
        });
        await setDoc(doc(db, `${clubPath}/channels/general`), {
          name: "general",
        });
        await setDoc(doc(db, `${clubPath}/channels/general/messages/m1`), {
          senderId: "host-uid",
          content: "private Club content",
        });
        await setDoc(doc(db, `${clubPath}/moments/m1`), {
          authorId: "host-uid",
        });
        await setDoc(doc(db, `${clubPath}/checkIns/c1`), {
          userId: "host-uid",
          status: "home",
        });
      });

      const db = attacker.firestore();
      const contentReferences = [
        doc(db, `${clubPath}/channels/general`),
        doc(db, `${clubPath}/channels/general/messages/m1`),
        doc(db, `${clubPath}/moments/m1`),
        doc(db, `${clubPath}/checkIns/c1`),
      ];
      for (const reference of contentReferences) {
        await assertSucceeds(getDoc(reference));
      }
      await assertSucceeds(getDocs(collection(db, `${clubPath}/members`)));
      await assertSucceeds(getDocs(collection(db, `${clubPath}/channels`)));

      async function assertContentDenied() {
        for (const reference of contentReferences) {
          await assertFails(getDoc(reference));
        }
        await assertFails(getDocs(collection(db, `${clubPath}/members`)));
        await assertFails(getDocs(collection(db, `${clubPath}/channels`)));
      }

      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await updateDoc(
          doc(ctx.firestore(), `${clubPath}/members/attacker-uid`),
          { banned: true },
        );
      });
      await assertContentDenied();

      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const serverDb = ctx.firestore();
        await updateDoc(doc(serverDb, `${clubPath}/members/attacker-uid`), {
          banned: false,
        });
        await updateDoc(doc(serverDb, clubPath), { status: "suspended" });
      });
      await assertContentDenied();

      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const serverDb = ctx.firestore();
        await updateDoc(doc(serverDb, clubPath), {
          status: "active",
          deletionInProgress: true,
        });
      });
      await assertContentDenied();

      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const serverDb = ctx.firestore();
        await updateDoc(doc(serverDb, clubPath), {
          deletionInProgress: false,
        });
        await updateDoc(doc(serverDb, "users/attacker-uid"), {
          banned: true,
        });
      });
      await assertContentDenied();
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await updateDoc(doc(ctx.firestore(), "users/attacker-uid"), {
          banned: false,
        });
      });
    },
  );

  // ---------------------------------------------------------------
  // CLUB CHAT MESSAGE REMOVAL
  //
  // Two defects were live in production together, and neither could be
  // fixed alone:
  //
  //  1. The update rule required `resource.data.senderId == request.auth.uid`
  //     — author only — so a club moderator, admin or OWNER could not
  //     remove an abusive message from their own club. The client
  //     (ClubChatService.deleteMessage) authorises exactly those roles,
  //     so the product promised a moderation action the database refused.
  //  2. The same rule carried NO field allowlist, so an author could
  //     rewrite `content`, `senderName` and `sentAt` on their own message
  //     after the fact. Admitting moderators without fixing that would
  //     have handed them the same unrestricted write over other people's
  //     messages — a moderation feature that doubles as a way to put
  //     words in someone's mouth.
  //
  // The cases below are split accordingly: the "DEFECT 1" group is denied
  // before the fix and allowed after; the "DEFECT 2" group SUCCEEDS
  // before the fix (that is the bug) and is denied after.
  // ---------------------------------------------------------------
  const CLUB_CHAT = "clubs/chatmod-club";
  const CLUB_CHAT_MESSAGES = `${CLUB_CHAT}/channels/general/messages`;
  const CHAT_SENT_AT = Timestamp.fromMillis(1_700_000_000_000);

  const clubChatOwner = testEnv.authenticatedContext("ccm-owner", {
    email_verified: true,
  });
  const clubChatAdmin = testEnv.authenticatedContext("ccm-admin", {
    email_verified: true,
  });
  const clubChatMod = testEnv.authenticatedContext("ccm-mod", {
    email_verified: true,
  });
  const clubChatAuthor = testEnv.authenticatedContext("ccm-author", {
    email_verified: true,
  });
  const clubChatPeer = testEnv.authenticatedContext("ccm-peer", {
    email_verified: true,
  });
  const clubChatBannedMod = testEnv.authenticatedContext("ccm-banned-mod", {
    email_verified: true,
  });
  const clubChatDisabledMod = testEnv.authenticatedContext("ccm-disabled-mod", {
    email_verified: true,
  });
  const clubChatOutsider = testEnv.authenticatedContext("ccm-outsider", {
    email_verified: true,
  });

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const accounts = {
      "ccm-owner": {},
      "ccm-admin": {},
      "ccm-mod": {},
      "ccm-author": {},
      "ccm-peer": {},
      "ccm-banned-mod": { banned: true },
      "ccm-disabled-mod": { disabled: true },
      "ccm-outsider": {},
    };
    await Promise.all(
      Object.entries(accounts).map(([uid, extra]) =>
        setDoc(doc(db, `users/${uid}`), {
          displayName: uid,
          banned: false,
          ...extra,
        }),
      ),
    );
    await setDoc(doc(db, CLUB_CHAT), {
      ownerId: "ccm-owner",
      name: "Moderated club",
      type: "community",
      status: "active",
      deletionInProgress: false,
    });
    const members = {
      "ccm-owner": "owner",
      "ccm-admin": "admin",
      "ccm-mod": "moderator",
      "ccm-author": "member",
      "ccm-peer": "member",
      "ccm-banned-mod": "moderator",
      "ccm-disabled-mod": "moderator",
    };
    await Promise.all(
      Object.entries(members).map(([uid, role]) =>
        setDoc(doc(db, `${CLUB_CHAT}/members/${uid}`), {
          userId: uid,
          displayName: uid,
          photoUrl: null,
          role,
          isOnline: false,
          joinedAt: CHAT_SENT_AT,
          invitedBy: null,
          // A club-level ban is separate from a platform ban; only
          // ccm-banned-mod carries the platform one.
          banned: false,
        }),
      ),
    );
    await setDoc(doc(db, `${CLUB_CHAT}/channels/general`), {
      name: "general",
      type: "text",
    });
    // A second club, used to prove that moderating one club grants
    // nothing in another.
    await setDoc(doc(db, "clubs/chatmod-other"), {
      ownerId: "ccm-peer",
      name: "Other club",
      type: "community",
      status: "active",
      deletionInProgress: false,
    });
    await setDoc(doc(db, "clubs/chatmod-other/members/ccm-peer"), {
      userId: "ccm-peer",
      role: "owner",
      banned: false,
    });
    await setDoc(doc(db, "clubs/chatmod-other/channels/general"), {
      name: "general",
      type: "text",
    });
  });

  // Restores one message to the exact shape ClubChatService.sendTextMessage
  // writes, so every case starts from a live production-shaped document.
  async function seedClubMessage(messageId, overrides = {}) {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `${CLUB_CHAT_MESSAGES}/${messageId}`), {
        clubId: "chatmod-club",
        channelId: "general",
        senderId: "ccm-author",
        senderName: "ccm-author",
        senderPhotoUrl: null,
        content: "something abusive",
        sentAt: CHAT_SENT_AT,
        editedAt: null,
        isDeleted: false,
        ...overrides,
      });
    });
  }

  // The write the CURRENT deployed client sends: content/isDeleted/editedAt
  // and no attribution.
  const legacyRemoval = () => ({
    content: "",
    isDeleted: true,
    editedAt: serverTimestamp(),
  });

  // --- DEFECT 3: create minted the tombstone the update rule forbids ---
  //
  // The removal rule promises no message ends up attributed to somebody
  // who did not remove it. That promise needed the create side too: an
  // ordinary member could write ONE document already carrying the exact
  // tombstone adminDeleteMessage writes, and nothing in the product
  // could clear it afterwards. Found by adversarial review of the first
  // version of this change, and fixed in the same commit because the
  // state it mints is permanent the moment anyone exercises it.

  await check(
    "DEFECT 3 CLUB CHAT: a member cannot create a message that is ALREADY removed",
    async () => {
      const db = clubChatPeer.firestore();
      await assertFails(
        addDoc(collection(db, CLUB_CHAT_MESSAGES), {
          clubId: "chatmod-club",
          channelId: "general",
          senderId: "ccm-peer",
          senderName: "ccm-peer",
          senderPhotoUrl: null,
          content: "",
          sentAt: Timestamp.now(),
          editedAt: null,
          isDeleted: true,
        }),
      );
    },
  );

  await check(
    "DEFECT 3 CLUB CHAT: the FORGED TOMBSTONE is refused end to end — staff-signed removal fields, an impersonated sender and a 2099 sentAt in one create",
    async () => {
      const db = clubChatPeer.firestore();
      await assertFails(
        addDoc(collection(db, CLUB_CHAT_MESSAGES), {
          clubId: "chatmod-club",
          channelId: "general",
          senderId: "ccm-peer",
          senderName: "YO Voice Support",
          senderPhotoUrl: null,
          content: "",
          sentAt: Timestamp.fromMillis(4_100_000_000_000),
          editedAt: null,
          isDeleted: true,
          deletedBy: "ccm-owner",
          deletedByRole: "superAdmin",
          moderationRemoved: true,
        }),
      );
    },
  );

  await check(
    "DEFECT 3 CLUB CHAT: a pre-attributed create is refused — deletedBy, deletedAt and editedAt must all be absent or null on a new message",
    async () => {
      const db = clubChatPeer.firestore();
      for (const forged of [
        { deletedBy: "ccm-owner" },
        { deletedAt: Timestamp.now() },
        { editedAt: Timestamp.now() },
      ]) {
        await assertFails(
          addDoc(collection(db, CLUB_CHAT_MESSAGES), {
            clubId: "chatmod-club",
            channelId: "general",
            senderId: "ccm-peer",
            senderName: "ccm-peer",
            senderPhotoUrl: null,
            content: "looks ordinary",
            sentAt: Timestamp.now(),
            editedAt: null,
            isDeleted: false,
            ...forged,
          }),
        );
      }
    },
  );

  await check(
    "DEFECT 3 CLUB CHAT: unlisted fields cannot ride along on a create — staff badges, moderation flags and media alike",
    async () => {
      const db = clubChatPeer.firestore();
      for (const smuggled of [
        { senderIsStaff: true },
        { deletedByRole: "superAdmin" },
        { moderationRemoved: true },
        // Club chat is text-only. A removal cannot clear media, so media
        // that cannot be attached is the only safe arrangement.
        { audioUrl: "https://example.invalid/a.m4a" },
        { imageUrl: "https://example.invalid/a.png" },
        { mediaUrl: "https://example.invalid/a.png" },
        { attachments: ["https://example.invalid/a.png"] },
      ]) {
        await assertFails(
          addDoc(collection(db, CLUB_CHAT_MESSAGES), {
            clubId: "chatmod-club",
            channelId: "general",
            senderId: "ccm-peer",
            senderName: "ccm-peer",
            senderPhotoUrl: null,
            content: "looks ordinary",
            sentAt: Timestamp.now(),
            editedAt: null,
            isDeleted: false,
            ...smuggled,
          }),
        );
      }
    },
  );

  await check(
    "DEFECT 3 CLUB CHAT: content bounds match what the client already enforces — blank and over-2000 are refused",
    async () => {
      const db = clubChatPeer.firestore();
      for (const content of ["", "   ", "x".repeat(2001)]) {
        await assertFails(
          addDoc(collection(db, CLUB_CHAT_MESSAGES), {
            clubId: "chatmod-club",
            channelId: "general",
            senderId: "ccm-peer",
            senderName: "ccm-peer",
            senderPhotoUrl: null,
            content,
            sentAt: Timestamp.now(),
            editedAt: null,
            isDeleted: false,
          }),
        );
      }
    },
  );

  await check(
    "DEFECT 3 CLUB CHAT: WHY the create gate had to ship in the same deploy — a pre-deleted message is unremovable by every client path there is",
    async () => {
      // Seeded through the Admin SDK because the rules now refuse to
      // create it. This asserts the state's permanence, which is the
      // whole reason the create gate could not be deferred: the removal
      // rule refuses an already-removed document, delete is `if false`
      // for everyone, and adminDeleteMessage short-circuits on
      // isDeleted === true and returns "alreadyRemoved" without
      // redacting (functions/admin/messages.js:343).
      await seedClubMessage("forged-tombstone", {
        senderId: "ccm-peer",
        senderName: "YO Voice Support",
        content: "",
        isDeleted: true,
        deletedBy: "ccm-owner",
      });
      const path = `${CLUB_CHAT_MESSAGES}/forged-tombstone`;
      for (const actor of [clubChatOwner, clubChatMod, clubChatPeer]) {
        const db = actor.firestore();
        await assertFails(
          updateDoc(doc(db, path), {
            content: "",
            isDeleted: true,
            editedAt: serverTimestamp(),
            deletedBy: "ccm-owner",
            deletedAt: serverTimestamp(),
          }),
        );
        await assertFails(deleteDoc(doc(db, path)));
      }
    },
  );

  // --- DEFECT 1: moderation is callable-only ---

  await check(
    "SECURITY CLUB CHAT: a club MODERATOR cannot bypass the audited moderation callable",
    async () => {
      await seedClubMessage("mod-removes");
      const db = clubChatMod.firestore();
      await assertFails(
        updateDoc(doc(db, `${CLUB_CHAT_MESSAGES}/mod-removes`), {
          content: "",
          isDeleted: true,
          editedAt: serverTimestamp(),
          deletedBy: "ccm-mod",
          deletedAt: serverTimestamp(),
        }),
      );
      const after = await getDoc(
        doc(db, `${CLUB_CHAT_MESSAGES}/mod-removes`),
      );
      assert.equal(after.data().isDeleted, false);
      assert.equal(after.data().content, "something abusive");
    },
  );

  await check(
    "SECURITY CLUB CHAT: the club OWNER also uses the audited moderation callable",
    async () => {
      await seedClubMessage("owner-removes");
      const db = clubChatOwner.firestore();
      await assertFails(
        updateDoc(doc(db, `${CLUB_CHAT_MESSAGES}/owner-removes`), {
          content: "",
          isDeleted: true,
          editedAt: serverTimestamp(),
          deletedBy: "ccm-owner",
          deletedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "SECURITY CLUB CHAT: a club ADMIN also uses the audited moderation callable",
    async () => {
      await seedClubMessage("admin-removes");
      const db = clubChatAdmin.firestore();
      await assertFails(
        updateDoc(doc(db, `${CLUB_CHAT_MESSAGES}/admin-removes`), {
          content: "",
          isDeleted: true,
          editedAt: serverTimestamp(),
          deletedBy: "ccm-admin",
          deletedAt: serverTimestamp(),
        }),
      );
    },
  );

  // --- DEFECT 2: the same rule had no field allowlist ---

  await check(
    "DEFECT 2 CLUB CHAT: an author cannot rewrite the CONTENT of their own message after the fact",
    async () => {
      await seedClubMessage("edit-content");
      const db = clubChatAuthor.firestore();
      await assertFails(
        updateDoc(doc(db, `${CLUB_CHAT_MESSAGES}/edit-content`), {
          content: "something entirely different",
        }),
      );
    },
  );

  await check(
    "DEFECT 2 CLUB CHAT: an author cannot rewrite senderName on their own message",
    async () => {
      await seedClubMessage("edit-name");
      const db = clubChatAuthor.firestore();
      await assertFails(
        updateDoc(doc(db, `${CLUB_CHAT_MESSAGES}/edit-name`), {
          senderName: "YO Voice Support",
        }),
      );
    },
  );

  await check(
    "DEFECT 2 CLUB CHAT: an author cannot move sentAt to re-order their message in the channel",
    async () => {
      await seedClubMessage("edit-sentat");
      const db = clubChatAuthor.firestore();
      await assertFails(
        updateDoc(doc(db, `${CLUB_CHAT_MESSAGES}/edit-sentat`), {
          sentAt: Timestamp.fromMillis(1_900_000_000_000),
        }),
      );
    },
  );

  await check(
    "DEFECT 2 CLUB CHAT: an author cannot smuggle an unlisted field onto a message while removing it",
    async () => {
      await seedClubMessage("smuggle-field");
      const db = clubChatAuthor.firestore();
      await assertFails(
        updateDoc(doc(db, `${CLUB_CHAT_MESSAGES}/smuggle-field`), {
          ...legacyRemoval(),
          senderIsStaff: true,
        }),
      );
    },
  );

  await check(
    "DEFECT 2 CLUB CHAT: a removal cannot name somebody else as the remover",
    async () => {
      await seedClubMessage("frame-mod");
      const db = clubChatAuthor.firestore();
      await assertFails(
        updateDoc(doc(db, `${CLUB_CHAT_MESSAGES}/frame-mod`), {
          ...legacyRemoval(),
          deletedBy: "ccm-mod",
          deletedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "DEFECT 2 CLUB CHAT: a deletedBy PLANTED at create time cannot survive a later self-removal — affectedKeys() never sees an unchanged field",
    async () => {
      // SECURITY.md principle 6: diff().affectedKeys() reports only
      // fields whose VALUE changed, so a guard gated on hasAny() is
      // skipped by resending the stored value or omitting the field.
      // The attribution check therefore reads the POST-WRITE document.
      await seedClubMessage("planted-attribution", { deletedBy: "ccm-mod" });
      const db = clubChatAuthor.firestore();
      await assertFails(
        updateDoc(
          doc(db, `${CLUB_CHAT_MESSAGES}/planted-attribution`),
          legacyRemoval(),
        ),
      );
    },
  );

  await check(
    "DEFECT 2 CLUB CHAT: a removal cannot back-date deletedAt or editedAt",
    async () => {
      await seedClubMessage("backdated");
      const db = clubChatAuthor.firestore();
      await assertFails(
        updateDoc(doc(db, `${CLUB_CHAT_MESSAGES}/backdated`), {
          content: "",
          isDeleted: true,
          editedAt: Timestamp.fromMillis(1_600_000_000_000),
          deletedBy: "ccm-author",
          deletedAt: Timestamp.fromMillis(1_600_000_000_000),
        }),
      );
    },
  );

  await check(
    "DEFECT 2 CLUB CHAT: an already-removed message cannot be re-attributed to a different remover",
    async () => {
      await seedClubMessage("reattribute", {
        content: "",
        isDeleted: true,
        deletedBy: "ccm-mod",
        deletedAt: CHAT_SENT_AT,
      });
      const db = clubChatAuthor.firestore();
      await assertFails(
        updateDoc(doc(db, `${CLUB_CHAT_MESSAGES}/reattribute`), {
          deletedBy: "ccm-author",
          deletedAt: serverTimestamp(),
          editedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "DEFECT 2 CLUB CHAT: a removed message cannot be un-removed and refilled with content",
    async () => {
      await seedClubMessage("undelete", {
        content: "",
        isDeleted: true,
        deletedBy: "ccm-author",
        deletedAt: CHAT_SENT_AT,
      });
      const db = clubChatAuthor.firestore();
      await assertFails(
        updateDoc(doc(db, `${CLUB_CHAT_MESSAGES}/undelete`), {
          content: "back again",
          isDeleted: false,
          editedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "DEFECT 2 CLUB CHAT: a MODERATOR cannot use the removal path to edit somebody else's words",
    async () => {
      await seedClubMessage("mod-rewrites");
      const db = clubChatMod.firestore();
      await assertFails(
        updateDoc(doc(db, `${CLUB_CHAT_MESSAGES}/mod-rewrites`), {
          content: "I confess to everything",
          isDeleted: true,
          editedAt: serverTimestamp(),
          deletedBy: "ccm-mod",
          deletedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "DEFECT 2 CLUB CHAT: a MODERATOR cannot re-attribute authorship while removing a message",
    async () => {
      await seedClubMessage("mod-reassigns");
      const db = clubChatMod.firestore();
      await assertFails(
        updateDoc(doc(db, `${CLUB_CHAT_MESSAGES}/mod-reassigns`), {
          content: "",
          isDeleted: true,
          editedAt: serverTimestamp(),
          deletedBy: "ccm-mod",
          deletedAt: serverTimestamp(),
          senderId: "ccm-peer",
          senderName: "ccm-peer",
        }),
      );
    },
  );

  // --- the moderator branch's own guards ---

  await check(
    "SECURITY CLUB CHAT: a moderator removal carrying NO attribution is refused — the actor is not derivable from someone else's message",
    async () => {
      await seedClubMessage("mod-anonymous");
      const db = clubChatMod.firestore();
      await assertFails(
        updateDoc(
          doc(db, `${CLUB_CHAT_MESSAGES}/mod-anonymous`),
          legacyRemoval(),
        ),
      );
    },
  );

  await check(
    "SECURITY CLUB CHAT: a moderator cannot attribute a removal to another moderator",
    async () => {
      await seedClubMessage("mod-frames-admin");
      const db = clubChatMod.firestore();
      await assertFails(
        updateDoc(doc(db, `${CLUB_CHAT_MESSAGES}/mod-frames-admin`), {
          content: "",
          isDeleted: true,
          editedAt: serverTimestamp(),
          deletedBy: "ccm-admin",
          deletedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "SECURITY CLUB CHAT: a plain MEMBER cannot remove another member's message",
    async () => {
      await seedClubMessage("peer-removes");
      const db = clubChatPeer.firestore();
      await assertFails(
        updateDoc(doc(db, `${CLUB_CHAT_MESSAGES}/peer-removes`), {
          content: "",
          isDeleted: true,
          editedAt: serverTimestamp(),
          deletedBy: "ccm-peer",
          deletedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "SECURITY CLUB CHAT: a NON-MEMBER cannot remove a club message",
    async () => {
      await seedClubMessage("outsider-removes");
      const db = clubChatOutsider.firestore();
      await assertFails(
        updateDoc(doc(db, `${CLUB_CHAT_MESSAGES}/outsider-removes`), {
          content: "",
          isDeleted: true,
          editedAt: serverTimestamp(),
          deletedBy: "ccm-outsider",
          deletedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "SECURITY CLUB CHAT: a PLATFORM-BANNED moderator cannot moderate — a branch does not inherit its helpers' status checks",
    async () => {
      await seedClubMessage("banned-mod-removes");
      const db = clubChatBannedMod.firestore();
      await assertFails(
        updateDoc(doc(db, `${CLUB_CHAT_MESSAGES}/banned-mod-removes`), {
          content: "",
          isDeleted: true,
          editedAt: serverTimestamp(),
          deletedBy: "ccm-banned-mod",
          deletedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "SECURITY CLUB CHAT: a DISABLED moderator cannot moderate — isRestrictedAccount() reads `banned` only, so `disabled` needs its own check",
    async () => {
      await seedClubMessage("disabled-mod-removes");
      const db = clubChatDisabledMod.firestore();
      await assertFails(
        updateDoc(doc(db, `${CLUB_CHAT_MESSAGES}/disabled-mod-removes`), {
          content: "",
          isDeleted: true,
          editedAt: serverTimestamp(),
          deletedBy: "ccm-disabled-mod",
          deletedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "SECURITY CLUB CHAT: a COMMUNICATION-MUTED moderator cannot moderate — the sanction's whole lifecycle was bypassed on this path",
    async () => {
      await seedClubMessage("muted-mod");
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "restrictions/ccm-mod"), {
          type: "communicationMute",
          expiresAt: null,
        });
      });
      await assertFails(
        updateDoc(
          doc(clubChatMod.firestore(), `${CLUB_CHAT_MESSAGES}/muted-mod`),
          {
            content: "",
            isDeleted: true,
            editedAt: serverTimestamp(),
            deletedBy: "ccm-mod",
            deletedAt: serverTimestamp(),
          },
        ),
      );
      // ...and the mute does NOT cost them their own retraction. That
      // asymmetry is deliberate: a sanction on speech that leaves a
      // member unable to take back what they said increases the harm
      // still on screen.
      await seedClubMessage("muted-mod-own", {
        senderId: "ccm-mod",
        senderName: "ccm-mod",
      });
      await assertSucceeds(
        updateDoc(
          doc(clubChatMod.firestore(), `${CLUB_CHAT_MESSAGES}/muted-mod-own`),
          legacyRemoval(),
        ),
      );
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await deleteDoc(doc(ctx.firestore(), "restrictions/ccm-mod"));
      });
    },
  );

  await check(
    "SECURITY CLUB CHAT: an UNVERIFIED moderator cannot moderate, but can still retract their own message",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, "users/ccm-unverified-mod"), {
          displayName: "ccm-unverified-mod",
          banned: false,
        });
        await setDoc(doc(db, `${CLUB_CHAT}/members/ccm-unverified-mod`), {
          userId: "ccm-unverified-mod",
          role: "moderator",
          banned: false,
        });
      });
      const unverifiedMod = testEnv.authenticatedContext("ccm-unverified-mod", {
        email_verified: false,
      });
      await seedClubMessage("unverified-mod");
      await assertFails(
        updateDoc(
          doc(unverifiedMod.firestore(), `${CLUB_CHAT_MESSAGES}/unverified-mod`),
          {
            content: "",
            isDeleted: true,
            editedAt: serverTimestamp(),
            deletedBy: "ccm-unverified-mod",
            deletedAt: serverTimestamp(),
          },
        ),
      );
      await seedClubMessage("unverified-mod-own", {
        senderId: "ccm-unverified-mod",
        senderName: "ccm-unverified-mod",
      });
      await assertSucceeds(
        updateDoc(
          doc(
            unverifiedMod.firestore(),
            `${CLUB_CHAT_MESSAGES}/unverified-mod-own`,
          ),
          legacyRemoval(),
        ),
      );
    },
  );

  await check(
    "regression CLUB CHAT: the two branches are DISJOINT — a moderator removing their OWN message goes through the author branch and still works",
    async () => {
      await seedClubMessage("mod-own-message", {
        senderId: "ccm-mod",
        senderName: "ccm-mod",
      });
      await assertSucceeds(
        updateDoc(
          doc(clubChatMod.firestore(), `${CLUB_CHAT_MESSAGES}/mod-own-message`),
          legacyRemoval(),
        ),
      );
    },
  );

  await check(
    "SECURITY CLUB CHAT: a CLUB-BANNED moderator cannot moderate",
    async () => {
      await seedClubMessage("club-banned-mod");
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await updateDoc(
          doc(ctx.firestore(), `${CLUB_CHAT}/members/ccm-mod`),
          { banned: true },
        );
      });
      const db = clubChatMod.firestore();
      await assertFails(
        updateDoc(doc(db, `${CLUB_CHAT_MESSAGES}/club-banned-mod`), {
          content: "",
          isDeleted: true,
          editedAt: serverTimestamp(),
          deletedBy: "ccm-mod",
          deletedAt: serverTimestamp(),
        }),
      );
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await updateDoc(
          doc(ctx.firestore(), `${CLUB_CHAT}/members/ccm-mod`),
          { banned: false },
        );
      });
    },
  );

  await check(
    "SECURITY CLUB CHAT: moderation does not survive the club being suspended or scheduled for deletion",
    async () => {
      await seedClubMessage("suspended-club");
      const db = clubChatMod.firestore();
      for (const clubState of [
        { status: "suspended", deletionInProgress: false },
        { status: "active", deletionInProgress: true },
      ]) {
        await testEnv.withSecurityRulesDisabled(async (ctx) => {
          await updateDoc(doc(ctx.firestore(), CLUB_CHAT), clubState);
        });
        await assertFails(
          updateDoc(doc(db, `${CLUB_CHAT_MESSAGES}/suspended-club`), {
            content: "",
            isDeleted: true,
            editedAt: serverTimestamp(),
            deletedBy: "ccm-mod",
            deletedAt: serverTimestamp(),
          }),
        );
      }
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await updateDoc(doc(ctx.firestore(), CLUB_CHAT), {
          status: "active",
          deletionInProgress: false,
        });
      });
    },
  );

  await check(
    "SECURITY CLUB CHAT: moderating one club grants nothing in another",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), "clubs/chatmod-other/channels/general/messages/m1"),
          {
            clubId: "chatmod-other",
            channelId: "general",
            senderId: "ccm-peer",
            senderName: "ccm-peer",
            senderPhotoUrl: null,
            content: "not your club",
            sentAt: CHAT_SENT_AT,
            editedAt: null,
            isDeleted: false,
          },
        );
      });
      const db = clubChatMod.firestore();
      await assertFails(
        updateDoc(
          doc(db, "clubs/chatmod-other/channels/general/messages/m1"),
          {
            content: "",
            isDeleted: true,
            editedAt: serverTimestamp(),
            deletedBy: "ccm-mod",
            deletedAt: serverTimestamp(),
          },
        ),
      );
    },
  );

  await check(
    "SECURITY CLUB CHAT: a moderator cannot remove the club OWNER's own message",
    async () => {
      await seedClubMessage("owner-authored", {
        senderId: "ccm-owner",
        senderName: "ccm-owner",
        content: "the owner's announcement",
      });
      const db = clubChatMod.firestore();
      await assertFails(
        updateDoc(doc(db, `${CLUB_CHAT_MESSAGES}/owner-authored`), {
          content: "",
          isDeleted: true,
          editedAt: serverTimestamp(),
          deletedBy: "ccm-mod",
          deletedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "regression CLUB CHAT: the OWNER can still remove their OWN message — the owner-message boundary is not a trap for the owner",
    async () => {
      await seedClubMessage("owner-self", {
        senderId: "ccm-owner",
        senderName: "ccm-owner",
        content: "the owner's announcement",
      });
      const db = clubChatOwner.firestore();
      await assertSucceeds(
        updateDoc(
          doc(db, `${CLUB_CHAT_MESSAGES}/owner-self`),
          legacyRemoval(),
        ),
      );
    },
  );

  // --- backward compatibility with what is deployed right now ---

  await check(
    "regression CLUB CHAT: the CURRENTLY DEPLOYED client's self-delete write still succeeds — content/isDeleted/editedAt with no attribution",
    async () => {
      // ClubChatService.deleteMessage sends exactly this today. If a
      // rules deploy landed before the app's next release and this
      // failed, every member would lose the ability to retract their own
      // message: an outage, not a hardening.
      await seedClubMessage("legacy-self-delete");
      const db = clubChatAuthor.firestore();
      await assertSucceeds(
        updateDoc(
          doc(db, `${CLUB_CHAT_MESSAGES}/legacy-self-delete`),
          legacyRemoval(),
        ),
      );
    },
  );

  await check(
    "regression CLUB CHAT: an author's ATTRIBUTED self-removal succeeds, so the client can start sending deletedBy/deletedAt without a second rules change",
    async () => {
      await seedClubMessage("attributed-self-delete");
      const db = clubChatAuthor.firestore();
      await assertSucceeds(
        updateDoc(doc(db, `${CLUB_CHAT_MESSAGES}/attributed-self-delete`), {
          content: "",
          isDeleted: true,
          editedAt: serverTimestamp(),
          deletedBy: "ccm-author",
          deletedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "regression CLUB CHAT: a LEGACY member document carrying no `role` field can still retract its own message — the moderator branch's clubRole() lookup must not take the author branch down with it",
    async () => {
      // `allow update` is an OR of two complete predicates. The second
      // calls clubRole(), which reads `.data.role` directly and errors
      // on a member document that predates the field. If that error
      // propagated through the OR, every such member would silently lose
      // the ability to delete their own message — a regression with no
      // attacker, which is exactly the failure mode ADR-056 was about.
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, `${CLUB_CHAT}/members/ccm-legacy`), {
          userId: "ccm-legacy",
        });
        await setDoc(doc(db, "users/ccm-legacy"), {
          displayName: "ccm-legacy",
          banned: false,
        });
      });
      await seedClubMessage("legacy-role", {
        senderId: "ccm-legacy",
        senderName: "ccm-legacy",
      });
      const legacy = testEnv.authenticatedContext("ccm-legacy", {
        email_verified: true,
      });
      await assertSucceeds(
        updateDoc(
          doc(legacy.firestore(), `${CLUB_CHAT_MESSAGES}/legacy-role`),
          legacyRemoval(),
        ),
      );
      // ...and the same role-less document buys no moderator authority:
      // the missing role fails CLOSED on the branch that needs it.
      await seedClubMessage("legacy-role-mod");
      await assertFails(
        updateDoc(
          doc(legacy.firestore(), `${CLUB_CHAT_MESSAGES}/legacy-role-mod`),
          {
            content: "",
            isDeleted: true,
            editedAt: serverTimestamp(),
            deletedBy: "ccm-legacy",
            deletedAt: serverTimestamp(),
          },
        ),
      );
    },
  );

  await check(
    "regression CLUB CHAT: callable-created messages remain readable through the production ordered query",
    async () => {
      const db = clubChatAuthor.firestore();
      await assertFails(
        addDoc(collection(db, CLUB_CHAT_MESSAGES), {
          clubId: "chatmod-club",
          channelId: "general",
          senderId: "ccm-author",
          senderName: "ccm-author",
          senderPhotoUrl: null,
          content: "direct bypass",
          sentAt: Timestamp.now(),
          editedAt: null,
          isDeleted: false,
        }),
      );
      await seedClubMessage("callable-created", { content: "hello club" });
      const snapshot = await assertSucceeds(
        getDocs(
          query(
            collection(db, CLUB_CHAT_MESSAGES),
            orderBy("sentAt", "desc"),
            limit(250),
          ),
        ),
      );
      if (snapshot.size < 1) throw new Error("expected messages back");
    },
  );

  await check(
    "PROOF CLUB CHAT: club messages are NOT reachable through collectionGroup('messages') — this fix widened a NESTED rule and added no top-level wildcard",
    async () => {
      // ADR-007: a nested match cannot authorize a collectionGroup()
      // query, and a top-level wildcard that could would fail OPEN —
      // handing every club's private chat to any signed-in account. The
      // app reads club chat per-channel (ClubChatService.watchMessages),
      // so no such wildcard exists, and this asserts it still doesn't.
      const db = clubChatMod.firestore();
      await assertFails(
        getDocs(
          query(
            collectionGroup(db, "messages"),
            where("clubId", "==", "chatmod-club"),
          ),
        ),
      );
    },
  );

  // Moderator/owner/admin writes intentionally have no client-side
  // discriminator anymore: the entire branch is `false`. The callable tests
  // cover rank, attribution, audit records and idempotency; the rule tests
  // above prove that no crafted update can bypass that server authority.

  await check(
    "SECURITY CLUB CHAT: a removal that omits editedAt is refused — every field a removal may touch is pinned, so none of them is the caller's choice",
    async () => {
      await seedClubMessage("no-editedat");
      const db = clubChatAuthor.firestore();
      await assertFails(
        updateDoc(doc(db, `${CLUB_CHAT_MESSAGES}/no-editedat`), {
          content: "",
          isDeleted: true,
        }),
      );
    },
  );

  // --- real collectionGroup() queries, not just direct doc reads ---
  //
  // A nested `match /parent/{id}/collection/{doc}` rule ONLY covers reads/
  // writes scoped to one specific parent. It does NOT authorize an actual
  // collectionGroup() query (which scans that collection name across every
  // parent) — Firestore rejects those outright as permission-denied unless a
  // separate top-level `match /{path=**}/collection/{doc}` rule also exists.
  // The cases above only ever call getDoc() on a fully-specified path, so
  // they'd stay green even if the wildcard rules were deleted — these two
  // are what actually catch that regression.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "rooms/cg-room1"), {
      hostId: "host-uid",
      roomType: "community",
      isActive: true,
    });
    await setDoc(doc(ctx.firestore(), "rooms/cg-room1/roomMembers/attacker-uid"), {
      userId: "attacker-uid",
    });
    await setDoc(doc(ctx.firestore(), "clubs/cg-club1"), {
      ownerId: "host-uid",
      status: "active",
    });
    await setDoc(doc(ctx.firestore(), "clubs/cg-club1/invites/attacker-uid"), {
      inviteeId: "attacker-uid",
      inviterId: "host-uid",
      status: "pending",
    });
  });

  await check(
    "regression: watchMyCommunities() collectionGroup('roomMembers') query succeeds",
    async () => {
      const db = attacker.firestore();
      const q = query(
        collectionGroup(db, "roomMembers"),
        where("userId", "==", "attacker-uid"),
      );
      const snapshot = await assertSucceeds(getDocs(q));
      if (snapshot.size < 1) throw new Error("expected at least 1 doc back");
    },
  );

  await check(
    "regression: watchMyClubInvites() collectionGroup('invites') query succeeds",
    async () => {
      const db = attacker.firestore();
      const q = query(
        collectionGroup(db, "invites"),
        where("inviteeId", "==", "attacker-uid"),
      );
      const snapshot = await assertSucceeds(getDocs(q));
      if (snapshot.size < 1) throw new Error("expected at least 1 doc back");
    },
  );

  await check(
    "SECURITY: collectionGroup('roomMembers') query cannot be filtered to someone else's userId",
    async () => {
      const db = attacker.firestore();
      const q = query(
        collectionGroup(db, "roomMembers"),
        where("userId", "==", "host-uid"),
      );
      await assertFails(getDocs(q));
    },
  );

  // --- blocking ---
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users/blocker-uid"), {
      displayName: "Blocker",
    });
    await setDoc(doc(ctx.firestore(), "users/blockee-uid"), {
      displayName: "Blockee",
    });
    await setDoc(doc(ctx.firestore(), "users/blocker-uid/blocked/blockee-uid"), {
      userId: "blockee-uid",
    });
  });

  const blocker = testEnv.authenticatedContext("blocker-uid", {
    email_verified: true,
  });
  const blockee = testEnv.authenticatedContext("blockee-uid", {
    email_verified: true,
  });
  const stranger = testEnv.authenticatedContext("stranger-uid", {
    email_verified: true,
  });

  await check(
    "SECURITY: block edges are server-write-only",
    async () => {
      const db = stranger.firestore();
      await assertFails(
        setDoc(doc(db, "users/stranger-uid/blocked/host-uid"), {
          userId: "host-uid",
          createdAt: serverTimestamp(),
        }),
      );
      await assertFails(
        deleteDoc(doc(blocker.firestore(), "users/blocker-uid/blocked/blockee-uid")),
      );
    },
  );

  await check(
    "SECURITY: a blocked user cannot send a friend request to their blocker",
    async () => {
      const db = blockee.firestore();
      const ref = doc(db, "users/blocker-uid/friendRequests/blockee-uid");
      await assertFails(
        setDoc(ref, { senderId: "blockee-uid", createdAt: new Date() }),
      );
    },
  );

  await check(
    "SECURITY: a blocker cannot send a friend request to someone they blocked",
    async () => {
      const db = blocker.firestore();
      const ref = doc(db, "users/blockee-uid/friendRequests/blocker-uid");
      await assertFails(
        setDoc(ref, { senderId: "blocker-uid", createdAt: new Date() }),
      );
    },
  );

  await check(
    "SECURITY: even an unrelated user must use the friend-request callable",
    async () => {
      const db = stranger.firestore();
      const ref = doc(db, "users/blocker-uid/friendRequests/stranger-uid");
      await assertFails(
        setDoc(ref, { senderId: "stranger-uid", createdAt: new Date() }),
      );
    },
  );

  await check(
    "SECURITY: a blocked user cannot follow their blocker",
    async () => {
      const db = blockee.firestore();
      const ref = doc(db, "users/blockee-uid/following/blocker-uid");
      await assertFails(setDoc(ref, { uid: "blocker-uid" }));
    },
  );

  await check(
    "SECURITY: nobody but the owner can read a user's blocked list",
    async () => {
      const db = stranger.firestore();
      const ref = doc(db, "users/blocker-uid/blocked/blockee-uid");
      await assertFails(getDoc(ref));
    },
  );

  await check(
    "SECURITY: a blocked user cannot start a new conversation with their blocker",
    async () => {
      const db = blockee.firestore();
      const ref = doc(db, "conversations/blocked-convo-1");
      await assertFails(
        setDoc(ref, { participantIds: ["blocker-uid", "blockee-uid"] }),
      );
    },
  );

  // --- messages: edit / delete / reactions / read receipts ---
  // Every supported mutation is server-authoritative. The callable validates
  // account state, sanctions, blocks, media identity and root/message shape;
  // a participant may never bypass that boundary with a direct SDK update.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "conversations/convo-1"), {
      participantIds: ["host-uid", "invitee-uid"],
    });
    await setDoc(doc(ctx.firestore(), "conversations/convo-1/messages/msg-1"), {
      senderId: "host-uid",
      content: "hello",
      readBy: ["host-uid"],
      reactions: {},
      isDeleted: false,
      editedAt: null,
    });
  });

  await check("SECURITY: sender cannot bypass callable message editing", async () => {
    const db = host.firestore();
    const ref = doc(db, "conversations/convo-1/messages/msg-1");
    await assertFails(
      updateDoc(ref, { content: "edited", editedAt: new Date() }),
    );
  });

  await check(
    "SECURITY: a non-sender cannot edit someone else's message",
    async () => {
      const db = invitee.firestore();
      const ref = doc(db, "conversations/convo-1/messages/msg-1");
      await assertFails(
        updateDoc(ref, { content: "hijacked", editedAt: new Date() }),
      );
    },
  );

  await check(
    "SECURITY: sender cannot bypass callable soft-delete",
    async () => {
      const db = host.firestore();
      const ref = doc(db, "conversations/convo-1/messages/msg-1");
      await assertFails(
        updateDoc(ref, {
          content: "",
          mediaUrl: null,
          isDeleted: true,
          editedAt: new Date(),
          reactions: {},
        }),
      );
    },
  );

  await check(
    "SECURITY: participant cannot bypass callable reaction mutation",
    async () => {
      const db = invitee.firestore();
      const ref = doc(db, "conversations/convo-1/messages/msg-1");
      await assertFails(
        updateDoc(ref, { "reactions.invitee-uid": "🔥" }),
      );
    },
  );

  await check(
    "SECURITY: a participant cannot set a reaction under someone else's key",
    async () => {
      const db = invitee.firestore();
      const ref = doc(db, "conversations/convo-1/messages/msg-1");
      await assertFails(updateDoc(ref, { "reactions.host-uid": "😡" }));
    },
  );

  await check(
    "SECURITY: participant cannot bypass callable read receipt mutation",
    async () => {
      const db = invitee.firestore();
      const ref = doc(db, "conversations/convo-1/messages/msg-1");
      await assertFails(
        updateDoc(ref, { readBy: ["host-uid", "invitee-uid"] }),
      );
    },
  );

  await check(
    "SECURITY: readBy cannot be used to remove an existing reader",
    async () => {
      const db = invitee.firestore();
      const ref = doc(db, "conversations/convo-1/messages/msg-1");
      await assertFails(updateDoc(ref, { readBy: ["invitee-uid"] }));
    },
  );

  await check(
    "SECURITY: readBy cannot be used to add someone else's uid on their behalf",
    async () => {
      const db = invitee.firestore();
      const ref = doc(db, "conversations/convo-1/messages/msg-1");
      await assertFails(
        updateDoc(ref, { readBy: ["host-uid", "invitee-uid", "attacker-uid"] }),
      );
    },
  );

  // --- delete-for-me: the per-participant read cut-off ---
  //
  // "Delete chat" removes a conversation for the person who asked and nobody
  // else, so the message documents survive and the READ rule is the whole of
  // the guarantee. These cases run the production-shaped queries — the list
  // the chat screen issues, the paged media list, and a direct get — because
  // a rule that only ever gets exercised by a single-document read proves
  // nothing about the query path a real client takes (ADR-007).
  const deleterConvo = "conversations/convo-deleted";
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, deleterConvo), {
      participantIds: ["host-uid", "invitee-uid"],
      // host deleted through sequence 2; invitee never deleted anything.
      deletedBy: ["host-uid"],
      deletedSequences: { "host-uid": 2, "invitee-uid": 0 },
      lastMessageSequence: 4,
    });
    for (let index = 1; index <= 4; index += 1) {
      await setDoc(doc(db, `${deleterConvo}/messages/m${index}`), {
        senderId: index % 2 === 0 ? "host-uid" : "invitee-uid",
        sequence: index,
        type: index === 4 ? "image" : "text",
        content: `message ${index}`,
        sentAt: Timestamp.fromMillis(1_800_000_000_000 + index * 1000),
        readBy: [],
        reactions: {},
        isDeleted: false,
      });
    }
  });

  await check(
    "DELETE-FOR-ME: the deleter's unconstrained message list is refused",
    async () => {
      // Rules are not filters. Without the matching bound the whole query is
      // denied rather than quietly returning the deleted history.
      await assertFails(
        getDocs(query(collection(host.firestore(), `${deleterConvo}/messages`))),
      );
    },
  );

  await check(
    "DELETE-FOR-ME: the deleter sees only what arrived after their cut-off",
    async () => {
      const snapshot = await assertSucceeds(
        getDocs(query(
          collection(host.firestore(), `${deleterConvo}/messages`),
          where("sequence", ">", 2),
          orderBy("sequence", "desc"),
          limit(250),
        )),
      );
      assert.deepEqual(
        snapshot.docs.map((document) => document.data().sequence).sort(),
        [3, 4],
      );
    },
  );

  await check(
    "DELETE-FOR-ME: the deleter cannot ask for a LOWER bound and get history back",
    async () => {
      await assertFails(
        getDocs(query(
          collection(host.firestore(), `${deleterConvo}/messages`),
          where("sequence", ">", 0),
          orderBy("sequence", "desc"),
        )),
      );
    },
  );

  await check(
    "DELETE-FOR-ME: the deleter cannot get a deleted message by id",
    async () => {
      await assertFails(
        getDoc(doc(host.firestore(), `${deleterConvo}/messages/m1`)),
      );
      await assertSucceeds(
        getDoc(doc(host.firestore(), `${deleterConvo}/messages/m3`)),
      );
    },
  );

  await check(
    "DELETE-FOR-ME: the shared-media query is bounded by the cut-off too",
    async () => {
      const snapshot = await assertSucceeds(
        getDocs(query(
          collection(host.firestore(), `${deleterConvo}/messages`),
          where("type", "==", "image"),
          where("sequence", ">", 2),
          orderBy("sequence", "desc"),
          limit(48),
        )),
      );
      assert.deepEqual(snapshot.docs.map((document) => document.id), ["m4"]);
      await assertFails(
        getDocs(query(
          collection(host.firestore(), `${deleterConvo}/messages`),
          where("type", "==", "image"),
          orderBy("sentAt", "desc"),
          limit(48),
        )),
      );
    },
  );

  await check(
    "DELETE-FOR-ME: the OTHER participant keeps the entire thread, unchanged",
    async () => {
      // The whole point: one participant deleting must not narrow, hide or
      // constrain anything for the other. Their ordinary unconstrained query
      // still returns all four messages.
      const snapshot = await assertSucceeds(
        getDocs(query(
          collection(invitee.firestore(), `${deleterConvo}/messages`),
          orderBy("sentAt", "desc"),
          limit(250),
        )),
      );
      assert.equal(snapshot.docs.length, 4);
      await assertSucceeds(
        getDoc(doc(invitee.firestore(), `${deleterConvo}/messages/m1`)),
      );
    },
  );

  await check(
    "SECURITY: a participant cannot hide the OTHER participant's messages",
    async () => {
      // Writing `deletedSequences` for the peer would delete their chat out
      // from under them; writing it for yourself would let you lower your own
      // cut-off and read back what you deleted. The root is server-only, so
      // both are refused, from either side.
      await assertFails(
        updateDoc(doc(invitee.firestore(), deleterConvo), {
          "deletedSequences.host-uid": 4,
        }),
      );
      await assertFails(
        updateDoc(doc(invitee.firestore(), deleterConvo), {
          deletedBy: ["host-uid", "invitee-uid"],
        }),
      );
      await assertFails(
        updateDoc(doc(host.firestore(), deleterConvo), {
          "deletedSequences.host-uid": 0,
        }),
      );
      await assertFails(
        updateDoc(doc(host.firestore(), deleterConvo), { deletedBy: [] }),
      );
    },
  );

  await check(
    "DELETE-FOR-ME: a conversation nobody deleted keeps its plain query",
    async () => {
      // The compatibility short circuit. Every install in the wild issues the
      // unconstrained `sentAt` query; a root with no deletion state at all
      // must keep serving it.
      const snapshot = await assertSucceeds(
        getDocs(query(
          collection(host.firestore(), "conversations/convo-1/messages"),
          limit(250),
        )),
      );
      assert.equal(snapshot.docs.length, 1);
    },
  );

  // --- Notifications (users/{userId}/notifications/{notificationId}) ---

  await check(
    "SECURITY: no notification type remains client-creatable",
    async () => {
      const db = host.firestore();
      const ref = doc(db, "users/invitee-uid/notifications/notif-1");
      await assertFails(
        setDoc(ref, {
          type: "clubInvite",
          actorId: "host-uid",
          actorName: "Host",
          actorPhotoUrl: null,
          targetId: null,
          targetLabel: null,
          isRead: false,
          createdAt: new Date(),
          dedupeKey: null,
        }),
      );
    },
  );

  // Seed the canonical server-authored row used by the owner read/update/
  // delete regressions below. Admin SDK writers bypass client rules.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users/invitee-uid/notifications/notif-1"), {
      type: "clubInvite",
      actorId: "host-uid",
      actorName: "Host",
      actorPhotoUrl: null,
      targetId: "club-1",
      targetLabel: "Club",
      isRead: false,
      createdAt: new Date(),
      dedupeKey: "clubInvite_club-1_invitee-uid",
    });
  });

  await check(
    "SECURITY: cannot forge a notification claiming to be sent by someone else",
    async () => {
      const db = attacker.firestore();
      const ref = doc(db, "users/invitee-uid/notifications/notif-forged");
      await assertFails(
        setDoc(ref, {
          type: "friendRequest",
          actorId: "host-uid",
          actorName: "Host",
          actorPhotoUrl: null,
          targetId: null,
          targetLabel: null,
          isRead: false,
          createdAt: new Date(),
        }),
      );
    },
  );

  await check(
    "SECURITY: cannot notify yourself",
    async () => {
      const db = host.firestore();
      const ref = doc(db, "users/host-uid/notifications/notif-self");
      await assertFails(
        setDoc(ref, {
          type: "friendRequest",
          actorId: "host-uid",
          actorName: "Host",
          actorPhotoUrl: null,
          targetId: null,
          targetLabel: null,
          isRead: false,
          createdAt: new Date(),
        }),
      );
    },
  );

  await check(
    "SECURITY: a client cannot forge a trusted 'system' or 'moderation' notification",
    async () => {
      const db = host.firestore();
      const ref = doc(db, "users/invitee-uid/notifications/notif-system");
      await assertFails(
        setDoc(ref, {
          type: "system",
          actorId: "host-uid",
          actorName: "Host",
          actorPhotoUrl: null,
          targetId: null,
          targetLabel: "You win",
          isRead: false,
          createdAt: new Date(),
        }),
      );
    },
  );

  await check(
    "SECURITY: a notification cannot carry an unlisted field",
    async () => {
      const db = host.firestore();
      const ref = doc(db, "users/invitee-uid/notifications/notif-extra");
      await assertFails(
        setDoc(ref, {
          type: "friendRequest",
          actorId: "host-uid",
          actorName: "Host",
          actorPhotoUrl: null,
          targetId: null,
          targetLabel: null,
          isRead: false,
          createdAt: new Date(),
          body: "click here",
        }),
      );
    },
  );

  // Suppression authority: the RECIPIENT's own friends list must contain
  // the sender — seed that canonical doc for the friend case only.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(
      doc(ctx.firestore(), "users/invitee-uid/friends/host-uid"),
      { uid: "host-uid", displayName: "Host" },
    );
  });

  await check(
    "SECURITY: even a friend cannot forge a server-derived DM notification",
    async () => {
      const db = host.firestore();
      const ref = doc(db, "users/invitee-uid/notifications/notif-dm-suppressed");
      await assertFails(
        setDoc(ref, {
          type: "directMessage",
          actorId: "host-uid",
          actorName: "Host",
          actorPhotoUrl: null,
          targetId: "conversation-1",
          targetLabel: null,
          isRead: false,
          createdAt: new Date(),
          dedupeKey: null,
          bellSuppressed: true,
        }),
      );
    },
  );

  await check(
    "SECURITY: a NON-FRIEND cannot suppress their message from the bell",
    async () => {
      // attacker-uid is not in invitee-uid's friends list — hiding a
      // message request from the recipient's bell must be denied.
      const db = attacker.firestore();
      const ref = doc(db, "users/invitee-uid/notifications/notif-dm-sneak");
      await assertFails(
        setDoc(ref, {
          type: "directMessage",
          actorId: "attacker-uid",
          actorName: "Attacker",
          actorPhotoUrl: null,
          targetId: "conversation-2",
          targetLabel: null,
          isRead: false,
          createdAt: new Date(),
          dedupeKey: null,
          bellSuppressed: true,
        }),
      );
    },
  );

  await check(
    "SECURITY: a non-friend cannot forge a visible message request either",
    async () => {
      const db = attacker.firestore();
      const ref = doc(db, "users/invitee-uid/notifications/notif-dm-request");
      await assertFails(
        setDoc(ref, {
          type: "directMessage",
          actorId: "attacker-uid",
          actorName: "Attacker",
          actorPhotoUrl: null,
          targetId: "conversation-2",
          targetLabel: null,
          isRead: false,
          createdAt: new Date(),
          dedupeKey: null,
          bellSuppressed: false,
        }),
      );
    },
  );

  await check(
    "notification routing: the OWNER can backfill bellSuppressed:false onto a legacy doc",
    async () => {
      // notif-1 was created earlier without the routing field (legacy
      // shape) — the recipient's client stamps it visible.
      const db = invitee.firestore();
      const ref = doc(db, "users/invitee-uid/notifications/notif-1");
      await assertSucceeds(updateDoc(ref, { bellSuppressed: false }));
    },
  );

  await check(
    "SECURITY: a non-owner cannot rewrite someone else's notification routing",
    async () => {
      const db = attacker.firestore();
      const ref = doc(db, "users/invitee-uid/notifications/notif-dm-request");
      await assertFails(updateDoc(ref, { bellSuppressed: true }));
    },
  );

  await check(
    "SECURITY: bellSuppressed must be a bool, not smuggled content",
    async () => {
      const db = host.firestore();
      const ref = doc(db, "users/invitee-uid/notifications/notif-dm-bad-flag");
      await assertFails(
        setDoc(ref, {
          type: "directMessage",
          actorId: "host-uid",
          actorName: "Host",
          actorPhotoUrl: null,
          targetId: "conversation-1",
          targetLabel: null,
          isRead: false,
          createdAt: new Date(),
          dedupeKey: null,
          bellSuppressed: "click here to win",
        }),
      );
    },
  );

  await check(
    "regression: the recipient can read their own notifications",
    async () => {
      const db = invitee.firestore();
      const ref = doc(db, "users/invitee-uid/notifications/notif-1");
      await assertSucceeds(getDoc(ref));
    },
  );

  await check(
    "SECURITY: nobody else can read a user's notifications",
    async () => {
      const db = attacker.firestore();
      const ref = doc(db, "users/invitee-uid/notifications/notif-1");
      await assertFails(getDoc(ref));
    },
  );

  await check(
    "regression: the recipient can mark their own notification read",
    async () => {
      const db = invitee.firestore();
      const ref = doc(db, "users/invitee-uid/notifications/notif-1");
      await assertSucceeds(
        updateDoc(ref, { isRead: true, readAt: new Date() }),
      );
    },
  );

  await check(
    "SECURITY: the recipient cannot rewrite notification authority or push state",
    async () => {
      const db = invitee.firestore();
      const ref = doc(db, "users/invitee-uid/notifications/notif-1");
      await assertFails(updateDoc(ref, { actorId: "invitee-uid" }));
      await assertFails(
        updateDoc(ref, {
          pushDeliveryStatus: "sent",
          pushAttemptCount: 3,
        }),
      );
    },
  );

  await check(
    "SECURITY: nobody else can update a user's notification",
    async () => {
      const db = attacker.firestore();
      const ref = doc(db, "users/invitee-uid/notifications/notif-1");
      await assertFails(updateDoc(ref, { isRead: true }));
    },
  );

  await check(
    "regression: the recipient can delete their own notification",
    async () => {
      const db = invitee.firestore();
      const ref = doc(db, "users/invitee-uid/notifications/notif-1");
      await assertSucceeds(deleteDoc(ref));
    },
  );

  // --- FCM tokens (users/{userId}/fcmTokens/{token}) ---

  await check(
    "regression: a user can register their own FCM token",
    async () => {
      const db = host.firestore();
      const ref = doc(db, "users/host-uid/fcmTokens/token-abc");
      await assertSucceeds(
        setDoc(ref, { platform: "ios", updatedAt: serverTimestamp() }),
      );
    },
  );

  await check(
    "SECURITY: a user cannot register an FCM token under someone else's account",
    async () => {
      const db = attacker.firestore();
      const ref = doc(db, "users/host-uid/fcmTokens/token-hijack");
      await assertFails(
        setDoc(ref, { platform: "ios", updatedAt: serverTimestamp() }),
      );
    },
  );

  await check(
    "SECURITY FCM: platform and freshness are exact server-authoritative fields",
    async () => {
      const db = host.firestore();
      const ref = doc(db, "users/host-uid/fcmTokens/token-shape");
      await assertFails(setDoc(ref, { platform: "desktop" }));
      await assertFails(setDoc(ref, {
        platform: "ios",
        updatedAt: new Date(Date.now() + 86_400_000),
      }));
      await assertFails(setDoc(ref, {
        platform: "android",
        updatedAt: serverTimestamp(),
        ownerId: "attacker-uid",
      }));
      await assertSucceeds(setDoc(ref, {
        platform: "other",
        updatedAt: serverTimestamp(),
      }));
      await assertFails(updateDoc(ref, { platform: "desktop" }));
      await assertSucceeds(updateDoc(ref, {
        platform: "web",
        updatedAt: serverTimestamp(),
      }));
    },
  );

  await check(
    "SECURITY: nobody else can read a user's FCM tokens",
    async () => {
      const db = attacker.firestore();
      const ref = doc(db, "users/host-uid/fcmTokens/token-abc");
      await assertFails(getDoc(ref));
    },
  );

  await check(
    "regression: a user can unregister their own FCM token",
    async () => {
      const db = host.firestore();
      const ref = doc(db, "users/host-uid/fcmTokens/token-abc");
      await assertSucceeds(deleteDoc(ref));
    },
  );

  // --- notificationPreferences (users/{userId} field) ---

  await check(
    "regression: a user can update their own notification preferences",
    async () => {
      const db = host.firestore();
      const ref = doc(db, "users/host-uid");
      await assertSucceeds(
        updateDoc(ref, { "notificationPreferences.friendRequest": false }),
      );
    },
  );

  await check(
    "SECURITY: a user cannot update someone else's notification preferences",
    async () => {
      const db = attacker.firestore();
      const ref = doc(db, "users/host-uid");
      await assertFails(
        updateDoc(ref, { "notificationPreferences.friendRequest": true }),
      );
    },
  );

  // --- isVerified() gate on sensitive/outbound actions ---

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users/unverified-uid"), {
      displayName: "Unverified",
    });
  });

  await check(
    "SECURITY: an unverified user cannot send a friend request",
    async () => {
      const db = unverified.firestore();
      const ref = doc(db, "users/host-uid/friendRequests/unverified-uid");
      await assertFails(
        setDoc(ref, {
          senderId: "unverified-uid",
          senderName: "Unverified",
          senderEmail: "unverified@example.com",
          senderPhotoUrl: null,
          createdAt: new Date(),
        }),
      );
    },
  );

  await check(
    "SECURITY: an unverified user cannot start a conversation",
    async () => {
      const db = unverified.firestore();
      const ref = doc(db, "conversations/unverified-convo");
      await assertFails(
        setDoc(ref, {
          participantIds: ["unverified-uid", "host-uid"],
          createdAt: new Date(),
        }),
      );
    },
  );

  await check(
    "SECURITY: an unverified user cannot send a message in an existing conversation",
    async () => {
      // host-uid + unverified-uid conversation, created with security rules
      // disabled so this test isolates the *message* create rule rather
      // than depending on the (separately tested) conversation create rule.
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "conversations/convo-unverified"), {
          participantIds: ["unverified-uid", "host-uid"],
        });
      });
      const db = unverified.firestore();
      const ref = doc(db, "conversations/convo-unverified/messages/msg-1");
      await assertFails(
        setDoc(ref, {
          senderId: "unverified-uid",
          content: "hello",
          sentAt: new Date(),
          readBy: ["unverified-uid"],
          reactions: {},
          isDeleted: false,
        }),
      );
    },
  );

  await check(
    "SECURITY: even a verified participant cannot send a message — the " +
      "client-direct send is gone (ADR-105)",
    async () => {
      // This case asserted the opposite until ADR-105, and the change is
      // the point: `_sendTextMessageDirectly` used to write this document
      // whenever the callable was unreachable, which skipped every
      // server-side moderation check at once. The send now queues in the
      // local outbox and retries through `sendDirectMessage` instead, so
      // nothing is lost by this denial.
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "conversations/convo-verified"), {
          participantIds: ["host-uid", "invitee-uid"],
        });
      });
      const db = host.firestore();
      const ref = doc(db, "conversations/convo-verified/messages/msg-1");
      await assertFails(
        setDoc(ref, {
          senderId: "host-uid",
          content: "hello",
          sentAt: new Date(),
          readBy: ["host-uid"],
          reactions: {},
          isDeleted: false,
        }),
      );
    },
  );

  // --- Direct messages are SERVER-ONLY (ADR-105) -----------------------
  //
  // `conversations/{id}/messages/{id}` create is `allow create: if false`.
  // `sendDirectMessage` is the sole writer, because the three things that
  // make a direct message legitimate are things this rule cannot both
  // afford and be trusted to check: the SENDER's standing (banned,
  // disabled, staff communicationMute), the RECIPIENT's messagePrivacy and
  // the follow/friendship edges behind it, and the rate limit plus the
  // idempotency ledger that makes a retry safe.
  //
  // The old rule checked isVerified() and the recipient's privacy but NOT
  // the sender's standing, so a banned or communication-muted account kept
  // full direct messaging through the client fallback. Adding the sender
  // check was measured against this emulator and exceeded Firestore's
  // per-request access-call budget — an exhausted rule errors, and an error
  // denies, which broke legitimate friends-mode sends. Hence server-only.
  //
  // These cases pin the DENIAL. What each privacy mode MEANS is proven
  // server-side in functions/test/direct_integrity.test.js, which is now
  // the only place it can be exercised.

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "conversations/privacy-convo"), {
      participantIds: ["host-uid", "invitee-uid"],
    });
  });

  const sendPrivacyProbe = (db, id) => setDoc(
    doc(db, `conversations/privacy-convo/messages/${id}`),
    {
      senderId: "host-uid",
      content: id,
      sentAt: new Date(),
      readBy: ["host-uid"],
      reactions: {},
      isDeleted: false,
    },
  );

  await check(
    "message privacy is owner-writable only and accepts the exact enum",
    async () => {
      const own = invitee.firestore();
      await assertSucceeds(updateDoc(doc(own, "users/invitee-uid"), {
        messagePrivacy: "nobody",
      }));
      await assertFails(updateDoc(doc(own, "users/invitee-uid"), {
        messagePrivacy: "followers",
      }));
      await assertFails(updateDoc(doc(attacker.firestore(), "users/invitee-uid"), {
        messagePrivacy: "everyone",
      }));
    },
  );

  await check(
    "SECURITY: no client may create a direct message, whatever the " +
      "recipient's privacy mode says",
    async () => {
      // Every one of these was ALLOWED by the previous rule: the recipient
      // accepts messages, the pair is unblocked, the sender is verified and
      // is a genuine participant. They are refused because no client
      // authors a message document any more — not because of who this
      // sender is or what the recipient prefers.
      for (const mode of ["everyone", "peopleYouFollow", "friends"]) {
        await testEnv.withSecurityRulesDisabled(async (ctx) => {
          const db = ctx.firestore();
          await updateDoc(doc(db, "users/invitee-uid"), {
            messagePrivacy: mode,
          });
          // The full permissive graph: following edge AND both canonical
          // friendship guard halves, so nothing but the server-only rule
          // is doing the denying.
          await setDoc(
            doc(db, "users/invitee-uid/following/host-uid"),
            { uid: "host-uid", followedAt: new Date() },
          );
          for (const [owner, friend] of [
            ["host-uid", "invitee-uid"],
            ["invitee-uid", "host-uid"],
          ]) {
            await setDoc(
              doc(db, `friendshipGuards/${owner}/friends/${friend}`),
              {
                ownerId: owner,
                friendId: friend,
                schemaVersion: 1,
                establishedAt: new Date(),
              },
            );
          }
        });
        await assertFails(
          sendPrivacyProbe(host.firestore(), `server-only-${mode}`),
        );
      }
    },
  );

  await check(
    "SECURITY: a restrictive privacy mode is still denied — server-only " +
      "is not a loophole that reopens what privacy closed",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await updateDoc(doc(ctx.firestore(), "users/invitee-uid"), {
          messagePrivacy: "nobody",
        });
      });
      await assertFails(sendPrivacyProbe(host.firestore(), "privacy-nobody"));
    },
  );

  await check(
    "SECURITY: the canonical server-shaped message is refused too — the " +
      "shape was never what made it legitimate",
    async () => {
      // Writing exactly what the callable writes, including schemaVersion
      // and sequence, still fails. There is no shape a client can produce
      // that this rule accepts.
      await assertFails(
        setDoc(
          doc(host.firestore(), "conversations/privacy-convo/messages/canonical"),
          {
            schemaVersion: 2,
            sequence: 1,
            conversationId: "privacy-convo",
            senderId: "host-uid",
            type: "text",
            content: "hello",
            mediaUrl: null,
            durationSeconds: null,
            sentAt: new Date(),
            readBy: ["host-uid"],
            reactions: {},
            isDeleted: false,
            editedAt: null,
            replyToMessageId: null,
            replyToSenderId: null,
            replyToContent: null,
          },
        ),
      );
    },
  );

  await check(
    "SECURITY: a sanctioned sender is denied — the gap that motivated " +
      "ADR-105, now closed by the rule refusing every client",
    async () => {
      // The original finding: a banned or communication-muted account could
      // still write here through the client fallback, because the server's
      // activeProfile()/assertNotRestricted() checks run only inside the
      // callable. Both are denied now, and so is the unsanctioned control —
      // which is the point. The rule no longer depends on getting the
      // sender's standing right, because it admits no client at all.
      const sanctioned = testEnv.authenticatedContext("sanctioned-uid", {
        email_verified: true,
      });
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, "users/sanctioned-uid"), {
          displayName: "Sanctioned",
          banned: false,
        });
        await setDoc(doc(db, "conversations/convo-sanction-gate"), {
          participantIds: ["sanctioned-uid", "host-uid"],
        });
      });

      const send = (id) => setDoc(
        doc(
          sanctioned.firestore(),
          `conversations/convo-sanction-gate/messages/${id}`,
        ),
        {
          senderId: "sanctioned-uid",
          content: "hello",
          sentAt: new Date(),
          readBy: ["sanctioned-uid"],
          reactions: {},
          isDeleted: false,
        },
      );

      // Unsanctioned: denied, because no client may write.
      await assertFails(send("unsanctioned"));

      // Communication-muted: denied.
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "restrictions/sanctioned-uid"), {
          type: "communicationMute",
          expiresAt: null,
        });
      });
      await assertFails(send("muted"));

      // Banned: denied.
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await deleteDoc(doc(db, "restrictions/sanctioned-uid"));
        await setDoc(doc(db, "users/sanctioned-uid"), {
          displayName: "Sanctioned",
          banned: true,
        });
      });
      await assertFails(send("banned"));
    },
  );

  await check(
    "regression: server-only create did not break reading or the " +
      "callable-only mutation boundary",
    async () => {
      // `allow create: if false` must not become `allow nothing`. Seed a
      // message the way the server would and prove a participant can still
      // read it. Read receipts, edits and reactions cross the callable
      // boundary; direct SDK updates must remain denied.
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), "conversations/privacy-convo/messages/seeded"),
          {
            senderId: "invitee-uid",
            content: "from the server",
            readBy: ["invitee-uid"],
            reactions: {},
            isDeleted: false,
            editedAt: null,
          },
        );
      });
      const db = host.firestore();
      const ref = doc(db, "conversations/privacy-convo/messages/seeded");
      await assertSucceeds(getDoc(ref));
      await assertFails(
        updateDoc(ref, { readBy: ["invitee-uid", "host-uid"] }),
      );
    },
  );

  await check(
    "SECURITY: an unverified user cannot create a club",
    async () => {
      const db = unverified.firestore();
      const ref = doc(db, "clubs/unverified-club");
      await assertFails(
        setDoc(ref, {
          ownerId: "unverified-uid",
          name: "Spam club",
          memberCount: 1,
        }),
      );
    },
  );

  await check(
    "SECURITY: an unverified user cannot create a room",
    async () => {
      const db = unverified.firestore();
      const ref = doc(db, "rooms/unverified-room");
      await assertFails(
        setDoc(ref, {
          hostId: "unverified-uid",
          hostName: "Unverified",
          name: "Spam room",
          category: "talk",
          visibility: "public",
        }),
      );
    },
  );

  await check(
    "SECURITY: an unverified user cannot post a voice moment",
    async () => {
      const db = unverified.firestore();
      const ref = doc(db, "voiceMoments/unverified-moment");
      await assertFails(
        setDoc(ref, {
          authorId: "unverified-uid",
          likeCount: 0,
          commentCount: 0,
        }),
      );
    },
  );

  // ── Creator pinned posts ───────────────────────────────────────────

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await Promise.all([
      setDoc(doc(db, "users/host-uid"), {
        accountType: "creator",
        banned: false,
        disabled: false,
      }, { merge: true }),
      setDoc(doc(db, "entitlements/host-uid"), {
        status: "active",
        isPremium: true,
        creatorEnabled: true,
        premiumIdentityEnabled: true,
        currentPeriodEnd: new Date(Date.now() + 86400000),
      }),
      setDoc(doc(db, "creatorPinnedPosts/host-uid"), {
        schemaVersion: 1,
        creatorId: "host-uid",
        momentId: "moment1",
        pinnedAt: new Date(),
        updatedAt: new Date(),
      }),
    ]);
  });

  await check(
    "creator pinned post is readable only as an exact known-id get",
    async () => {
      await assertSucceeds(
        getDoc(doc(attacker.firestore(), "creatorPinnedPosts/host-uid")),
      );
      await assertFails(
        getDocs(collection(attacker.firestore(), "creatorPinnedPosts")),
      );
      await assertFails(
        getDoc(
          doc(
            testEnv.unauthenticatedContext().firestore(),
            "creatorPinnedPosts/host-uid",
          ),
        ),
      );
    },
  );

  const pinnedPost = () =>
    doc(attacker.firestore(), "creatorPinnedPosts/host-uid");
  const restorePinnedAuthority = async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await Promise.all([
        setDoc(doc(db, "creatorPinnedPosts/host-uid"), {
          schemaVersion: 1,
          creatorId: "host-uid",
          momentId: "moment1",
          pinnedAt: new Date(),
          updatedAt: new Date(),
        }),
        setDoc(doc(db, "entitlements/host-uid"), {
          status: "active",
          isPremium: true,
          creatorEnabled: true,
          premiumIdentityEnabled: true,
          currentPeriodEnd: new Date(Date.now() + 86400000),
        }),
        setDoc(doc(db, "users/host-uid"), {
          accountType: "creator",
          banned: false,
          deleted: false,
          disabled: false,
          status: "active",
        }, { merge: true }),
        setDoc(doc(db, "users/attacker-uid"), {
          banned: false,
          deleted: false,
          disabled: false,
          status: "active",
        }, { merge: true }),
      ]);
    });
  };

  await check("pinned post denies a mismatched creatorId", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), "creatorPinnedPosts/host-uid"), {
        creatorId: "attacker-uid",
      });
    });
    await assertFails(getDoc(pinnedPost()));
    await restorePinnedAuthority();
  });

  await check("pinned post denies an inexact server projection", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), "creatorPinnedPosts/host-uid"), {
        unexpected: true,
      });
    });
    await assertFails(getDoc(pinnedPost()));
    await restorePinnedAuthority();
  });

  for (const unsafeMomentId of ["bad/path", "unicode-ę"]) {
    await check(
      `pinned post denies unsafe Moment id ${JSON.stringify(unsafeMomentId)}`,
      async () => {
        await testEnv.withSecurityRulesDisabled(async (ctx) => {
          await updateDoc(doc(ctx.firestore(), "creatorPinnedPosts/host-uid"), {
            momentId: unsafeMomentId,
          });
        });
        await assertFails(getDoc(pinnedPost()));
        await restorePinnedAuthority();
      },
    );
  }

  await check("pinned post denies an expired creator entitlement", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), "entitlements/host-uid"), {
        currentPeriodEnd: new Date(0),
      });
    });
    await assertFails(getDoc(pinnedPost()));
    await restorePinnedAuthority();
  });

  await check("pinned post denies a banned reader", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), "users/attacker-uid"), {
        banned: true,
      });
    });
    await assertFails(getDoc(pinnedPost()));
    await restorePinnedAuthority();
  });

  await check("pinned post denies a target with deleted true", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), "users/host-uid"), {
        deleted: true,
        status: "active",
      });
    });
    await assertFails(getDoc(pinnedPost()));
    await restorePinnedAuthority();
  });

  await check("pinned post denies a target with deleted status", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), "users/host-uid"), {
        deleted: false,
        status: "deleted",
      });
    });
    await assertFails(getDoc(pinnedPost()));
    await restorePinnedAuthority();
  });

  await check(
    "SECURITY: clients cannot create, replace, update, or delete creator pins",
    async () => {
      const db = host.firestore();
      await assertFails(
        setDoc(doc(db, "creatorPinnedPosts/new-creator"), {
          creatorId: "host-uid",
          momentId: "moment1",
        }),
      );
      await assertFails(
        setDoc(doc(db, "creatorPinnedPosts/host-uid"), {
          creatorId: "host-uid",
          momentId: "attacker-choice",
        }),
      );
      await assertFails(
        updateDoc(doc(db, "creatorPinnedPosts/host-uid"), {
          momentId: "attacker-choice",
        }),
      );
      await assertFails(
        deleteDoc(doc(db, "creatorPinnedPosts/host-uid")),
      );
    },
  );

  // ── Premium entitlements (ADR-024) ────────────────────────────────

  await check("client cannot write its own entitlements doc", async () => {
    const db = host.firestore();
    await assertFails(
      setDoc(doc(db, "entitlements/host-uid"), { isPremium: true }),
    );
  });

  await check("client can read own entitlements, not someone else's", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "entitlements/host-uid"), {
        status: "active",
        currentPeriodEnd: new Date(Date.now() + 86400000),
        creatorEnabled: true,
        canCreateClubs: true,
        premiumIdentityEnabled: true,
      });
    });
    await assertSucceeds(getDoc(doc(host.firestore(), "entitlements/host-uid")));
    await assertFails(
      getDoc(doc(attacker.firestore(), "entitlements/host-uid")),
    );
  });

  await check(
    "SECURITY BILLING: Stripe operational collections are invisible and server-only",
    async () => {
      const collections = [
        "billingAccounts",
        "billingRateLimits",
        "billingCheckoutLocks",
        "stripeWebhookEvents",
        "stripeCustomerCleanup",
      ];
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        for (const name of collections) {
          await setDoc(doc(ctx.firestore(), `${name}/host-uid`), {
            secret: "server-owned",
          });
        }
      });
      for (const name of collections) {
        const reference = doc(host.firestore(), `${name}/host-uid`);
        await assertFails(getDoc(reference));
        await assertFails(setDoc(reference, { forged: true }));
        await assertFails(updateDoc(reference, { forged: true }));
        await assertFails(deleteDoc(reference));
      }
    },
  );

  await check("community Club creation is callable-only", async () => {
    // Even a fully entitled client cannot skip the serialized server quota by
    // submitting the old real ClubService batch directly. The callable's
    // Admin transaction is covered in functions/test/club_creation.test.js.
    const db = host.firestore();
    const clubPath = "clubs/premium-club";
    const batch = writeBatch(db);
    batch.set(doc(db, clubPath), {
      ownerId: "host-uid",
      ownerName: "Host",
      name: "Premium Club",
      description: "A complete creation batch",
      privacy: "public",
      type: "community",
      defaultLanguage: "English",
      memberCount: 1,
      onlineCount: 1,
      defaultChatChannelId: "general",
      defaultVoiceChannelId: "lounge",
      loungeRoomId: "club_lounge_premium-club",
      announcementChannelId: "announcements",
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    batch.set(doc(db, `${clubPath}/members/host-uid`), {
      userId: "host-uid",
      displayName: "Host",
      photoUrl: null,
      role: "owner",
      isOnline: true,
      joinedAt: serverTimestamp(),
      invitedBy: null,
    });
    batch.set(doc(db, "users/host-uid/clubs/premium-club"), {
      clubId: "premium-club",
      name: "Premium Club",
      avatarUrl: null,
      role: "owner",
      joinedAt: serverTimestamp(),
    });
    for (const [id, type, position] of [
      ["general", "chat", 0],
      ["announcements", "announcement", 1],
      ["lounge", "voice", 2],
    ]) {
      batch.set(doc(db, `${clubPath}/channels/${id}`), {
        name: id,
        type,
        position,
        isPrivate: false,
        createdBy: "host-uid",
        ...(id === "lounge"
          ? { roomId: "club_lounge_premium-club" }
          : {}),
        createdAt: serverTimestamp(),
      });
    }
    batch.set(doc(db, "rooms/club_lounge_premium-club"), {
      hostId: "host-uid",
      hostName: "Host",
      hostPhotoUrl: null,
      name: "Premium Club Lounge",
      description: "Private voice lounge for Premium Club members.",
      category: "club",
      visibility: "private",
      language: "English",
      maxParticipants: null,
      participantCount: 0,
      memberCount: 1,
      isLive: false,
      roomType: "community",
      status: "active",
      imageUrl: null,
      approvalRequired: false,
      slowModeSeconds: 0,
      autoMuteNewUsers: false,
      membersCanStartVoice: true,
      experience: "community",
      clubId: "premium-club",
      roomKind: "clubLounge",
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    await assertFails(batch.commit());

    // host has active entitlements (seeded above); attacker has none. Both
    // direct paths are denied for community Clubs.
    await assertFails(
      setDoc(doc(attacker.firestore(), "clubs/free-club"), {
        ownerId: "attacker-uid",
        name: "Free Club",
        memberCount: 1,
      }),
    );
  });

  await check("expired premium cannot create clubs", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "entitlements/invitee-uid"), {
        status: "active",
        currentPeriodEnd: new Date(Date.now() - 1000), // already past
      });
    });
    await assertFails(
      setDoc(doc(invitee.firestore(), "clubs/expired-club"), {
        ownerId: "invitee-uid",
        name: "Expired Club",
        memberCount: 1,
      }),
    );
  });

  // ── Club invitation acceptance authorization ─────────────────────
  // A pending invitation authorizes exactly one plain membership for the
  // invitee. It must never become a path for self-assigning an organizer
  // role or smuggling permission-like fields into the membership document.
  async function seedClubInviteAcceptanceCase(clubId) {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, `clubs/${clubId}`), {
        ownerId: "host-uid",
        name: "Invitation security club",
        type: "community",
        status: "active",
        memberCount: 1,
        onlineCount: 1,
      });
      await setDoc(doc(db, `clubs/${clubId}/invites/invitee-uid`), {
        clubId,
        clubName: "Invitation security club",
        clubAvatarUrl: null,
        inviteeId: "invitee-uid",
        inviterId: "host-uid",
        inviterName: "Host",
        status: "pending",
        createdAt: serverTimestamp(),
      });
    });
  }

  function invitedMemberDocument(overrides = {}) {
    return {
      userId: "invitee-uid",
      displayName: "Invitee",
      photoUrl: null,
      role: "member",
      isOnline: true,
      joinedAt: serverTimestamp(),
      invitedBy: "host-uid",
      ...overrides,
    };
  }

  function inviteAcceptanceBatch(
    db,
    clubId,
    clubUpdate = {},
    projectionUpdate = {},
    memberUpdate = {},
  ) {
    const batch = writeBatch(db);
    batch.set(
      doc(db, `clubs/${clubId}/members/invitee-uid`),
      invitedMemberDocument(memberUpdate),
    );
    batch.set(doc(db, `users/invitee-uid/clubs/${clubId}`), {
      clubId,
      name: "Invitation security club",
      avatarUrl: null,
      role: "member",
      joinedAt: serverTimestamp(),
      ...projectionUpdate,
    });
    batch.update(doc(db, `clubs/${clubId}`), {
      memberCount: 2,
      onlineCount: 2,
      updatedAt: serverTimestamp(),
      ...clubUpdate,
    });
    batch.delete(doc(db, `clubs/${clubId}/invites/invitee-uid`));
    return batch;
  }

  for (const privilegedRole of ["owner", "coOwner", "admin"]) {
    await check(
      `SECURITY CLUBS: an invitee cannot join as ${privilegedRole}`,
      async () => {
        const clubId = `invite-role-${privilegedRole}`;
        await seedClubInviteAcceptanceCase(clubId);
        await assertFails(
          setDoc(
            doc(invitee.firestore(), `clubs/${clubId}/members/invitee-uid`),
            invitedMemberDocument({ role: privilegedRole }),
          ),
        );
      },
    );
  }

  await check(
    "SECURITY CLUBS: an invitee cannot add privileged membership fields",
    async () => {
      const clubId = "invite-extra-fields";
      await seedClubInviteAcceptanceCase(clubId);
      await assertFails(
        setDoc(
          doc(invitee.firestore(), `clubs/${clubId}/members/invitee-uid`),
          invitedMemberDocument({
            permissions: ["manageMembers", "manageChannels"],
            isAdmin: true,
          }),
        ),
      );
    },
  );

  await check(
    "SECURITY CLUBS: membership cannot consume an invite without the Club transition",
    async () => {
      const clubId = "invite-no-root-transition";
      await seedClubInviteAcceptanceCase(clubId);
      const db = invitee.firestore();
      const batch = writeBatch(db);
      batch.set(
        doc(db, `clubs/${clubId}/members/invitee-uid`),
        invitedMemberDocument(),
      );
      batch.delete(doc(db, `clubs/${clubId}/invites/invitee-uid`));
      await assertFails(batch.commit());
    },
  );

  await check(
    "SECURITY CLUBS: a standalone user Club mirror cannot forge membership",
    async () => {
      const clubId = "invite-forged-user-mirror";
      await seedClubInviteAcceptanceCase(clubId);
      await assertFails(
        setDoc(doc(invitee.firestore(), `users/invitee-uid/clubs/${clubId}`), {
          clubId,
          name: "Invitation security club",
          avatarUrl: null,
          role: "owner",
          joinedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "SECURITY CLUBS: invite acceptance cannot forge its private mirror role",
    async () => {
      const clubId = "invite-forged-mirror-role";
      await seedClubInviteAcceptanceCase(clubId);
      const batch = inviteAcceptanceBatch(
        invitee.firestore(),
        clubId,
        {},
        { role: "owner" },
      );
      await assertFails(batch.commit());
    },
  );

  await check(
    "SECURITY CLUBS: a membership mirror cannot be deleted while membership remains",
    async () => {
      const clubId = "invite-hidden-owner-count";
      await seedClubInviteAcceptanceCase(clubId);
      await assertSucceeds(
        inviteAcceptanceBatch(invitee.firestore(), clubId).commit(),
      );
      await assertFails(
        deleteDoc(
          doc(invitee.firestore(), `users/invitee-uid/clubs/${clubId}`),
        ),
      );
    },
  );

  await check(
    "SECURITY CLUBS: a stale invite cannot be reused for standalone membership",
    async () => {
      const clubId = "invite-reuse-token";
      await seedClubInviteAcceptanceCase(clubId);
      await assertFails(
        setDoc(
          doc(invitee.firestore(), `clubs/${clubId}/members/invitee-uid`),
          invitedMemberDocument(),
        ),
      );
    },
  );

  await check(
    "SECURITY CLUBS: a pending invite cannot authorize a standalone Club counter update",
    async () => {
      const clubId = "invite-standalone-root-update";
      await seedClubInviteAcceptanceCase(clubId);
      await assertFails(
        updateDoc(doc(invitee.firestore(), `clubs/${clubId}`), {
          memberCount: 2,
          onlineCount: 2,
          updatedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "SECURITY CLUBS: a pending invite cannot repeatedly bump Club counters",
    async () => {
      const clubId = "invite-repeated-root-update";
      await seedClubInviteAcceptanceCase(clubId);
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), `clubs/${clubId}/members/invitee-uid`),
          {
            userId: "invitee-uid",
            displayName: "Invitee",
            photoUrl: null,
            role: "member",
            isOnline: true,
            joinedAt: serverTimestamp(),
            invitedBy: "host-uid",
          },
        );
      });
      await assertFails(
        updateDoc(doc(invitee.firestore(), `clubs/${clubId}`), {
          memberCount: 2,
          onlineCount: 2,
          updatedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "SECURITY CLUBS: invite acceptance cannot mutate Club metadata",
    async () => {
      const clubId = "invite-metadata-tamper";
      await seedClubInviteAcceptanceCase(clubId);
      const batch = inviteAcceptanceBatch(invitee.firestore(), clubId, {
        name: "Hijacked Club",
        visibility: "public",
        defaultChatChannelId: "attacker-chat",
        defaultVoiceChannelId: "attacker-voice",
        announcementChannelId: "attacker-announcements",
      });
      await assertFails(batch.commit());
    },
  );

  await check(
    "SECURITY CLUBS: invite acceptance cannot forge onlineCount",
    async () => {
      const clubId = "invite-counter-tamper";
      await seedClubInviteAcceptanceCase(clubId);
      const batch = inviteAcceptanceBatch(invitee.firestore(), clubId, {
        onlineCount: 99,
      });
      await assertFails(batch.commit());
    },
  );

  await check(
    "SECURITY CLUBS: invite acceptance requires a server update timestamp",
    async () => {
      const clubId = "invite-timestamp-tamper";
      await seedClubInviteAcceptanceCase(clubId);
      const batch = inviteAcceptanceBatch(invitee.firestore(), clubId, {
        updatedAt: new Date(0),
      });
      await assertFails(batch.commit());
    },
  );

  await check(
    "SECURITY CLUBS: invite acceptance binds displayName to users/{uid}",
    async () => {
      const clubId = "invite-forged-display-name";
      await seedClubInviteAcceptanceCase(clubId);
      const batch = inviteAcceptanceBatch(
        invitee.firestore(),
        clubId,
        {},
        {},
        { displayName: "Bypass Auth Name" },
      );
      await assertFails(batch.commit());
    },
  );

  await check(
    "CLUBS: an invitee can accept as a plain member in the real batch shape",
    async () => {
      const clubId = "invite-plain-member";
      await seedClubInviteAcceptanceCase(clubId);
      const db = invitee.firestore();
      const batch = inviteAcceptanceBatch(db, clubId);
      await assertSucceeds(batch.commit());
    },
  );

  await check(
    "SECURITY CLUBS: self identity refresh accepts only the canonical displayName",
    async () => {
      const clubId = "invite-plain-member";
      const db = invitee.firestore();
      const member = doc(db, `clubs/${clubId}/members/invitee-uid`);
      await assertFails(
        updateDoc(member, {
          displayName: "Arbitrary Member Name",
          updatedAt: serverTimestamp(),
        }),
      );
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await updateDoc(doc(ctx.firestore(), "users/invitee-uid"), {
          displayName: "Canonical Invitee Rename",
        });
      });
      await assertSucceeds(
        updateDoc(member, {
          displayName: "Canonical Invitee Rename",
          updatedAt: serverTimestamp(),
        }),
      );
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await updateDoc(doc(ctx.firestore(), "users/invitee-uid"), {
          displayName: "Invitee",
        });
      });
    },
  );

  await check(
    "SECURITY CLUBS: direct manager removal is denied in favor of the callable",
    async () => {
      const clubId = "manager-removes-member";
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, `clubs/${clubId}`), {
          ownerId: "host-uid",
          name: "Managed club",
          type: "community",
          status: "active",
          memberCount: 2,
          onlineCount: 2,
        });
        await setDoc(doc(db, `clubs/${clubId}/members/host-uid`), {
          userId: "host-uid",
          displayName: "Host",
          photoUrl: null,
          role: "owner",
          isOnline: true,
          joinedAt: serverTimestamp(),
          invitedBy: null,
        });
        await setDoc(doc(db, `clubs/${clubId}/members/invitee-uid`), {
          userId: "invitee-uid",
          displayName: "Invitee",
          photoUrl: null,
          role: "member",
          isOnline: true,
          joinedAt: serverTimestamp(),
          invitedBy: "host-uid",
        });
        await setDoc(doc(db, `users/invitee-uid/clubs/${clubId}`), {
          clubId,
          name: "Managed club",
          avatarUrl: null,
          role: "member",
          joinedAt: serverTimestamp(),
        });
      });

      const db = host.firestore();
      const batch = writeBatch(db);
      batch.delete(doc(db, `clubs/${clubId}/members/invitee-uid`));
      batch.delete(doc(db, `users/invitee-uid/clubs/${clubId}`));
      batch.update(doc(db, `clubs/${clubId}`), {
        memberCount: 1,
        onlineCount: 1,
        updatedAt: serverTimestamp(),
      });
      await assertFails(batch.commit());
    },
  );

  await check(
    "CLUBS: owner and co-owner can edit only validated Club metadata",
    async () => {
      const clubId = "metadata-edit-club";
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, `clubs/${clubId}`), {
          ownerId: "host-uid",
          name: "Before Club",
          description: "Before",
          defaultLanguage: "English",
          privacy: "public",
          type: "community",
          status: "active",
          memberCount: 2,
          onlineCount: 2,
          defaultChatChannelId: "general",
        });
        await setDoc(doc(db, `clubs/${clubId}/members/host-uid`), {
          userId: "host-uid",
          role: "owner",
          joinedAt: serverTimestamp(),
        });
        await setDoc(doc(db, `clubs/${clubId}/members/invitee-uid`), {
          userId: "invitee-uid",
          role: "coOwner",
          joinedAt: serverTimestamp(),
        });
      });

      for (const db of [host.firestore(), invitee.firestore()]) {
        await assertSucceeds(
          updateDoc(doc(db, `clubs/${clubId}`), {
            name: "Edited Club",
            description: "Validated metadata",
            defaultLanguage: "Polish",
            privacy: "private",
            updatedAt: serverTimestamp(),
          }),
        );
      }
    },
  );

  await check(
    "SECURITY CLUBS: managers cannot forge root authority or counters",
    async () => {
      const clubId = "root-authority-tamper";
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, `clubs/${clubId}`), {
          ownerId: "host-uid",
          name: "Secure Club",
          description: "Before",
          defaultLanguage: "English",
          privacy: "public",
          type: "community",
          status: "active",
          memberCount: 2,
          onlineCount: 2,
          defaultChatChannelId: "general",
        });
        await setDoc(doc(db, `clubs/${clubId}/members/host-uid`), {
          userId: "host-uid",
          role: "owner",
          joinedAt: serverTimestamp(),
        });
        await setDoc(doc(db, `clubs/${clubId}/members/invitee-uid`), {
          userId: "invitee-uid",
          role: "admin",
          joinedAt: serverTimestamp(),
        });
      });

      await assertFails(
        updateDoc(doc(invitee.firestore(), `clubs/${clubId}`), {
          name: "Admin takeover",
          updatedAt: serverTimestamp(),
        }),
      );
      await assertFails(
        updateDoc(doc(host.firestore(), `clubs/${clubId}`), {
          memberCount: 999,
          defaultChatChannelId: "attacker-channel",
          updatedAt: serverTimestamp(),
        }),
      );
      await assertFails(
        updateDoc(doc(host.firestore(), `clubs/${clubId}`), {
          name: "x",
          description: "",
          defaultLanguage: "English",
          privacy: "public",
          updatedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "SECURITY CLUBS: direct owner deletion is denied to prevent orphaned subcollections",
    async () => {
      const clubId = "direct-delete-denied";
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), `clubs/${clubId}`), {
          ownerId: "host-uid",
          name: "Do not orphan",
          type: "community",
        });
      });
      await assertFails(deleteDoc(doc(host.firestore(), `clubs/${clubId}`)));
    },
  );

  await check(
    "room chat: reactions-only updates allowed for people in the room; text immutable; host-only delete",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, "rooms/chat-room"), {
          hostId: "host-uid",
          name: "Chat Room",
          visibility: "public",
          isLive: true,
        });
        // A real account behind the participant row. Reacting is now gated
        // on isActiveAccount() like posting already was, so an account
        // document is part of the production shape of "someone in the room"
        // — a participant row is created by a rule that itself requires
        // canCommunicate(), which cannot pass without this document.
        await setDoc(doc(db, "users/guest-uid"), {
          displayName: "Guest",
          banned: false,
        });
        await setDoc(doc(db, "rooms/chat-room/participants/guest-uid"), {
          userId: "guest-uid",
          role: "listener",
          isSpeaker: false,
        });
        await setDoc(doc(db, "rooms/chat-room/messages/m1"), {
          senderId: "host-uid",
          senderName: "Host",
          text: "hello room",
          reactions: {},
        });
      });
      const guest = testEnv.authenticatedContext("guest-uid", {
        email_verified: true,
      });
      // Participant may toggle reactions…
      await assertSucceeds(
        updateDoc(doc(guest.firestore(), "rooms/chat-room/messages/m1"), {
          reactions: { "🔥": ["guest-uid"] },
        }),
      );
      // A participant cannot attribute a reaction to another uid.
      await assertFails(
        updateDoc(doc(guest.firestore(), "rooms/chat-room/messages/m1"), {
          reactions: { "🔥": ["guest-uid", "forged-victim-uid"] },
        }),
      );
      // …but not rewrite the message body.
      await assertFails(
        updateDoc(doc(guest.firestore(), "rooms/chat-room/messages/m1"), {
          text: "hijacked",
        }),
      );
      // Someone outside the room can't react at all.
      const outsider = testEnv.authenticatedContext("outsider-uid", {
        email_verified: true,
      });
      await assertFails(
        updateDoc(doc(outsider.firestore(), "rooms/chat-room/messages/m1"), {
          reactions: { "🔥": ["outsider-uid"] },
        }),
      );
      // Delete is host moderation only.
      await assertFails(
        deleteDoc(doc(guest.firestore(), "rooms/chat-room/messages/m1")),
      );
      const roomHost = testEnv.authenticatedContext("host-uid", {
        email_verified: true,
      });
      await assertSucceeds(
        deleteDoc(doc(roomHost.firestore(), "rooms/chat-room/messages/m1")),
      );
    },
  );

  // ------------------------------------------------------------------
  // ROOM CHAT DOCUMENT SHAPE.
  //
  // Until roomMessageCreateShapeAllowed() existed, the create rule checked
  // WHO was writing and nothing at all about the document. Every attack
  // below was reproduced from an ordinary member account against the
  // deployed-shaped ruleset and ALLOWED; every regression above it is the
  // literal payload room_service.dart writes.
  //
  // The regressions matter more than the attacks here. Pinning senderName
  // and the timestamp broke sending on the club side, so each pin is paired
  // with the exact legitimate write it must not refuse — including the two
  // shapes that made the club-side pins unsafe, an identity read from the
  // canonical profile and a server timestamp.
  // ------------------------------------------------------------------
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/shape-sender"), {
      uid: "shape-sender",
      // RoomService._identity() preserves the exact stored bytes of this
      // field, including surrounding whitespace, and calls that out as a
      // byte-for-byte Rules binding. Seeding a name that is NOT a tidy
      // identifier is what proves the pin compares bytes rather than a
      // normalized form.
      displayName: "  Shape Sender  ",
      photoUrl: "https://cdn.example/shape-sender.png",
      banned: false,
    });
    await setDoc(doc(db, "users/shape-victim"), {
      uid: "shape-victim",
      displayName: "Shape Victim",
      photoUrl: "https://cdn.example/shape-victim.png",
      banned: false,
    });
    // An account with NO photoUrl on its profile, so RoomService._identity()
    // falls back to the Firebase Auth photoURL — the reason senderPhotoUrl
    // is bounded rather than pinned.
    await setDoc(doc(db, "users/shape-nophoto"), {
      uid: "shape-nophoto",
      displayName: "Shape NoPhoto",
      banned: false,
    });
    await setDoc(doc(db, "rooms/shape-room"), {
      hostId: "shape-host",
      hostName: "Shape Host",
      name: "Shape Room",
      visibility: "public",
      status: "active",
      isLive: true,
      roomType: "temporary",
      updatedAt: Timestamp.fromMillis(1_700_000_000_000),
    });
    for (const uid of ["shape-sender", "shape-victim", "shape-nophoto"]) {
      await setDoc(doc(db, `rooms/shape-room/participants/${uid}`), {
        userId: uid,
        displayName: uid,
        role: "listener",
        isMuted: true,
        isSpeaker: false,
        isHandRaised: false,
      });
    }
  });

  const shapeSender = testEnv.authenticatedContext("shape-sender", {
    email_verified: true,
  });
  const shapeNoPhoto = testEnv.authenticatedContext("shape-nophoto", {
    email_verified: true,
  });

  // The canonical payload, byte for byte, as room_service.dart builds it.
  const roomMessage = (overrides = {}) => ({
    senderId: "shape-sender",
    senderName: "  Shape Sender  ",
    senderPhotoUrl: null,
    text: "hello room",
    createdAt: serverTimestamp(),
    reactions: {},
    ...overrides,
  });

  await check(
    "SECURITY ROOM CHAT: the exact legacy sendRoomMessage() payload is " +
      "callable-only while an authorized recency-only bump remains bounded",
    async () => {
      const db = shapeSender.firestore();
      await assertFails(
        addDoc(collection(db, "rooms/shape-room/messages"), roomMessage()),
      );
      await assertSucceeds(
        updateDoc(doc(db, "rooms/shape-room"), {
          updatedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "SECURITY ROOM CHAT: a Firebase Auth fallback URL is not denormalized",
    async () => {
      const db = shapeNoPhoto.firestore();
      await assertFails(
        addDoc(collection(db, "rooms/shape-room/messages"), {
          senderId: "shape-nophoto",
          senderName: "Shape NoPhoto",
          // The account's profile carries no canonical first-party media.
          // Falling back to Auth would publish an external tracking URL.
          senderPhotoUrl: "https://lh3.googleusercontent.com/auth-mirror",
          text: "sent with an Auth avatar",
          createdAt: serverTimestamp(),
          reactions: {},
        }),
      );
    },
  );

  await check(
    "SECURITY ROOM CHAT: a null-avatar legacy payload is also callable-only",
    async () => {
      await assertFails(
        addDoc(
          collection(shapeSender.firestore(), "rooms/shape-room/messages"),
          roomMessage({ senderPhotoUrl: null }),
        ),
      );
    },
  );

  await check(
    "SECURITY ROOM CHAT: even previously valid bounded text is callable-only",
    async () => {
      const db = shapeSender.firestore();
      // RoomService rejects `normalized.length > 500`, and Dart's
      // String.length counts UTF-16 units, so 250 astral emoji (500 units,
      // 250 code points, 1000 UTF-8 bytes) is the longest all-emoji message
      // the app can send. A rules cap counting BYTES would refuse it; one
      // counting CODE POINTS would be slacker than the client. It counts
      // UTF-16 units, so the two boundaries coincide exactly.
      await assertFails(
        addDoc(
          collection(db, "rooms/shape-room/messages"),
          roomMessage({ text: "\u{1F600}".repeat(250) }),
        ),
      );
      await assertFails(
        addDoc(
          collection(db, "rooms/shape-room/messages"),
          roomMessage({ text: "a".repeat(500) }),
        ),
      );
      await assertFails(
        addDoc(
          collection(db, "rooms/shape-room/messages"),
          roomMessage({ text: "a".repeat(501) }),
        ),
      );
    },
  );

  await check(
    "SECURITY ROOM CHAT: a member cannot post under another member's senderName — impersonation inside a private conversation",
    async () => {
      await assertFails(
        addDoc(
          collection(shapeSender.firestore(), "rooms/shape-room/messages"),
          roomMessage({
            senderName: "Shape Victim",
            senderPhotoUrl: "https://cdn.example/shape-victim.png",
            text: "I am the victim speaking",
          }),
        ),
      );
    },
  );

  await check(
    "SECURITY ROOM CHAT: senderName must be the canonical profile name, not a plausible variant of the caller's own",
    async () => {
      // Trimmed — the tidy-looking value — is still not what the profile
      // stores, and a rule comparing anything but bytes would accept it.
      await assertFails(
        addDoc(
          collection(shapeSender.firestore(), "rooms/shape-room/messages"),
          roomMessage({ senderName: "Shape Sender" }),
        ),
      );
    },
  );

  await check(
    "SECURITY ROOM CHAT: a 60,000-character body is refused (unbounded storage growth)",
    async () => {
      await assertFails(
        addDoc(
          collection(shapeSender.firestore(), "rooms/shape-room/messages"),
          roomMessage({ text: "A".repeat(60000) }),
        ),
      );
    },
  );

  await check(
    "SECURITY ROOM CHAT: createdAt cannot be set to 2099, which would pin the message to the top of every member's chat permanently",
    async () => {
      const db = shapeSender.firestore();
      await assertFails(
        addDoc(
          collection(db, "rooms/shape-room/messages"),
          roomMessage({
            createdAt: Timestamp.fromDate(new Date("2099-01-01T00:00:00Z")),
          }),
        ),
      );
      // A client CLOCK value rather than a server timestamp is refused too,
      // even when it is roughly now — this is the pin that broke club chat,
      // and it is safe here only because sendRoomMessage() writes
      // FieldValue.serverTimestamp().
      await assertFails(
        addDoc(
          collection(db, "rooms/shape-room/messages"),
          roomMessage({ createdAt: Timestamp.fromDate(new Date()) }),
        ),
      );
    },
  );

  await check(
    "SECURITY ROOM CHAT: arbitrary extra fields are refused — senderIsStaff, isPinnedForever, a second sentAt ordering key",
    async () => {
      const db = shapeSender.firestore();
      await assertFails(
        addDoc(
          collection(db, "rooms/shape-room/messages"),
          roomMessage({ senderIsStaff: true }),
        ),
      );
      await assertFails(
        addDoc(
          collection(db, "rooms/shape-room/messages"),
          roomMessage({ isPinnedForever: true }),
        ),
      );
      await assertFails(
        addDoc(
          collection(db, "rooms/shape-room/messages"),
          roomMessage({
            sentAt: Timestamp.fromDate(new Date("2099-01-01T00:00:00Z")),
          }),
        ),
      );
    },
  );

  await check(
    "SECURITY ROOM CHAT: a message cannot be BORN removed — the forged staff tombstone clubMessageCreateShapeAllowed() was written to stop",
    async () => {
      // adminDeleteMessage writes exactly these fields onto room messages
      // too, and short-circuits on isDeleted === true without redacting, so
      // a forged tombstone would be permanent and unreachable by every
      // client path. hasOnly() keeps the fields out of the collection.
      await assertFails(
        addDoc(
          collection(shapeSender.firestore(), "rooms/shape-room/messages"),
          roomMessage({
            text: "",
            isDeleted: true,
            deletedBy: "shape-host",
            deletedByRole: "superAdmin",
            moderationRemoved: true,
          }),
        ),
      );
    },
  );

  await check(
    "SECURITY ROOM CHAT: a message cannot be created pre-loaded with reactions attributed to other people",
    async () => {
      await assertFails(
        addDoc(
          collection(shapeSender.firestore(), "rooms/shape-room/messages"),
          roomMessage({
            reactions: Object.fromEntries(
              Array.from({ length: 200 }, (_, i) => [
                `e${i}`,
                Array.from({ length: 25 }, (_, j) => `victim-${j}`),
              ]),
            ),
          }),
        ),
      );
    },
  );

  await check(
    "SECURITY ROOM CHAT: a blank-after-trim body, and a message missing createdAt or reactions, are all refused",
    async () => {
      const db = shapeSender.firestore();
      await assertFails(
        addDoc(
          collection(db, "rooms/shape-room/messages"),
          roomMessage({ text: "      " }),
        ),
      );
      const { createdAt, ...noCreatedAt } = roomMessage();
      await assertFails(
        addDoc(collection(db, "rooms/shape-room/messages"), noCreatedAt),
      );
      const { reactions, ...noReactions } = roomMessage();
      await assertFails(
        addDoc(collection(db, "rooms/shape-room/messages"), noReactions),
      );
    },
  );

  await check(
    "SECURITY ROOM CHAT: reaction deltas are self-attributed, canonical and bounded",
    async () => {
      const db = shapeSender.firestore();
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), "rooms/shape-room/messages/reaction-target"),
          {
            senderId: "shape-victim",
            senderName: "Shape Victim",
            senderPhotoUrl: null,
            text: "a real message",
            createdAt: serverTimestamp(),
            reactions: {},
          },
        );
      });
      const target = doc(db, "rooms/shape-room/messages/reaction-target");
      // What toggleRoomMessageReaction() writes: the whole map, recomputed.
      // room_chat_sheet.dart offers five quick reactions, so this is the
      // realistic ceiling for the client.
      await assertSucceeds(
        updateDoc(target, {
          reactions: {
            "❤️": ["shape-sender"],
            "\u{1F602}": ["shape-sender"],
            "\u{1F44F}": ["shape-sender"],
            "\u{1F525}": ["shape-sender"],
            "\u{1F4AF}": ["shape-sender"],
          },
        }),
      );
      // 200 emoji keys is not a reaction, it is storage.
      await assertFails(
        updateDoc(target, {
          reactions: Object.fromEntries(
            Array.from({ length: 200 }, (_, i) => [`e${i}`, ["shape-sender"]]),
          ),
        }),
      );
      await assertFails(
        updateDoc(target, {
          reactions: { "🔥": ["shape-sender", "forged-victim"] },
        }),
      );
      await assertFails(
        updateDoc(target, {
          reactions: { "🔥": ["shape-sender", "shape-sender"] },
        }),
      );

      // A legacy document with unknown keys can be rewritten only to the
      // canonical map. Retaining even one unknown key stays denied.
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), "rooms/shape-room/messages/reaction-target"),
          {
            senderId: "shape-victim",
            senderName: "Shape Victim",
            senderPhotoUrl: null,
            text: "a real message",
            createdAt: serverTimestamp(),
            reactions: Object.fromEntries(
              Array.from({ length: 90 }, (_, i) => [`e${i}`, ["someone"]]),
            ),
          },
        );
      });
      await assertFails(
        updateDoc(target, {
          reactions: Object.fromEntries(
            Array.from({ length: 89 }, (_, i) => [`e${i}`, ["someone"]]),
          ),
        }),
      );
      await assertSucceeds(updateDoc(target, { reactions: {} }));

      // Even a purely self-attributed delta cannot cross the per-emoji cap.
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), "rooms/shape-room/messages/reaction-target"),
          {
            senderId: "shape-victim",
            senderName: "Shape Victim",
            senderPhotoUrl: null,
            text: "a real message",
            createdAt: serverTimestamp(),
            reactions: {
              "🔥": Array.from({ length: 500 }, (_, i) => `member-${i}`),
            },
          },
        );
      });
      await assertFails(
        updateDoc(target, {
          reactions: {
            "🔥": [
              ...Array.from({ length: 500 }, (_, i) => `member-${i}`),
              "shape-sender",
            ],
          },
        }),
      );
    },
  );

  // ------------------------------------------------------------------
  // CLUB DISCOVERY (`match /clubs` LIST).
  //
  // `allow list: if false` denied HomeFeedService.watchSuggestedClubs() for
  // everyone, including a club owner listing their own public club, so
  // Home's "Discover clubs" rail has never worked for anybody.
  //
  // A list rule is evaluated against the QUERY'S CONSTRAINTS, not against
  // the documents returned — measured on the emulator across six rule
  // variants, because the design depends entirely on which it is. So these
  // cases are about which QUERY is authorized. The document-level exclusions
  // asserted below are performed by the query's own index, which is the only
  // mechanism that actually works here: a rule clause on a field the query
  // does not constrain is either unprovable (deny) or, if written as
  // `.get(field, default)`, silently satisfied by the default.
  // ------------------------------------------------------------------
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/discover-reader"), {
      uid: "discover-reader",
      displayName: "Discover Reader",
      banned: false,
    });
    await setDoc(doc(db, "users/discover-banned"), {
      uid: "discover-banned",
      displayName: "Discover Banned",
      banned: true,
    });
    await setDoc(doc(db, "clubs/discover-public"), {
      name: "Discover Public",
      description: "an ordinary public community club",
      ownerId: "discover-owner",
      ownerName: "Discover Owner",
      avatarUrl: null,
      bannerUrl: null,
      privacy: "public",
      type: "community",
      status: "active",
      defaultLanguage: "English",
      memberCount: 12,
      onlineCount: 3,
    });
    await setDoc(doc(db, "clubs/discover-private"), {
      name: "Discover Private",
      ownerId: "discover-owner",
      privacy: "private",
      type: "community",
      status: "active",
      memberCount: 2,
    });
    // A FAMILY room whose owner set privacy to "public" — which
    // clubMetadataUpdateAllowed() permits today, and the club settings
    // screen offers. If discovery keyed on privacy alone, this private
    // family space's name would land on every user's Home.
    await setDoc(doc(db, "clubs/family_discover-rogue"), {
      name: "Rogue Family Room",
      ownerId: "discover-rogue",
      privacy: "public",
      type: "family",
      status: "active",
      memberCount: 3,
    });
    // A legacy public club carrying neither `type` nor `status`.
    await setDoc(doc(db, "clubs/discover-legacy"), {
      name: "Legacy Club",
      ownerId: "discover-owner",
      privacy: "public",
      memberCount: 1,
    });
    // The private per-user projection that shares the `clubs` collection
    // NAME — the ADR-005/007 collision that makes the collectionGroup case
    // below worth running rather than reasoning about.
    await setDoc(doc(db, "users/discover-owner/clubs/discover-public"), {
      clubId: "discover-public",
      name: "Discover Public",
      avatarUrl: null,
      role: "owner",
      privacy: "public",
    });
  });

  const discoverReader = testEnv.authenticatedContext("discover-reader", {
    email_verified: true,
  });
  const discoverBanned = testEnv.authenticatedContext("discover-banned", {
    email_verified: true,
  });
  // The query the rule authorizes, and the one HomeFeedService must issue.
  const discoveryQuery = (db) =>
    query(
      collection(db, "clubs"),
      where("privacy", "==", "public"),
      where("type", "==", "community"),
      where("status", "==", "active"),
      limit(8),
    );

  await check(
    "regression CLUB DISCOVERY: the discovery query succeeds and returns the public community club — the rail that `allow list: if false` denied to everyone",
    async () => {
      const snapshot = await assertSucceeds(
        getDocs(discoveryQuery(discoverReader.firestore())),
      );
      const ids = snapshot.docs.map((d) => d.id);
      if (!ids.includes("discover-public")) {
        throw new Error(`expected discover-public in the rail, got ${ids}`);
      }
    },
  );

  await check(
    "SECURITY CLUB DISCOVERY: the rail cannot reach a private club, a family room whose owner set privacy=public, or a legacy club with no type/status",
    async () => {
      const snapshot = await assertSucceeds(
        getDocs(discoveryQuery(discoverReader.firestore())),
      );
      const ids = snapshot.docs.map((d) => d.id);
      for (const forbidden of [
        "discover-private",
        "family_discover-rogue",
        "discover-legacy",
      ]) {
        if (ids.includes(forbidden)) {
          throw new Error(`${forbidden} leaked into the discovery rail`);
        }
      }
    },
  );

  await check(
    "SECURITY CLUB DISCOVERY: an unfiltered `collection('clubs')` listing is still denied — enumeration was the reason this rule was false",
    async () => {
      await assertFails(
        getDocs(query(collection(discoverReader.firestore(), "clubs"), limit(8))),
      );
    },
  );

  await check(
    "SECURITY CLUB DISCOVERY: a query filtering on privacy ALONE is denied, so nothing can list clubs without also proving type and status",
    async () => {
      const db = discoverReader.firestore();
      // This is the query HomeFeedService.watchSuggestedClubs() issues
      // TODAY. It is still denied, on purpose: privacy alone cannot exclude
      // the rogue family room above. The client must add both filters — the
      // rail does not start working until it does.
      await assertFails(
        getDocs(
          query(collection(db, "clubs"), where("privacy", "==", "public"), limit(8)),
        ),
      );
      await assertFails(
        getDocs(
          query(
            collection(db, "clubs"),
            where("privacy", "==", "public"),
            where("type", "==", "community"),
            limit(8),
          ),
        ),
      );
    },
  );

  await check(
    "SECURITY CLUB DISCOVERY: private and invite-only clubs cannot be listed by asking for them directly",
    async () => {
      const db = discoverReader.firestore();
      for (const value of ["private", "inviteOnly"]) {
        await assertFails(
          getDocs(
            query(
              collection(db, "clubs"),
              where("privacy", "==", value),
              where("type", "==", "community"),
              where("status", "==", "active"),
              limit(8),
            ),
          ),
        );
      }
    },
  );

  await check(
    "SECURITY CLUB DISCOVERY: a banned account cannot run the discovery query — account status is re-stated in the list rule, not inherited from `get`",
    async () => {
      await assertFails(getDocs(discoveryQuery(discoverBanned.firestore())));
    },
  );

  await check(
    "SECURITY CLUB DISCOVERY ADR-007: opening `clubs` list does NOT authorize a real collectionGroup('clubs') query, which would also span every user's private users/{uid}/clubs projection",
    async () => {
      const db = discoverReader.firestore();
      // Only a top-level `match /{path=**}/clubs/{clubId}` wildcard could
      // authorize this, and there is none. Getting that wrong fails OPEN
      // (SECURITY.md principle 3), so it is proven with the real query
      // rather than inferred from the nested rule's shape.
      await assertFails(
        getDocs(
          query(
            collectionGroup(db, "clubs"),
            where("privacy", "==", "public"),
            limit(8),
          ),
        ),
      );
      await assertFails(
        getDocs(
          query(
            collectionGroup(db, "clubs"),
            where("privacy", "==", "public"),
            where("type", "==", "community"),
            where("status", "==", "active"),
            limit(8),
          ),
        ),
      );
    },
  );

  // ------------------------------------------------------------------
  // ROOM RECENCY: the room-root `updatedAt` bump that sendRoomMessage()
  // issues after every message.
  //
  // These run the PRODUCTION SHAPE of room_service.dart's sendRoomMessage():
  // an addDoc() into rooms/{id}/messages followed by a separate
  // updateDoc(rooms/{id}, {updatedAt: serverTimestamp()}). The two are not
  // batched in the client and are deliberately not batched here — the whole
  // point of the defect is that the first write landed and the second was
  // refused, so a test that fused them would prove the wrong thing.
  // ------------------------------------------------------------------
  await check(
    "room recency: a PARTICIPANT's legacy direct message is denied while the " +
      "strict recency-only root transition remains bounded",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, "rooms/recency-room"), {
          hostId: "recency-host",
          hostName: "Recency Host",
          name: "Recency Room",
          description: "",
          category: "general",
          visibility: "public",
          language: "English",
          maxParticipants: null,
          participantCount: 2,
          memberCount: 1,
          isLive: true,
          roomType: "community",
          status: "active",
          approvalRequired: false,
          slowModeSeconds: 0,
          autoMuteNewUsers: true,
          membersCanStartVoice: false,
          createdAt: Timestamp.fromMillis(1_700_000_000_000),
          updatedAt: Timestamp.fromMillis(1_700_000_000_000),
        });
        for (const uid of [
          "recency-host",
          "recency-speaker",
          "recency-member",
          "recency-outsider",
          "recency-unverified",
        ]) {
          await setDoc(doc(db, `users/${uid}`), {
            uid,
            displayName: uid,
            banned: false,
          });
        }
        // A banned account that still holds a participant row — the exact
        // state a suspension mid-session leaves behind.
        await setDoc(doc(db, "users/recency-banned"), {
          uid: "recency-banned",
          displayName: "Banned",
          banned: true,
        });
        // A communication-muted account: active, but silenced by staff.
        await setDoc(doc(db, "users/recency-muted"), {
          uid: "recency-muted",
          displayName: "Muted",
          banned: false,
        });
        await setDoc(doc(db, "restrictions/recency-muted"), {
          type: "communicationMute",
          expiresAt: null,
        });
        for (const uid of [
          "recency-speaker",
          "recency-banned",
          "recency-muted",
          "recency-unverified",
        ]) {
          await setDoc(doc(db, `rooms/recency-room/participants/${uid}`), {
            userId: uid,
            displayName: uid,
            role: "listener",
            isMuted: false,
            isSpeaker: false,
            isHandRaised: false,
          });
        }
        await setDoc(doc(db, "rooms/recency-room/roomMembers/recency-member"), {
          userId: "recency-member",
          displayName: "Member",
          role: "member",
        });
      });

      const speaker = testEnv.authenticatedContext("recency-speaker", {
        email_verified: true,
      });
      const db = speaker.firestore();

      // Exactly what sendRoomMessage() writes, in the same order.
      //
      // senderName is the account's canonical users/{uid}.displayName —
      // which the seed above sets to the uid — because the message create
      // rule now pins it there, exactly as RoomService._identity() reads it.
      // A name invented by the test would prove the rule is NOT pinned.
      await assertFails(
        addDoc(collection(db, "rooms/recency-room/messages"), {
          senderId: "recency-speaker",
          senderName: "recency-speaker",
          senderPhotoUrl: null,
          text: "hello from a non-host",
          createdAt: serverTimestamp(),
          reactions: {},
        }),
      );
      // THIS is the write that was denied before the fix. The message above
      // has already committed at this point, which is why the failure was
      // user-visible rather than a clean rejection.
      await assertSucceeds(
        updateDoc(doc(db, "rooms/recency-room"), {
          updatedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "room recency: a Community member's legacy direct message is denied while " +
      "their recency-only transition remains bounded",
    async () => {
      const member = testEnv.authenticatedContext("recency-member", {
        email_verified: true,
      });
      const db = member.firestore();
      await assertFails(
        addDoc(collection(db, "rooms/recency-room/messages"), {
          senderId: "recency-member",
          senderName: "recency-member",
          senderPhotoUrl: null,
          text: "member chatter",
          createdAt: serverTimestamp(),
          reactions: {},
        }),
      );
      await assertSucceeds(
        updateDoc(doc(db, "rooms/recency-room"), {
          updatedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "room recency: the host still bumps (regression — the host branch already allowed a bare updatedAt and must keep doing so)",
    async () => {
      const roomHost = testEnv.authenticatedContext("recency-host", {
        email_verified: true,
      });
      await assertSucceeds(
        updateDoc(doc(roomHost.firestore(), "rooms/recency-room"), {
          updatedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "room recency BOUNDARY: may-bump is exactly may-post — a signed-in stranger in a PUBLIC room can do neither",
    async () => {
      const outsider = testEnv.authenticatedContext("recency-outsider", {
        email_verified: true,
      });
      const db = outsider.firestore();
      // No participant row, no membership: the create rule refuses the post…
      await assertFails(
        addDoc(collection(db, "rooms/recency-room/messages"), {
          senderId: "recency-outsider",
          senderName: "Outsider",
          text: "not in this room",
          createdAt: serverTimestamp(),
          reactions: {},
        }),
      );
      // …so the recency bump has to be refused on the same terms. A public
      // room is READABLE by anyone signed in; that must not become a way to
      // push it to the top of Discover without saying anything in it.
      await assertFails(
        updateDoc(doc(db, "rooms/recency-room"), {
          updatedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "room recency BOUNDARY: a BANNED participant cannot bump — the status check is re-stated inside the branch, not inherited (SECURITY.md principle 9)",
    async () => {
      const banned = testEnv.authenticatedContext("recency-banned", {
        email_verified: true,
      });
      const db = banned.firestore();
      await assertFails(
        addDoc(collection(db, "rooms/recency-room/messages"), {
          senderId: "recency-banned",
          senderName: "Banned",
          text: "still here",
          createdAt: serverTimestamp(),
          reactions: {},
        }),
      );
      await assertFails(
        updateDoc(doc(db, "rooms/recency-room"), {
          updatedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "room recency BOUNDARY: a communication-muted participant cannot bump, matching canCommunicate() on the create rule",
    async () => {
      const muted = testEnv.authenticatedContext("recency-muted", {
        email_verified: true,
      });
      const db = muted.firestore();
      await assertFails(
        addDoc(collection(db, "rooms/recency-room/messages"), {
          senderId: "recency-muted",
          senderName: "Muted",
          text: "muted chatter",
          createdAt: serverTimestamp(),
          reactions: {},
        }),
      );
      await assertFails(
        updateDoc(doc(db, "rooms/recency-room"), {
          updatedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "room recency BOUNDARY: an UNVERIFIED participant cannot bump, matching isVerified() on the create rule",
    async () => {
      const unverifiedMember = testEnv.authenticatedContext(
        "recency-unverified",
        { email_verified: false },
      );
      const db = unverifiedMember.firestore();
      await assertFails(
        addDoc(collection(db, "rooms/recency-room/messages"), {
          senderId: "recency-unverified",
          senderName: "Unverified",
          text: "unverified chatter",
          createdAt: serverTimestamp(),
          reactions: {},
        }),
      );
      await assertFails(
        updateDoc(doc(db, "rooms/recency-room"), {
          updatedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "room recency BOUNDARY: the bump carries NOTHING else — no counter, no visibility flip, no isLive, no host takeover can ride along with updatedAt",
    async () => {
      const speaker = testEnv.authenticatedContext("recency-speaker", {
        email_verified: true,
      });
      const db = speaker.firestore();
      const room = doc(db, "rooms/recency-room");
      // Each of these is `updatedAt` plus one extra key. hasOnly(['updatedAt'])
      // is the only thing standing between a recency marker and a lever.
      await assertFails(
        updateDoc(room, { updatedAt: serverTimestamp(), visibility: "private" }),
      );
      await assertFails(
        updateDoc(room, { updatedAt: serverTimestamp(), memberCount: 99 }),
      );
      await assertFails(
        updateDoc(room, { updatedAt: serverTimestamp(), participantCount: 99 }),
      );
      await assertFails(
        updateDoc(room, { updatedAt: serverTimestamp(), isLive: false }),
      );
      await assertFails(
        updateDoc(room, {
          updatedAt: serverTimestamp(),
          hostId: "recency-speaker",
        }),
      );
      await assertFails(
        updateDoc(room, { updatedAt: serverTimestamp(), maxParticipants: 1 }),
      );
      await assertFails(
        updateDoc(room, {
          updatedAt: serverTimestamp(),
          membersCanStartVoice: true,
        }),
      );
      await assertFails(
        updateDoc(room, { updatedAt: serverTimestamp(), name: "Hijacked" }),
      );
      // And the timestamp itself is pinned to the server clock, so the bump
      // cannot be backdated or pushed into the future to game the sort.
      await assertFails(
        updateDoc(room, { updatedAt: Timestamp.fromMillis(4_100_000_000_000) }),
      );
    },
  );

  await check(
    "room recency BOUNDARY: a room being torn down refuses the bump, matching hostRoomUpdateAllowed()'s own deletionInProgress guard",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, "rooms/recency-deleting"), {
          hostId: "recency-host",
          name: "Closing Room",
          visibility: "public",
          roomType: "community",
          status: "active",
          isLive: true,
          participantCount: 1,
          memberCount: 0,
          deletionInProgress: true,
          updatedAt: Timestamp.fromMillis(1_700_000_000_000),
        });
        await setDoc(
          doc(db, "rooms/recency-deleting/participants/recency-speaker"),
          { userId: "recency-speaker", role: "listener", isSpeaker: false },
        );
      });
      const speaker = testEnv.authenticatedContext("recency-speaker", {
        email_verified: true,
      });
      await assertFails(
        updateDoc(doc(speaker.firestore(), "rooms/recency-deleting"), {
          updatedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "room recency BOUNDARY: a private room a participant was never admitted to stays unbumpable — canAccessRoom() still gates the participant branch",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, "rooms/recency-private"), {
          hostId: "recency-host",
          name: "Private Room",
          visibility: "private",
          roomType: "temporary",
          status: "active",
          isLive: true,
          participantCount: 1,
          memberCount: 0,
          updatedAt: Timestamp.fromMillis(1_700_000_000_000),
        });
        // A self-forged participant row with no admittedBy — exactly what
        // isHostAdmittedRoomParticipant() exists to refuse.
        await setDoc(
          doc(db, "rooms/recency-private/participants/recency-speaker"),
          { userId: "recency-speaker", role: "listener", isSpeaker: false },
        );
      });
      const speaker = testEnv.authenticatedContext("recency-speaker", {
        email_verified: true,
      });
      await assertFails(
        updateDoc(doc(speaker.firestore(), "rooms/recency-private"), {
          updatedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "room recency ANTI-REGRESSION: join and leave still work while voice start " +
      "is callable-only",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, "rooms/recency-transitions"), {
          hostId: "recency-host",
          name: "Transitions",
          visibility: "public",
          roomType: "community",
          status: "active",
          isLive: false,
          approvalRequired: false,
          membersCanStartVoice: true,
          participantCount: 0,
          memberCount: 0,
          maxParticipants: null,
          updatedAt: Timestamp.fromMillis(1_700_000_000_000),
        });
      });
      const joiner = testEnv.authenticatedContext("recency-member", {
        email_verified: true,
      });
      const db = joiner.firestore();

      // joinCommunity(): membership row + memberCount, one transaction.
      await assertFails(
        runTransaction(db, async (tx) => {
          tx.set(doc(db, "rooms/recency-transitions/roomMembers/recency-member"), {
            userId: "recency-member",
            displayName: "Bypass Auth Name",
            photoUrl: null,
            role: "member",
            joinedAt: serverTimestamp(),
          });
          tx.update(doc(db, "rooms/recency-transitions"), {
            memberCount: 1,
            updatedAt: serverTimestamp(),
          });
        }),
      );
      await assertSucceeds(
        runTransaction(db, async (tx) => {
          tx.set(doc(db, "rooms/recency-transitions/roomMembers/recency-member"), {
            userId: "recency-member",
            displayName: "recency-member",
            photoUrl: null,
            role: "member",
            joinedAt: serverTimestamp(),
          });
          tx.update(doc(db, "rooms/recency-transitions"), {
            memberCount: 1,
            updatedAt: serverTimestamp(),
          });
        }),
      );

      // Direct start is closed. Seed the exact state the callable commits so
      // the remaining join/leave compatibility assertions still exercise
      // their real rules branches.
      await assertFails(
        updateDoc(doc(db, "rooms/recency-transitions"), {
          isLive: true,
          updatedAt: serverTimestamp(),
          endedAt: deleteField(),
        }),
      );
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await updateDoc(doc(ctx.firestore(), "rooms/recency-transitions"), {
          isLive: true,
          voiceSessionId: "recency-session-0001",
          voiceStartedAt: serverTimestamp(),
          updatedAt: serverTimestamp(),
        });
      });

      // joinRoom(): participant row + participantCount, one transaction.
      await assertSucceeds(
        runTransaction(db, async (tx) => {
          tx.set(
            doc(db, "rooms/recency-transitions/participants/recency-member"),
            {
              userId: "recency-member",
              displayName: "recency-member",
              photoUrl: null,
              role: "speaker",
              isMuted: false,
              isSpeaker: true,
              isHandRaised: false,
              joinedAt: serverTimestamp(),
              updatedAt: serverTimestamp(),
            },
          );
          tx.update(doc(db, "rooms/recency-transitions"), {
            participantCount: 1,
            updatedAt: serverTimestamp(),
          });
        }),
      );

      // leave: membership row goes, memberCount follows it down.
      await assertSucceeds(
        runTransaction(db, async (tx) => {
          tx.delete(
            doc(db, "rooms/recency-transitions/roomMembers/recency-member"),
          );
          tx.update(doc(db, "rooms/recency-transitions"), {
            memberCount: 0,
            updatedAt: serverTimestamp(),
          });
        }),
      );
    },
  );

  await check(
    "room recency ADR-007: watchMyCommunities() hydrates and reorders after the " +
      "server callable commits chat activity",
    async () => {
      // ADR-007: the rule touched here is the rooms/{id} ROOT update, which no
      // collectionGroup query authorizes — the top-level
      // `match /{path=**}/roomMembers/{memberId}` wildcard is untouched. But
      // the feed this fix exists to serve IS a collectionGroup query, and
      // SECURITY.md principle 3 says getting that wildcard wrong fails OPEN,
      // so the claim "ordering now advances" is only proven by running the
      // query the client actually runs rather than a direct-path get().
      const member = testEnv.authenticatedContext("recency-member", {
        email_verified: true,
      });
      const db = member.firestore();

      // 1. The exact query in watchMyCommunities().
      const snapshot = await assertSucceeds(
        getDocs(
          query(
            collectionGroup(db, "roomMembers"),
            where("userId", "==", "recency-member"),
          ),
        ),
      );
      const roomIds = snapshot.docs
        .map((d) => d.ref.parent.parent && d.ref.parent.parent.id)
        .filter(Boolean);
      if (!roomIds.includes("recency-room")) {
        throw new Error(
          `expected recency-room in the collectionGroup feed, got ${roomIds}`,
        );
      }

      // 2. The Future.wait hydration that follows it. One unreadable room
      //    empties the whole Communities tab, so every id must resolve.
      const before = await Promise.all(
        roomIds.map((id) => assertSucceeds(getDoc(doc(db, `rooms/${id}`)))),
      );
      const stamp = (snap) => {
        const value = snap.data().updatedAt;
        return value ? value.toMillis() : 0;
      };
      const beforeStamp = stamp(
        before[roomIds.indexOf("recency-room")],
      );

      // 3. Chat, then the bump — and the ordering field must actually move,
      //    which is the whole user-visible point. A permitted write that did
      //    not advance updatedAt would leave the feed just as stale.
      await assertFails(
        addDoc(collection(db, "rooms/recency-room/messages"), {
          senderId: "recency-member",
          senderName: "recency-member",
          senderPhotoUrl: null,
          text: "does this room look active yet",
          createdAt: serverTimestamp(),
          reactions: {},
        }),
      );
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const serverDb = ctx.firestore();
        await addDoc(collection(serverDb, "rooms/recency-room/messages"), {
          senderId: "recency-member",
          senderName: "recency-member",
          senderPhotoUrl: null,
          text: "does this room look active yet",
          createdAt: serverTimestamp(),
          reactions: {},
        });
        await updateDoc(doc(serverDb, "rooms/recency-room"), {
          updatedAt: serverTimestamp(),
        });
      });

      const after = await assertSucceeds(
        getDoc(doc(db, "rooms/recency-room")),
      );
      if (stamp(after) <= beforeStamp) {
        throw new Error(
          `updatedAt did not advance: ${beforeStamp} -> ${stamp(after)}`,
        );
      }
    },
  );

  await check(
    "statusMessage (vibe): owner can set it, another user cannot",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "users/vibe-uid"), {
          uid: "vibe-uid",
          displayName: "Vibe User",
        });
      });
      const owner = testEnv.authenticatedContext("vibe-uid", {
        email_verified: true,
      });
      await assertSucceeds(
        updateDoc(doc(owner.firestore(), "users/vibe-uid"), {
          statusMessage: "Music + late night talks",
        }),
      );
      await assertFails(
        updateDoc(doc(host.firestore(), "users/vibe-uid"), {
          statusMessage: "hijacked vibe",
        }),
      );
    },
  );

  await check(
    "accountType: creator requires premium; personal is free; official never client-settable",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await Promise.all([
          setDoc(
            doc(db, "users/host-uid"),
            { accountType: "personal" },
            { merge: true },
          ),
          setDoc(
            doc(db, "users/attacker-uid"),
            { accountType: "personal" },
            { merge: true },
          ),
          setDoc(doc(db, "entitlements/host-uid"), {
            status: "active",
            isPremium: true,
            creatorEnabled: true,
            premiumIdentityEnabled: true,
            currentPeriodEnd: new Date(Date.now() + 86400000),
          }),
        ]);
      });
      // Premium host can become creator.
      await assertSucceeds(
        updateDoc(doc(host.firestore(), "users/host-uid"), {
          accountType: "creator",
        }),
      );
      // Free attacker cannot.
      await assertFails(
        updateDoc(doc(attacker.firestore(), "users/attacker-uid"), {
          accountType: "creator",
        }),
      );
      // Nobody can self-declare official.
      await assertFails(
        updateDoc(doc(host.firestore(), "users/host-uid"), {
          accountType: "official",
        }),
      );
      // Dropping back to personal is always allowed.
      await assertSucceeds(
        updateDoc(doc(host.firestore(), "users/host-uid"), {
          accountType: "personal",
        }),
      );
    },
  );

  // Moderator and superModerator receive a non-billing Premium preview so
  // they can exercise Creator and Clubs. The signed role claim must match the
  // server-owned users/{uid}.role mirror; superAdmin and every other role stay
  // outside this product benefit.
  const moderatorPreviewCases = [
    {
      uid: "premium-preview-mod-uid",
      claimRole: "moderator",
      mirrorRole: "moderator",
      allowed: true,
    },
    {
      uid: "premium-preview-super-mod-uid",
      claimRole: "superModerator",
      mirrorRole: "superModerator",
      allowed: true,
    },
    {
      uid: "premium-preview-owner-uid",
      claimRole: "superAdmin",
      mirrorRole: "superAdmin",
      allowed: false,
    },
    {
      uid: "premium-preview-stale-uid",
      claimRole: "moderator",
      mirrorRole: "user",
      allowed: false,
    },
    {
      uid: "premium-preview-mismatched-staff-uid",
      claimRole: "moderator",
      mirrorRole: "superModerator",
      allowed: false,
    },
    {
      uid: "premium-preview-disabled-uid",
      claimRole: "moderator",
      mirrorRole: "moderator",
      disabled: true,
      allowed: false,
    },
    {
      uid: "premium-preview-deleted-uid",
      claimRole: "superModerator",
      mirrorRole: "superModerator",
      deleted: true,
      allowed: false,
    },
  ];

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await Promise.all(
      moderatorPreviewCases.map((entry) =>
        setDoc(doc(db, `users/${entry.uid}`), {
          uid: entry.uid,
          displayName: entry.uid,
          accountType: "personal",
          role: entry.mirrorRole,
          banned: false,
          disabled: entry.disabled === true,
          deleted: entry.deleted === true,
          status: entry.deleted === true ? "deleted" : "active",
        }),
      ),
    );
  });

  for (const entry of moderatorPreviewCases) {
    await check(
      `moderator Premium preview ${entry.allowed ? "allows" : "denies"} `
        + `${entry.claimRole}/${entry.mirrorRole} for Creator`,
      async () => {
        const context = testEnv.authenticatedContext(entry.uid, {
          email_verified: true,
          role: entry.claimRole,
        });
        const operation = updateDoc(doc(context.firestore(), `users/${entry.uid}`), {
          accountType: "creator",
        });
        if (entry.allowed) {
          await assertSucceeds(operation);
        } else {
          await assertFails(operation);
        }
      },
    );
  }

  await check(
    "moderator public Creator pin works without a billing entitlement and stops after demotion",
    async () => {
      const creatorId = "premium-preview-pinned-mod-uid";
      const readerId = "premium-preview-reader-uid";
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await Promise.all([
          setDoc(doc(db, `users/${creatorId}`), {
            uid: creatorId,
            displayName: "Preview moderator",
            accountType: "creator",
            role: "moderator",
            banned: false,
            disabled: false,
            deleted: false,
            status: "active",
          }),
          setDoc(doc(db, `users/${readerId}`), {
            uid: readerId,
            displayName: "Preview reader",
            role: "user",
            banned: false,
            disabled: false,
            deleted: false,
            status: "active",
          }),
          setDoc(doc(db, `creatorPinnedPosts/${creatorId}`), {
            schemaVersion: 1,
            creatorId,
            momentId: "preview-moment",
            pinnedAt: new Date(),
            updatedAt: new Date(),
          }),
        ]);
      });

      const reader = testEnv.authenticatedContext(readerId, {
        email_verified: true,
      });
      const pin = doc(reader.firestore(), `creatorPinnedPosts/${creatorId}`);
      await assertSucceeds(getDoc(pin));

      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await updateDoc(doc(ctx.firestore(), `users/${creatorId}`), {
          role: "user",
        });
      });
      await assertFails(getDoc(pin));
    },
  );

  await check(
    "SECURITY: first users-doc write allows normal bootstrap but rejects forged premium identity",
    async () => {
      const fresh = testEnv.authenticatedContext("fresh-profile-uid", {
        email_verified: true,
      });
      await assertSucceeds(
        setDoc(doc(fresh.firestore(), "users/fresh-profile-uid"), {
          uid: "fresh-profile-uid",
          email: "fresh@yovoice.app",
          displayName: "Fresh Profile",
          username: "fresh",
          accountType: "personal",
          friendCount: 0,
          isOnline: true,
          lastSeen: serverTimestamp(),
        }),
      );

      const presence = testEnv.authenticatedContext("presence-first-uid", {
        email_verified: true,
      });
      await assertSucceeds(
        setDoc(doc(presence.firestore(), "users/presence-first-uid"), {
          isOnline: true,
          lastSeen: serverTimestamp(),
          presenceUpdatedAt: serverTimestamp(),
        }),
      );

      const forged = testEnv.authenticatedContext("forged-profile-uid", {
        email_verified: true,
      });
      await assertFails(
        setDoc(doc(forged.firestore(), "users/forged-profile-uid"), {
          uid: "forged-profile-uid",
          accountType: "creator",
        }),
      );
      await assertFails(
        setDoc(doc(forged.firestore(), "users/forged-profile-uid"), {
          uid: "forged-profile-uid",
          premiumIdentity: true,
        }),
      );
      await assertFails(
        setDoc(doc(forged.firestore(), "users/forged-profile-uid"), {
          uid: "forged-profile-uid",
          role: "superAdmin",
        }),
      );
      await assertFails(
        setDoc(doc(forged.firestore(), "users/forged-profile-uid"), {
          uid: "forged-profile-uid",
          friendCount: 500,
          followerCount: 500,
          followingCount: 500,
        }),
      );
    },
  );

  await check(
    "active subscription cannot bypass disabled Creator/Clubs capability flags",
    async () => {
      const limited = testEnv.authenticatedContext("limited-premium-uid", {
        email_verified: true,
      });
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "users/limited-premium-uid"), {
          uid: "limited-premium-uid",
          accountType: "personal",
        });
        await setDoc(
          doc(ctx.firestore(), "entitlements/limited-premium-uid"),
          {
            status: "active",
            currentPeriodEnd: new Date(Date.now() + 86400000),
            creatorEnabled: false,
            canCreateClubs: false,
            premiumIdentityEnabled: true,
          },
        );
      });

      await assertFails(
        updateDoc(doc(limited.firestore(), "users/limited-premium-uid"), {
          accountType: "creator",
        }),
      );
      await assertFails(
        setDoc(doc(limited.firestore(), "clubs/limited-premium-club"), {
          ownerId: "limited-premium-uid",
          name: "No capability",
          memberCount: 1,
        }),
      );

      // Feature flags cannot manufacture paid authority when the canonical
      // billing writer did not mark the entitlement itself Premium.
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), "entitlements/limited-premium-uid"),
          {
            status: "active",
            currentPeriodEnd: new Date(Date.now() + 86400000),
            creatorEnabled: true,
            canCreateClubs: true,
            premiumIdentityEnabled: true,
          },
        );
      });
      await assertFails(
        updateDoc(doc(limited.firestore(), "users/limited-premium-uid"), {
          accountType: "creator",
        }),
      );

      // Legacy/malformed entitlement documents must fail closed too. The
      // rules default absent capability flags to false, matching Flutter.
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), "entitlements/limited-premium-uid"),
          {
            status: "active",
            currentPeriodEnd: new Date(Date.now() + 86400000),
          },
        );
      });
      await assertFails(
        updateDoc(doc(limited.firestore(), "users/limited-premium-uid"), {
          accountType: "creator",
        }),
      );
      await assertFails(
        setDoc(doc(limited.firestore(), "clubs/missing-capability-club"), {
          ownerId: "limited-premium-uid",
          name: "Missing capability",
          memberCount: 1,
        }),
      );
    },
  );

  await check("client cannot write premiumIdentity on users doc", async () => {
    await assertFails(
      updateDoc(doc(host.firestore(), "users/host-uid"), {
        premiumIdentity: true,
      }),
    );
  });

  await check(
    "SECURITY: role transition marker is server-only and client-immutable",
    async () => {
      const ref = doc(host.firestore(), "users/host-uid");
      await assertFails(updateDoc(ref, { roleTransitionInProgress: true }));
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await updateDoc(doc(ctx.firestore(), "users/host-uid"), {
          roleTransitionInProgress: true,
        });
      });
      await assertFails(updateDoc(ref, { roleTransitionInProgress: false }));
      await assertFails(
        updateDoc(ref, { roleTransitionInProgress: deleteField() }),
      );
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await updateDoc(doc(ctx.firestore(), "users/host-uid"), {
          roleTransitionInProgress: false,
        });
      });
    },
  );

  // ── Conversation bootstrap (first-chat transaction.get) ──────────

  await check(
    "get on a NONEXISTENT conversation whose id contains my uid succeeds " +
      "(openOrCreateConversation's transaction.get)",
    async () => {
      await assertSucceeds(
        getDoc(doc(host.firestore(), "conversations/attacker-uid_host-uid")),
      );
      await assertSucceeds(
        getDoc(doc(host.firestore(), "conversations/host-uid_zzz-uid")),
      );
    },
  );

  await check(
    "get on a nonexistent conversation between two OTHER users is denied",
    async () => {
      await assertFails(
        getDoc(
          doc(attacker.firestore(), "conversations/host-uid_invitee-uid"),
        ),
      );
    },
  );

  await check(
    "existing conversation stays participant-only for get and list",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "conversations/host-uid_invitee-uid"), {
          participantIds: ["host-uid", "invitee-uid"],
        });
      });
      await assertSucceeds(
        getDoc(doc(host.firestore(), "conversations/host-uid_invitee-uid")),
      );
      await assertFails(
        getDoc(
          doc(attacker.firestore(), "conversations/host-uid_invitee-uid"),
        ),
      );
    },
  );

  // ── Conversation roots are server-only (ADR-062) ─────────────────
  //
  // `allow create: if false`. A conversation root asserts three things a
  // client does not own: the OTHER participant's server-derived display
  // name and photo (canonicalPublicProfile, ADR-054), BOTH participants'
  // unreadCounts/readSequences cursors, and — via
  // directConversationPairs/{pairKey} — which document id is THE thread
  // for that pair, forever. `openDirectConversation` writes the root and
  // its pair guard in one transaction; they are two halves of one atomic
  // binding.

  await check(
    "SECURITY: even a verified, active, unblocked participant cannot " +
      "create a conversation root (server-only, ADR-062)",
    async () => {
      const db = host.firestore();
      // Nothing about this caller is wrong: verified, not blocked with
      // invitee-uid, and named in participantIds. It is denied because
      // NO client may author a conversation root, not because of who
      // this one is.
      await assertFails(
        setDoc(doc(db, "conversations/host-uid_invitee-uid-fresh"), {
          participantIds: ["host-uid", "invitee-uid"],
          createdAt: new Date(),
        }),
      );
      // Nor by writing the full canonical shape the server would write —
      // the shape was never what made it legitimate.
      await assertFails(
        setDoc(doc(db, "conversations/host-uid_invitee-uid-canonical"), {
          schemaVersion: 2,
          pairKey: "host-uid_invitee-uid",
          participantIds: ["host-uid", "invitee-uid"],
          participantNames: { "host-uid": "Host", "invitee-uid": "Invitee" },
          participantEmails: { "host-uid": "", "invitee-uid": "" },
          participantPhotoUrls: { "host-uid": "", "invitee-uid": "" },
          unreadCounts: { "host-uid": 0, "invitee-uid": 0 },
          readSequences: { "host-uid": 0, "invitee-uid": 0 },
          typing: {},
          archivedBy: [],
          mutedBy: [],
          lastMessage: "",
          lastMessageId: null,
          lastMessageSequence: 0,
          lastMessageType: "text",
          lastMessageSenderId: "",
          createdAt: new Date(),
          updatedAt: new Date(),
        }),
      );
    },
  );

  const serverOwnedRootPath =
    "conversations/server-owned-host-uid-invitee-uid";
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), serverOwnedRootPath), {
      schemaVersion: 2,
      pairKey: "host-uid_invitee-uid",
      participantIds: ["host-uid", "invitee-uid"],
      participantNames: { "host-uid": "Host", "invitee-uid": "Invitee" },
      participantEmails: { "host-uid": "", "invitee-uid": "" },
      participantPhotoUrls: { "host-uid": "", "invitee-uid": "" },
      unreadCounts: { "host-uid": 0, "invitee-uid": 2 },
      readSequences: { "host-uid": 3, "invitee-uid": 1 },
      typing: {},
      archivedBy: [],
      mutedBy: [],
      lastMessage: "server-authored summary",
      lastMessageId: "message-3",
      lastMessageSequence: 3,
      lastMessageType: "text",
      lastMessageSenderId: "invitee-uid",
      createdAt: new Date(),
      updatedAt: new Date(),
    });
  });

  await check(
    "SECURITY: a participant cannot mutate either member's unread cursor",
    async () => {
      await assertFails(
        updateDoc(doc(host.firestore(), serverOwnedRootPath), {
          unreadCounts: { "host-uid": 0, "invitee-uid": 0 },
        }),
      );
    },
  );

  await check(
    "SECURITY: a participant cannot mutate either member's read sequence",
    async () => {
      await assertFails(
        updateDoc(doc(host.firestore(), serverOwnedRootPath), {
          readSequences: { "host-uid": 3, "invitee-uid": 3 },
        }),
      );
    },
  );

  await check(
    "SECURITY: a participant cannot forge the last-message summary",
    async () => {
      await assertFails(
        updateDoc(doc(host.firestore(), serverOwnedRootPath), {
          lastMessage: "forged by participant",
          lastMessageId: "forged-message",
          lastMessageSequence: 99,
          lastMessageType: "text",
          lastMessageSenderId: "host-uid",
        }),
      );
    },
  );

  await check(
    "SECURITY: a participant cannot publish typing state on the root",
    async () => {
      await assertFails(
        updateDoc(doc(host.firestore(), serverOwnedRootPath), {
          typing: {
            "invitee-uid": { isTyping: true, updatedAt: new Date() },
          },
        }),
      );
    },
  );

  await check(
    "SECURITY: a participant cannot rewrite conversation participants",
    async () => {
      await assertFails(
        updateDoc(doc(host.firestore(), serverOwnedRootPath), {
          participantIds: ["host-uid", "attacker-uid"],
        }),
      );
    },
  );

  await check(
    "SECURITY: archive and mute preferences are server-owned too",
    async () => {
      const reference = doc(host.firestore(), serverOwnedRootPath);
      await assertFails(updateDoc(reference, { archivedBy: ["host-uid"] }));
      await assertFails(updateDoc(reference, { mutedBy: ["host-uid"] }));
    },
  );

  await check(
    "Admin-authoritative conversation root updates bypass client Rules",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await updateDoc(doc(ctx.firestore(), serverOwnedRootPath), {
          unreadCounts: { "host-uid": 0, "invitee-uid": 0 },
          readSequences: { "host-uid": 3, "invitee-uid": 3 },
          typing: {
            "host-uid": { isTyping: false, updatedAt: new Date() },
          },
          lastMessage: "authoritative server update",
          lastMessageId: "message-4",
          lastMessageSequence: 4,
          lastMessageSenderId: "host-uid",
          updatedAt: new Date(),
        });
      });
      const snapshot = await getDoc(
        doc(host.firestore(), serverOwnedRootPath),
      );
      assert.equal(snapshot.data().lastMessage, "authoritative server update");
      assert.equal(snapshot.data().lastMessageSequence, 4);
      assert.equal(snapshot.data().unreadCounts["invitee-uid"], 0);
    },
  );

  await check(
    "old installs fail at CREATE, not at GET — the resource == null get " +
      "branch still succeeds",
    async () => {
      // Builds already in the wild still run transaction.get() on the
      // deterministic id before attempting the create. Denying that read
      // would be a rules EVALUATION error, which surfaced on web as the
      // boxed "Dart exception thrown from converted Future" text. Letting
      // the get through and failing the create gives those installs a
      // clean, mappable permission-denied instead.
      const db = host.firestore();
      await assertSucceeds(
        getDoc(doc(db, "conversations/host-uid_someone-else-uid")),
      );
      await assertFails(
        setDoc(doc(db, "conversations/host-uid_someone-else-uid"), {
          participantIds: ["host-uid", "someone-else-uid"],
          createdAt: new Date(),
        }),
      );
    },
  );

  await check(
    "SECURITY: directConversationPairs is default-denied to every client " +
      "— read AND write, participant or not",
    async () => {
      // The absence of a match block for this collection is a DECISION,
      // not an oversight (ADR-062). The pair guard is what binds a pair
      // to one conversation id forever; a client able to write it could
      // pre-bind a victim to a root whose participantNames[victim] the
      // attacker authored.
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), "directConversationPairs/host-uid_invitee-uid"),
          {
            schemaVersion: 1,
            pairKey: "host-uid_invitee-uid",
            conversationId: "dm_seeded",
            participantIds: ["host-uid", "invitee-uid"],
            createdAt: new Date(),
          },
        );
      });

      const pairPath = "directConversationPairs/host-uid_invitee-uid";
      // A participant of the pair.
      await assertFails(getDoc(doc(host.firestore(), pairPath)));
      await assertFails(
        setDoc(doc(host.firestore(), pairPath), {
          schemaVersion: 1,
          pairKey: "host-uid_invitee-uid",
          conversationId: "dm_hijacked",
          participantIds: ["host-uid", "invitee-uid"],
          createdAt: new Date(),
        }),
      );
      await assertFails(
        updateDoc(doc(host.firestore(), pairPath), {
          conversationId: "dm_hijacked",
        }),
      );
      await assertFails(deleteDoc(doc(host.firestore(), pairPath)));

      // A non-participant.
      await assertFails(getDoc(doc(attacker.firestore(), pairPath)));
      await assertFails(
        setDoc(
          doc(attacker.firestore(), "directConversationPairs/attacker-forged"),
          { conversationId: "dm_forged" },
        ),
      );

      // Unauthenticated.
      const anonymous = testEnv.unauthenticatedContext();
      await assertFails(getDoc(doc(anonymous.firestore(), pairPath)));
      await assertFails(
        setDoc(doc(anonymous.firestore(), pairPath), {
          conversationId: "dm_forged",
        }),
      );

      // And the collection cannot be enumerated to learn who talks to whom.
      await assertFails(
        getDocs(collection(host.firestore(), "directConversationPairs")),
      );
    },
  );

  // All notification types are now server-derived. A client writing one is,
  // by definition, a forgery; only safe owner acknowledgement remains.
  for (const forged of [
    "friendRequest",
    "friendAccepted",
    "follow",
    "clubInvite",
    "clubInviteAccepted",
    "roomInvite",
    "broadcastInvite",
    "mention",
  ]) {
    await check(
      `SECURITY: a client cannot write a '${forged}' notification — it is ` +
        "server-derived",
      async () => {
        await assertFails(
          setDoc(
            doc(
              host.firestore(),
              `users/invitee-uid/notifications/${forged}_host-uid`,
            ),
            {
              type: forged,
              actorId: "host-uid",
              actorName: "Host",
              actorPhotoUrl: null,
              targetId: null,
              targetLabel: null,
              isRead: false,
              createdAt: new Date(),
              dedupeKey: null,
              bellSuppressed: false,
            },
          ),
        );
      },
    );
  }

  await check(
    "a recipient can still acknowledge a server-written social " +
      "notification, and only through the safe fields",
    async () => {
      const path = "users/invitee-uid/notifications/follow_host-uid";
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), path), {
          type: "follow",
          actorId: "host-uid",
          actorName: "Host",
          actorPhotoUrl: null,
          targetId: null,
          targetLabel: null,
          isRead: false,
          createdAt: new Date(),
          dedupeKey: "follow_host-uid",
          bellSuppressed: false,
        });
      });
      // The owner may mark it read...
      await assertSucceeds(
        updateDoc(doc(invitee.firestore(), path), {
          isRead: true,
          readAt: new Date(),
        }),
      );
      // ...but may not rewrite who it came from.
      await assertFails(
        updateDoc(doc(invitee.firestore(), path), { actorId: "someone-else" }),
      );
      // ...and a third party cannot touch it at all.
      await assertFails(
        updateDoc(doc(attacker.firestore(), path), { isRead: true }),
      );
    },
  );


  // ==================================================================
  // GLOBAL CHAT — the public community channel. Every case below is an
  // attack scenario or a real client path; a public write surface with
  // no test coverage is not a shippable public write surface.
  // ==================================================================

  const GLOBAL = "globalChat/main/messages";
  const SENDER_STATE = (uid) => `globalChat/main/senders/${uid}`;

  // Profiles the create rule validates denormalised identity against.
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "users/host-uid"), {
      uid: "host-uid",
      displayName: "Host",
      accountType: "personal",
    });
    await setDoc(doc(db, "users/attacker-uid"), {
      uid: "attacker-uid",
      displayName: "Attacker",
      accountType: "personal",
    });
    await setDoc(doc(db, "users/mod-uid"), {
      uid: "mod-uid",
      displayName: "Mod",
      accountType: "personal",
      // isActiveStaff() requires BOTH the signed claim and this
      // server-written mirror, which is what assignUserRole maintains.
      role: "moderator",
    });
    await setDoc(doc(db, "users/mod-disabled-uid"), {
      uid: "mod-disabled-uid",
      displayName: "Disabled mod",
      role: "moderator",
      disabled: true,
    });
    await setDoc(doc(db, "users/mod-deleted-flag-uid"), {
      uid: "mod-deleted-flag-uid",
      displayName: "Deleted mod",
      role: "moderator",
      deleted: true,
    });
    await setDoc(doc(db, "users/mod-deleted-status-uid"), {
      uid: "mod-deleted-status-uid",
      displayName: "Deleted mod",
      role: "moderator",
      status: "deleted",
    });
    await setDoc(doc(db, "users/mod-cross-role-uid"), {
      uid: "mod-cross-role-uid",
      displayName: "Crossed mod",
      role: "superModerator",
    });
    // Historical record retained for Admin SDK moderation/export. Rules must
    // keep it invisible and immutable to every client, including staff.
    await setDoc(doc(db, "globalChat/main/messages/g-ok-1"), {
      senderId: "host-uid",
      senderName: "Host",
      senderPhotoUrl: null,
      senderIsCreator: false,
      senderIsStaff: false,
      content: "legacy community message",
      sentAt: new Date(),
      isDeleted: false,
      deletedBy: null,
      deletedAt: null,
    });
  });

  const moderator = testEnv.authenticatedContext("mod-uid", {
    email_verified: true,
    role: "moderator",
  });

  // A legitimate send: message + cooldown doc in ONE batch, exactly what
  // GlobalChatService.sendMessage() writes.
  function sendGlobal(db, uid, name, id, overrides = {}) {
    const batch = writeBatch(db);
    batch.set(doc(db, `${GLOBAL}/${id}`), {
      senderId: uid,
      senderName: name,
      senderPhotoUrl: null,
      senderIsCreator: false,
      senderIsStaff: false,
      content: "hello community",
      sentAt: serverTimestamp(),
      isDeleted: false,
      deletedBy: null,
      deletedAt: null,
      ...Object.fromEntries(
        Object.entries(overrides).filter(([key]) => key !== "__state"),
      ),
    });
    batch.set(doc(db, SENDER_STATE(uid)), {
      lastMessageAt: serverTimestamp(),
      lastMessageId: id,
      windowStartAt: serverTimestamp(),
      windowCount: 1,
      ...(overrides.__state ?? {}),
    });
    return batch.commit();
  }

  await check(
    "SECURITY GLOBAL: an old verified client cannot post after retirement",
    async () => {
      await assertFails(
        sendGlobal(host.firestore(), "host-uid", "Host", "g-ok-1"),
      );
    },
  );

  await check(
    "SECURITY GLOBAL: historical messages are client-invisible",
    async () => {
      await assertFails(
        getDoc(doc(attacker.firestore(), `${GLOBAL}/g-ok-1`)),
      );
    },
  );

  await check("GLOBAL: unauthenticated users cannot READ the channel", async () => {
    await assertFails(
      getDocs(
        query(
          collection(testEnv.unauthenticatedContext().firestore(), GLOBAL),
          orderBy("sentAt", "desc"),
          limit(25),
        ),
      ),
    );
  });

  await check("GLOBAL: unauthenticated users cannot SEND", async () => {
    await assertFails(
      sendGlobal(
        testEnv.unauthenticatedContext().firestore(),
        "host-uid",
        "Host",
        "g-anon",
      ),
    );
  });

  await check(
    "SECURITY GLOBAL: a client cannot post as someone else (senderId spoof)",
    async () => {
      await assertFails(
        sendGlobal(attacker.firestore(), "host-uid", "Host", "g-spoof-id"),
      );
    },
  );

  await check(
    "SECURITY GLOBAL: a client cannot post under another member's NAME " +
      "(display name must match their own profile document)",
    async () => {
      await assertFails(
        sendGlobal(attacker.firestore(), "attacker-uid", "Host", "g-spoof-name"),
      );
    },
  );

  await check(
    "SECURITY GLOBAL: a client cannot award itself the staff badge",
    async () => {
      await assertFails(
        sendGlobal(
          attacker.firestore(),
          "attacker-uid",
          "Attacker",
          "g-spoof-staff",
          { senderIsStaff: true },
        ),
      );
    },
  );

  await check(
    "SECURITY GLOBAL: a client cannot supply its own timestamp",
    async () => {
      const db = attacker.firestore();
      const batch = writeBatch(db);
      batch.set(doc(db, `${GLOBAL}/g-fake-time`), {
        senderId: "attacker-uid",
        senderName: "Attacker",
        senderPhotoUrl: null,
        senderIsCreator: false,
        senderIsStaff: false,
        content: "backdated",
        // A client-chosen date instead of the server's clock.
        sentAt: new Date(2020, 0, 1),
        isDeleted: false,
        deletedBy: null,
        deletedAt: null,
      });
      batch.set(doc(db, SENDER_STATE("attacker-uid")), {
        lastMessageAt: serverTimestamp(),
        lastMessageId: "g-fake-time",
      });
      await assertFails(batch.commit());
    },
  );

  await check("GLOBAL: empty and blank-only messages are rejected", async () => {
    await assertFails(
      sendGlobal(host.firestore(), "host-uid", "Host", "g-empty", {
        content: "",
      }),
    );
    await assertFails(
      sendGlobal(host.firestore(), "host-uid", "Host", "g-blank", {
        content: "      ",
      }),
    );
  });

  await check("GLOBAL: oversized messages are rejected", async () => {
    await assertFails(
      sendGlobal(host.firestore(), "host-uid", "Host", "g-long", {
        content: "x".repeat(501),
      }),
    );
  });

  await check(
    "GLOBAL: a message cannot arrive already flagged as deleted",
    async () => {
      await assertFails(
        sendGlobal(host.firestore(), "host-uid", "Host", "g-predeleted", {
          isDeleted: true,
        }),
      );
    },
  );

  await check(
    "SECURITY GLOBAL: posting WITHOUT advancing the cooldown doc is " +
      "rejected — the rate limiter cannot be skipped",
    async () => {
      await assertFails(
        setDoc(doc(attacker.firestore(), `${GLOBAL}/g-no-cooldown`), {
          senderId: "attacker-uid",
          senderName: "Attacker",
          senderPhotoUrl: null,
          senderIsCreator: false,
          senderIsStaff: false,
          content: "no cooldown doc",
          sentAt: serverTimestamp(),
          isDeleted: false,
          deletedBy: null,
          deletedAt: null,
        }),
      );
    },
  );

  await check(
    "SECURITY GLOBAL: a second message inside the cooldown window is " +
      "rejected (spam floor)",
    async () => {
      // host-uid posted g-ok-1 moments ago; 3s cannot have elapsed.
      await assertFails(
        sendGlobal(host.firestore(), "host-uid", "Host", "g-too-fast"),
      );
    },
  );

  await check(
    "SECURITY GLOBAL: a BATCH of many messages sharing one cooldown " +
      "update is rejected — burst spam cannot buy N sends for one slot",
    async () => {
      const db = attacker.firestore();
      const batch = writeBatch(db);
      for (const id of ["g-burst-1", "g-burst-2", "g-burst-3"]) {
        batch.set(doc(db, `${GLOBAL}/${id}`), {
          senderId: "attacker-uid",
          senderName: "Attacker",
          senderPhotoUrl: null,
          senderIsCreator: false,
          senderIsStaff: false,
          content: "burst",
          sentAt: serverTimestamp(),
          isDeleted: false,
          deletedBy: null,
          deletedAt: null,
        });
      }
      batch.set(doc(db, SENDER_STATE("attacker-uid")), {
        lastMessageAt: serverTimestamp(),
        lastMessageId: "g-burst-1",
      });
      await assertFails(batch.commit());
    },
  );

  await check(
    "SECURITY GLOBAL: the cooldown doc cannot be deleted to reset the limit",
    async () => {
      await assertFails(
        deleteDoc(doc(host.firestore(), SENDER_STATE("host-uid"))),
      );
    },
  );

  await check(
    "SECURITY GLOBAL: nobody can read or write another member's cooldown doc",
    async () => {
      await assertFails(
        getDoc(doc(attacker.firestore(), SENDER_STATE("host-uid"))),
      );
      await assertFails(
        setDoc(doc(attacker.firestore(), SENDER_STATE("host-uid")), {
          lastMessageAt: serverTimestamp(),
          lastMessageId: "whatever",
        }),
      );
    },
  );

  await check(
    "SECURITY GLOBAL: an author cannot silently REWRITE a posted message",
    async () => {
      await assertFails(
        updateDoc(doc(host.firestore(), `${GLOBAL}/g-ok-1`), {
          content: "something else entirely",
        }),
      );
    },
  );

  await check(
    "SECURITY GLOBAL: a member cannot delete someone else's message",
    async () => {
      await assertFails(
        updateDoc(doc(attacker.firestore(), `${GLOBAL}/g-ok-1`), {
          isDeleted: true,
          deletedBy: "attacker-uid",
          deletedAt: serverTimestamp(),
          content: "",
        }),
      );
    },
  );

  await check(
    "SECURITY GLOBAL: a moderator cannot re-attribute a message while " +
      "removing it",
    async () => {
      await assertFails(
        updateDoc(doc(moderator.firestore(), `${GLOBAL}/g-ok-1`), {
          isDeleted: true,
          deletedBy: "mod-uid",
          deletedAt: serverTimestamp(),
          content: "",
          senderId: "attacker-uid",
        }),
      );
    },
  );

  await check(
    "SECURITY GLOBAL: staff clients cannot mutate historical messages",
    async () => {
      await assertFails(
        updateDoc(doc(moderator.firestore(), `${GLOBAL}/g-ok-1`), {
          isDeleted: true,
          deletedBy: "mod-uid",
          deletedAt: serverTimestamp(),
          content: "",
        }),
      );
    },
  );

  await check(
    "SECURITY GLOBAL: authors cannot mutate retired history",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await setDoc(doc(context.firestore(), "users/invitee-uid"), {
          uid: "invitee-uid",
          displayName: "Invitee",
          accountType: "personal",
        });
      });
      await assertFails(
        sendGlobal(invitee.firestore(), "invitee-uid", "Invitee", "g-mine"),
      );
      await assertFails(
        updateDoc(doc(invitee.firestore(), `${GLOBAL}/g-mine`), {
          isDeleted: true,
          deletedBy: "invitee-uid",
          deletedAt: serverTimestamp(),
          content: "",
        }),
      );
    },
  );

  await check(
    "GLOBAL: hard delete is never allowed — removals stay visible as " +
      "removals, even to staff",
    async () => {
      await assertFails(
        deleteDoc(doc(moderator.firestore(), `${GLOBAL}/g-ok-1`)),
      );
    },
  );

  await check(
    "SECURITY GLOBAL: old-client paging is denied",
    async () => {
      await assertFails(
        getDocs(
          query(
            collection(attacker.firestore(), GLOBAL),
            orderBy("sentAt", "desc"),
            limit(25),
          ),
        ),
      );
    },
  );

  await check(
    "GLOBAL: nobody can create a SECOND global channel and pass it off " +
      "as the community one",
    async () => {
      await assertFails(
        setDoc(doc(attacker.firestore(), "globalChat/fake"), {
          name: "Global",
        }),
      );
      await assertFails(
        sendGlobal(
          attacker.firestore(),
          "attacker-uid",
          "Attacker",
          "g-other-channel",
        ).then(() =>
          setDoc(doc(attacker.firestore(), "globalChat/fake/messages/x"), {
            senderId: "attacker-uid",
            senderName: "Attacker",
            senderPhotoUrl: null,
            senderIsCreator: false,
            senderIsStaff: false,
            content: "hi",
            sentAt: serverTimestamp(),
            isDeleted: false,
            deletedBy: null,
            deletedAt: null,
          }),
        ),
      );
    },
  );

  // ==================================================================
  // REPORTS — write-only for members, staff-readable, and hardened
  // against being used as a flooding or free-text channel.
  // ==================================================================

  // The deterministic id rules require. Uniqueness needs no counter:
  // a duplicate is a create against a document that already exists.
  const reportId = (uid, targetType, targetId) =>
    `${uid}_${targetType}_${targetId}`;

  function fileReport(db, uid, overrides = {}) {
    const fields = {
      targetType: "globalMessage",
      targetId: "g-ok-1",
      reportedUserId: "host-uid",
      contextPath: `${GLOBAL}/g-ok-1`,
      reason: "spam",
      note: "",
      // The one workflow field a client may write, pinned by rules.
      status: "open",
      ...overrides,
    };
    const id =
      overrides.__id ?? reportId(uid, fields.targetType, fields.targetId);
    delete fields.__id;
    const state = overrides.__state;
    delete fields.__state;

    const batch = writeBatch(db);
    batch.set(doc(db, `reports/${id}`), {
      reporterId: uid,
      createdAt: serverTimestamp(),
      ...fields,
    });
    batch.set(doc(db, `reportLimits/${uid}`), {
      lastReportAt: serverTimestamp(),
      lastReportId: id,
      windowStartAt: serverTimestamp(),
      windowCount: 1,
      ...(state ?? {}),
    });
    return batch.commit();
  }

  await check("REPORTS: a member can file a report", async () => {
    await assertSucceeds(fileReport(attacker.firestore(), "attacker-uid"));
  });

  await check(
    "SECURITY REPORTS: the SAME reporter cannot report the SAME target " +
      "twice — the deterministic id makes it a create over an existing doc",
    async () => {
      await assertFails(fileReport(attacker.firestore(), "attacker-uid"));
    },
  );

  await check(
    "SECURITY REPORTS: a report cannot be filed under a NON-deterministic " +
      "id, which would defeat the uniqueness mechanism",
    async () => {
      await assertFails(
        fileReport(attacker.firestore(), "attacker-uid", {
          __id: "some-random-id",
        }),
      );
    },
  );

  await check(
    "SECURITY REPORTS: the cooldown cannot be bypassed — a second report " +
      "within 30s is rejected",
    async () => {
      // attacker-uid filed one moments ago; a different target, so the
      // id is fresh and only the cooldown can stop it.
      await assertFails(
        fileReport(attacker.firestore(), "attacker-uid", {
          targetType: "user",
          targetId: "host-uid",
          reportedUserId: "host-uid",
          contextPath: null,
        }),
      );
    },
  );

  await check(
    "SECURITY REPORTS: the fixed 24h window cap rejects the 21st report",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await setDoc(doc(context.firestore(), "reportLimits/invitee-uid"), {
          lastReportAt: new Date(Date.now() - 5 * 60 * 1000),
          lastReportId: "earlier",
          windowStartAt: new Date(Date.now() - 60 * 60 * 1000),
          windowCount: 20,
        });
      });
      await assertFails(
        fileReport(invitee.firestore(), "invitee-uid", {
          __state: {
            windowStartAt: new Date(Date.now() - 60 * 60 * 1000),
            windowCount: 21,
          },
        }),
      );
    },
  );

  await check(
    "SECURITY REPORTS: a nonexistent target cannot be reported",
    async () => {
      await assertFails(
        fileReport(moderator.firestore(), "mod-uid", {
          targetId: "no-such-message",
          reportedUserId: "host-uid",
        }),
      );
      await assertFails(
        fileReport(moderator.firestore(), "mod-uid", {
          targetType: "user",
          targetId: "no-such-user",
          reportedUserId: "no-such-user",
          contextPath: null,
        }),
      );
    },
  );

  await check(
    "SECURITY REPORTS: reportedUserId must be the target's REAL owner, " +
      "not an arbitrary uid attached to a real message",
    async () => {
      await assertFails(
        fileReport(moderator.firestore(), "mod-uid", {
          targetId: "g-ok-1",
          // g-ok-1 was written by host-uid.
          reportedUserId: "invitee-uid",
        }),
      );
    },
  );

  await check(
    "SECURITY REPORTS: a member cannot file one in someone else's name",
    async () => {
      const db = attacker.firestore();
      const id = reportId("host-uid", "globalMessage", "g-ok-1");
      const batch = writeBatch(db);
      batch.set(doc(db, `reports/${id}`), {
        reporterId: "host-uid",
        targetType: "globalMessage",
        targetId: "g-ok-1",
        reportedUserId: "host-uid",
        contextPath: null,
        reason: "spam",
        note: "",
        createdAt: serverTimestamp(),
      });
      batch.set(doc(db, "reportLimits/attacker-uid"), {
        lastReportAt: serverTimestamp(),
        lastReportId: id,
        windowStartAt: serverTimestamp(),
        windowCount: 1,
      });
      await assertFails(batch.commit());
    },
  );

  await check(
    "SECURITY REPORTS: a client cannot supply its own createdAt",
    async () => {
      await assertFails(
        fileReport(moderator.firestore(), "mod-uid", {
          createdAt: new Date(2020, 0, 1),
        }),
      );
    },
  );

  await check(
    "SECURITY REPORTS: invalid target types and reasons are rejected",
    async () => {
      await assertFails(
        fileReport(moderator.firestore(), "mod-uid", {
          targetType: "room",
        }),
      );
      await assertFails(
        fileReport(moderator.firestore(), "mod-uid", {
          reason: "because I said so",
        }),
      );
    },
  );

  await check(
    "SECURITY REPORTS: an oversized explanation is rejected",
    async () => {
      await assertFails(
        fileReport(moderator.firestore(), "mod-uid", {
          note: "x".repeat(301),
        }),
      );
    },
  );

  await check(
    "SECURITY REPORTS: a reporter cannot set staff workflow fields " +
      "(status, assignee, resolution)",
    async () => {
      for (const extra of [
        { status: "closed" },
        { assignedTo: "mod-uid" },
        { resolution: "dismissed" },
      ]) {
        await assertFails(
          fileReport(moderator.firestore(), "mod-uid", extra),
        );
      }
    },
  );

  await check(
    "SECURITY REPORTS: nobody can report themselves",
    async () => {
      await assertFails(
        fileReport(moderator.firestore(), "mod-uid", {
          targetType: "user",
          targetId: "mod-uid",
          reportedUserId: "mod-uid",
          contextPath: null,
        }),
      );
    },
  );

  await check(
    "SECURITY REPORTS: filing without advancing the rate-limit document " +
      "is rejected",
    async () => {
      await assertFails(
        setDoc(
          doc(
            invitee.firestore(),
            `reports/${reportId("invitee-uid", "globalMessage", "g-ok-1")}`,
          ),
          {
            reporterId: "invitee-uid",
            targetType: "globalMessage",
            targetId: "g-ok-1",
            reportedUserId: "host-uid",
            contextPath: null,
            reason: "spam",
            note: "",
            createdAt: serverTimestamp(),
          },
        ),
      );
    },
  );

  await check(
    "SECURITY REPORTS: the rate-limit document is private and undeletable",
    async () => {
      await assertFails(
        getDoc(doc(host.firestore(), "reportLimits/attacker-uid")),
      );
      await assertFails(
        deleteDoc(doc(attacker.firestore(), "reportLimits/attacker-uid")),
      );
    },
  );

  await check(
    "SECURITY REPORTS: reports cannot be read, edited or withdrawn by " +
      "members — not even their own",
    async () => {
      const own = `reports/${reportId("attacker-uid", "globalMessage", "g-ok-1")}`;
      await assertFails(getDoc(doc(attacker.firestore(), own)));
      await assertFails(
        updateDoc(doc(attacker.firestore(), own), { status: "closed" }),
      );
      await assertFails(deleteDoc(doc(attacker.firestore(), own)));
    },
  );

  await check(
    "REPORTS: staff can READ a filed report — triage itself is not a " +
      "client write, it goes through the moderateReport callable",
    async () => {
      const filed = `reports/${reportId("attacker-uid", "globalMessage", "g-ok-1")}`;
      await assertSucceeds(getDoc(doc(moderator.firestore(), filed)));
      await assertFails(
        updateDoc(doc(moderator.firestore(), filed), { status: "resolved" }),
      );
    },
  );

  await check(
    "SECURITY REPORTS: disabled, deleted and cross-role staff tokens cannot read the queue",
    async () => {
      const filed = `reports/${reportId("attacker-uid", "globalMessage", "g-ok-1")}`;
      const denied = [
        ["mod-disabled-uid", "moderator"],
        ["mod-deleted-flag-uid", "moderator"],
        ["mod-deleted-status-uid", "moderator"],
        ["mod-cross-role-uid", "moderator"],
      ];
      for (const [uid, role] of denied) {
        const context = testEnv.authenticatedContext(uid, {
          email_verified: true,
          role,
        });
        await assertFails(getDoc(doc(context.firestore(), filed)));
      }
    },
  );

  await check(
    "SECURITY: adminAuditLogs is invisible to every client, staff included",
    async () => {
      await assertFails(getDoc(doc(host.firestore(), "adminAuditLogs/x")));
      await assertFails(getDoc(doc(moderator.firestore(), "adminAuditLogs/x")));
      await assertFails(
        setDoc(doc(moderator.firestore(), "adminAuditLogs/x"), { a: 1 }),
      );
    },
  );

  // ==================================================================
  // ACCOUNT STATUS — a ban must bite immediately, not when the banned
  // user's ID token happens to expire.
  // ==================================================================

  const banned = testEnv.authenticatedContext("banned-uid", {
    email_verified: true,
  });

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "users/banned-uid"), {
      uid: "banned-uid",
      displayName: "Banned",
      accountType: "personal",
      // Exactly what functions/admin/users.js's setUserBan writes.
      banned: true,
      banReason: "Administrative action",
      bannedUntil: null,
    });
  });

  await check(
    "SECURITY BAN: a banned account holding a still-valid token cannot " +
      "READ Global Chat",
    async () => {
      await assertFails(
        getDocs(
          query(
            collection(banned.firestore(), GLOBAL),
            orderBy("sentAt", "desc"),
            limit(25),
          ),
        ),
      );
    },
  );

  await check("SECURITY BAN: a banned account cannot SEND", async () => {
    await assertFails(
      sendGlobal(banned.firestore(), "banned-uid", "Banned", "g-banned"),
    );
  });

  await check(
    "SECURITY BAN: a banned account cannot soft-delete its own message",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await setDoc(doc(context.firestore(), `${GLOBAL}/g-by-banned`), {
          senderId: "banned-uid",
          senderName: "Banned",
          senderPhotoUrl: null,
          senderIsCreator: false,
          senderIsStaff: false,
          content: "posted before the ban",
          sentAt: new Date(),
          isDeleted: false,
          deletedBy: null,
          deletedAt: null,
        });
      });
      await assertFails(
        updateDoc(doc(banned.firestore(), `${GLOBAL}/g-by-banned`), {
          isDeleted: true,
          deletedBy: "banned-uid",
          deletedAt: serverTimestamp(),
          content: "",
        }),
      );
    },
  );

  await check("SECURITY BAN: a banned account cannot file a report", async () => {
    await assertFails(
      fileReport(banned.firestore(), "banned-uid", {
        targetType: "globalMessage",
        targetId: "g-ok-1",
        reportedUserId: "host-uid",
      }),
    );
  });

  await check(
    "SECURITY BAN: the banned flag is NOT self-writable — a user cannot " +
      "clear their own restriction, or set someone else's",
    async () => {
      await assertFails(
        updateDoc(doc(banned.firestore(), "users/banned-uid"), {
          banned: false,
        }),
      );
      await assertFails(
        updateDoc(doc(attacker.firestore(), "users/attacker-uid"), {
          banned: true,
        }),
      );
      // Legitimate profile edits still work — the allowlist is intact.
      await assertSucceeds(
        updateDoc(doc(attacker.firestore(), "users/attacker-uid"), {
          bio: "still editable",
        }),
      );
    },
  );

  await check(
    "SECURITY GLOBAL: retirement denies even an otherwise active account",
    async () => {
      await assertFails(
        getDocs(
          query(
            collection(invitee.firestore(), GLOBAL),
            orderBy("sentAt", "desc"),
            limit(5),
          ),
        ),
      );
    },
  );

  // ==================================================================
  // CHANNEL BOOTSTRAP — the parent document is not a prerequisite.
  // ==================================================================

  await check(
    "SECURITY GLOBAL: an absent parent cannot reopen retired messages",
    async () => {
      let parentExists = true;
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const snapshot = await getDoc(
          doc(context.firestore(), "globalChat/main"),
        );
        parentExists = snapshot.exists();
      });
      if (parentExists) {
        throw new Error(
          "the suite never created globalChat/main, yet it exists",
        );
      }
      await assertFails(
        getDocs(
          query(
            collection(invitee.firestore(), GLOBAL),
            orderBy("sentAt", "desc"),
            limit(5),
          ),
        ),
      );
    },
  );

  await check(
    "SECURITY GLOBAL: the client cannot create the channel document",
    async () => {
      await assertFails(
        setDoc(doc(host.firestore(), "globalChat/main"), { name: "Global" }),
      );
    },
  );

  // ==================================================================
  // SUSTAINED SEND LIMIT — the 3s floor alone still allows 1,200/hour.
  // ==================================================================

  await check(
    "SECURITY RATE: the fixed-window cap rejects the 201st message",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await setDoc(doc(context.firestore(), SENDER_STATE("invitee-uid")), {
          lastMessageAt: new Date(Date.now() - 60 * 1000),
          lastMessageId: "earlier",
          windowStartAt: new Date(Date.now() - 30 * 60 * 1000),
          windowCount: 200,
        });
      });
      const db = invitee.firestore();
      const batch = writeBatch(db);
      batch.set(doc(db, `${GLOBAL}/g-over-cap`), {
        senderId: "invitee-uid",
        senderName: "Invitee",
        senderPhotoUrl: null,
        senderIsCreator: false,
        senderIsStaff: false,
        content: "one too many",
        sentAt: serverTimestamp(),
        isDeleted: false,
        deletedBy: null,
        deletedAt: null,
      });
      batch.set(doc(db, SENDER_STATE("invitee-uid")), {
        lastMessageAt: serverTimestamp(),
        lastMessageId: "g-over-cap",
        windowStartAt: new Date(Date.now() - 30 * 60 * 1000),
        windowCount: 201,
      });
      await assertFails(batch.commit());
    },
  );

  await check(
    "SECURITY GLOBAL: retirement supersedes the former rate-limit boundary",
    async () => {
      const windowStart = new Date(Date.now() - 30 * 60 * 1000);
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await setDoc(doc(context.firestore(), SENDER_STATE("invitee-uid")), {
          lastMessageAt: new Date(Date.now() - 60 * 1000),
          lastMessageId: "earlier",
          windowStartAt: windowStart,
          windowCount: 199,
        });
      });
      const db = invitee.firestore();
      const batch = writeBatch(db);
      batch.set(doc(db, `${GLOBAL}/g-at-cap`), {
        senderId: "invitee-uid",
        senderName: "Invitee",
        senderPhotoUrl: null,
        senderIsCreator: false,
        senderIsStaff: false,
        content: "the two hundredth",
        sentAt: serverTimestamp(),
        isDeleted: false,
        deletedBy: null,
        deletedAt: null,
      });
      batch.set(doc(db, SENDER_STATE("invitee-uid")), {
        lastMessageAt: serverTimestamp(),
        lastMessageId: "g-at-cap",
        windowStartAt: windowStart,
        windowCount: 200,
      });
      await assertFails(batch.commit());
    },
  );

  await check(
    "SECURITY RATE: a client cannot silently RESET the window to dodge " +
      "the cap",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await setDoc(doc(context.firestore(), SENDER_STATE("invitee-uid")), {
          lastMessageAt: new Date(Date.now() - 60 * 1000),
          lastMessageId: "earlier",
          // A window that is still very much running.
          windowStartAt: new Date(Date.now() - 60 * 1000),
          windowCount: 200,
        });
      });
      const db = invitee.firestore();
      const batch = writeBatch(db);
      batch.set(doc(db, `${GLOBAL}/g-reset`), {
        senderId: "invitee-uid",
        senderName: "Invitee",
        senderPhotoUrl: null,
        senderIsCreator: false,
        senderIsStaff: false,
        content: "fresh window please",
        sentAt: serverTimestamp(),
        isDeleted: false,
        deletedBy: null,
        deletedAt: null,
      });
      batch.set(doc(db, SENDER_STATE("invitee-uid")), {
        lastMessageAt: serverTimestamp(),
        lastMessageId: "g-reset",
        // Pretending the window just started.
        windowStartAt: serverTimestamp(),
        windowCount: 1,
      });
      await assertFails(batch.commit());
    },
  );

  await check(
    "SECURITY GLOBAL: retirement supersedes a rolled rate-limit window",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await setDoc(doc(context.firestore(), SENDER_STATE("invitee-uid")), {
          lastMessageAt: new Date(Date.now() - 60 * 1000),
          lastMessageId: "earlier",
          windowStartAt: new Date(Date.now() - 61 * 60 * 1000),
          windowCount: 200,
        });
      });
      const db = invitee.firestore();
      const batch = writeBatch(db);
      batch.set(doc(db, `${GLOBAL}/g-rolled`), {
        senderId: "invitee-uid",
        senderName: "Invitee",
        senderPhotoUrl: null,
        senderIsCreator: false,
        senderIsStaff: false,
        content: "new hour",
        sentAt: serverTimestamp(),
        isDeleted: false,
        deletedBy: null,
        deletedAt: null,
      });
      batch.set(doc(db, SENDER_STATE("invitee-uid")), {
        lastMessageAt: serverTimestamp(),
        lastMessageId: "g-rolled",
        windowStartAt: serverTimestamp(),
        windowCount: 1,
      });
      await assertFails(batch.commit());
    },
  );


  // ==================================================================
  // EMAIL VERIFICATION — the project's existing publishing policy,
  // applied to the most outbound surface it has.
  // ==================================================================

  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users/unverified-uid"), {
      uid: "unverified-uid",
      displayName: "Unverified",
      accountType: "personal",
    });
  });

  await check(
    "SECURITY GLOBAL: an unverified old client cannot read retired history",
    async () => {
      await assertFails(
        getDocs(
          query(
            collection(unverified.firestore(), GLOBAL),
            orderBy("sentAt", "desc"),
            limit(25),
          ),
        ),
      );
    },
  );

  await check(
    "SECURITY VERIFY: an unverified account CANNOT send to Global Chat",
    async () => {
      await assertFails(
        sendGlobal(
          unverified.firestore(),
          "unverified-uid",
          "Unverified",
          "g-unverified",
        ),
      );
    },
  );

  await check(
    "SECURITY GLOBAL: verification does not reopen the retired channel",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await setDoc(doc(context.firestore(), "users/verified-uid"), {
          uid: "verified-uid",
          displayName: "Verified",
          accountType: "personal",
        });
      });
      const verified = testEnv.authenticatedContext("verified-uid", {
        email_verified: true,
      });
      await assertFails(
        sendGlobal(
          verified.firestore(),
          "verified-uid",
          "Verified",
          "g-verified",
        ),
      );
    },
  );

  await check(
    "SECURITY VERIFY: a VERIFIED but BANNED account still cannot read or " +
      "send — the two checks are independent",
    async () => {
      // `banned` context already carries email_verified: true.
      await assertFails(
        getDocs(
          query(
            collection(banned.firestore(), GLOBAL),
            orderBy("sentAt", "desc"),
            limit(5),
          ),
        ),
      );
      await assertFails(
        sendGlobal(
          banned.firestore(),
          "banned-uid",
          "Banned",
          "g-verified-banned",
        ),
      );
    },
  );

  await check(
    "SECURITY VERIFY: verification cannot be spoofed through the profile " +
      "document — it is a token claim, and the field is not writable",
    async () => {
      // Writing an emailVerified-looking field changes nothing, and the
      // allowlist rejects it outright.
      await assertFails(
        updateDoc(doc(unverified.firestore(), "users/unverified-uid"), {
          emailVerified: true,
        }),
      );
      await assertFails(
        updateDoc(doc(unverified.firestore(), "users/unverified-uid"), {
          email_verified: true,
        }),
      );
      // And sending still fails afterwards.
      await assertFails(
        sendGlobal(
          unverified.firestore(),
          "unverified-uid",
          "Unverified",
          "g-still-denied",
        ),
      );
    },
  );

  await check(
    "VERIFY: an unverified account CAN still file a report — reporting is " +
      "a safety action and follows the blocking precedent, not publishing",
    async () => {
      await assertSucceeds(
        fileReport(unverified.firestore(), "unverified-uid", {
          targetId: "g-ok-1",
          reportedUserId: "host-uid",
        }),
      );
    },
  );


  // ==================================================================
  // STAFF AUTHORITY + THE MODERATION QUEUE.
  //
  // Reports are readable only by active staff, and their workflow is
  // NOT client-writable at all — triage goes through the moderateReport
  // callable, which uses the Admin SDK.
  // ==================================================================

  // A claim that says moderator over a server record that does not.
  // This is a revoked moderator still holding a valid ID token.
  const revokedMod = testEnv.authenticatedContext("revoked-mod-uid", {
    email_verified: true,
    role: "moderator",
  });
  // Claim and record agree, but the account is restricted.
  const bannedMod = testEnv.authenticatedContext("banned-mod-uid", {
    email_verified: true,
    role: "moderator",
  });
  const adminStaff = testEnv.authenticatedContext("admin-uid", {
    email_verified: true,
    role: "superModerator",
  });

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "users/revoked-mod-uid"), {
      uid: "revoked-mod-uid",
      displayName: "Revoked",
      role: "user",
    });
    await setDoc(doc(db, "users/banned-mod-uid"), {
      uid: "banned-mod-uid",
      displayName: "Banned mod",
      role: "moderator",
      banned: true,
    });
    await setDoc(doc(db, "users/admin-uid"), {
      uid: "admin-uid",
      displayName: "Admin",
      role: "superModerator",
    });
  });

  const QUEUE = query(
    collection(moderator.firestore(), "reports"),
    where("status", "==", "open"),
    orderBy("createdAt", "desc"),
    limit(20),
  );

  await check(
    "MODERATION: an active moderator can read the report queue",
    async () => {
      await assertSucceeds(getDocs(QUEUE));
    },
  );

  await check("MODERATION: a super moderator can read the report queue", async () => {
    await assertSucceeds(
      getDocs(
        query(
          collection(adminStaff.firestore(), "reports"),
          where("status", "==", "open"),
          orderBy("createdAt", "desc"),
          limit(20),
        ),
      ),
    );
  });

  await check(
    "SECURITY MODERATION: an ordinary user cannot read the queue",
    async () => {
      await assertFails(
        getDocs(
          query(
            collection(attacker.firestore(), "reports"),
            where("status", "==", "open"),
            orderBy("createdAt", "desc"),
            limit(20),
          ),
        ),
      );
    },
  );

  await check(
    "SECURITY MODERATION: an unverified ordinary user cannot read the queue",
    async () => {
      await assertFails(
        getDocs(
          query(
            collection(unverified.firestore(), "reports"),
            where("status", "==", "open"),
            orderBy("createdAt", "desc"),
            limit(20),
          ),
        ),
      );
    },
  );

  await check(
    "SECURITY MODERATION: a REVOKED moderator holding a stale token is " +
      "denied — the server record, not the claim, decides",
    async () => {
      await assertFails(
        getDocs(
          query(
            collection(revokedMod.firestore(), "reports"),
            where("status", "==", "open"),
            orderBy("createdAt", "desc"),
            limit(20),
          ),
        ),
      );
    },
  );

  await check(
    "SECURITY MODERATION: a BANNED moderator is denied",
    async () => {
      await assertFails(
        getDocs(
          query(
            collection(bannedMod.firestore(), "reports"),
            where("status", "==", "open"),
            orderBy("createdAt", "desc"),
            limit(20),
          ),
        ),
      );
    },
  );

  await check(
    "SECURITY MODERATION: a client cannot promote itself by writing its " +
      "own role field",
    async () => {
      await assertFails(
        updateDoc(doc(attacker.firestore(), "users/attacker-uid"), {
          role: "moderator",
        }),
      );
      await assertFails(
        setDoc(
          doc(attacker.firestore(), "users/attacker-uid"),
          { role: "admin" },
          { merge: true },
        ),
      );
      // And the queue is still closed to them.
      await assertFails(
        getDocs(
          query(
            collection(attacker.firestore(), "reports"),
            where("status", "==", "open"),
            orderBy("createdAt", "desc"),
            limit(20),
          ),
        ),
      );
    },
  );

  await check(
    "SECURITY MODERATION: NOBODY writes report workflow fields directly " +
      "— not an ordinary user, and not staff",
    async () => {
      const filed = `reports/${reportId("attacker-uid", "globalMessage", "g-ok-1")}`;
      for (const context of [attacker, moderator, adminStaff]) {
        await assertFails(
          updateDoc(doc(context.firestore(), filed), { status: "resolved" }),
        );
        await assertFails(
          updateDoc(doc(context.firestore(), filed), {
            assignedTo: "mod-uid",
          }),
        );
        await assertFails(
          updateDoc(doc(context.firestore(), filed), {
            resolution: "noActionNeeded",
            resolvedBy: "mod-uid",
          }),
        );
        await assertFails(deleteDoc(doc(context.firestore(), filed)));
      }
    },
  );

  await check(
    "SECURITY MODERATION: a report cannot be filed pre-claimed, " +
      "pre-resolved or attributed to a moderator",
    async () => {
      for (const extra of [
        { status: "inReview" },
        { status: "resolved" },
        { assignedTo: "mod-uid" },
        { resolvedBy: "mod-uid" },
        { resolution: "noActionNeeded" },
        { contentRemoved: true },
      ]) {
        await assertFails(
          fileReport(adminStaff.firestore(), "admin-uid", {
            targetId: "g-ok-1",
            reportedUserId: "host-uid",
            ...extra,
          }),
        );
      }
    },
  );

  await check(
    "MODERATION: a report filed with the pinned status:open is accepted",
    async () => {
      await assertSucceeds(
        fileReport(adminStaff.firestore(), "admin-uid", {
          targetId: "g-ok-1",
          reportedUserId: "host-uid",
        }),
      );
    },
  );

  await check(
    "SECURITY MODERATION: moderation audit records stay invisible to " +
      "staff clients too — they are Admin SDK only",
    async () => {
      await assertFails(
        getDoc(doc(moderator.firestore(), "adminAuditLogs/report_x")),
      );
      await assertFails(
        setDoc(doc(moderator.firestore(), "adminAuditLogs/report_x"), {
          actorId: "mod-uid",
        }),
      );
    },
  );

  // --- Family Room (clubs/{id} with type: 'family') ---------------------
  //
  // A Family Room is a Club with a private data boundary. These cases pin
  // both halves: the boundary itself, and the fact that ordinary Club
  // authorization is untouched by it.

  const parent = testEnv.authenticatedContext("parent-uid", {
    email_verified: true,
  });
  const sibling = testEnv.authenticatedContext("sibling-uid", {
    email_verified: true,
  });
  const outsider = testEnv.authenticatedContext("outsider-uid", {
    email_verified: true,
  });
  const familyBatchOwner = testEnv.authenticatedContext("family-batch-uid", {
    email_verified: true,
  });
  const familyIncompleteOwner = testEnv.authenticatedContext(
    "family-incomplete-uid",
    { email_verified: true },
  );
  const familyMalformedOwner = testEnv.authenticatedContext(
    "family-malformed-uid",
    { email_verified: true },
  );
  const familyMediaOwner = testEnv.authenticatedContext("family-media-uid", {
    email_verified: true,
  });
  const familyIdentityOwner = testEnv.authenticatedContext(
    "family-identity-uid",
    {
      email_verified: true,
      name: "Bypass Auth Name",
    },
  );
  const FAMILY = "clubs/family_parent-uid";

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await Promise.all([
      setDoc(doc(db, "users/parent-uid"), {
        displayName: "Parent",
        banned: false,
        disabled: false,
      }),
      setDoc(doc(db, "users/sibling-uid"), {
        displayName: "Sibling",
        banned: false,
        disabled: false,
      }),
      setDoc(doc(db, "users/outsider-uid"), {
        displayName: "Outsider",
        banned: false,
        disabled: false,
      }),
      setDoc(doc(db, "users/family-batch-uid"), {
        displayName: "Batch Parent",
        banned: false,
        disabled: false,
      }),
      setDoc(doc(db, "users/family-incomplete-uid"), {
        displayName: "Incomplete Parent",
        banned: false,
        disabled: false,
      }),
      setDoc(doc(db, "users/family-malformed-uid"), {
        displayName: "Malformed Parent",
        banned: false,
        disabled: false,
      }),
      setDoc(doc(db, "users/family-media-uid"), {
        displayName: "Private Media Parent",
        banned: false,
        disabled: false,
      }),
      setDoc(doc(db, "users/family-identity-uid"), {
        displayName: "Canonical Family Parent",
        banned: false,
        disabled: false,
      }),
    ]);
  });

  function familyDoc(overrides = {}) {
    return {
      name: "The Family",
      description: "Ours",
      ownerId: "parent-uid",
      ownerName: "Parent",
      type: "family",
      status: "active",
      privacy: "inviteOnly",
      defaultLanguage: "English",
      memberCount: 1,
      onlineCount: 1,
      defaultChatChannelId: "general",
      defaultVoiceChannelId: "lounge",
      announcementChannelId: "announcements",
      avatarUrl: null,
      bannerUrl: null,
      loungeRoomId: "club_lounge_family_parent-uid",
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      ...overrides,
    };
  }

  function familyGraphBatch(db, uid, options = {}) {
    const clubId = `family_${uid}`;
    const roomId = `club_lounge_${clubId}`;
    const ownerName = options.ownerName ?? "Family Organizer";
    const memberName = options.memberName ?? ownerName;
    const roomHostName = options.roomHostName ?? ownerName;
    const omitted = new Set(options.omit ?? []);
    const refs = {
      club: doc(db, `clubs/${clubId}`),
      member: doc(db, `clubs/${clubId}/members/${uid}`),
      projection: doc(db, `users/${uid}/clubs/${clubId}`),
      general: doc(db, `clubs/${clubId}/channels/general`),
      announcements: doc(db, `clubs/${clubId}/channels/announcements`),
      lounge: doc(db, `clubs/${clubId}/channels/lounge`),
      room: doc(db, `rooms/${roomId}`),
    };
    const batch = writeBatch(db);

    batch.set(refs.club, {
      name: "Batch Family",
      description: "Our private home",
      ownerId: uid,
      ownerName,
      avatarUrl: options.rootAvatarUrl ?? null,
      bannerUrl: options.rootBannerUrl ?? null,
      privacy: "inviteOnly",
      type: "family",
      status: "active",
      defaultLanguage: "English",
      memberCount: 1,
      onlineCount: 1,
      defaultChatChannelId: "general",
      defaultVoiceChannelId: "lounge",
      loungeRoomId: roomId,
      announcementChannelId: "announcements",
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    if (!omitted.has("member")) {
      batch.set(refs.member, {
        userId: uid,
        displayName: memberName,
        photoUrl: null,
        role: "owner",
        isOnline: true,
        joinedAt: serverTimestamp(),
        invitedBy: null,
      });
    }
    if (!omitted.has("projection")) {
      batch.set(refs.projection, {
        clubId,
        name: "Batch Family",
        avatarUrl: options.projectionAvatarUrl ?? null,
        role: "owner",
        joinedAt: serverTimestamp(),
      });
    }
    if (!omitted.has("general")) {
      batch.set(refs.general, {
        name: "general",
        type: options.chatType ?? "chat",
        position: 0,
        isPrivate: false,
        createdBy: options.chatCreatedBy ?? uid,
        createdAt: serverTimestamp(),
      });
    }
    if (!omitted.has("announcements")) {
      batch.set(refs.announcements, {
        name: "announcements",
        type: options.announcementType ?? "announcement",
        position: 1,
        isPrivate: false,
        createdBy: options.announcementCreatedBy ?? uid,
        createdAt: serverTimestamp(),
      });
    }
    if (!omitted.has("lounge")) {
      batch.set(refs.lounge, {
        name: "Family Lounge",
        type: options.voiceType ?? "voice",
        position: 2,
        isPrivate: false,
        createdBy: options.voiceCreatedBy ?? uid,
        roomId: options.voiceRoomId ?? roomId,
        createdAt: serverTimestamp(),
      });
    }
    if (!omitted.has("room")) {
      batch.set(refs.room, {
        hostId: uid,
        hostName: roomHostName,
        hostPhotoUrl: null,
        name: "Batch Family Lounge",
        description: "Our private home",
        category: "club",
        visibility: "private",
        language: "English",
        maxParticipants: null,
        participantCount: 0,
        memberCount: 1,
        isLive: false,
        roomType: "community",
        status: "active",
        imageUrl: options.roomImageUrl ?? null,
        approvalRequired: false,
        slowModeSeconds: 0,
        autoMuteNewUsers: false,
        membersCanStartVoice: true,
        experience: "community",
        clubId,
        roomKind: "clubLounge",
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
    }

    return { batch, clubId, roomId, refs };
  }

  await check(
    "FAMILY: the client can probe its missing canonical id before creation",
    async () => {
      // ClubService.createFamilyRoom() performs this read first so a retry or
      // reopen returns the existing room without uploading media again. A
      // missing resource has no resource.data; this exact request used to
      // fail with a rules null-value evaluation error.
      const snapshot = await assertSucceeds(
        getDoc(
          doc(
            familyBatchOwner.firestore(),
            "clubs/family_family-batch-uid",
          ),
        ),
      );
      assert.equal(snapshot.exists(), false);
      await assertFails(
        getDoc(
          doc(
            outsider.firestore(),
            "clubs/family_someone-else-who-does-not-exist",
          ),
        ),
      );
    },
  );

  await check(
    "FAMILY: the exact production batch creates root, ownership, channels and lounge",
    async () => {
      const db = familyBatchOwner.firestore();
      const uid = "family-batch-uid";
      const { batch, clubId, refs } = familyGraphBatch(db, uid, {
        ownerName: "Batch Parent",
      });

      await assertSucceeds(batch.commit());

      for (const ref of Object.values(refs)) {
        const snapshot = await assertSucceeds(getDoc(ref));
        assert.equal(snapshot.exists(), true, `${ref.path} should exist`);
      }

      // Reopening is the same canonical read — no second write or Premium
      // entitlement is needed.
      const reopened = await assertSucceeds(getDoc(refs.club));
      assert.equal(reopened.id, clubId);
      assert.equal(reopened.data().type, "family");

      // This is the losing half of a two-device race. Its root has become an
      // UPDATE, so the complete atomic batch is rejected and the client must
      // recover the canonical winner through the read above.
      const replay = writeBatch(db);
      replay.set(refs.club, {
        ...reopened.data(),
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
      await assertFails(replay.commit());
      assert.equal((await assertSucceeds(getDoc(refs.club))).id, clubId);

      let entitlementExists = true;
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        entitlementExists = (
          await getDoc(doc(ctx.firestore(), `entitlements/${uid}`))
        ).exists();
      });
      assert.equal(entitlementExists, false);
    },
  );

  await check(
    "FAMILY SECURITY: Auth metadata and arbitrary root/member/lounge names cannot enter the graph",
    async () => {
      const db = familyIdentityOwner.firestore();
      const uid = "family-identity-uid";
      const canonical = "Canonical Family Parent";
      for (const forged of [
        {
          ownerName: "Bypass Auth Name",
          memberName: canonical,
          roomHostName: canonical,
        },
        {
          ownerName: canonical,
          memberName: "Arbitrary Owner Member",
          roomHostName: canonical,
        },
        {
          ownerName: canonical,
          memberName: canonical,
          roomHostName: "Arbitrary Lounge Host",
        },
      ]) {
        const { batch } = familyGraphBatch(db, uid, forged);
        await assertFails(batch.commit());
      }

      const { batch, refs } = familyGraphBatch(db, uid, {
        ownerName: canonical,
      });
      await assertSucceeds(batch.commit());
      assert.equal((await getDoc(refs.club)).data().ownerName, canonical);
      assert.equal((await getDoc(refs.member)).data().displayName, canonical);
      assert.equal((await getDoc(refs.room)).data().hostName, canonical);
    },
  );

  await check(
    "FAMILY SECURITY: root, projection and lounge media stay null atomically",
    async () => {
      const db = familyMediaOwner.firestore();
      const uid = "family-media-uid";
      for (const forged of [
        { rootAvatarUrl: "https://evil.invalid/root.jpg" },
        { rootBannerUrl: "https://evil.invalid/banner.jpg" },
        { projectionAvatarUrl: "https://evil.invalid/projection.jpg" },
        { roomImageUrl: "https://evil.invalid/lounge.jpg" },
      ]) {
        const { batch } = familyGraphBatch(db, uid, {
          ownerName: "Private Media Parent",
          ...forged,
        });
        await assertFails(batch.commit());
      }
      const { batch, refs } = familyGraphBatch(db, uid, {
        ownerName: "Private Media Parent",
      });
      await assertSucceeds(batch.commit());
      assert.equal((await getDoc(refs.club)).data().avatarUrl, null);
      assert.equal((await getDoc(refs.club)).data().bannerUrl, null);
      assert.equal((await getDoc(refs.projection)).data().avatarUrl, null);
      assert.equal((await getDoc(refs.room)).data().imageUrl, null);
    },
  );

  await check(
    "FAMILY SECURITY: root-only creation cannot reserve the one canonical id",
    async () => {
      // Family remains free, but only through the complete production batch.
      // A root on its own would make every retry an UPDATE and permanently
      // strand this account without its owner membership or navigation graph.
      await assertFails(
        setDoc(doc(parent.firestore(), FAMILY), familyDoc()),
      );
    },
  );

  await check(
    "FAMILY SECURITY: an incomplete graph is rejected atomically",
    async () => {
      const { batch, refs } = familyGraphBatch(
        familyIncompleteOwner.firestore(),
        "family-incomplete-uid",
        {
          ownerName: "Incomplete Parent",
          omit: ["projection"],
        },
      );
      await assertFails(batch.commit());

      let canonicalExists = true;
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        canonicalExists = (
          await getDoc(doc(ctx.firestore(), refs.club.path))
        ).exists();
      });
      assert.equal(canonicalExists, false);
    },
  );

  await check(
    "FAMILY SECURITY: malformed default-channel type, author or room binding is rejected",
    async () => {
      for (const malformed of [
        { chatType: "announcement" },
        { chatCreatedBy: "outsider-uid" },
        { announcementType: "chat" },
        { announcementCreatedBy: "outsider-uid" },
        { voiceType: "chat" },
        { voiceCreatedBy: "outsider-uid" },
        { voiceRoomId: "club_lounge_someone-else" },
      ]) {
        const { batch } = familyGraphBatch(
          familyMalformedOwner.firestore(),
          "family-malformed-uid",
          {
            ownerName: "Malformed Parent",
            ...malformed,
          },
        );
        await assertFails(batch.commit());
      }

      let canonicalExists = true;
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        canonicalExists = (
          await getDoc(
            doc(ctx.firestore(), "clubs/family_family-malformed-uid"),
          )
        ).exists();
      });
      assert.equal(canonicalExists, false);
    },
  );

  await check(
    "FAMILY SECURITY: the deterministic id IS the one-per-account limit",
    async () => {
      // Any id other than family_{uid} is refused, so there is nowhere to
      // write a second family room.
      await assertFails(
        setDoc(doc(parent.firestore(), "clubs/family_parent-uid-2"), familyDoc()),
      );
      await assertFails(
        setDoc(doc(parent.firestore(), "clubs/some-random-id"), familyDoc()),
      );
    },
  );

  await check(
    "FAMILY SECURITY: nobody can create a family room under someone else's id",
    async () => {
      await assertFails(
        setDoc(
          doc(attacker.firestore(), FAMILY),
          familyDoc({ ownerId: "attacker-uid" }),
        ),
      );
      await assertFails(
        setDoc(
          doc(attacker.firestore(), "clubs/family_attacker-uid"),
          familyDoc({ ownerId: "parent-uid" }),
        ),
      );
    },
  );

  await check(
    "FAMILY SECURITY: an unverified account cannot create a family room",
    async () => {
      await assertFails(
        setDoc(
          doc(unverified.firestore(), "clubs/family_unverified-uid"),
          familyDoc({ ownerId: "unverified-uid" }),
        ),
      );
    },
  );

  await check(
    "regression: creating an ORDINARY club still requires premium",
    async () => {
      // The family path must not have opened a free door for clubs.
      await assertFails(
        setDoc(doc(parent.firestore(), "clubs/free-club-attempt"), {
          ownerId: "parent-uid",
          name: "Free club",
          type: "community",
        }),
      );
      // ...and the same is true with no type field at all (every club
      // that already exists in production).
      await assertFails(
        setDoc(doc(parent.firestore(), "clubs/free-club-attempt-2"), {
          ownerId: "parent-uid",
          name: "Free club",
        }),
      );
    },
  );

  await check("FAMILY: the owner is a member and can read the space", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), FAMILY), {
        ...familyDoc(),
        createdAt: new Date(),
        updatedAt: new Date(),
      });
      await setDoc(doc(ctx.firestore(), `${FAMILY}/members/parent-uid`), {
        userId: "parent-uid",
        displayName: "Parent",
        role: "owner",
        joinedAt: serverTimestamp(),
      });
    });
    await assertSucceeds(getDoc(doc(parent.firestore(), FAMILY)));
  });

  await check(
    "FAMILY SECURITY: a signed-in NON-member cannot read the family room at all",
    async () => {
      // An ordinary club's metadata is readable to any signed-in user;
      // a family room's is not — not its name, not its member count.
      await assertFails(getDoc(doc(outsider.firestore(), FAMILY)));
    },
  );

  await check(
    "FAMILY SECURITY: a non-member cannot read family chat, moments, "
      + "check-ins or the roster",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), `${FAMILY}/channels/general/messages/m1`),
          { senderId: "parent-uid", content: "dinner at 7", clubId: "family_parent-uid" },
        );
        await setDoc(doc(ctx.firestore(), `${FAMILY}/moments/mo1`), {
          authorId: "parent-uid",
          clubId: "family_parent-uid",
          caption: "private",
        });
        await setDoc(doc(ctx.firestore(), `${FAMILY}/checkIns/c1`), {
          userId: "parent-uid",
          clubId: "family_parent-uid",
          status: "home",
        });
      });
      const db = outsider.firestore();
      await assertFails(
        getDoc(doc(db, `${FAMILY}/channels/general/messages/m1`)),
      );
      await assertFails(getDoc(doc(db, `${FAMILY}/moments/mo1`)));
      await assertFails(getDoc(doc(db, `${FAMILY}/checkIns/c1`)));
      await assertFails(getDocs(collection(db, `${FAMILY}/members`)));
    },
  );

  await check(
    "FAMILY: an invited-but-not-yet-joined user can read the room they "
      + "were invited to, and nothing inside it",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), `${FAMILY}/invites/sibling-uid`), {
          inviteeId: "sibling-uid",
          inviterId: "parent-uid",
          status: "pending",
        });
      });
      const db = sibling.firestore();
      await assertSucceeds(getDoc(doc(db, FAMILY)));
      // The invitation is not membership: content stays closed.
      await assertFails(getDoc(doc(db, `${FAMILY}/moments/mo1`)));
      await assertFails(getDoc(doc(db, `${FAMILY}/checkIns/c1`)));
    },
  );

  await check(
    "FAMILY SECURITY: a revoked invitation cannot be reused to read the room",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await deleteDoc(doc(ctx.firestore(), `${FAMILY}/invites/sibling-uid`));
      });
      await assertFails(getDoc(doc(sibling.firestore(), FAMILY)));
    },
  );

  await check("FAMILY: a member can read and post moments and check-ins", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `${FAMILY}/members/sibling-uid`), {
        userId: "sibling-uid",
        displayName: "Sibling",
        role: "member",
        joinedAt: serverTimestamp(),
      });
    });
    const db = sibling.firestore();
    await assertSucceeds(getDoc(doc(db, `${FAMILY}/moments/mo1`)));
    await assertSucceeds(
      setDoc(doc(db, `${FAMILY}/moments/mine`), {
        authorId: "sibling-uid",
        clubId: "family_parent-uid",
        caption: "hello",
      }),
    );
    await assertSucceeds(
      setDoc(doc(db, `${FAMILY}/checkIns/mine`), {
        userId: "sibling-uid",
        clubId: "family_parent-uid",
        displayName: "Sibling",
        photoUrl: null,
        status: "onMyWay",
        createdAt: serverTimestamp(),
      }),
    );
  });

  await check(
    "FAMILY SECURITY: a check-in is scoped to the account writing it, "
      + "immutable, and may carry no location",
    async () => {
      const db = sibling.firestore();
      // Cannot check in AS someone else.
      await assertFails(
        setDoc(doc(db, `${FAMILY}/checkIns/spoofed`), {
          userId: "parent-uid",
          clubId: "family_parent-uid",
          status: "home",
        }),
      );
      // Only the four defined statuses.
      await assertFails(
        setDoc(doc(db, `${FAMILY}/checkIns/bogus`), {
          userId: "sibling-uid",
          clubId: "family_parent-uid",
          status: "sos",
        }),
      );
      // The visible identity snapshot comes from users/{uid}, never Auth or
      // caller input.
      await assertFails(
        setDoc(doc(db, `${FAMILY}/checkIns/forged-name`), {
          userId: "sibling-uid",
          clubId: "family_parent-uid",
          displayName: "Parent",
          photoUrl: null,
          status: "home",
          createdAt: serverTimestamp(),
        }),
      );
      // Precise location is refused outright, not merely ignored.
      await assertFails(
        setDoc(doc(db, `${FAMILY}/checkIns/located`), {
          userId: "sibling-uid",
          clubId: "family_parent-uid",
          status: "home",
          latitude: 52.23,
          longitude: 21.01,
        }),
      );
      // Append-only: a check-in cannot be rewritten after the fact.
      await assertFails(
        updateDoc(doc(db, `${FAMILY}/checkIns/mine`), { status: "callMe" }),
      );
    },
  );

  await check(
    "FAMILY SECURITY: a member cannot post a moment as another member",
    async () => {
      await assertFails(
        setDoc(doc(sibling.firestore(), `${FAMILY}/moments/spoofed`), {
          authorId: "parent-uid",
          clubId: "family_parent-uid",
          caption: "not mine",
        }),
      );
    },
  );

  await check(
    "FAMILY SECURITY: every invite, including organizer invites, uses the callable",
    async () => {
      await assertFails(
        setDoc(doc(sibling.firestore(), `${FAMILY}/invites/outsider-uid`), {
          inviteeId: "outsider-uid",
          inviterId: "sibling-uid",
          status: "pending",
        }),
      );
      await assertFails(
        setDoc(doc(parent.firestore(), `${FAMILY}/invites/outsider-uid`), {
          inviteeId: "outsider-uid",
          inviterId: "parent-uid",
          status: "pending",
        }),
      );
    },
  );

  await check(
    "FAMILY SECURITY: removal closes the door immediately",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await deleteDoc(doc(ctx.firestore(), `${FAMILY}/members/sibling-uid`));
      });
      const db = sibling.firestore();
      await assertFails(getDoc(doc(db, FAMILY)));
      await assertFails(getDoc(doc(db, `${FAMILY}/moments/mo1`)));
      await assertFails(getDoc(doc(db, `${FAMILY}/checkIns/c1`)));
    },
  );

  await check(
    "FAMILY SECURITY: the type and owner of a space are immutable",
    async () => {
      const db = parent.firestore();
      // Relabelling a family space as a community club would strip its
      // read boundary in one write.
      await assertFails(updateDoc(doc(db, FAMILY), { type: "community" }));
      await assertFails(updateDoc(doc(db, FAMILY), { ownerId: "attacker-uid" }));
      // An ordinary rename still works.
      await assertSucceeds(
        updateDoc(doc(db, FAMILY), {
          name: "Our Family",
          updatedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "FAMILY SECURITY: Premium does NOT buy a second family room",
    async () => {
      // A premium account gets the community create path; it does not
      // get a second family id, and a family-typed document cannot slip
      // through the community branch either.
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "entitlements/parent-uid"), {
          status: "active",
          currentPeriodEnd: new Date(Date.now() + 86400000),
        });
      });
      await assertFails(
        setDoc(doc(parent.firestore(), "clubs/family_parent-uid-second"),
          familyDoc()),
      );
      await assertFails(
        setDoc(doc(parent.firestore(), "clubs/another-family"), familyDoc()),
      );
    },
  );

  await check(
    "FAMILY SECURITY: family rooms cannot be swept up by a listing query",
    async () => {
      // A per-document read condition does NOT protect a listing: during
      // list evaluation resource.data is not the document, so the earlier
      // `resource.data.get('type','community')` fell back to its default
      // and an outsider could enumerate clubs and read a family room's
      // name. Listing the collection is now refused outright.
      await assertFails(getDocs(collection(outsider.firestore(), "clubs")));
      await assertFails(
        getDocs(
          query(
            collection(outsider.firestore(), "clubs"),
            where("ownerId", "==", "parent-uid"),
          ),
        ),
      );
    },
  );

  // --- room metadata (three-step creation wizard) -----------------------

  function roomDoc(overrides = {}) {
    return {
      hostId: "host-uid",
      hostName: "Host",
      name: "Metadata room",
      description: "",
      category: "talk",
      visibility: "public",
      language: "English",
      maxParticipants: 25,
      participantCount: 1,
      memberCount: 0,
      isLive: true,
      roomType: "temporary",
      status: "active",
      experience: "community",
      approvalRequired: false,
      slowModeSeconds: 0,
      autoMuteNewUsers: true,
      membersCanStartVoice: false,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      ...overrides,
    };
  }

  function createMetadataRoom(roomId, overrides = {}) {
    const db = host.firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, `rooms/${roomId}`), roomDoc(overrides));
    batch.set(doc(db, `rooms/${roomId}/participants/host-uid`), {
      userId: "host-uid",
      displayName: "Host",
      photoUrl: null,
      role: "host",
      isMuted: false,
      isSpeaker: true,
      isHandRaised: false,
      joinedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
    return batch.commit();
  }

  async function seedMetadataRoom(roomId, overrides = {}) {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, `rooms/${roomId}`), roomDoc(overrides));
      await setDoc(doc(db, `rooms/${roomId}/participants/host-uid`), {
        userId: "host-uid",
        displayName: "Host",
        photoUrl: null,
        role: "host",
        isMuted: false,
        isSpeaker: true,
        isHandRaised: false,
        joinedAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
    });
  }

  await check("ROOM META: a server-created community room persists metadata", async () => {
    await seedMetadataRoom("meta-community", {
      targetAudience: "newcomers",
      topicTags: ["flutter", "dart"],
      roomGuidelines: "Be kind.",
      conversationStyle: "supportive",
      newcomerFriendly: true,
    });
    const snapshot = await assertSucceeds(
      getDoc(doc(host.firestore(), "rooms/meta-community")),
    );
    if (snapshot.data().targetAudience !== "newcomers") {
      throw new Error("server-created Community metadata did not persist");
    }
  });

  await check("ROOM META: a server-created podcast room persists metadata", async () => {
    await seedMetadataRoom("meta-podcast", {
      experience: "broadcast",
      topic: "Episode one",
      audienceCanSpeak: false,
      handRaisingEnabled: true,
      stageLimit: 8,
      targetAudience: "professionals",
      topicTags: ["interview"],
      showFormat: "panel",
    });
    const snapshot = await assertSucceeds(
      getDoc(doc(host.firestore(), "rooms/meta-podcast")),
    );
    if (snapshot.data().showFormat !== "panel") {
      throw new Error("server-created Podcast metadata did not persist");
    }
  });

  await check(
    "ROOM META SECURITY: experience is immutable after atomic creation",
    async () => {
      const db = host.firestore();
      await seedMetadataRoom("meta-immutable-community");
      await assertFails(
        updateDoc(doc(db, "rooms/meta-immutable-community"), {
          experience: "broadcast",
          topic: "Forged broadcast",
          audienceCanSpeak: false,
          handRaisingEnabled: true,
          stageLimit: 8,
          showFormat: "panel",
          updatedAt: serverTimestamp(),
        }),
      );

      await seedMetadataRoom("meta-immutable-broadcast", {
        experience: "broadcast",
        topic: "Original episode",
        audienceCanSpeak: false,
        handRaisingEnabled: true,
        stageLimit: 8,
        showFormat: "panel",
      });
      await assertFails(
        updateDoc(doc(db, "rooms/meta-immutable-broadcast"), {
          experience: "community",
          showFormat: deleteField(),
          updatedAt: serverTimestamp(),
        }),
      );
      await assertSucceeds(
        updateDoc(doc(db, "rooms/meta-immutable-broadcast"), {
          topic: "Edited episode title",
          updatedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "ROOM META regression: a server-created legacy room with NO optional " +
      "metadata remains readable and editable",
    async () => {
      await seedMetadataRoom("meta-legacy");
      await assertSucceeds(
        updateDoc(doc(host.firestore(), "rooms/meta-legacy"), {
          description: "Legacy edit",
          updatedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "ROOM META regression: a legacy podcast value can use Podcast settings",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), "rooms/meta-legacy-podcast"),
          roomDoc({
            experience: "podcast",
            topic: "Legacy episode",
            showFormat: "solo",
          }),
        );
      });
      await assertSucceeds(
        updateDoc(doc(host.firestore(), "rooms/meta-legacy-podcast"), {
          topic: "Edited legacy episode",
          showFormat: "interview",
          handRaisingEnabled: false,
          updatedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "ROOM META SECURITY: a community room cannot forge podcast-only fields",
    async () => {
      await assertFails(
        createMetadataRoom("forge-1", { showFormat: "panel" }),
      );
    },
  );

  await check(
    "ROOM META SECURITY: a podcast room cannot forge community-only fields",
    async () => {
      await assertFails(
        createMetadataRoom("forge-2", {
          experience: "broadcast",
          conversationStyle: "casual",
        }),
      );
      await assertFails(
        createMetadataRoom("forge-3", {
          experience: "broadcast",
          newcomerFriendly: true,
        }),
      );
    },
  );

  await check(
    "ROOM META SECURITY: invented enum values are refused for every field",
    async () => {
      await assertFails(
        createMetadataRoom("bad-1", { targetAudience: "vip" }),
      );
      await assertFails(
        createMetadataRoom("bad-2", { conversationStyle: "chaotic" }),
      );
      await assertFails(
        createMetadataRoom("bad-3", {
          experience: "broadcast",
          showFormat: "livestream",
        }),
      );
      await assertFails(
        createMetadataRoom("bad-podcast-contract", {
          experience: "broadcast",
          topic: "x".repeat(121),
          audienceCanSpeak: "yes",
          handRaisingEnabled: 1,
          stageLimit: 99,
        }),
      );
    },
  );

  await check(
    "ROOM META SECURITY: more than three tags, or oversized guidelines, "
      + "are refused",
    async () => {
      await assertFails(
        createMetadataRoom("bad-4", {
          topicTags: ["a", "b", "c", "d"],
        }),
      );
      await assertFails(
        createMetadataRoom("bad-5", {
          roomGuidelines: "x".repeat(281),
        }),
      );
      await assertFails(
        createMetadataRoom("bad-6", { topicTags: "not-a-list" }),
      );
    },
  );

  await check(
    "ROOM META SECURITY: a host cannot smuggle a bad value in via update",
    async () => {
      await assertFails(
        updateDoc(doc(host.firestore(), "rooms/meta-community"), {
          targetAudience: "vip",
        }),
      );
      await assertFails(
        updateDoc(doc(host.firestore(), "rooms/meta-community"), {
          showFormat: "panel",
        }),
      );
      // A legitimate edit still works.
      await assertSucceeds(
        updateDoc(doc(host.firestore(), "rooms/meta-community"), {
          targetAudience: "enthusiasts",
          updatedAt: serverTimestamp(),
        }),
      );
    },
  );

  // --- VIP grants and the public badge mirror -------------------------

  await check(
    "VIP GRANT SECURITY: a client cannot grant itself VIP",
    async () => {
      await assertFails(
        setDoc(doc(host.firestore(), "vipGrants/host-uid"), {
          source: "adminGrant",
          expiresAt: null,
        }),
      );
      // Nor anyone else.
      await assertFails(
        setDoc(doc(host.firestore(), "vipGrants/attacker-uid"), {
          source: "adminGrant",
        }),
      );
    },
  );

  await check(
    "VIP GRANT: the holder can READ their own grant, nobody else can",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "vipGrants/host-uid"), {
          source: "adminGrant",
          expiresAt: null,
        });
      });
      await assertSucceeds(getDoc(doc(host.firestore(), "vipGrants/host-uid")));
      await assertFails(
        getDoc(doc(attacker.firestore(), "vipGrants/host-uid")),
      );
    },
  );

  await check(
    "BADGE SECURITY: badges cannot be LISTED — staff and VIP accounts "
      + "are not enumerable",
    async () => {
      await assertFails(
        getDocs(collection(attacker.firestore(), "publicBadges")),
      );
    },
  );

  await check(
    "BADGE SECURITY: the public badge mirror is readable by GET but never "
      + "client-writable",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "publicBadges/host-uid"), {
          role: "moderator",
          vip: true,
        });
      });
      // Public by design — that is what a badge is for.
      await assertSucceeds(
        getDoc(doc(attacker.firestore(), "publicBadges/host-uid")),
      );
      // But nobody may forge one, for themselves or anyone else.
      await assertFails(
        setDoc(doc(attacker.firestore(), "publicBadges/attacker-uid"), {
          role: "superAdmin",
          vip: true,
        }),
      );
      await assertFails(
        updateDoc(doc(host.firestore(), "publicBadges/host-uid"), {
          role: "superAdmin",
        }),
      );
    },
  );

  await check(
    "DIRECTORY SECURITY: the staff user directory is invisible to every "
      + "client — no get, no list, no write, owner session included",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "userDirectory/host-uid"), {
          displayName: "Host",
          usernameLower: "host",
          emailLower: "host@example.com",
          staffRole: "user",
        });
      });
      // Not even the document's own subject may read it: the ONLY road
      // is the owner-authorized callable. A client read here would be a
      // user-enumeration oracle carrying emails.
      await assertFails(
        getDoc(doc(host.firestore(), "userDirectory/host-uid")),
      );
      await assertFails(
        getDoc(doc(attacker.firestore(), "userDirectory/host-uid")),
      );
      await assertFails(
        getDocs(collection(attacker.firestore(), "userDirectory")),
      );
      await assertFails(
        setDoc(doc(attacker.firestore(), "userDirectory/attacker-uid"), {
          displayName: "Fake",
          staffRole: "superAdmin",
        }),
      );
    },
  );

  await check(
    "ROLE SECURITY: a client still cannot write role or the premium mirror",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "users/attacker-uid"), {
          uid: "attacker-uid",
          displayName: "Attacker",
          role: "user",
        });
      });
      const db = attacker.firestore();
      await assertFails(
        updateDoc(doc(db, "users/attacker-uid"), { role: "superAdmin" }),
      );
      await assertFails(
        updateDoc(doc(db, "users/attacker-uid"), { premiumIdentity: true }),
      );
      await assertFails(
        updateDoc(doc(db, "users/attacker-uid"), { banned: false }),
      );
    },
  );

  await check(
    "BAN SECURITY: a globally banned account cannot create or communicate",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await updateDoc(doc(db, "users/attacker-uid"), { banned: true });
        await setDoc(doc(db, "rooms/banned-join-room"), {
          hostId: "host-uid",
          visibility: "public",
          status: "active",
          isLive: true,
          participantCount: 0,
        });
      });
      const db = attacker.firestore();
      await assertFails(
        setDoc(doc(db, "voiceMoments/banned-voice-moment"), {
          authorId: "attacker-uid",
          caption: "should not publish",
        }),
      );
      const batch = writeBatch(db);
      batch.set(
        doc(db, "rooms/banned-join-room/participants/attacker-uid"),
        {
          userId: "attacker-uid",
          displayName: "Attacker",
          photoUrl: null,
          role: "listener",
          isMuted: true,
          isSpeaker: false,
          isHandRaised: false,
          joinedAt: serverTimestamp(),
          updatedAt: serverTimestamp(),
        },
      );
      batch.update(doc(db, "rooms/banned-join-room"), {
        participantCount: 1,
        updatedAt: serverTimestamp(),
      });
      await assertFails(batch.commit());
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await updateDoc(doc(ctx.firestore(), "users/attacker-uid"), {
          banned: false,
        });
      });
    },
  );

  // --- staff communication mute (restrictions/{uid}) --------------------

  const mutedUser = testEnv.authenticatedContext("muted-uid", {
    email_verified: true,
  });
  const sendMuteRoomMessage = (db, id, text) => setDoc(
    doc(db, `rooms/mute-room/messages/${id}`),
    {
      senderId: "muted-uid",
      senderName: "Muted",
      senderPhotoUrl: null,
      text,
      createdAt: serverTimestamp(),
      reactions: {},
    },
  );

  await check(
    "MUTE SECURITY: a client cannot write its own (or anyone's) restriction",
    async () => {
      await assertFails(
        setDoc(doc(mutedUser.firestore(), "restrictions/muted-uid"), {
          type: "communicationMute",
        }),
      );
      await assertFails(
        deleteDoc(doc(mutedUser.firestore(), "restrictions/muted-uid")),
      );
      await assertFails(
        setDoc(doc(attacker.firestore(), "restrictions/host-uid"), {
          type: "communicationMute",
        }),
      );
    },
  );

  await check(
    "MUTE: room chat stays callable-only before and during an active mute",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "users/muted-uid"), {
          uid: "muted-uid",
          displayName: "Muted",
          role: "user",
          accountType: "personal",
        });
        await setDoc(doc(ctx.firestore(), "rooms/mute-room"), {
          authorId: "host-uid",
          hostId: "host-uid",
          visibility: "public",
          status: "active",
          isLive: true,
        });
        await setDoc(doc(ctx.firestore(), "rooms/mute-room/participants/muted-uid"), {
          userId: "muted-uid",
          displayName: "Muted",
          role: "listener",
          isMuted: true,
          isSpeaker: false,
          isHandRaised: false,
        });
      });
      // Room chat admission, including restriction expiry, is enforced in
      // sendRoomMessage. Security Rules keep every legacy direct write closed.
      await assertFails(sendMuteRoomMessage(
        mutedUser.firestore(),
        "mute-c0",
        "baseline",
      ));

      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "restrictions/muted-uid"), {
          type: "communicationMute",
          expiresAt: null, // indefinite
        });
      });
      const mutedDb = mutedUser.firestore();

      // Global Chat stays retired regardless of the restriction state.
      await assertFails(
        sendGlobal(mutedDb, "muted-uid", "Muted", "mute-legacy"),
      );
      // Public Room chat is callable-only regardless of the restriction.
      await assertFails(sendMuteRoomMessage(mutedDb, "mute-c1", "muted"));
      // The holder can still READ their restriction and see the why.
      await assertSucceeds(
        getDoc(doc(mutedDb, "restrictions/muted-uid")),
      );
      // ...but nobody else can.
      await assertFails(
        getDoc(doc(attacker.firestore(), "restrictions/muted-uid")),
      );
    },
  );

  await check(
    "MUTE: an expired restriction does not reopen legacy direct room chat",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "restrictions/muted-uid"), {
          type: "communicationMute",
          expiresAt: Timestamp.fromMillis(Date.now() - 60_000),
        });
      });
      await assertFails(sendMuteRoomMessage(
        mutedUser.firestore(),
        "mute-c2",
        "expired restriction",
      ));
    },
  );

  await check(
    "MUTE ISOLATION: a personal block cannot reopen callable-only room chat",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await deleteDoc(doc(ctx.firestore(), "restrictions/muted-uid"));
        // host blocks muted-uid: a PERSONAL act.
        await setDoc(
          doc(ctx.firestore(), "users/host-uid/blocked/muted-uid"),
          { blockedAt: serverTimestamp() },
        );
      });
      await assertFails(sendMuteRoomMessage(
        mutedUser.firestore(),
        "mute-c3",
        "personal block is not a sanction",
      ));
    },
  );

  await check(
    "PERSONAL MUTE: a user manages their own muted list and nobody else's",
    async () => {
      const db = host.firestore();
      await assertSucceeds(
        setDoc(doc(db, "users/host-uid/muted/muted-uid"), {
          mutedAt: serverTimestamp(),
        }),
      );
      await assertSucceeds(deleteDoc(doc(db, "users/host-uid/muted/muted-uid")));
      await assertFails(
        setDoc(doc(attacker.firestore(), "users/host-uid/muted/x"), {
          mutedAt: serverTimestamp(),
        }),
      );
    },
  );

  // ==================================================================
  // PRIVATE ACCOUNT RECORDS + SERVER-OWNED PUBLIC IDENTITY PROJECTIONS
  // ==================================================================

  const privacyReader = testEnv.authenticatedContext("privacy-reader-uid", {
    email_verified: true,
  });
  const privacyTarget = testEnv.authenticatedContext("privacy-target-uid", {
    email_verified: true,
  });
  const privacyStranger = testEnv.authenticatedContext("privacy-stranger-uid", {
    email_verified: true,
  });
  const privacyModerator = testEnv.authenticatedContext("privacy-mod-uid", {
    email_verified: true,
    role: "moderator",
  });
  const privacyStaleModerator = testEnv.authenticatedContext(
    "privacy-stale-mod-uid",
    { email_verified: true, role: "moderator" },
  );
  const privacyBannedModerator = testEnv.authenticatedContext(
    "privacy-banned-mod-uid",
    { email_verified: true, role: "moderator" },
  );
  const privacySuperAdmin = testEnv.authenticatedContext(
    "privacy-super-admin-uid",
    { email_verified: true, role: "superAdmin" },
  );
  const privacyUnauthenticated = testEnv.unauthenticatedContext();

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      setDoc(doc(db, "users/privacy-reader-uid"), {
        uid: "privacy-reader-uid",
        displayName: "Reader",
        email: "reader@private.invalid",
        notificationPreferences: { directMessage: false },
        isOnline: true,
        lastSeen: Timestamp.now(),
        role: "user",
        banned: false,
      }),
      setDoc(doc(db, "users/privacy-target-uid"), {
        uid: "privacy-target-uid",
        displayName: "Target",
        email: "target@private.invalid",
        notificationPreferences: { directMessage: false },
        isOnline: true,
        lastSeen: Timestamp.now(),
        role: "superAdmin",
        banned: false,
      }),
      setDoc(doc(db, "users/privacy-stranger-uid"), {
        uid: "privacy-stranger-uid",
        displayName: "Stranger",
        role: "user",
        banned: false,
      }),
      setDoc(doc(db, "users/privacy-mod-uid"), {
        uid: "privacy-mod-uid",
        displayName: "Moderator",
        role: "moderator",
        banned: false,
      }),
      setDoc(doc(db, "users/privacy-stale-mod-uid"), {
        uid: "privacy-stale-mod-uid",
        displayName: "Stale moderator",
        role: "user",
        banned: false,
      }),
      setDoc(doc(db, "users/privacy-banned-mod-uid"), {
        uid: "privacy-banned-mod-uid",
        displayName: "Banned moderator",
        role: "moderator",
        banned: true,
      }),
      setDoc(doc(db, "users/privacy-super-admin-uid"), {
        uid: "privacy-super-admin-uid",
        displayName: "Super admin",
        role: "superAdmin",
        banned: false,
      }),
      setDoc(doc(db, "users/privacy-banned-target-uid"), {
        uid: "privacy-banned-target-uid",
        displayName: "Banned target",
        role: "user",
        banned: true,
      }),
      setDoc(doc(db, "publicProfiles/privacy-target-uid"), {
        uid: "privacy-target-uid",
        displayName: "Target",
        username: "target",
        displayNameSearch: "target",
        usernameSearch: "target",
        photoUrl: null,
        bannerUrl: null,
        bio: "Public bio",
        country: "",
        nativeLanguage: "Polish",
        spokenLanguages: ["English"],
        learningLanguages: [],
        website: null,
        statusMessage: "Public vibe",
        accountType: "personal",
        premiumIdentity: false,
        friendCount: 1,
        followerCount: 2,
        followingCount: 3,
        schemaVersion: 1,
        updatedAt: Timestamp.now(),
      }),
      setDoc(doc(db, "socialPresence/privacy-target-uid"), {
        uid: "privacy-target-uid",
        isOnline: true,
        lastSeen: Timestamp.now(),
        schemaVersion: 1,
        updatedAt: Timestamp.now(),
      }),
      setDoc(doc(db, "publicProfiles/privacy-banned-target-uid"), {
        uid: "privacy-banned-target-uid",
        displayName: "Stale banned projection",
      }),
      setDoc(
        doc(db, "users/privacy-reader-uid/friends/privacy-target-uid"),
        { userId: "privacy-target-uid" },
      ),
      setDoc(
        doc(db, "users/privacy-target-uid/friends/privacy-reader-uid"),
        { userId: "privacy-reader-uid" },
      ),
      setDoc(
        doc(
          db,
          "friendshipGuards/privacy-reader-uid/friends/privacy-target-uid",
        ),
        {
          ownerId: "privacy-reader-uid",
          friendId: "privacy-target-uid",
          schemaVersion: 1,
          establishedAt: Timestamp.now(),
        },
      ),
      setDoc(
        doc(
          db,
          "friendshipGuards/privacy-target-uid/friends/privacy-reader-uid",
        ),
        {
          ownerId: "privacy-target-uid",
          friendId: "privacy-reader-uid",
          schemaVersion: 1,
          establishedAt: Timestamp.now(),
        },
      ),
      setDoc(doc(db, "privateRateLimits/searchPublicProfiles_private"), {
        kind: "searchPublicProfiles",
        minuteCount: 1,
      }),
    ]);
  });

  await check("PRIVACY: an account can read its own private users document", async () => {
    const snapshot = await assertSucceeds(
      getDoc(doc(privacyReader.firestore(), "users/privacy-reader-uid")),
    );
    assert.equal(snapshot.data().email, "reader@private.invalid");
  });

  await check(
    "SECURITY PRIVACY: ordinary users cannot get another private account record",
    async () => {
      await assertFails(
        getDoc(doc(privacyReader.firestore(), "users/privacy-target-uid")),
      );
    },
  );

  await check(
    "SECURITY PRIVACY: ordinary users cannot list or query private users",
    async () => {
      await assertFails(getDocs(collection(privacyReader.firestore(), "users")));
      await assertFails(
        getDocs(
          query(
            collection(privacyReader.firestore(), "users"),
            where("username", "==", "target"),
          ),
        ),
      );
    },
  );

  await check(
    "SECURITY PRIVACY: a moderator cannot get or list private user records",
    async () => {
      await assertFails(
        getDoc(doc(privacyModerator.firestore(), "users/privacy-target-uid")),
      );
      await assertFails(
        getDocs(collection(privacyModerator.firestore(), "users")),
      );
      await assertFails(
        getDocs(
          query(
            collection(privacyModerator.firestore(), "users"),
            where("email", "==", "target@private.invalid"),
          ),
        ),
      );
    },
  );

  await check(
    "SECURITY PRIVACY: a super-admin client cannot bypass private user callables",
    async () => {
      await assertFails(
        getDoc(doc(privacySuperAdmin.firestore(), "users/privacy-target-uid")),
      );
      await assertFails(
        getDocs(collection(privacySuperAdmin.firestore(), "users")),
      );
    },
  );

  await check(
    "SECURITY PRIVACY: stale or banned staff claims cannot read private records",
    async () => {
      await assertFails(
        getDoc(
          doc(
            privacyStaleModerator.firestore(),
            "users/privacy-target-uid",
          ),
        ),
      );
      await assertFails(
        getDoc(
          doc(
            privacyBannedModerator.firestore(),
            "users/privacy-target-uid",
          ),
        ),
      );
    },
  );

  await check(
    "PRIVACY: a known public profile is readable but contains no private fields",
    async () => {
      const snapshot = await assertSucceeds(
        getDoc(
          doc(privacyReader.firestore(), "publicProfiles/privacy-target-uid"),
        ),
      );
      const data = snapshot.data();
      for (const forbidden of [
        "email",
        "notificationPreferences",
        "isOnline",
        "lastSeen",
        "role",
        "banned",
        "disabled",
      ]) {
        assert.equal(forbidden in data, false, forbidden);
      }
    },
  );

  await check(
    "PROFILE VISIBILITY: a missing legacy preference remains public",
    async () => {
      await assertSucceeds(
        getDoc(
          doc(
            privacyStranger.firestore(),
            "publicProfiles/privacy-target-uid",
          ),
        ),
      );
    },
  );

  await check(
    "PROFILE VISIBILITY: friends requires both canonical friendship guards",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await updateDoc(doc(context.firestore(), "users/privacy-target-uid"), {
          profileVisibility: "friends",
        });
      });
      await assertSucceeds(
        getDoc(
          doc(privacyReader.firestore(), "publicProfiles/privacy-target-uid"),
        ),
      );
      await assertFails(
        getDoc(
          doc(
            privacyStranger.firestore(),
            "publicProfiles/privacy-target-uid",
          ),
        ),
      );

      await testEnv.withSecurityRulesDisabled(async (context) => {
        await deleteDoc(
          doc(
            context.firestore(),
            "friendshipGuards/privacy-target-uid/friends/privacy-reader-uid",
          ),
        );
      });
      await assertFails(
        getDoc(
          doc(privacyReader.firestore(), "publicProfiles/privacy-target-uid"),
        ),
      );
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await setDoc(
          doc(
            context.firestore(),
            "friendshipGuards/privacy-target-uid/friends/privacy-reader-uid",
          ),
          {
            ownerId: "privacy-target-uid",
            friendId: "privacy-reader-uid",
            schemaVersion: 1,
            establishedAt: Timestamp.now(),
          },
        );
      });
    },
  );

  await check(
    "SECURITY PROFILE VISIBILITY: private denies every foreign client, including staff",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await updateDoc(doc(context.firestore(), "users/privacy-target-uid"), {
          profileVisibility: "private",
        });
      });
      for (const context of [
        privacyReader,
        privacyStranger,
        privacyModerator,
        privacySuperAdmin,
      ]) {
        await assertFails(
          getDoc(
            doc(context.firestore(), "publicProfiles/privacy-target-uid"),
          ),
        );
      }
      await assertSucceeds(
        getDoc(
          doc(privacyTarget.firestore(), "publicProfiles/privacy-target-uid"),
        ),
      );
    },
  );

  await check(
    "SECURITY PROFILE VISIBILITY: clients cannot forge the server-owned preference",
    async () => {
      await assertFails(
        updateDoc(doc(privacyTarget.firestore(), "users/privacy-target-uid"), {
          profileVisibility: "public",
          profileVisibilityUpdatedAt: serverTimestamp(),
        }),
      );
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await updateDoc(doc(context.firestore(), "users/privacy-target-uid"), {
          profileVisibility: "public",
        });
      });
    },
  );

  await check(
    "PROFILE VISIBILITY: the blocker can resolve Blocked users but the blocked account cannot open the blocker",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        await Promise.all([
          setDoc(
            doc(db, "users/privacy-reader-uid/blocked/privacy-target-uid"),
            { blockedAt: Timestamp.now() },
          ),
          setDoc(doc(db, "publicProfiles/privacy-reader-uid"), {
            uid: "privacy-reader-uid",
            displayName: "Reader",
            username: "reader",
            displayNameSearch: "reader",
            usernameSearch: "reader",
            photoUrl: null,
            bannerUrl: null,
            bio: "",
            country: "",
            nativeLanguage: "",
            spokenLanguages: [],
            learningLanguages: [],
            website: null,
            statusMessage: "",
            accountType: "personal",
            premiumIdentity: false,
            friendCount: 1,
            followerCount: 0,
            followingCount: 0,
            schemaVersion: 1,
            updatedAt: Timestamp.now(),
          }),
        ]);
      });
      await assertSucceeds(
        getDoc(
          doc(privacyReader.firestore(), "publicProfiles/privacy-target-uid"),
        ),
      );
      await assertFails(
        getDoc(
          doc(privacyTarget.firestore(), "publicProfiles/privacy-reader-uid"),
        ),
      );
    },
  );

  await check(
    "SECURITY PRIVACY: unauthenticated and banned-target profile reads fail",
    async () => {
      await assertFails(
        getDoc(
          doc(
            privacyUnauthenticated.firestore(),
            "publicProfiles/privacy-target-uid",
          ),
        ),
      );
      await assertFails(
        getDoc(
          doc(
            privacyReader.firestore(),
            "publicProfiles/privacy-banned-target-uid",
          ),
        ),
      );
    },
  );

  await check(
    "SECURITY PRIVACY: public profiles are no-list and server-write-only",
    async () => {
      await assertFails(
        getDocs(collection(privacyReader.firestore(), "publicProfiles")),
      );
      await assertFails(
        setDoc(
          doc(privacyReader.firestore(), "publicProfiles/privacy-reader-uid"),
          { uid: "privacy-reader-uid", displayName: "Forged" },
        ),
      );
      await assertFails(
        updateDoc(
          doc(privacyReader.firestore(), "publicProfiles/privacy-target-uid"),
          { role: "superAdmin" },
        ),
      );
    },
  );

  await check(
    "SECURITY PRIVACY: poisoned public projection schemas fail closed",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await updateDoc(
          doc(
            context.firestore(),
            "publicProfiles/privacy-target-uid",
          ),
          { email: "must-not-leak@private.invalid" },
        );
      });
      await assertFails(
        getDoc(
          doc(
            privacyReader.firestore(),
            "publicProfiles/privacy-target-uid",
          ),
        ),
      );
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await updateDoc(
          doc(
            context.firestore(),
            "publicProfiles/privacy-target-uid",
          ),
          { email: deleteField() },
        );
      });
    },
  );

  await check(
    "PRIVACY: social presence is available to a canonical friend",
    async () => {
      await assertSucceeds(
        getDoc(
          doc(privacyReader.firestore(), "socialPresence/privacy-target-uid"),
        ),
      );
    },
  );

  await check(
    "SECURITY PRIVACY: strangers and legacy friend mirrors without both guards cannot read presence",
    async () => {
      await assertFails(
        getDoc(
          doc(privacyStranger.firestore(), "socialPresence/privacy-target-uid"),
        ),
      );
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await deleteDoc(
          doc(
            context.firestore(),
            "friendshipGuards/privacy-target-uid/friends/privacy-reader-uid",
          ),
        );
      });
      await assertFails(
        getDoc(
          doc(privacyReader.firestore(), "socialPresence/privacy-target-uid"),
        ),
      );
    },
  );

  await check(
    "SECURITY PRIVACY: friendship guards are invisible and immutable to clients",
    async () => {
      const guard = doc(
        privacyReader.firestore(),
        "friendshipGuards/privacy-reader-uid/friends/privacy-target-uid",
      );
      await assertFails(getDoc(guard));
      await assertFails(
        setDoc(guard, {
          ownerId: "privacy-reader-uid",
          friendId: "privacy-target-uid",
          schemaVersion: 1,
          establishedAt: serverTimestamp(),
        }),
      );
      await assertFails(deleteDoc(guard));
    },
  );

  await check(
    "SECURITY PRIVACY: poisoned presence and follow-edge schemas fail closed",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        await Promise.all([
          updateDoc(doc(db, "socialPresence/privacy-target-uid"), {
            email: "presence-leak@private.invalid",
          }),
          setDoc(
            doc(
              db,
              "users/privacy-target-uid/followers/privacy-reader-uid",
            ),
            {
              uid: "privacy-reader-uid",
              followedAt: Timestamp.now(),
              displayName: "Stale identity snapshot",
            },
          ),
        ]);
      });
      await assertFails(
        getDoc(
          doc(
            privacyTarget.firestore(),
            "socialPresence/privacy-target-uid",
          ),
        ),
      );
      await assertFails(
        getDoc(
          doc(
            privacyReader.firestore(),
            "users/privacy-target-uid/followers/privacy-reader-uid",
          ),
        ),
      );
    },
  );

  await check(
    "SECURITY PRIVACY: presence and search quota documents are Admin-only",
    async () => {
      await assertFails(
        setDoc(
          doc(privacyReader.firestore(), "socialPresence/privacy-reader-uid"),
          { uid: "privacy-reader-uid", isOnline: true },
        ),
      );
      await assertFails(
        getDoc(
          doc(
            privacyReader.firestore(),
            "privateRateLimits/searchPublicProfiles_private",
          ),
        ),
      );
      await assertFails(
        setDoc(
          doc(
            privacyReader.firestore(),
            "privateRateLimits/searchPublicProfiles_private",
          ),
          { minuteCount: 0 },
        ),
      );
    },
  );

  // ------------------------------------------------------------------
  // Deployed-client compatibility: the rules have to serve BOTH the client
  // build that is live in production and the one in this tree, because the
  // deploy sequence has a window where both talk to the same ruleset. Every
  // case below is the exact operation shape one of those two clients issues
  // (same fields, same batch/transaction grouping, same query), not a
  // convenient approximation of it.
  // ------------------------------------------------------------------

  const clubManager = testEnv.authenticatedContext("cm-owner-uid", {
    email_verified: true,
  });
  const clubAdmin = testEnv.authenticatedContext("cm-admin-uid", {
    email_verified: true,
  });

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await Promise.all([
      setDoc(doc(db, "users/cm-owner-uid"), { displayName: "CM Owner", banned: false }),
      setDoc(doc(db, "users/cm-admin-uid"), { displayName: "CM Admin", banned: false }),
      setDoc(doc(db, "users/cm-member-uid"), { displayName: "CM Member", banned: false }),
      setDoc(doc(db, "clubs/role-club"), {
        ownerId: "cm-owner-uid",
        status: "active",
        name: "Role club",
        memberCount: 3,
      }),
    ]);
    await Promise.all([
      setDoc(doc(db, "clubs/role-club/members/cm-owner-uid"), {
        userId: "cm-owner-uid",
        role: "owner",
        displayName: "CM Owner",
        joinedAt: Timestamp.fromMillis(1700000000000),
        banned: false,
      }),
      setDoc(doc(db, "clubs/role-club/members/cm-admin-uid"), {
        userId: "cm-admin-uid",
        role: "admin",
        displayName: "CM Admin",
        joinedAt: Timestamp.fromMillis(1700000000000),
        banned: false,
      }),
      setDoc(doc(db, "clubs/role-club/members/cm-member-uid"), {
        userId: "cm-member-uid",
        role: "member",
        displayName: "CM Member",
        joinedAt: Timestamp.fromMillis(1700000000000),
        banned: false,
      }),
    ]);
  });

  // ClubService.updateMemberRole() writes role + roleUpdatedAt + roleUpdatedBy
  // in ONE update, in both the deployed client and this tree's client. A
  // field allowlist that names only `role` denies every promotion and every
  // demotion in the product.
  await check(
    "regression: a Club owner promotes a member with the client's real " +
      "role/roleUpdatedAt/roleUpdatedBy write",
    async () => {
      const db = clubManager.firestore();
      await assertSucceeds(
        updateDoc(doc(db, "clubs/role-club/members/cm-member-uid"), {
          role: "moderator",
          roleUpdatedAt: serverTimestamp(),
          roleUpdatedBy: "cm-owner-uid",
        }),
      );
    },
  );

  await check(
    "regression: a Club owner demotes an admin with the same three-field write",
    async () => {
      const db = clubManager.firestore();
      await assertSucceeds(
        updateDoc(doc(db, "clubs/role-club/members/cm-admin-uid"), {
          role: "member",
          roleUpdatedAt: serverTimestamp(),
          roleUpdatedBy: "cm-owner-uid",
        }),
      );
      // Put the admin back for the privilege cases below.
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await updateDoc(
          doc(ctx.firestore(), "clubs/role-club/members/cm-admin-uid"),
          { role: "admin" },
        );
      });
    },
  );

  await check(
    "SECURITY: widening the role field set does not let a manager forge " +
      "who performed the change",
    async () => {
      const db = clubManager.firestore();
      await assertFails(
        updateDoc(doc(db, "clubs/role-club/members/cm-member-uid"), {
          role: "admin",
          roleUpdatedAt: serverTimestamp(),
          roleUpdatedBy: "cm-admin-uid",
        }),
      );
    },
  );

  await check(
    "SECURITY: a role change cannot backdate roleUpdatedAt to a client value",
    async () => {
      const db = clubManager.firestore();
      await assertFails(
        updateDoc(doc(db, "clubs/role-club/members/cm-member-uid"), {
          role: "admin",
          roleUpdatedAt: Timestamp.fromMillis(1600000000000),
          roleUpdatedBy: "cm-owner-uid",
        }),
      );
    },
  );

  await check(
    "SECURITY: the role write path still refuses self-promotion, owner " +
      "assignment and climbing above the actor's own power",
    async () => {
      const owner = clubManager.firestore();
      const admin = clubAdmin.firestore();
      // An admin is not owner/coOwner, so the manager branch is closed to it.
      await assertFails(
        updateDoc(doc(admin, "clubs/role-club/members/cm-member-uid"), {
          role: "admin",
          roleUpdatedAt: serverTimestamp(),
          roleUpdatedBy: "cm-admin-uid",
        }),
      );
      // Self-promotion, through the widened field set.
      await assertFails(
        updateDoc(doc(admin, "clubs/role-club/members/cm-admin-uid"), {
          role: "coOwner",
          roleUpdatedAt: serverTimestamp(),
          roleUpdatedBy: "cm-admin-uid",
        }),
      );
      // Ownership never moves through this path.
      await assertFails(
        updateDoc(doc(owner, "clubs/role-club/members/cm-member-uid"), {
          role: "owner",
          roleUpdatedAt: serverTimestamp(),
          roleUpdatedBy: "cm-owner-uid",
        }),
      );
      // Permission smuggling alongside a legitimate role change.
      await assertFails(
        updateDoc(doc(owner, "clubs/role-club/members/cm-member-uid"), {
          role: "moderator",
          roleUpdatedAt: serverTimestamp(),
          roleUpdatedBy: "cm-owner-uid",
          banned: false,
          permissions: ["manageClub"],
        }),
      );
    },
  );

  // --- Private Community rooms and their own members ---
  //
  // A Community room is joined while it is public; the host can later flip
  // `visibility` to private through the ordinary metadata update. The member
  // documents survive that flip, and RoomService.watchMyCommunities() then
  // hydrates EVERY room id the collectionGroup query returned with a
  // rooms/{id} get(). One denial rejects the whole Future.wait, so a single
  // unreadable room empties the entire Communities list.
  const communityMember = testEnv.authenticatedContext("cr-member-uid", {
    email_verified: true,
  });
  const communityStranger = testEnv.authenticatedContext("cr-stranger-uid", {
    email_verified: true,
  });

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await Promise.all([
      setDoc(doc(db, "users/cr-member-uid"), { displayName: "CR Member", banned: false }),
      setDoc(doc(db, "users/cr-stranger-uid"), { displayName: "CR Stranger", banned: false }),
      setDoc(doc(db, "users/cr-host-uid"), { displayName: "CR Host", banned: false }),
      setDoc(doc(db, "rooms/cr-public"), {
        hostId: "cr-host-uid",
        roomType: "community",
        visibility: "public",
        status: "active",
        memberCount: 2,
        participantCount: 0,
        isLive: false,
        approvalRequired: false,
      }),
      setDoc(doc(db, "rooms/cr-private"), {
        hostId: "cr-host-uid",
        roomType: "community",
        visibility: "private",
        status: "active",
        memberCount: 2,
        participantCount: 0,
        isLive: false,
        approvalRequired: false,
        membersCanStartVoice: true,
      }),
    ]);
    await Promise.all([
      setDoc(doc(db, "rooms/cr-public/roomMembers/cr-member-uid"), {
        userId: "cr-member-uid",
        role: "member",
        displayName: "CR Member",
      }),
      setDoc(doc(db, "rooms/cr-private/roomMembers/cr-member-uid"), {
        userId: "cr-member-uid",
        role: "member",
        displayName: "CR Member",
      }),
      setDoc(doc(db, "rooms/cr-private/roomMembers/cr-host-uid"), {
        userId: "cr-host-uid",
        role: "owner",
        displayName: "CR Host",
      }),
    ]);
  });

  await check(
    "regression: a member of a private Community room can get the room document",
    async () => {
      const db = communityMember.firestore();
      const snapshot = await assertSucceeds(getDoc(doc(db, "rooms/cr-private")));
      if (!snapshot.exists()) throw new Error("expected the room document back");
    },
  );

  await check(
    "regression: watchMyCommunities() hydration — real collectionGroup query " +
      "plus a get() for every room it returned, including a private one",
    async () => {
      const db = communityMember.firestore();
      const snapshot = await assertSucceeds(
        getDocs(
          query(
            collectionGroup(db, "roomMembers"),
            where("userId", "==", "cr-member-uid"),
          ),
        ),
      );
      const roomIds = [
        ...new Set(
          snapshot.docs
            .map((document) => document.ref.parent.parent &&
              document.ref.parent.parent.id)
            .filter(Boolean),
        ),
      ];
      if (roomIds.length < 2) {
        throw new Error(`expected 2 rooms from the query, got ${roomIds.length}`);
      }
      // Future.wait in room_service.dart: ONE denial rejects everything.
      await assertSucceeds(
        Promise.all(roomIds.map((id) => getDoc(doc(db, `rooms/${id}`)))),
      );
    },
  );

  await check(
    "regression: a member can read their private Community roster while " +
      "voice start remains callable-only",
    async () => {
      const db = communityMember.firestore();
      await assertSucceeds(
        getDocs(collection(db, "rooms/cr-private/roomMembers")),
      );
      await assertFails(
        updateDoc(doc(db, "rooms/cr-private"), {
          isLive: true,
          updatedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "SECURITY: a non-member still cannot get a private Community room, its " +
      "roster or its participants",
    async () => {
      const db = communityStranger.firestore();
      await assertFails(getDoc(doc(db, "rooms/cr-private")));
      await assertFails(getDocs(collection(db, "rooms/cr-private/roomMembers")));
      await assertFails(getDocs(collection(db, "rooms/cr-private/participants")));
    },
  );

  await check(
    "SECURITY: membership cannot be self-minted on a private Community room " +
      "to buy read access",
    async () => {
      const db = communityStranger.firestore();
      // Standalone forged membership.
      await assertFails(
        setDoc(doc(db, "rooms/cr-private/roomMembers/cr-stranger-uid"), {
          userId: "cr-stranger-uid",
          displayName: "CR Stranger",
          role: "member",
          joinedAt: serverTimestamp(),
        }),
      );
      // The production joinCommunity() transaction shape (member document +
      // memberCount increment together) must fail on a private room too.
      await assertFails(
        runTransaction(db, async (transaction) => {
          transaction.set(
            doc(db, "rooms/cr-private/roomMembers/cr-stranger-uid"),
            {
              userId: "cr-stranger-uid",
              displayName: "CR Stranger",
              photoUrl: null,
              role: "member",
              joinedAt: serverTimestamp(),
            },
          );
          transaction.update(doc(db, "rooms/cr-private"), {
            memberCount: 3,
            updatedAt: serverTimestamp(),
          });
        }),
      );
      await assertFails(getDoc(doc(db, "rooms/cr-private")));
    },
  );

  await check(
    "regression: joinCommunity()'s transaction still works on a public " +
      "Community room and grants that member the room read",
    async () => {
      const db = communityStranger.firestore();
      await assertSucceeds(
        runTransaction(db, async (transaction) => {
          const snapshot = await transaction.get(doc(db, "rooms/cr-public"));
          const count = snapshot.data().memberCount;
          transaction.set(
            doc(db, "rooms/cr-public/roomMembers/cr-stranger-uid"),
            {
              userId: "cr-stranger-uid",
              displayName: "CR Stranger",
              photoUrl: null,
              role: "member",
              joinedAt: serverTimestamp(),
            },
          );
          transaction.update(doc(db, "rooms/cr-public"), {
            memberCount: count + 1,
            updatedAt: serverTimestamp(),
          });
        }),
      );
      await assertSucceeds(getDoc(doc(db, "rooms/cr-public")));
    },
  );

  // --- collectionGroup provability, pinned rather than assumed ---
  //
  // ADR-007: the only thing that proves a collectionGroup() query works is a
  // collectionGroup() query. These two pin the CURRENT top-level wildcard
  // rules against the account-status gate they now carry: an active invitee
  // gets their feed, a banned one does not — proven through the query path,
  // not a direct get().
  const bannedInvitee = testEnv.authenticatedContext("cg-banned-uid", {
    email_verified: true,
  });
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/cg-banned-uid"), {
      displayName: "Banned invitee",
      banned: true,
    });
    await setDoc(doc(db, "clubs/cg-club2"), {
      ownerId: "host-uid",
      status: "active",
    });
    await setDoc(doc(db, "clubs/cg-club2/invites/cg-banned-uid"), {
      inviteeId: "cg-banned-uid",
      inviterId: "host-uid",
      status: "pending",
    });
  });

  await check(
    "SECURITY: a banned account's watchMyClubInvites() collectionGroup " +
      "query is denied, through the query path",
    async () => {
      const db = bannedInvitee.firestore();
      await assertFails(
        getDocs(
          query(
            collectionGroup(db, "invites"),
            where("inviteeId", "==", "cg-banned-uid"),
          ),
        ),
      );
    },
  );

  await check(
    "regression: a private Community room does not break the " +
      "collectionGroup('roomMembers') query that lists it",
    async () => {
      const db = communityMember.firestore();
      const snapshot = await assertSucceeds(
        getDocs(
          query(
            collectionGroup(db, "roomMembers"),
            where("userId", "==", "cr-member-uid"),
          ),
        ),
      );
      if (snapshot.size < 2) {
        throw new Error(`expected 2 membership rows, got ${snapshot.size}`);
      }
    },
  );

  // ------------------------------------------------------------------
  // Second review pass. Each case below is a hole the first pass left in
  // the private-Community-room widening, or in the club role write it
  // widened alongside it.
  // ------------------------------------------------------------------

  // --- A membership row is authority, so a suspension has to reach it ---
  const bannedMember = testEnv.authenticatedContext("rm-banned-uid", {
    email_verified: true,
  });
  const disabledMember = testEnv.authenticatedContext("rm-disabled-uid", {
    email_verified: true,
  });

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await Promise.all([
      setDoc(doc(db, "users/rm-banned-uid"), {
        displayName: "Banned member",
        banned: true,
      }),
      setDoc(doc(db, "users/rm-disabled-uid"), {
        displayName: "Disabled member",
        disabled: true,
      }),
    ]);
    await Promise.all([
      setDoc(doc(db, "rooms/cr-private/roomMembers/rm-banned-uid"), {
        userId: "rm-banned-uid",
        role: "member",
        displayName: "Banned member",
      }),
      setDoc(doc(db, "rooms/cr-private/roomMembers/rm-disabled-uid"), {
        userId: "rm-disabled-uid",
        role: "member",
        displayName: "Disabled member",
      }),
      setDoc(doc(db, "rooms/cr-private/participants/cr-host-uid"), {
        userId: "cr-host-uid",
        role: "host",
        isSpeaker: true,
      }),
    ]);
  });

  for (const [label, context] of [
    ["banned", bannedMember],
    ["disabled", disabledMember],
  ]) {
    await check(
      `SECURITY: a ${label} account's room membership does not open the ` +
        "private room, its roster or its participant list",
      async () => {
        const db = context.firestore();
        await assertFails(getDoc(doc(db, "rooms/cr-private")));
        await assertFails(getDocs(collection(db, "rooms/cr-private/roomMembers")));
        await assertFails(getDocs(collection(db, "rooms/cr-private/participants")));
      },
    );
  }

  await check(
    "SECURITY: a banned member cannot start the voice session its " +
      "membership would otherwise permit",
    async () => {
      const db = bannedMember.firestore();
      await assertFails(
        updateDoc(doc(db, "rooms/cr-private"), {
          isLive: true,
          updatedAt: serverTimestamp(),
        }),
      );
    },
  );

  // --- Role attribution has to be unforgeable, including by omission ---
  //
  // diff().affectedKeys() reports only fields whose VALUE changed, so a
  // guard hanging off hasAny() is silently skipped when the caller resends
  // an existing value or sends nothing at all. Both leave the audit trail
  // naming somebody else.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/cm-coowner-uid"), {
      displayName: "CM CoOwner",
      banned: false,
    });
    await setDoc(doc(db, "clubs/role-club/members/cm-coowner-uid"), {
      userId: "cm-coowner-uid",
      role: "coOwner",
      displayName: "CM CoOwner",
      joinedAt: Timestamp.fromMillis(1700000000000),
      banned: false,
    });
    // The state a legitimate co-owner write leaves behind.
    await updateDoc(doc(db, "clubs/role-club/members/cm-member-uid"), {
      role: "member",
      roleUpdatedAt: Timestamp.fromMillis(1755000000000),
      roleUpdatedBy: "cm-coowner-uid",
    });
  });

  await check(
    "SECURITY: a role change cannot keep another manager's attribution by " +
      "resending its existing value",
    async () => {
      const db = clubManager.firestore();
      await assertFails(
        updateDoc(doc(db, "clubs/role-club/members/cm-member-uid"), {
          role: "moderator",
          roleUpdatedAt: Timestamp.fromMillis(1755000000000),
          roleUpdatedBy: "cm-coowner-uid",
        }),
      );
    },
  );

  await check(
    "SECURITY: a role change cannot leave stale attribution standing by " +
      "omitting the fields entirely",
    async () => {
      const db = clubManager.firestore();
      await assertFails(
        updateDoc(doc(db, "clubs/role-club/members/cm-member-uid"), {
          role: "moderator",
        }),
      );
      await assertFails(
        updateDoc(doc(db, "clubs/role-club/members/cm-member-uid"), {
          role: "moderator",
          updatedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "regression: the real client write still lands on a row another " +
      "manager last touched",
    async () => {
      const db = clubManager.firestore();
      await assertSucceeds(
        updateDoc(doc(db, "clubs/role-club/members/cm-member-uid"), {
          role: "moderator",
          roleUpdatedAt: serverTimestamp(),
          roleUpdatedBy: "cm-owner-uid",
        }),
      );
    },
  );

  // --- A room host is not a licence to rewrite a membership row ---
  //
  // `userId` is what watchMyCommunities() filters its collectionGroup query
  // on, so a row carrying somebody else's uid is a remote denial of service
  // against that person's Communities tab: their query returns the row, the
  // room it points at is one they cannot read, and Future.wait in
  // room_service.dart rejects the whole list.
  const roomAttacker = testEnv.authenticatedContext("rm-attacker-uid", {
    email_verified: true,
  });
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/rm-attacker-uid"), {
      displayName: "Room attacker",
      banned: false,
    });
    await setDoc(doc(db, "rooms/rm-attack-room"), {
      hostId: "rm-attacker-uid",
      roomType: "community",
      visibility: "private",
      status: "active",
      memberCount: 1,
      participantCount: 0,
      isLive: false,
    });
    await setDoc(doc(db, "rooms/rm-attack-room/roomMembers/rm-attacker-uid"), {
      userId: "rm-attacker-uid",
      role: "owner",
      displayName: "Room attacker",
      joinedAt: Timestamp.fromMillis(1755000000000),
    });
  });

  await check(
    "SECURITY: a room host cannot repoint a membership row at another " +
      "account's uid",
    async () => {
      const db = roomAttacker.firestore();
      await assertFails(
        updateDoc(doc(db, "rooms/rm-attack-room/roomMembers/rm-attacker-uid"), {
          userId: "cr-member-uid",
        }),
      );
      // The victim's Communities tab is unaffected: the query returns only
      // their own rows and every one of them hydrates.
      const victim = communityMember.firestore();
      const snapshot = await assertSucceeds(
        getDocs(
          query(
            collectionGroup(victim, "roomMembers"),
            where("userId", "==", "cr-member-uid"),
          ),
        ),
      );
      const roomIds = [
        ...new Set(
          snapshot.docs
            .map((document) => document.ref.parent.parent &&
              document.ref.parent.parent.id)
            .filter(Boolean),
        ),
      ];
      if (roomIds.includes("rm-attack-room")) {
        throw new Error("the forged row reached the victim's query");
      }
      await assertSucceeds(
        Promise.all(roomIds.map((id) => getDoc(doc(victim, `rooms/${id}`)))),
      );
    },
  );

  await check(
    "SECURITY: a room host cannot inject fields into a membership row or " +
      "rewrite its role and join time",
    async () => {
      const db = roomAttacker.firestore();
      await assertFails(
        updateDoc(doc(db, "rooms/rm-attack-room/roomMembers/rm-attacker-uid"), {
          role: "superAdmin",
        }),
      );
      await assertFails(
        updateDoc(doc(db, "rooms/rm-attack-room/roomMembers/rm-attacker-uid"), {
          banned: true,
          permissions: ["moderate"],
        }),
      );
      await assertFails(
        updateDoc(doc(db, "rooms/rm-attack-room/roomMembers/rm-attacker-uid"), {
          joinedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "SECURITY: room membership identity refresh accepts only users/{uid}.displayName",
    async () => {
      const host = roomAttacker.firestore();
      await assertFails(
        updateDoc(doc(host, "rooms/rm-attack-room/roomMembers/rm-attacker-uid"), {
          displayName: "Arbitrary host name",
          photoUrl: "https://example.invalid/a.jpg",
          updatedAt: serverTimestamp(),
        }),
      );
      const member = communityMember.firestore();
      await assertFails(
        updateDoc(doc(member, "rooms/cr-private/roomMembers/cr-member-uid"), {
          displayName: "Arbitrary member name",
          updatedAt: serverTimestamp(),
        }),
      );
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await updateDoc(doc(db, "users/rm-attacker-uid"), {
          displayName: "Canonical renamed host",
        });
        await updateDoc(doc(db, "users/cr-member-uid"), {
          displayName: "Canonical renamed member",
        });
      });
      await assertSucceeds(
        updateDoc(doc(host, "rooms/rm-attack-room/roomMembers/rm-attacker-uid"), {
          displayName: "Canonical renamed host",
          photoUrl: null,
          updatedAt: serverTimestamp(),
        }),
      );
      await assertSucceeds(
        updateDoc(doc(member, "rooms/cr-private/roomMembers/cr-member-uid"), {
          displayName: "Canonical renamed member",
          photoUrl: null,
          updatedAt: serverTimestamp(),
        }),
      );
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await updateDoc(doc(db, "users/rm-attacker-uid"), {
          displayName: "Room attacker",
        });
        await updateDoc(doc(db, "users/cr-member-uid"), {
          displayName: "CR Member",
        });
      });
    },
  );

  // --- Membership has to be revocable ---
  //
  // Every case here reads the room's live memberCount first, so the only
  // thing under test is the delete/decrement pairing — never an arithmetic
  // assumption about what earlier cases left behind.
  const memberCountOf = async (roomId) => {
    let count = null;
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const snapshot = await getDoc(doc(ctx.firestore(), `rooms/${roomId}`));
      count = snapshot.data().memberCount;
    });
    if (typeof count !== "number") {
      throw new Error(`could not read memberCount for ${roomId}`);
    }
    return count;
  };

  await check(
    "regression: a member leaves a Community room — row delete and the " +
      "room's memberCount decrement in one batch",
    async () => {
      const db = communityStranger.firestore();
      const before = await memberCountOf("cr-public");
      const batch = writeBatch(db);
      batch.delete(doc(db, "rooms/cr-public/roomMembers/cr-stranger-uid"));
      batch.update(doc(db, "rooms/cr-public"), {
        memberCount: before - 1,
        updatedAt: serverTimestamp(),
      });
      await assertSucceeds(batch.commit());
      if ((await memberCountOf("cr-public")) !== before - 1) {
        throw new Error("memberCount did not follow the departure");
      }
    },
  );

  await check(
    "SECURITY: a host cannot delete membership rows — not one, and not " +
      "twenty behind a single counter decrement",
    async () => {
      const db = testEnv
        .authenticatedContext("cr-host-uid", { email_verified: true })
        .firestore();
      const before = await memberCountOf("cr-private");
      await assertFails(
        deleteDoc(doc(db, "rooms/cr-private/roomMembers/rm-disabled-uid")),
      );
      // The rule condition is evaluated per write but shared across a commit,
      // and rules cannot count writes — so a bulk delete behind one −1 is the
      // shape any counter-paired eviction rule would have let through.
      const batch = writeBatch(db);
      batch.delete(doc(db, "rooms/cr-private/roomMembers/rm-disabled-uid"));
      batch.delete(doc(db, "rooms/cr-private/roomMembers/rm-banned-uid"));
      batch.delete(doc(db, "rooms/cr-private/roomMembers/cr-member-uid"));
      batch.update(doc(db, "rooms/cr-private"), {
        memberCount: before - 1,
        updatedAt: serverTimestamp(),
      });
      await assertFails(batch.commit());
    },
  );

  // F1: the counter must never be able to trap a member in a room. These
  // three are the starvation primitive and the two no-attacker variants of
  // the same trap — a drifted counter and a legacy room that predates the
  // field entirely (ADR-005's rename era produced exactly those).
  await check(
    "SECURITY: a host cannot move memberCount by hand, so the counter " +
      "cannot be starved toward zero",
    async () => {
      const db = testEnv
        .authenticatedContext("cr-host-uid", { email_verified: true })
        .firestore();
      const before = await memberCountOf("cr-private");
      await assertFails(
        updateDoc(doc(db, "rooms/cr-private"), {
          memberCount: before - 1,
          updatedAt: serverTimestamp(),
        }),
      );
      await assertFails(
        updateDoc(doc(db, "rooms/cr-private"), {
          memberCount: 0,
          updatedAt: serverTimestamp(),
        }),
      );
    },
  );

  const trappedMember = testEnv.authenticatedContext("rm-trapped-uid", {
    email_verified: true,
  });
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/rm-trapped-uid"), {
      displayName: "Trapped member",
      banned: false,
    });
    // A room whose stored counter is already short of its real row count.
    await setDoc(doc(db, "rooms/rm-starved"), {
      hostId: "cr-host-uid",
      roomType: "community",
      visibility: "public",
      status: "active",
      memberCount: 0,
      participantCount: 0,
      isLive: false,
    });
    await setDoc(doc(db, "rooms/rm-starved/roomMembers/rm-trapped-uid"), {
      userId: "rm-trapped-uid",
      role: "member",
      displayName: "Trapped member",
    });
    // A room from before memberCount existed at all.
    await setDoc(doc(db, "rooms/rm-legacy"), {
      hostId: "cr-host-uid",
      roomType: "community",
      visibility: "public",
      status: "active",
    });
    await setDoc(doc(db, "rooms/rm-legacy/roomMembers/rm-trapped-uid"), {
      userId: "rm-trapped-uid",
      role: "member",
      displayName: "Trapped member",
    });
    // A suspended room — staff froze it; its members must still get out.
    await setDoc(doc(db, "rooms/rm-suspended"), {
      hostId: "cr-host-uid",
      roomType: "community",
      visibility: "public",
      status: "suspended",
      memberCount: 2,
      participantCount: 0,
      isLive: false,
    });
    await setDoc(doc(db, "rooms/rm-suspended/roomMembers/rm-trapped-uid"), {
      userId: "rm-trapped-uid",
      role: "member",
      displayName: "Trapped member",
    });
  });

  await check(
    "regression: a member can leave a room whose memberCount has already " +
      "drifted to zero",
    async () => {
      const db = trappedMember.firestore();
      await assertSucceeds(
        deleteDoc(doc(db, "rooms/rm-starved/roomMembers/rm-trapped-uid")),
      );
    },
  );

  await check(
    "regression: a member can leave a legacy room that carries no " +
      "memberCount field at all",
    async () => {
      const db = trappedMember.firestore();
      await assertSucceeds(
        deleteDoc(doc(db, "rooms/rm-legacy/roomMembers/rm-trapped-uid")),
      );
    },
  );

  // F3: a staff suspension freezes the host, not the members. Leaving keeps
  // working; what the freeze withholds is the room write that would move the
  // counter and bump updatedAt, which is watchMyCommunities' sort key.
  await check(
    "SECURITY: a suspended room stays frozen for its host — no metadata, " +
      "no counter, no updatedAt bump",
    async () => {
      const db = testEnv
        .authenticatedContext("cr-host-uid", { email_verified: true })
        .firestore();
      await assertFails(
        updateDoc(doc(db, "rooms/rm-suspended"), {
          name: "Renamed while suspended",
          updatedAt: serverTimestamp(),
        }),
      );
      await assertFails(
        updateDoc(doc(db, "rooms/rm-suspended"), {
          memberCount: 1,
          updatedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "regression: a member still leaves a suspended room, and the frozen " +
      "room refuses the paired counter write rather than trapping them",
    async () => {
      const db = trappedMember.firestore();
      const paired = writeBatch(db);
      paired.delete(doc(db, "rooms/rm-suspended/roomMembers/rm-trapped-uid"));
      paired.update(doc(db, "rooms/rm-suspended"), {
        memberCount: 1,
        updatedAt: serverTimestamp(),
      });
      await assertFails(paired.commit());
      await assertSucceeds(
        deleteDoc(doc(db, "rooms/rm-suspended/roomMembers/rm-trapped-uid")),
      );
    },
  );

  await check(
    "SECURITY: leaving still cannot reach another member's row, inflate the " +
      "counter, or orphan the room's owner row",
    async () => {
      const member = communityMember.firestore();
      const before = await memberCountOf("cr-private");
      // Somebody else's row, with or without a counter move.
      await assertFails(
        deleteDoc(doc(member, "rooms/cr-private/roomMembers/rm-banned-uid")),
      );
      const otherBatch = writeBatch(member);
      otherBatch.delete(doc(member, "rooms/cr-private/roomMembers/rm-banned-uid"));
      otherBatch.update(doc(member, "rooms/cr-private"), {
        memberCount: before - 1,
        updatedAt: serverTimestamp(),
      });
      await assertFails(otherBatch.commit());
      // A counter decrement with no departure behind it.
      await assertFails(
        updateDoc(doc(member, "rooms/cr-private"), {
          memberCount: before - 1,
          updatedAt: serverTimestamp(),
        }),
      );
      // Leaving must not be a way to inflate the counter.
      const inflateBatch = writeBatch(member);
      inflateBatch.delete(doc(member, "rooms/cr-private/roomMembers/cr-member-uid"));
      inflateBatch.update(doc(member, "rooms/cr-private"), {
        memberCount: before + 1,
        updatedAt: serverTimestamp(),
      });
      await assertFails(inflateBatch.commit());
      // The owner row stays put so a Community room cannot be orphaned.
      const host = testEnv
        .authenticatedContext("cr-host-uid", { email_verified: true })
        .firestore();
      await assertFails(
        deleteDoc(doc(host, "rooms/cr-private/roomMembers/cr-host-uid")),
      );
      if ((await memberCountOf("cr-private")) !== before) {
        throw new Error("a denied case still moved the counter");
      }
    },
  );

  await check(
    "regression: the accurate leave — row delete and the room's memberCount " +
      "decrement in one batch — still works and still lands",
    async () => {
      const db = communityMember.firestore();
      const before = await memberCountOf("cr-private");
      const batch = writeBatch(db);
      batch.delete(doc(db, "rooms/cr-private/roomMembers/cr-member-uid"));
      batch.update(doc(db, "rooms/cr-private"), {
        memberCount: before - 1,
        updatedAt: serverTimestamp(),
      });
      await assertSucceeds(batch.commit());
      if ((await memberCountOf("cr-private")) !== before - 1) {
        throw new Error("memberCount did not follow the departure");
      }
    },
  );

  // ------------------------------------------------------------------
  // A suspension has to reach the HOST, not only the members.
  //
  // The 2026-08-16 pass gated isRoomMember() and isActiveClubRoomMember()
  // on isActiveAccount() and left the room-root update rule's host branch
  // selecting on `resource.data.hostId == request.auth.uid` alone. A banned
  // or disabled host kept metadata editing and voice-start on their own
  // room — the exact shape docs/SECURITY.md's own checklist warns about
  // ("a branch that selects on resource.data.hostId == request.auth.uid and
  // stops there grants a banned account everything that ownership grants").
  //
  // The cases below come in matched pairs on purpose: every deny has an
  // active-account counterpart proving the guard bites on account status
  // and not on being the host, and every guard has an anti-trap case
  // proving a suspended host's room is still reachable by staff and still
  // leavable by everyone else. Tightening this already went wrong once
  // today in the other direction (952d8e4 removed a rules-level eviction
  // that was trapping members), so both directions are pinned here.
  // ------------------------------------------------------------------
  const bannedHost = testEnv.authenticatedContext("hb-banned-uid", {
    email_verified: true,
  });
  const disabledHost = testEnv.authenticatedContext("hb-disabled-uid", {
    email_verified: true,
  });
  const activeHost = testEnv.authenticatedContext("hb-active-uid", {
    email_verified: true,
  });
  const hostRoomMember = testEnv.authenticatedContext("hb-member-uid", {
    email_verified: true,
  });
  const admittedGuest = testEnv.authenticatedContext("hb-guest-uid", {
    email_verified: true,
  });
  const bannedAdmittedGuest = testEnv.authenticatedContext(
    "hb-banned-guest-uid",
    { email_verified: true },
  );

  const hostBanRooms = {
    banned: "hb-banned-room",
    disabled: "hb-disabled-room",
  };

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await Promise.all([
      setDoc(doc(db, "users/hb-banned-uid"), {
        displayName: "Banned host",
        banned: true,
      }),
      setDoc(doc(db, "users/hb-disabled-uid"), {
        displayName: "Disabled host",
        disabled: true,
      }),
      setDoc(doc(db, "users/hb-active-uid"), {
        displayName: "Active host",
        banned: false,
      }),
      setDoc(doc(db, "users/hb-member-uid"), {
        displayName: "Room member",
        banned: false,
      }),
      setDoc(doc(db, "users/hb-guest-uid"), {
        displayName: "Admitted guest",
        banned: false,
      }),
      setDoc(doc(db, "users/hb-banned-guest-uid"), {
        displayName: "Banned admitted guest",
        banned: true,
      }),
    ]);

    // One public Community room per suspended host, each in the exact shape
    // room_service.dart leaves behind: the host owns a roomMembers row, sits
    // in participants, and members may start voice.
    const room = (hostId, name) => ({
      hostId,
      hostName: name,
      name: `${name}'s room`,
      description: "Original description",
      category: "talk",
      visibility: "public",
      language: "English",
      maxParticipants: 25,
      participantCount: 1,
      memberCount: 2,
      isLive: false,
      roomType: "community",
      status: "active",
      approvalRequired: false,
      slowModeSeconds: 0,
      autoMuteNewUsers: true,
      membersCanStartVoice: true,
    });
    await Promise.all([
      setDoc(doc(db, "rooms/hb-banned-room"), room("hb-banned-uid", "Banned host")),
      setDoc(
        doc(db, "rooms/hb-disabled-room"),
        room("hb-disabled-uid", "Disabled host"),
      ),
      setDoc(doc(db, "rooms/hb-active-room"), room("hb-active-uid", "Active host")),
      // A clean join target: no pre-existing membership row for any of the
      // suspended identities, so a refused join is refused on account status
      // and not because `create` collided with a document already there.
      setDoc(doc(db, "rooms/hb-join-target"), {
        ...room("hb-active-uid", "Active host"),
        memberCount: 1,
        participantCount: 0,
      }),
      // A private, non-Club room whose only way in for a non-member is the
      // host-admitted participant row isHostAdmittedRoomParticipant reads.
      setDoc(doc(db, "rooms/hb-private"), {
        ...room("hb-active-uid", "Active host"),
        visibility: "private",
        participantCount: 2,
        memberCount: 1,
      }),
    ]);
    await Promise.all([
      setDoc(doc(db, "rooms/hb-banned-room/roomMembers/hb-banned-uid"), {
        userId: "hb-banned-uid",
        role: "owner",
        displayName: "Banned host",
      }),
      setDoc(doc(db, "rooms/hb-banned-room/roomMembers/hb-member-uid"), {
        userId: "hb-member-uid",
        role: "member",
        displayName: "Room member",
      }),
      setDoc(doc(db, "rooms/hb-disabled-room/roomMembers/hb-disabled-uid"), {
        userId: "hb-disabled-uid",
        role: "owner",
        displayName: "Disabled host",
      }),
      setDoc(doc(db, "rooms/hb-disabled-room/roomMembers/hb-member-uid"), {
        userId: "hb-member-uid",
        role: "member",
        displayName: "Room member",
      }),
      setDoc(doc(db, "rooms/hb-active-room/roomMembers/hb-active-uid"), {
        userId: "hb-active-uid",
        role: "owner",
        displayName: "Active host",
      }),
      setDoc(doc(db, "rooms/hb-active-room/roomMembers/hb-member-uid"), {
        userId: "hb-member-uid",
        role: "member",
        displayName: "Room member",
      }),
      // A plain (non-owner) membership row for the banned host in someone
      // else's room, so the exit path can be proven separately from the
      // owner row, which is undeletable by design.
      setDoc(doc(db, "rooms/hb-active-room/roomMembers/hb-banned-uid"), {
        userId: "hb-banned-uid",
        role: "member",
        displayName: "Banned host",
      }),
      setDoc(doc(db, "rooms/hb-private/roomMembers/hb-active-uid"), {
        userId: "hb-active-uid",
        role: "owner",
        displayName: "Active host",
      }),
      setDoc(doc(db, "rooms/hb-join-target/roomMembers/hb-active-uid"), {
        userId: "hb-active-uid",
        role: "owner",
        displayName: "Active host",
      }),
    ]);
    await Promise.all([
      setDoc(doc(db, "rooms/hb-banned-room/participants/hb-banned-uid"), {
        userId: "hb-banned-uid",
        displayName: "Banned host",
        role: "host",
        isMuted: false,
        isSpeaker: true,
        isHandRaised: false,
      }),
      setDoc(doc(db, "rooms/hb-disabled-room/participants/hb-disabled-uid"), {
        userId: "hb-disabled-uid",
        displayName: "Disabled host",
        role: "host",
        isMuted: false,
        isSpeaker: true,
        isHandRaised: false,
      }),
      setDoc(doc(db, "rooms/hb-active-room/participants/hb-active-uid"), {
        userId: "hb-active-uid",
        displayName: "Active host",
        role: "host",
        isMuted: false,
        isSpeaker: true,
        isHandRaised: false,
      }),
      // Both guests were admitted by the private room's current host. Only
      // their account status differs.
      setDoc(doc(db, "rooms/hb-private/participants/hb-guest-uid"), {
        userId: "hb-guest-uid",
        displayName: "Admitted guest",
        role: "listener",
        isMuted: true,
        isSpeaker: false,
        isHandRaised: false,
        admittedBy: "hb-active-uid",
      }),
      setDoc(doc(db, "rooms/hb-private/participants/hb-banned-guest-uid"), {
        userId: "hb-banned-guest-uid",
        displayName: "Banned admitted guest",
        role: "listener",
        isMuted: true,
        isSpeaker: false,
        isHandRaised: false,
        admittedBy: "hb-active-uid",
      }),
    ]);
    await Promise.all([
      setDoc(doc(db, "rooms/hb-banned-room/messages/hb-banned-msg"), {
        senderId: "hb-member-uid",
        senderName: "Room member",
        text: "hello",
        reactions: {},
      }),
      setDoc(doc(db, "rooms/hb-disabled-room/messages/hb-disabled-msg"), {
        senderId: "hb-member-uid",
        senderName: "Room member",
        text: "hello",
        reactions: {},
      }),
      setDoc(doc(db, "rooms/hb-active-room/messages/hb-active-msg"), {
        senderId: "hb-member-uid",
        senderName: "Room member",
        text: "hello",
        reactions: {},
      }),
      setDoc(doc(db, "rooms/hb-private/messages/hb-private-msg"), {
        senderId: "hb-active-uid",
        senderName: "Active host",
        text: "private hello",
        reactions: {},
      }),
    ]);
  });

  const hostBanRoomState = async (roomId) => {
    let data = null;
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const snapshot = await getDoc(doc(ctx.firestore(), `rooms/${roomId}`));
      data = snapshot.data();
    });
    if (!data) throw new Error(`could not read rooms/${roomId}`);
    return data;
  };

  for (const [label, context] of [
    ["banned", bannedHost],
    ["disabled", disabledHost],
  ]) {
    const roomId = hostBanRooms[label];
    const uid = `hb-${label}-uid`;

    await check(
      `SECURITY HOST SUSPENSION: a ${label} host cannot edit their room's ` +
        "metadata",
      async () => {
        const db = context.firestore();
        await assertFails(
          updateDoc(doc(db, `rooms/${roomId}`), {
            name: "Renamed while suspended",
            updatedAt: serverTimestamp(),
          }),
        );
        // Flipping a public room private is the same branch, and it is the
        // damaging one: canAccessRoom stops serving every member who joined
        // while the room was public.
        await assertFails(
          updateDoc(doc(db, `rooms/${roomId}`), {
            visibility: "private",
            updatedAt: serverTimestamp(),
          }),
        );
        await assertFails(
          updateDoc(doc(db, `rooms/${roomId}`), {
            description: "Rewritten while suspended",
            approvalRequired: true,
            membersCanStartVoice: false,
            maxParticipants: 2,
            updatedAt: serverTimestamp(),
          }),
        );
        const stored = await hostBanRoomState(roomId);
        if (
          stored.name === "Renamed while suspended" ||
          stored.visibility !== "public" ||
          stored.description !== "Original description" ||
          stored.approvalRequired === true ||
          stored.membersCanStartVoice !== true
        ) {
          throw new Error("a denied metadata write still landed on the room");
        }
      },
    );

    await check(
      `SECURITY HOST SUSPENSION: a ${label} host cannot start their room's ` +
        "voice session",
      async () => {
        const db = context.firestore();
        await assertFails(
          updateDoc(doc(db, `rooms/${roomId}`), {
            isLive: true,
            updatedAt: serverTimestamp(),
          }),
        );
        if ((await hostBanRoomState(roomId)).isLive !== false) {
          throw new Error("a denied voice start still went live");
        }
      },
    );

    await check(
      `SECURITY HOST SUSPENSION: a ${label} host cannot toggle a reaction on ` +
        "their own room's chat",
      async () => {
        const db = context.firestore();
        await assertFails(
          updateDoc(doc(db, `rooms/${roomId}/messages/hb-${label}-msg`), {
            reactions: { "🔥": [uid] },
          }),
        );
      },
    );

    // The membership row must be keyed on the caller's OWN uid: both the
    // create rule (`request.auth.uid == memberId`) and
    // roomMemberJoinTransitionAllowed (`roomMembers/$(request.auth.uid)`)
    // key off it, so any other document id is refused on the path and
    // proves nothing about account status.
    await check(
      `SECURITY HOST SUSPENSION: a ${label} account cannot join a Community ` +
        "room — the real joinCommunity() transaction is refused",
      async () => {
        const db = context.firestore();
        await assertFails(
          runTransaction(db, async (transaction) => {
            const snapshot = await transaction.get(doc(db, "rooms/hb-join-target"));
            const count = snapshot.data().memberCount;
            transaction.set(
              doc(db, `rooms/hb-join-target/roomMembers/${uid}`),
              {
                userId: uid,
                displayName: "Suspended joiner",
                photoUrl: null,
                role: "member",
                joinedAt: serverTimestamp(),
              },
            );
            transaction.update(doc(db, "rooms/hb-join-target"), {
              memberCount: count + 1,
              updatedAt: serverTimestamp(),
            });
          }),
        );
        let landed = true;
        await testEnv.withSecurityRulesDisabled(async (ctx) => {
          const snapshot = await getDoc(
            doc(ctx.firestore(), `rooms/hb-join-target/roomMembers/${uid}`),
          );
          landed = snapshot.exists();
        });
        if (landed) {
          throw new Error("a denied join still wrote the membership row");
        }
      },
    );

    await check(
      `SECURITY HOST SUSPENSION: after moderation sweeps the roster, a ` +
        `${label} host cannot rejoin their own room as its host participant`,
      async () => {
        // The state setRoomModerationStatus leaves behind: participants gone.
        await testEnv.withSecurityRulesDisabled(async (ctx) => {
          const db = ctx.firestore();
          await deleteDoc(doc(db, `rooms/${roomId}/participants/${uid}`));
          await updateDoc(doc(db, `rooms/${roomId}`), { participantCount: 0 });
        });
        const db = context.firestore();
        const batch = writeBatch(db);
        batch.update(doc(db, `rooms/${roomId}`), {
          participantCount: 1,
          updatedAt: serverTimestamp(),
        });
        batch.set(doc(db, `rooms/${roomId}/participants/${uid}`), {
          userId: uid,
          displayName: "Suspended host",
          photoUrl: null,
          role: "host",
          isMuted: false,
          isSpeaker: true,
          isHandRaised: false,
          joinedAt: serverTimestamp(),
          updatedAt: serverTimestamp(),
        });
        await assertFails(batch.commit());
        // The room-root half must be refused on its own too, so the deny is
        // not resting solely on the participant create rule.
        await assertFails(
          updateDoc(doc(db, `rooms/${roomId}`), {
            participantCount: 1,
            updatedAt: serverTimestamp(),
          }),
        );
      },
    );
  }

  // --- The same guard must not bite an ACTIVE host -------------------
  await check(
    "regression: an ACTIVE host still edits metadata and reacts while " +
      "visibility changes and voice start remain callable-only",
    async () => {
      const db = activeHost.firestore();
      await assertSucceeds(
        updateDoc(doc(db, "rooms/hb-active-room"), {
          name: "Renamed by its active host",
          description: "Rewritten by its active host",
          approvalRequired: true,
          maxParticipants: 30,
          updatedAt: serverTimestamp(),
        }),
      );
      await assertFails(
        updateDoc(doc(db, "rooms/hb-active-room"), {
          visibility: "private",
          updatedAt: serverTimestamp(),
        }),
      );
      await assertFails(
        updateDoc(doc(db, "rooms/hb-active-room"), {
          isLive: true,
          updatedAt: serverTimestamp(),
        }),
      );
      await assertSucceeds(
        updateDoc(doc(db, "rooms/hb-active-room/messages/hb-active-msg"), {
          reactions: { "🔥": ["hb-active-uid"] },
        }),
      );
      // Put the fixture back the way the remaining cases expect it.
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await updateDoc(doc(ctx.firestore(), "rooms/hb-active-room"), {
          visibility: "public",
          approvalRequired: false,
          isLive: false,
        });
      });
    },
  );

  await check(
    "regression: an ACTIVE member still joins a Community room and an " +
      "ACTIVE host-admitted guest keeps the private room, its roster, its " +
      "participants and its chat",
    async () => {
      const joiner = testEnv.authenticatedContext("hb-joiner-uid", {
        email_verified: true,
      });
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "users/hb-joiner-uid"), {
          displayName: "Active joiner",
          banned: false,
        });
      });
      const joinerDb = joiner.firestore();
      await assertSucceeds(
        runTransaction(joinerDb, async (transaction) => {
          const snapshot = await transaction.get(
            doc(joinerDb, "rooms/hb-active-room"),
          );
          const count = snapshot.data().memberCount;
          transaction.set(
            doc(joinerDb, "rooms/hb-active-room/roomMembers/hb-joiner-uid"),
            {
              userId: "hb-joiner-uid",
              displayName: "Active joiner",
              photoUrl: null,
              role: "member",
              joinedAt: serverTimestamp(),
            },
          );
          transaction.update(doc(joinerDb, "rooms/hb-active-room"), {
            memberCount: count + 1,
            updatedAt: serverTimestamp(),
          });
        }),
      );

      const guestDb = admittedGuest.firestore();
      await assertSucceeds(getDoc(doc(guestDb, "rooms/hb-private")));
      await assertSucceeds(
        getDocs(collection(guestDb, "rooms/hb-private/roomMembers")),
      );
      await assertSucceeds(
        getDocs(collection(guestDb, "rooms/hb-private/participants")),
      );
      await assertSucceeds(
        getDocs(collection(guestDb, "rooms/hb-private/messages")),
      );
    },
  );

  await check(
    "SECURITY HOST SUSPENSION: a BANNED host-admitted participant loses the " +
      "private room, its roster, its participants and its chat",
    async () => {
      const db = bannedAdmittedGuest.firestore();
      await assertFails(getDoc(doc(db, "rooms/hb-private")));
      await assertFails(getDocs(collection(db, "rooms/hb-private/roomMembers")));
      await assertFails(
        getDocs(collection(db, "rooms/hb-private/participants")),
      );
      await assertFails(getDocs(collection(db, "rooms/hb-private/messages")));
      await assertFails(
        updateDoc(doc(db, "rooms/hb-private/messages/hb-private-msg"), {
          reactions: { "🔥": ["hb-banned-guest-uid"] },
        }),
      );
    },
  );

  // --- The other direction: a suspended host must stay ACTIONABLE ----
  //
  // 952d8e4 removed a rules-level eviction because tightening a room rule
  // had trapped members. The same failure mode applies here: if hardening
  // the host branch made a banned host's room unreachable or unleavable,
  // the fix would be an outage rather than a boundary.
  await check(
    "regression ANTI-TRAP: staff moderation still reaches a suspended " +
      "host's room — the setRoomModerationStatus transaction and its " +
      "participant sweep land through the Admin SDK",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        // The exact transaction functions/admin/rooms.js runs.
        await runTransaction(db, async (transaction) => {
          const snapshot = await transaction.get(doc(db, "rooms/hb-banned-room"));
          if (!snapshot.exists()) throw new Error("the room vanished");
          if (snapshot.data().status === "deleted") {
            throw new Error("unexpected tombstone");
          }
          transaction.update(doc(db, "rooms/hb-banned-room"), {
            status: "suspended",
            isLive: false,
            participantCount: 0,
            moderationReason: "Host suspended",
            moderatedBy: "hb-staff-uid",
            moderatedAt: serverTimestamp(),
            updatedAt: serverTimestamp(),
          });
        });
        // …and the participant sweep that follows it.
        await deleteDoc(
          doc(db, "rooms/hb-banned-room/participants/hb-banned-uid"),
        );
      });
      const stored = await hostBanRoomState("hb-banned-room");
      if (stored.status !== "suspended" || stored.moderatedBy !== "hb-staff-uid") {
        throw new Error("staff moderation did not land on the room");
      }
      // The banned host must not be able to undo it either.
      await assertFails(
        updateDoc(doc(bannedHost.firestore(), "rooms/hb-banned-room"), {
          status: "active",
          updatedAt: serverTimestamp(),
        }),
      );
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await updateDoc(doc(ctx.firestore(), "rooms/hb-banned-room"), {
          status: "active",
          moderationReason: null,
        });
      });
    },
  );

  await check(
    "regression ANTI-TRAP: a suspended host does not freeze their room for " +
      "everyone else — a member still reads it and leaves with the counter, " +
      "while voice start remains callable-only",
    async () => {
      const db = hostRoomMember.firestore();
      await assertSucceeds(getDoc(doc(db, "rooms/hb-banned-room")));
      await assertSucceeds(
        getDocs(collection(db, "rooms/hb-banned-room/roomMembers")),
      );
      await assertFails(
        updateDoc(doc(db, "rooms/hb-banned-room"), {
          isLive: true,
          updatedAt: serverTimestamp(),
        }),
      );
      const before = await memberCountOf("hb-banned-room");
      const batch = writeBatch(db);
      batch.delete(doc(db, "rooms/hb-banned-room/roomMembers/hb-member-uid"));
      batch.update(doc(db, "rooms/hb-banned-room"), {
        memberCount: before - 1,
        updatedAt: serverTimestamp(),
      });
      await assertSucceeds(batch.commit());
      if ((await memberCountOf("hb-banned-room")) !== before - 1) {
        throw new Error("the member's departure did not move the counter");
      }
    },
  );

  await check(
    "regression ANTI-TRAP: a suspended account can still LEAVE a room — the " +
      "exit is deliberately not gated on account status",
    async () => {
      await assertSucceeds(
        deleteDoc(
          doc(
            bannedHost.firestore(),
            "rooms/hb-active-room/roomMembers/hb-banned-uid",
          ),
        ),
      );
    },
  );

  // --- The boundary this pass deliberately did NOT move ----------------
  //
  // canAccessRoom()'s `visibility == 'public'` clause and the top-level
  // `match /{path=**}/roomMembers/{memberId}` wildcard both still run on
  // isSignedIn(), so a suspended account keeps READING public rooms it
  // belongs to. That is deliberate, and this case exists to prove the host
  // hardening above did not cascade into it rather than to bless it:
  //
  //  - ADR-006 keeps the top-level wildcard narrow and provable from the
  //    query's own filter, and per docs/SECURITY.md principle 3 getting
  //    that rule wrong fails OPEN. It is the last rule in this file that
  //    should acquire an unnecessary conjunct.
  //  - watchMyCommunities() hydrates every id the query returns inside a
  //    single Future.wait, so a read denial there empties the whole
  //    Communities tab. Denying a suspended account's own feed is the
  //    trap shape 952d8e4 was reverted for, not a containment win.
  //  - Reading is not authority. Every WRITE this feed could lead to is
  //    now account-status gated; what is left is a member seeing rooms
  //    they already joined.
  //
  // Run as a real collectionGroup() query, not a per-document get(), per
  // ADR-007 — the nested roomMembers `create` rule changed in this pass and
  // a direct-path check would not have proven the query surface intact.
  await check(
    "BOUNDARY (deliberate, unchanged): a suspended account's own " +
      "collectionGroup('roomMembers') feed still resolves and still " +
      "hydrates its public rooms, so hardening the host branch did not " +
      "cascade into the top-level wildcard rule",
    async () => {
      const db = bannedHost.firestore();
      const snapshot = await assertSucceeds(
        getDocs(
          query(
            collectionGroup(db, "roomMembers"),
            where("userId", "==", "hb-banned-uid"),
          ),
        ),
      );
      if (snapshot.size < 1) {
        throw new Error(`expected the banned account's own rows, got ${snapshot.size}`);
      }
      const roomIds = [
        ...new Set(
          snapshot.docs
            .map((document) =>
              document.ref.parent.parent && document.ref.parent.parent.id)
            .filter(Boolean),
        ),
      ];
      // Future.wait in room_service.dart: one denial rejects the whole tab.
      await assertSucceeds(
        Promise.all(roomIds.map((id) => getDoc(doc(db, `rooms/${id}`)))),
      );
      // …and the feed is still somebody else's uid away from being useful.
      await assertFails(
        getDocs(
          query(
            collectionGroup(db, "roomMembers"),
            where("userId", "==", "hb-member-uid"),
          ),
        ),
      );
    },
  );

  // --- consent-backed public marketing showcase ---

  const showcaseStranger = testEnv.unauthenticatedContext();
  const inactiveConsentUser = testEnv.authenticatedContext(
    "inactive-consent-uid",
    { email_verified: true },
  );
  const accountConsentRef = doc(
    host.firestore(),
    "marketingConsents/host-uid",
  );

  await check(
    "MARKETING CONSENT: an account can create and read its exact own consent",
    async () => {
      await assertSucceeds(setDoc(accountConsentRef, {
        schemaVersion: 1,
        showProfileOnWebsite: true,
        showActivityOnWebsite: true,
        updatedAt: serverTimestamp(),
      }));
      const snapshot = await assertSucceeds(getDoc(accountConsentRef));
      assert.equal(snapshot.data()?.showProfileOnWebsite, true);
    },
  );

  await check(
    "SECURITY MARKETING CONSENT: unverified and inactive accounts cannot opt in",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await setDoc(doc(context.firestore(), "users/inactive-consent-uid"), {
          displayName: "Inactive consent",
          banned: false,
          disabled: true,
        });
      });
      const payload = {
        schemaVersion: 1,
        showProfileOnWebsite: true,
        showActivityOnWebsite: false,
        updatedAt: serverTimestamp(),
      };
      await assertFails(setDoc(
        doc(unverified.firestore(), "marketingConsents/unverified-uid"),
        payload,
      ));
      await assertFails(setDoc(
        doc(
          inactiveConsentUser.firestore(),
          "marketingConsents/inactive-consent-uid",
        ),
        payload,
      ));
    },
  );

  await check(
    "SECURITY MARKETING CONSENT: activity cannot be public when profile is private",
    async () => {
      await assertFails(setDoc(
        doc(attacker.firestore(), "marketingConsents/attacker-uid"),
        {
          schemaVersion: 1,
          showProfileOnWebsite: false,
          showActivityOnWebsite: true,
          updatedAt: serverTimestamp(),
        },
      ));
    },
  );

  await check(
    "SECURITY MARKETING CONSENT: extra fields and caller timestamps are denied",
    async () => {
      await assertFails(setDoc(accountConsentRef, {
        schemaVersion: 1,
        showProfileOnWebsite: true,
        showActivityOnWebsite: false,
        email: "must-not-be-published@private.invalid",
        updatedAt: serverTimestamp(),
      }));
      await assertFails(setDoc(accountConsentRef, {
        schemaVersion: 1,
        showProfileOnWebsite: true,
        showActivityOnWebsite: false,
        updatedAt: Timestamp.fromMillis(1_800_000_000_000),
      }));
    },
  );

  await check(
    "SECURITY MARKETING CONSENT: another account and anonymous caller cannot read or write it",
    async () => {
      await assertFails(getDoc(doc(
        attacker.firestore(),
        "marketingConsents/host-uid",
      )));
      await assertFails(getDoc(doc(
        showcaseStranger.firestore(),
        "marketingConsents/host-uid",
      )));
      await assertFails(setDoc(
        doc(attacker.firestore(), "marketingConsents/host-uid"),
        {
          schemaVersion: 1,
          showProfileOnWebsite: true,
          showActivityOnWebsite: false,
          updatedAt: serverTimestamp(),
        },
      ));
    },
  );

  await check(
    "SECURITY MARKETING CONSENT: clients cannot enumerate account consents",
    async () => {
      await assertFails(getDocs(collection(host.firestore(), "marketingConsents")));
      await assertFails(getDocs(collection(
        showcaseStranger.firestore(),
        "marketingConsents",
      )));
    },
  );

  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "clubs/showcase-club"), {
      ownerId: "host-uid",
      name: "Real public club",
      type: "community",
      privacy: "public",
      status: "active",
      memberCount: 3,
    });
  });

  const clubConsentRef = doc(
    host.firestore(),
    "clubMarketingConsents/showcase-club",
  );

  await check(
    "CLUB MARKETING CONSENT: the current owner can grant an exact owner-bound consent",
    async () => {
      await assertSucceeds(setDoc(clubConsentRef, {
        schemaVersion: 1,
        clubId: "showcase-club",
        ownerId: "host-uid",
        showOnWebsite: true,
        updatedAt: serverTimestamp(),
      }));
      await assertSucceeds(getDoc(clubConsentRef));
    },
  );

  await check(
    "SECURITY CLUB MARKETING CONSENT: non-owner, wrong binding and extra fields fail",
    async () => {
      await assertFails(getDoc(doc(
        attacker.firestore(),
        "clubMarketingConsents/showcase-club",
      )));
      await assertFails(setDoc(
        doc(attacker.firestore(), "clubMarketingConsents/showcase-club"),
        {
          schemaVersion: 1,
          clubId: "showcase-club",
          ownerId: "attacker-uid",
          showOnWebsite: true,
          updatedAt: serverTimestamp(),
        },
      ));
      await assertFails(setDoc(clubConsentRef, {
        schemaVersion: 1,
        clubId: "some-other-club",
        ownerId: "host-uid",
        showOnWebsite: true,
        updatedAt: serverTimestamp(),
      }));
      await assertFails(setDoc(clubConsentRef, {
        schemaVersion: 1,
        clubId: "showcase-club",
        ownerId: "host-uid",
        showOnWebsite: true,
        ownerEmail: "must-not-leak@private.invalid",
        updatedAt: serverTimestamp(),
      }));
    },
  );

  await check(
    "SECURITY CLUB MARKETING CONSENT: clients cannot enumerate club consents",
    async () => {
      await assertFails(getDocs(collection(
        host.firestore(),
        "clubMarketingConsents",
      )));
      await assertFails(getDocs(collection(
        showcaseStranger.firestore(),
        "clubMarketingConsents",
      )));
    },
  );

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      setDoc(doc(db, "publicShowcase/live"), {
        schemaVersion: 1,
        people: [{
          displayName: "Consenting creator",
          accountType: "creator",
          activity: "undisclosed",
        }],
        clubs: [{ name: "Real public club", memberCount: 3 }],
        generatedAt: Timestamp.now(),
        activityValidUntil: Timestamp.now(),
        validUntil: Timestamp.now(),
      }),
      setDoc(doc(db, "publicShowcase/internal"), {
        secret: "not public",
      }),
    ]);
  });

  await check(
    "PUBLIC SHOWCASE: anonymous and signed-in callers can get only the pinned live document",
    async () => {
      await assertSucceeds(getDoc(doc(
        showcaseStranger.firestore(),
        "publicShowcase/live",
      )));
      await assertSucceeds(getDoc(doc(host.firestore(), "publicShowcase/live")));
      await assertFails(getDoc(doc(
        showcaseStranger.firestore(),
        "publicShowcase/internal",
      )));
    },
  );

  await check(
    "SECURITY PUBLIC SHOWCASE: no caller can list, create, update or delete the projection",
    async () => {
      await assertFails(getDocs(collection(
        showcaseStranger.firestore(),
        "publicShowcase",
      )));
      await assertFails(getDocs(collection(host.firestore(), "publicShowcase")));
      await assertFails(setDoc(
        doc(attacker.firestore(), "publicShowcase/live"),
        { people: [{ displayName: "Forged" }] },
      ));
      await assertFails(updateDoc(
        doc(host.firestore(), "publicShowcase/live"),
        { people: [] },
      ));
      await assertFails(deleteDoc(doc(
        showcaseStranger.firestore(),
        "publicShowcase/live",
      )));
    },
  );

  await check(
    "SECURITY PUBLIC SHOWCASE: privacy-generation control is backend-only",
    async () => {
      const anonymous = showcaseStranger.firestore();
      const signedIn = host.firestore();
      await assertFails(getDoc(doc(
        anonymous,
        "privateShowcaseControl/live",
      )));
      await assertFails(getDoc(doc(
        signedIn,
        "privateShowcaseControl/live",
      )));
      await assertFails(setDoc(doc(
        signedIn,
        "privateShowcaseControl/live",
      ), { privacyGeneration: 999 }));
      await assertFails(getDocs(collection(
        signedIn,
        "privateShowcaseControl",
      )));
    },
  );

  // --- publicStats/live: the project's first aggregate-only world-readable document ---
  //
  // Every other `allow` in this file ends at some account. This one does not,
  // so the cases below are the entire boundary and they are written as if the
  // reader were hostile, because the reader is the internet.
  //
  // Two things are proved separately and must stay separate. That a stranger
  // can GET the one pinned document is the feature. That NOTHING else about
  // the collection is reachable — no enumeration, no sibling, no subcollection,
  // no write from any caller — is the containment. A suite that only checked
  // the first would pass just as happily against `match /publicStats/{id}
  // { allow read: if true; }`, which is a different and much worse rule.

  const statsStranger = testEnv.unauthenticatedContext();

  await check(
    "PUBLIC STATS: an unauthenticated stranger gets publicStats/live even " +
      "before it exists — the rule reads no document state, so a run before " +
      "the scheduler's first publish is a miss, never a denial",
    async () => {
      const snapshot = await assertSucceeds(
        getDoc(doc(statsStranger.firestore(), "publicStats/live")),
      );
      if (snapshot.exists()) {
        throw new Error(
          "publicStats/live was already seeded — this case must run first",
        );
      }
    },
  );

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      // Exactly the shape functions/stats/public_stats.js publishes. Nothing
      // here identifies anyone; that is the actual security control on this
      // path, and it is asserted in functions/test/public_stats.test.js.
      setDoc(doc(db, "publicStats/live"), {
        schemaVersion: 2,
        activeAccounts: 14,
        existingRooms: 6,
        updatedAt: Timestamp.now(),
      }),
      // A sibling, seeded deliberately. If the match statement is ever
      // loosened to a wildcard, this document starts leaking and the case
      // below turns red.
      setDoc(doc(db, "publicStats/internal"), { secret: "not for the world" }),
      setDoc(doc(db, "publicStats/live/history/entry"), { activeAccounts: 13 }),
    ]);
  });

  await check(
    "PUBLIC STATS: an unauthenticated stranger reads the published document",
    async () => {
      const snapshot = await assertSucceeds(
        getDoc(doc(statsStranger.firestore(), "publicStats/live")),
      );
      if (snapshot.data()?.activeAccounts !== 14) {
        throw new Error(
          `expected the published aggregate, got ${JSON.stringify(snapshot.data())}`,
        );
      }
    },
  );

  await check(
    "PUBLIC STATS: a signed-in account reads it too — the grant is not " +
      "accidentally scoped to anonymous callers",
    async () => {
      await assertSucceeds(getDoc(doc(host.firestore(), "publicStats/live")));
    },
  );

  await check(
    "SECURITY PUBLIC STATS: an unauthenticated stranger cannot create it",
    async () => {
      await assertFails(
        setDoc(doc(statsStranger.firestore(), "publicStats/live"), {
          schemaVersion: 2,
          activeAccounts: 9_999_999,
          existingRooms: 9_999_999,
          updatedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "SECURITY PUBLIC STATS: a signed-in account cannot overwrite the " +
      "published numbers",
    async () => {
      await assertFails(
        setDoc(doc(attacker.firestore(), "publicStats/live"), {
          schemaVersion: 2,
          activeAccounts: 9_999_999,
          existingRooms: 9_999_999,
          updatedAt: serverTimestamp(),
        }),
      );
    },
  );

  await check(
    "SECURITY PUBLIC STATS: a signed-in account cannot nudge one field",
    async () => {
      await assertFails(
        updateDoc(doc(attacker.firestore(), "publicStats/live"), {
          activeAccounts: 2_481,
        }),
      );
    },
  );

  await check(
    "SECURITY PUBLIC STATS: nobody can delete the published document — a " +
      "world-readable document is also a world-visible outage if a client " +
      "can remove it",
    async () => {
      await assertFails(
        deleteDoc(doc(statsStranger.firestore(), "publicStats/live")),
      );
      await assertFails(
        deleteDoc(doc(attacker.firestore(), "publicStats/live")),
      );
    },
  );

  await check(
    "SECURITY PUBLIC STATS: a signed-in account cannot LIST the collection — " +
      "`read` would have granted this, `get` does not",
    async () => {
      await assertFails(
        getDocs(collection(attacker.firestore(), "publicStats")),
      );
    },
  );

  await check(
    "SECURITY PUBLIC STATS: an unauthenticated stranger cannot LIST the " +
      "collection either",
    async () => {
      await assertFails(
        getDocs(collection(statsStranger.firestore(), "publicStats")),
      );
    },
  );

  await check(
    "SECURITY PUBLIC STATS: naming the readable document inside a QUERY is " +
      "still a list and is still refused — the get grant cannot be reached " +
      "through a filter",
    async () => {
      await assertFails(
        getDocs(
          query(
            collection(statsStranger.firestore(), "publicStats"),
            where(documentId(), "==", "live"),
          ),
        ),
      );
    },
  );

  await check(
    "SECURITY PUBLIC STATS: publicStats/anythingElse is denied — the pinned " +
      "document id is what stops a future sibling from being published by " +
      "accident",
    async () => {
      await assertFails(
        getDoc(doc(statsStranger.firestore(), "publicStats/internal")),
      );
      await assertFails(
        getDoc(doc(attacker.firestore(), "publicStats/internal")),
      );
    },
  );

  await check(
    "SECURITY PUBLIC STATS: the grant does not cascade to a subcollection " +
      "under the published document",
    async () => {
      await assertFails(
        getDoc(doc(statsStranger.firestore(), "publicStats/live/history/entry")),
      );
      await assertFails(
        getDocs(
          collection(statsStranger.firestore(), "publicStats/live/history"),
        ),
      );
    },
  );

  // --- The publicStats discriminators, run rather than asserted ---
  //
  // The twelve cases above prove the shipped rule denies enumeration. They do
  // NOT prove the denial is caused by the two choices made deliberately —
  // `get` instead of `read`, and a pinned id instead of `{statsId}`. A suite
  // can pass for the wrong reason (the emulator refusing something unrelated),
  // and this project has been bitten by exactly that: see ADR-007 and the
  // collectionGroup discriminator below. So the alternatives are compiled and
  // RUN, and the leak they would have shipped is observed directly.

  const PINNED_PUBLIC_STATS =
    "    match /publicStats/live {\n" +
    "      allow get: if true;\n" +
    "      allow list: if false;\n" +
    "      allow create, update, delete: if false;\n" +
    "    }";

  async function publicStatsUnderVariantRules(projectId, edits, run) {
    const source = fs.readFileSync(RULES_PATH, "utf8");
    let variant = source;
    for (const [find, replaceWith] of edits) {
      if (!variant.includes(find)) {
        throw new Error(
          `rule text drifted — variant snippet not found:\n${find}`,
        );
      }
      variant = variant.replace(find, replaceWith);
    }
    if (variant === source) {
      throw new Error(
        "rule text drifted — the variant transform matched nothing",
      );
    }
    const variantEnv = await initializeTestEnvironment({
      projectId,
      firestore: { rules: variant, host: EMULATOR_HOST, port: EMULATOR_PORT },
    });
    try {
      await variantEnv.clearFirestore();
      await variantEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        await Promise.all([
          setDoc(doc(db, "publicStats/live"), {
            schemaVersion: 2,
            activeAccounts: 14,
            existingRooms: 6,
            updatedAt: Timestamp.now(),
          }),
          setDoc(doc(db, "publicStats/internal"), {
            secret: "not for the world",
          }),
        ]);
      });
      return await run(variantEnv.unauthenticatedContext().firestore());
    } finally {
      await variantEnv.cleanup();
    }
  }

  await check(
    "PROOF: `allow read` on a WILDCARD publicStats match hands the whole " +
      "collection to an anonymous stranger, sibling documents included — " +
      "which is the rule that was proposed, and the leak the pinned id stops",
    async () => {
      const snapshot = await assertSucceeds(
        publicStatsUnderVariantRules(
          "demo-yovoice-stats-a",
          [[
            PINNED_PUBLIC_STATS,
            "    match /publicStats/{statsId} {\n" +
              "      allow read: if true;\n" +
              "      allow create, update, delete: if false;\n" +
              "    }",
          ]],
          (db) => getDocs(collection(db, "publicStats")),
        ),
      );
      const ids = snapshot.docs.map((document) => document.id).sort();
      if (ids.length !== 2 || !ids.includes("internal")) {
        throw new Error(
          `expected the wildcard variant to leak both documents, got ${ids}`,
        );
      }
    },
  );

  await check(
    "PROOF: `allow read` on the PINNED id still refuses the list, so the " +
      "pinned id — not the get/read choice — is what contains enumeration; " +
      "`get` is the narrower grant kept because the product needs nothing more",
    async () => {
      await assertFails(
        publicStatsUnderVariantRules(
          "demo-yovoice-stats-b",
          [[
            PINNED_PUBLIC_STATS,
            "    match /publicStats/live {\n" +
              "      allow read: if true;\n" +
              "      allow create, update, delete: if false;\n" +
              "    }",
          ]],
          (db) => getDocs(collection(db, "publicStats")),
        ),
      );
    },
  );

  // --- The collectionGroup discriminator, run rather than asserted ---
  //
  // Setting the nested rule to `if false` proves nothing: Firestore unions
  // allow rules, so `false || <top-level provable>` is allowed under either
  // hypothesis. The experiment that separates them is the opposite one —
  // make the NESTED rule maximally permissive and the TOP-LEVEL rule deny.
  // If a nested block could authorize a collectionGroup query, `if true`
  // would do it. It does not, which is what makes the top-level wildcard
  // rule the single thing keeping watchMyCommunities() alive.
  //
  // `edits` is a list of [find, replaceWith] pairs. EACH `find` is asserted
  // present before anything is replaced — checking only that the result
  // differs from the source is not enough when a case makes more than one
  // substitution, because one match is enough to hide the other's silent
  // miss, and the case then runs a variant that proves nothing while still
  // reporting OK.
  async function collectionGroupUnderVariantRules(projectId, edits) {
    const source = fs.readFileSync(RULES_PATH, "utf8");
    let variant = source;
    for (const [find, replaceWith] of edits) {
      if (!variant.includes(find)) {
        throw new Error(
          `rule text drifted — variant snippet not found:\n${find}`,
        );
      }
      variant = variant.replace(find, replaceWith);
    }
    if (variant === source) {
      throw new Error(
        "rule text drifted — the variant transform matched nothing",
      );
    }
    const variantEnv = await initializeTestEnvironment({
      projectId,
      firestore: { rules: variant, host: EMULATOR_HOST, port: EMULATOR_PORT },
    });
    try {
      await variantEnv.clearFirestore();
      await variantEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, "users/cg-probe-uid"), {
          displayName: "CG probe",
          banned: false,
        });
        await setDoc(doc(db, "rooms/cg-probe-room"), {
          hostId: "cg-probe-host",
          roomType: "community",
          visibility: "public",
          status: "active",
          memberCount: 1,
        });
        await setDoc(
          doc(db, "rooms/cg-probe-room/roomMembers/cg-probe-uid"),
          { userId: "cg-probe-uid", role: "member" },
        );
      });
      const db = variantEnv
        .authenticatedContext("cg-probe-uid", { email_verified: true })
        .firestore();
      return await getDocs(
        query(
          collectionGroup(db, "roomMembers"),
          where("userId", "==", "cg-probe-uid"),
        ),
      );
    } finally {
      await variantEnv.cleanup();
    }
  }

  // === VOICE START vs. A ROOM WHOSE TEARDOWN HAS ALREADY COMMITTED =====
  //
  // executeDeleteRoom() sets `deletionInProgress: true` in the transaction
  // that closes the room; LiveKit endRoom, the active-session mirrors, the
  // Storage media sweep and the recursive document delete all happen AFTER
  // that transaction commits. Everything else in this ruleset that moves a
  // room reads the flag — roomActivityTouchAllowed, the member-leave
  // transition, hostRoomUpdateAllowed's metadata branch. The two START
  // branches did not, and that was invisible only because nothing in the app
  // ever set `isLive: true` on an ordinary room. The client now performs
  // that transition, so the omission became reachable.
  //
  // EVERY FIXTURE HERE IS A LEGACY DOCUMENT, on purpose. 24 of the 45
  // production rooms carry neither `roomType` nor `experience`, and none
  // carries `deletionInProgress` at all — so these rooms omit those fields
  // rather than setting them to false. That is the shape the existing lounge
  // and room fixtures in this file never exercise, and it is exactly the
  // shape a guard written as a bare field read would break: a bare read of a
  // missing field RAISES, and a raising rule DENIES, which would have locked
  // every legacy room out of voice while pretending to protect deleting
  // ones. The final PROOF case builds that variant and measures it.
  const LEGACY_ROOM = {
    hostId: "vsd-host-uid",
    hostName: "Legacy Host",
    name: "Legacy room",
    visibility: "public",
    isLive: false,
    participantCount: 0,
    memberCount: 1,
    maxParticipants: null,
    // Deliberately absent: roomType, experience, status, deletionInProgress.
  };

  // The exact write room_service.dart's startRoomVoice() performs — the key
  // set both start branches allowlist, and nothing else. `endedAt` deletes a
  // field these documents do not have, so it contributes no affected key.
  const startVoice = (db, roomId) =>
    updateDoc(doc(db, `rooms/${roomId}`), {
      isLive: true,
      updatedAt: serverTimestamp(),
      endedAt: deleteField(),
    });

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await Promise.all([
      setDoc(doc(db, "users/vsd-host-uid"), {
        displayName: "Legacy Host",
        banned: false,
      }),
      setDoc(doc(db, "users/vsd-member-uid"), {
        displayName: "Legacy Member",
        banned: false,
      }),
      setDoc(doc(db, "users/vsd-club-uid"), {
        displayName: "Legacy Club Member",
        banned: false,
      }),
      setDoc(doc(db, "clubs/vsd-club"), {
        ownerId: "vsd-host-uid",
        name: "Legacy Club",
        status: "active",
      }),
      setDoc(doc(db, "clubs/vsd-club/members/vsd-club-uid"), {
        userId: "vsd-club-uid",
        role: "member",
        displayName: "Legacy Club Member",
      }),
    ]);
    await Promise.all([
      setDoc(doc(db, "rooms/vsd-deleting-member"), {
        ...LEGACY_ROOM,
        membersCanStartVoice: true,
        deletionInProgress: true,
      }),
      setDoc(doc(db, "rooms/vsd-live-member"), {
        ...LEGACY_ROOM,
        membersCanStartVoice: true,
      }),
      setDoc(doc(db, "rooms/vsd-deleting-host"), {
        ...LEGACY_ROOM,
        deletionInProgress: true,
      }),
      setDoc(doc(db, "rooms/vsd-live-host"), { ...LEGACY_ROOM }),
      setDoc(doc(db, "rooms/vsd-deleting-lounge"), {
        ...LEGACY_ROOM,
        visibility: "private",
        roomKind: "clubLounge",
        clubId: "vsd-club",
        deletionInProgress: true,
      }),
      setDoc(doc(db, "rooms/vsd-live-lounge"), {
        ...LEGACY_ROOM,
        visibility: "private",
        roomKind: "clubLounge",
        clubId: "vsd-club",
      }),
    ]);
    await Promise.all([
      setDoc(doc(db, "rooms/vsd-deleting-member/roomMembers/vsd-member-uid"), {
        userId: "vsd-member-uid",
        role: "member",
        displayName: "Legacy Member",
      }),
      setDoc(doc(db, "rooms/vsd-live-member/roomMembers/vsd-member-uid"), {
        userId: "vsd-member-uid",
        role: "member",
        displayName: "Legacy Member",
      }),
    ]);
  });

  const legacyRoomMember = testEnv.authenticatedContext("vsd-member-uid", {
    email_verified: true,
  });
  const legacyRoomHost = testEnv.authenticatedContext("vsd-host-uid", {
    email_verified: true,
  });
  const legacyClubMember = testEnv.authenticatedContext("vsd-club-uid", {
    email_verified: true,
  });

  await check(
    "SECURITY VOICE START: a roomMembers holder cannot start either a " +
      "deleting or healthy LEGACY room directly; both use the callable",
    async () => {
      const db = legacyRoomMember.firestore();
      await assertFails(startVoice(db, "vsd-deleting-member"));
      await assertFails(startVoice(db, "vsd-live-member"));
    },
  );

  await check(
    "SECURITY VOICE START: the HOST cannot directly start either a deleting " +
      "or healthy room; the callable owns both paths",
    async () => {
      const db = legacyRoomHost.firestore();
      // The metadata branch already refused this; the two branches now agree
      // instead of the same host being denied a rename and allowed a restart.
      await assertFails(
        updateDoc(doc(db, "rooms/vsd-deleting-host"), {
          name: "Renamed mid-teardown",
          updatedAt: serverTimestamp(),
        }),
      );
      await assertFails(startVoice(db, "vsd-deleting-host"));
      await assertFails(startVoice(db, "vsd-live-host"));
    },
  );

  await check(
    "SECURITY VOICE START: a Club member cannot directly start either a " +
      "deleting or healthy lounge; callable Club authorization is preserved",
    async () => {
      const db = legacyClubMember.firestore();
      await assertFails(startVoice(db, "vsd-deleting-lounge"));
      await assertFails(startVoice(db, "vsd-live-lounge"));
    },
  );

  const TOP_LEVEL_ROOM_MEMBERS =
    "    match /{path=**}/roomMembers/{memberId} {\n" +
    "      allow read: if isSignedIn() && resource.data.userId == request.auth.uid;\n" +
    "    }";
  const TOP_LEVEL_ROOM_MEMBERS_DENIED =
    "    match /{path=**}/roomMembers/{memberId} {\n" +
    "      allow read: if false;\n" +
    "    }";
  const NESTED_ROOM_MEMBERS_READ =
    "        allow read: if resource.data.userId == request.auth.uid ||\n" +
    "            canAccessRoom(roomId);";

  await check(
    "PROOF: a nested match block cannot authorize a collectionGroup query " +
      "even when it says `if true` — the top-level wildcard is the only " +
      "thing that can",
    async () => {
      await assertFails(
        collectionGroupUnderVariantRules("demo-yovoice-cg-a", [
          [TOP_LEVEL_ROOM_MEMBERS, TOP_LEVEL_ROOM_MEMBERS_DENIED],
          [NESTED_ROOM_MEMBERS_READ, "        allow read: if true;"],
        ]),
      );
    },
  );

  await check(
    "PROOF: the same query succeeds with the top-level wildcard restored " +
      "and the nested rule denying, so the deny above is not incidental",
    async () => {
      const snapshot = await assertSucceeds(
        collectionGroupUnderVariantRules("demo-yovoice-cg-b", [
          [NESTED_ROOM_MEMBERS_READ, "        allow read: if false;"],
        ]),
      );
      if (snapshot.size !== 1) {
        throw new Error(`expected 1 membership row, got ${snapshot.size}`);
      }
    },
  );

  // -----------------------------------------------------------------------
  // DIRECT CALLS — callables are the only writers; each participant may
  // point-read canonical call state, while the callee alone owns the compact
  // incoming-call subscription beneath users/{uid}.
  // -----------------------------------------------------------------------
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await Promise.all([
      setDoc(doc(db, "users/call-caller"), {
        displayName: "Call Caller",
        banned: false,
      }),
      setDoc(doc(db, "users/call-callee"), {
        displayName: "Call Callee",
        banned: false,
      }),
      setDoc(doc(db, "users/call-outsider"), {
        displayName: "Call Outsider",
        banned: false,
      }),
      setDoc(doc(db, "directCalls/call-security"), {
        callerId: "call-caller",
        calleeId: "call-callee",
        participantIds: ["call-callee", "call-caller"],
        status: "ringing",
      }),
      setDoc(doc(db, "users/call-callee/incomingCalls/call-security"), {
        callId: "call-security",
        callerId: "call-caller",
        status: "ringing",
      }),
      setDoc(doc(db, "directCallLocks/call-callee"), {
        callId: "call-security",
        status: "ringing",
      }),
      setDoc(doc(db, "directCallStartLimits/call-callee-limit"), {
        schemaVersion: 1,
        scope: "callee",
        startedAt: [new Date()],
        updatedAt: new Date(),
      }),
      setDoc(doc(db, "directCallControlOutbox/call-security"), {
        callId: "call-security",
        status: "pending",
      }),
    ]);
  });

  const callCaller = testEnv.authenticatedContext("call-caller", {
    email_verified: true,
  });
  const callCallee = testEnv.authenticatedContext("call-callee", {
    email_verified: true,
  });
  const callOutsider = testEnv.authenticatedContext("call-outsider", {
    email_verified: true,
  });

  await check(
    "DIRECT CALL SECURITY: both participants can point-read the canonical " +
      "call and an outsider cannot",
    async () => {
      await assertSucceeds(
        getDoc(doc(callCaller.firestore(), "directCalls/call-security")),
      );
      await assertSucceeds(
        getDoc(doc(callCallee.firestore(), "directCalls/call-security")),
      );
      await assertFails(
        getDoc(doc(callOutsider.firestore(), "directCalls/call-security")),
      );
    },
  );

  await check(
    "DIRECT CALL SECURITY: clients cannot forge or transition call state",
    async () => {
      const callerDb = callCaller.firestore();
      await assertFails(
        setDoc(doc(callerDb, "directCalls/forged-call"), {
          callerId: "call-caller",
          calleeId: "call-callee",
          participantIds: ["call-callee", "call-caller"],
          status: "active",
        }),
      );
      await assertFails(
        updateDoc(doc(callerDb, "directCalls/call-security"), {
          status: "active",
        }),
      );
      await assertFails(
        deleteDoc(doc(callerDb, "directCalls/call-security")),
      );
    },
  );

  await check(
    "DIRECT CALL SECURITY: only the callee can read their ringing inbox, " +
      "and even they cannot dismiss or forge it",
    async () => {
      const calleeDb = callCallee.firestore();
      await assertSucceeds(
        getDocs(
          query(
            collection(calleeDb, "users/call-callee/incomingCalls"),
            where("status", "==", "ringing"),
          ),
        ),
      );
      await assertFails(
        getDoc(
          doc(
            callCaller.firestore(),
            "users/call-callee/incomingCalls/call-security",
          ),
        ),
      );
      await assertFails(
        deleteDoc(
          doc(calleeDb, "users/call-callee/incomingCalls/call-security"),
        ),
      );
    },
  );

  await check(
    "DIRECT CALL SECURITY: concurrency locks and LiveKit teardown jobs are " +
      "opaque even to their subject",
    async () => {
      const calleeDb = callCallee.firestore();
      await assertFails(
        getDoc(doc(calleeDb, "directCallLocks/call-callee")),
      );
      await assertFails(
        getDoc(doc(calleeDb, "directCallControlOutbox/call-security")),
      );
      await assertFails(
        getDoc(doc(calleeDb, "directCallStartLimits/call-callee-limit")),
      );
    },
  );

  await check(
    "SOCIAL DISCOVERY SECURITY: private caches, quotas and capacity ledgers " +
      "are opaque and server-only",
    async () => {
      const db = host.firestore();
      for (const path of [
        "privateFriendDiscoveryCaches/cache-probe",
        "privateSocialGraphCapacities/capacity-probe",
        "privateRateLimits/discovery-probe",
      ]) {
        const reference = doc(db, path);
        await assertFails(getDoc(reference));
        await assertFails(setDoc(reference, { count: 0 }));
        await assertFails(deleteDoc(reference));
      }
    },
  );

  await check(
    "ROOM INTEGRITY SECURITY: creation, voice-start and live-fanout control " +
      "documents are opaque and server-only",
    async () => {
      const db = host.firestore();
      for (const path of [
        "privateRoomHostGuards/host-uid",
        "privateRoomCreationAttempts/create-probe",
        "privateRoomVoiceStartGuards/start-guard-probe",
        "privateRoomVoiceStartAttempts/start-attempt-probe",
        "roomLiveFanoutOutbox/fanout-probe",
      ]) {
        const reference = doc(db, path);
        await assertFails(getDoc(reference));
        await assertFails(setDoc(reference, { count: 0 }));
        await assertFails(deleteDoc(reference));
      }
    },
  );

  await check(
    "VOICE MOMENT SECURITY: short-lived report receipts are opaque and " +
      "server-only",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), "voiceMomentReportReceipts/receipt-probe"),
          {
            schemaVersion: 1,
            ownerId: "host-uid",
            targetType: "voiceMoment",
            momentId: "moment-probe",
            commentId: null,
            targetAuthorId: "other-uid",
            token: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            issuedAt: Timestamp.fromMillis(1_800_000_000_000),
            expiresAt: Timestamp.fromMillis(1_800_000_600_000),
          },
        );
      });
      const reference = doc(
        host.firestore(),
        "voiceMomentReportReceipts/receipt-probe",
      );
      await assertFails(getDoc(reference));
      await assertFails(setDoc(reference, { forged: true }));
      await assertFails(deleteDoc(reference));
    },
  );

  await check(
    "REELS SECURITY: content, reservations, cleanup and ledgers are opaque " +
      "and server-only",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await Promise.all([
          setDoc(doc(db, "reels/reel-security"), {
            ownerId: "host-uid",
            moderationStatus: "visible",
          }),
          setDoc(doc(db, "reelUploadReservations/reel-security"), {
            ownerId: "host-uid",
            status: "uploading",
          }),
          setDoc(doc(db, "reelAvailability/reel-security"), {
            ownerId: "host-uid",
            status: "published",
          }),
          setDoc(doc(db, "reelCleanupOutbox/reel-security"), {
            ownerId: "host-uid",
            status: "pending",
          }),
          setDoc(doc(db, "integrityOperationLedgers/reel-security"), {
            ownerId: "host-uid",
          }),
        ]);
      });
      const db = host.firestore();
      for (const path of [
        "reels/reel-security",
        "reelUploadReservations/reel-security",
        "reelAvailability/reel-security",
        "reelCleanupOutbox/reel-security",
        "integrityOperationLedgers/reel-security",
      ]) {
        const reference = doc(db, path);
        await assertFails(getDoc(reference));
        await assertFails(setDoc(reference, { forged: true }));
        await assertFails(deleteDoc(reference));
      }
    },
  );

  await check(
    "SECURITY: availability is owner-written, four values only, and projected form is readable",
    async () => {
      const owner = testEnv.authenticatedContext("availability-owner", {
        email_verified: true,
      });
      const other = testEnv.authenticatedContext("availability-other", {
        email_verified: true,
      });
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await setDoc(doc(db, "users/availability-owner"), {
          uid: "availability-owner",
          email: "owner@yovoice.app",
          displayName: "Owner",
          accountType: "personal",
          isOnline: true,
        });
        await setDoc(doc(db, "users/availability-other"), {
          uid: "availability-other",
          email: "other@yovoice.app",
          displayName: "Other",
          accountType: "personal",
          isOnline: true,
        });
        await setDoc(doc(db, "socialPresence/availability-owner"), {
          uid: "availability-owner",
          isOnline: true,
          lastSeen: new Date(),
          availability: "busy",
          schemaVersion: 1,
          updatedAt: new Date(),
        });
      });
      const ownerDoc = doc(owner.firestore(), "users/availability-owner");
      for (const value of ["available", "away", "busy", "invisible"]) {
        await assertSucceeds(
          setDoc(
            ownerDoc,
            { availability: value, presenceUpdatedAt: serverTimestamp() },
            { merge: true },
          ),
        );
      }
      await assertFails(
        setDoc(ownerDoc, { availability: "party" }, { merge: true }),
      );
      await assertFails(setDoc(ownerDoc, { availability: 7 }, { merge: true }));
      await assertFails(
        setDoc(
          doc(other.firestore(), "users/availability-owner"),
          { availability: "busy" },
          { merge: true },
        ),
      );
      // The projection stays server-only, and its optional key is readable
      // by the account itself.
      await assertFails(
        setDoc(
          doc(owner.firestore(), "socialPresence/availability-owner"),
          { availability: "away" },
          { merge: true },
        ),
      );
      await assertSucceeds(
        getDoc(doc(owner.firestore(), "socialPresence/availability-owner")),
      );
    },
  );

  await check(
    "REELS ENGAGEMENT: likes and comments are unreadable and unwritable by " +
      "every client, exactly like the Reel itself",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await Promise.all([
          setDoc(doc(db, "reels/reel-engagement"), {
            schemaVersion: 1,
            status: "published",
            moderationStatus: "visible",
            authorId: "attacker-uid",
            likeCount: 3,
            commentCount: 1,
          }),
          // The caller's OWN like edge and OWN comment. If any read path
          // existed it would be this one, and it must still be denied: a
          // Reel document has never been client-readable, so its engagement
          // is reached only through the server callables.
          setDoc(doc(db, "reels/reel-engagement/likes/host-uid"), {
            schemaVersion: 1,
            userId: "host-uid",
            reelId: "reel-engagement",
            createdAt: Timestamp.fromMillis(1_800_000_000_000),
          }),
          setDoc(doc(db, "reels/reel-engagement/comments/comment-1"), {
            schemaVersion: 1,
            type: "text",
            reelId: "reel-engagement",
            authorId: "host-uid",
            authorName: "Host",
            text: "mine",
            durationSeconds: null,
            createdAt: Timestamp.fromMillis(1_800_000_000_000),
          }),
        ]);
      });

      const db = host.firestore();
      const likeRef = doc(db, "reels/reel-engagement/likes/host-uid");
      const commentRef = doc(db, "reels/reel-engagement/comments/comment-1");

      // Point reads of the caller's own engagement.
      await assertFails(getDoc(likeRef));
      await assertFails(getDoc(commentRef));
      // Listing either subcollection.
      await assertFails(
        getDocs(collection(db, "reels/reel-engagement/likes")),
      );
      await assertFails(
        getDocs(
          query(
            collection(db, "reels/reel-engagement/comments"),
            orderBy("createdAt", "asc"),
            limit(7),
          ),
        ),
      );

      // Forging a like edge for yourself, and for somebody else.
      await assertFails(
        setDoc(doc(db, "reels/reel-engagement/likes/host-uid"), {
          schemaVersion: 1,
          userId: "host-uid",
          reelId: "reel-engagement",
          createdAt: serverTimestamp(),
        }),
      );
      await assertFails(
        setDoc(doc(db, "reels/reel-engagement/likes/attacker-uid"), {
          schemaVersion: 1,
          userId: "attacker-uid",
          reelId: "reel-engagement",
          createdAt: serverTimestamp(),
        }),
      );
      await assertFails(deleteDoc(likeRef));

      // Writing a comment directly, editing one, and deleting your own.
      await assertFails(
        setDoc(doc(db, "reels/reel-engagement/comments/forged"), {
          schemaVersion: 1,
          type: "text",
          reelId: "reel-engagement",
          authorId: "host-uid",
          authorName: "Host",
          text: "written without a counter, a ledger or a rate budget",
          durationSeconds: null,
          createdAt: serverTimestamp(),
        }),
      );
      await assertFails(updateDoc(commentRef, { text: "edited" }));
      await assertFails(deleteDoc(commentRef));
    },
  );

  await check(
    "REELS ENGAGEMENT: counters on the Reel root are server-only and cannot " +
      "be seeded, merged or bumped by a client",
    async () => {
      const db = host.firestore();
      const reelRef = doc(db, "reels/reel-engagement");
      await assertFails(getDoc(reelRef));
      // Direct set, merge-update and a fresh root carrying a forged count.
      await assertFails(updateDoc(reelRef, { likeCount: 999999 }));
      await assertFails(
        setDoc(reelRef, { commentCount: 0 }, { merge: true }),
      );
      await assertFails(
        setDoc(doc(db, "reels/reel-forged"), {
          schemaVersion: 1,
          status: "published",
          moderationStatus: "visible",
          authorId: "host-uid",
          likeCount: 500,
          commentCount: 500,
        }),
      );
      // A batch that pairs a legitimate-looking child write with the counter
      // is refused as a whole, not partially applied.
      const batch = writeBatch(db);
      batch.set(doc(db, "reels/reel-engagement/likes/host-uid"), {
        schemaVersion: 1,
        userId: "host-uid",
        reelId: "reel-engagement",
        createdAt: serverTimestamp(),
      });
      batch.update(reelRef, { likeCount: 4 });
      await assertFails(batch.commit());
    },
  );

  await check(
    "REELS ENGAGEMENT: a collectionGroup query over the shared `comments` " +
      "and `likes` names reaches nothing",
    async () => {
      // Reel engagement deliberately reuses the Voice Moment subcollection
      // names. That is only safe while NO top-level wildcard rule exists for
      // either name — a nested match cannot authorize a collectionGroup query
      // (ADR-006), and getting a top-level one wrong fails OPEN. This is the
      // production-shaped query an attacker would actually run, not a
      // point-get standing in for it (ADR-007).
      const db = host.firestore();
      await assertFails(getDocs(query(collectionGroup(db, "comments"))));
      await assertFails(getDocs(query(collectionGroup(db, "likes"))));
      await assertFails(
        getDocs(
          query(
            collectionGroup(db, "comments"),
            where("reelId", "==", "reel-engagement"),
          ),
        ),
      );
      await assertFails(
        getDocs(
          query(collectionGroup(db, "likes"), where("userId", "==", "host-uid")),
        ),
      );
    },
  );

  await check(
    "REELS ENGAGEMENT: an unverified, anonymous or blocked-adjacent client " +
      "gains no engagement path either",
    async () => {
      for (const context of [
        unverified.firestore(),
        testEnv.unauthenticatedContext().firestore(),
        attacker.firestore(),
      ]) {
        await assertFails(
          getDoc(doc(context, "reels/reel-engagement/comments/comment-1")),
        );
        await assertFails(
          setDoc(doc(context, "reels/reel-engagement/likes/host-uid"), {
            schemaVersion: 1,
            userId: "host-uid",
            reelId: "reel-engagement",
            createdAt: serverTimestamp(),
          }),
        );
      }
    },
  );

  // -----------------------------------------------------------------
  // REEL COMMENT MODERATION
  //
  // Three separate boundaries, and all three have to hold at once:
  //   1. a client cannot FILE a Reel comment report — not for somebody
  //      else, and not even for itself; `createReelCommentReport` is the
  //      only writer and it runs on the Admin SDK;
  //   2. a client cannot REMOVE a Reel comment by writing Firestore,
  //      including the Reel's own author, who genuinely holds that
  //      authority but only through `removeReelComment`;
  //   3. the report's `targetTextSnapshot` — a copy of somebody's words,
  //      the one field in the queue that quotes reported content — is
  //      readable by active staff and by nobody else, including the
  //      reporter and the person reported.
  // -----------------------------------------------------------------

  const RC_REEL = "reel-comment-moderation";
  const RC_COMMENT = "0123456789abcdef0123456789abcdef01234567";
  const RC_REPORT = "server-written-reel-comment-report";
  const RC_TEXT = "the reported words, quoted into the queue";

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await Promise.all([
      setDoc(doc(db, `reels/${RC_REEL}`), {
        schemaVersion: 1,
        status: "published",
        moderationStatus: "visible",
        // host-uid owns the Reel; attacker-uid wrote the comment.
        authorId: "host-uid",
        commentCount: 1,
        likeCount: 0,
      }),
      setDoc(doc(db, `reels/${RC_REEL}/comments/${RC_COMMENT}`), {
        schemaVersion: 1,
        type: "text",
        reelId: RC_REEL,
        authorId: "attacker-uid",
        authorName: "Attacker",
        text: RC_TEXT,
        durationSeconds: null,
        createdAt: Timestamp.fromMillis(1_800_000_000_000),
      }),
      // Exactly what createReelCommentReport writes through the Admin SDK.
      setDoc(doc(db, `reports/${RC_REPORT}`), {
        schemaVersion: 2,
        reporterId: "invitee-uid",
        targetType: "reelComment",
        targetId: RC_COMMENT,
        reportedUserId: "attacker-uid",
        contextPath: `reels/${RC_REEL}/comments/${RC_COMMENT}`,
        reelId: RC_REEL,
        commentId: RC_COMMENT,
        reelAuthorId: "host-uid",
        targetTextSnapshot: RC_TEXT,
        note: "",
        reason: "harassment",
        status: "open",
        createdAt: Timestamp.fromMillis(1_800_000_000_000),
      }),
    ]);
  });

  await check(
    "SECURITY REEL COMMENT REPORTS: no client can file one — the create " +
      "rule has no reelComment branch and no room for its fields",
    async () => {
      const db = invitee.firestore();
      const full = {
        schemaVersion: 2,
        reporterId: "invitee-uid",
        targetType: "reelComment",
        targetId: RC_COMMENT,
        reportedUserId: "attacker-uid",
        contextPath: `reels/${RC_REEL}/comments/${RC_COMMENT}`,
        reelId: RC_REEL,
        commentId: RC_COMMENT,
        reelAuthorId: "host-uid",
        targetTextSnapshot: RC_TEXT,
        note: "",
        reason: "harassment",
        status: "open",
        createdAt: serverTimestamp(),
      };
      // The full server shape, at the id the server would use.
      await assertFails(
        setDoc(doc(db, `reports/${RC_REPORT}-forged`), full),
      );
      // The same shape at the deterministic id the CLIENT path requires,
      // with the rate-limit document advanced exactly as a legal v1 report
      // would advance it. The extra keys and the unknown targetType are
      // both fatal on their own.
      const batch = writeBatch(db);
      batch.set(
        doc(db, `reports/invitee-uid_reelComment_${RC_COMMENT}`),
        full,
      );
      batch.set(doc(db, "reportLimits/invitee-uid"), {
        lastReportAt: serverTimestamp(),
        lastReportId: `invitee-uid_reelComment_${RC_COMMENT}`,
        windowStartAt: serverTimestamp(),
        windowCount: 1,
      });
      await assertFails(batch.commit());
      // Stripped back to the v1 field allowlist, the targetType still has
      // no existence branch, so there is nothing to prove the comment is
      // real or that attacker-uid wrote it.
      const minimal = writeBatch(db);
      minimal.set(
        doc(db, `reports/invitee-uid_reelComment_${RC_COMMENT}`),
        {
          reporterId: "invitee-uid",
          targetType: "reelComment",
          targetId: RC_COMMENT,
          reportedUserId: "attacker-uid",
          contextPath: `reels/${RC_REEL}/comments/${RC_COMMENT}`,
          reason: "harassment",
          note: "",
          status: "open",
          createdAt: serverTimestamp(),
        },
      );
      minimal.set(doc(db, "reportLimits/invitee-uid"), {
        lastReportAt: serverTimestamp(),
        lastReportId: `invitee-uid_reelComment_${RC_COMMENT}`,
        windowStartAt: serverTimestamp(),
        windowCount: 1,
      });
      await assertFails(minimal.commit());
    },
  );

  await check(
    "SECURITY REEL COMMENT REPORTS: a reporter cannot file one naming " +
      "somebody else as the reporter, nor smuggle a text snapshot onto a " +
      "report shape that IS accepted",
    async () => {
      const db = attacker.firestore();
      // Reporter identity is pinned to request.auth.uid on every branch.
      await assertFails(
        setDoc(doc(db, `reports/invitee-uid_reelComment_${RC_COMMENT}`), {
          reporterId: "invitee-uid",
          targetType: "reelComment",
          targetId: RC_COMMENT,
          reportedUserId: "host-uid",
          contextPath: `reels/${RC_REEL}/comments/${RC_COMMENT}`,
          reason: "harassment",
          note: "",
          status: "open",
          createdAt: serverTimestamp(),
        }),
      );
      // A `user` report is a shape the client path DOES accept. Adding the
      // quoted-content field to it must still be refused, or the queue
      // becomes a place to publish text about somebody under their name.
      const batch = writeBatch(db);
      batch.set(doc(db, "reports/attacker-uid_user_invitee-uid"), {
        reporterId: "attacker-uid",
        targetType: "user",
        targetId: "invitee-uid",
        reportedUserId: "invitee-uid",
        contextPath: null,
        reason: "harassment",
        note: "",
        status: "open",
        createdAt: serverTimestamp(),
        targetTextSnapshot: "words invitee-uid never wrote",
      });
      batch.set(doc(db, "reportLimits/attacker-uid"), {
        lastReportAt: serverTimestamp(),
        lastReportId: "attacker-uid_user_invitee-uid",
        windowStartAt: serverTimestamp(),
        windowCount: 1,
      });
      await assertFails(batch.commit());
    },
  );

  await check(
    "SECURITY REEL COMMENT REPORTS: the quoted comment text is readable by " +
      "active staff and by nobody else — not the reporter, not the person " +
      "reported, not the Reel's author",
    async () => {
      const filed = `reports/${RC_REPORT}`;
      const staffRead = await getDoc(doc(moderator.firestore(), filed));
      assert.equal(staffRead.data().targetTextSnapshot, RC_TEXT);
      assert.equal(staffRead.data().reelId, RC_REEL);
      assert.equal(staffRead.data().commentId, RC_COMMENT);
      await assertSucceeds(getDoc(doc(adminStaff.firestore(), filed)));

      // invitee-uid FILED this report; attacker-uid is the person reported;
      // host-uid owns the Reel it sits under. None of them may read it.
      for (const context of [
        invitee.firestore(),
        attacker.firestore(),
        host.firestore(),
        unverified.firestore(),
        testEnv.unauthenticatedContext().firestore(),
        revokedMod.firestore(),
        bannedMod.firestore(),
      ]) {
        await assertFails(getDoc(doc(context, filed)));
      }
      // Nor list their way to it.
      await assertFails(
        getDocs(
          query(
            collection(attacker.firestore(), "reports"),
            where("targetType", "==", "reelComment"),
          ),
        ),
      );
    },
  );

  await check(
    "SECURITY REEL COMMENT REPORTS: not even staff may edit or delete one " +
      "— triage is moderateReport's alone",
    async () => {
      const filed = `reports/${RC_REPORT}`;
      for (const context of [moderator.firestore(), adminStaff.firestore()]) {
        await assertFails(updateDoc(doc(context, filed), { status: "resolved" }));
        await assertFails(
          updateDoc(doc(context, filed), { targetTextSnapshot: "rewritten" }),
        );
        await assertFails(deleteDoc(doc(context, filed)));
      }
    },
  );

  await check(
    "SECURITY REEL COMMENT REMOVAL: the Reel's author holds real authority " +
      "over the thread and STILL cannot reach it through Firestore",
    async () => {
      // host-uid owns this Reel. removeReelComment will let them clear this
      // exact comment — through the Admin SDK, with a rate budget, an
      // idempotency ledger and a durable record of whose words were
      // removed. None of that exists on a direct client write, so the rule
      // must deny it even for the one person who is allowed to do it.
      const db = host.firestore();
      const commentRef = doc(db, `reels/${RC_REEL}/comments/${RC_COMMENT}`);
      await assertFails(getDoc(commentRef));
      await assertFails(deleteDoc(commentRef));
      await assertFails(updateDoc(commentRef, { text: "" }));
      // Nor by pairing the delete with an honest counter correction.
      const batch = writeBatch(db);
      batch.delete(commentRef);
      batch.update(doc(db, `reels/${RC_REEL}`), { commentCount: 0 });
      await assertFails(batch.commit());
      // And the comment's own author cannot either — deleteReelComment is
      // the only path there too.
      await assertFails(
        deleteDoc(doc(attacker.firestore(), `reels/${RC_REEL}/comments/${RC_COMMENT}`)),
      );
      // A moderator has no client path to the content either; theirs is
      // moderateReport.
      await assertFails(
        deleteDoc(doc(moderator.firestore(), `reels/${RC_REEL}/comments/${RC_COMMENT}`)),
      );
    },
  );

  console.log(`\n${passed} passed, ${failed} failed`);
  await testEnv.cleanup();
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
