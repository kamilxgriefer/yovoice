const fs = require("fs");
const path = require("path");
const assert = require("node:assert/strict");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
const {
  doc,
  getDoc,
  getDocs,
  deleteDoc,
  deleteField,
  collection,
  collectionGroup,
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
      host: "127.0.0.1",
      port: 8080,
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
  await check(
    "host can create a room + their own host participant doc in one batch",
    async () => {
      const db = host.firestore();
      const roomRef = doc(db, "rooms/room1");
      const participantRef = doc(db, "rooms/room1/participants/host-uid");
      const batch = writeBatch(db);
      batch.set(roomRef, {
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
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
      batch.set(participantRef, {
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
      await assertSucceeds(batch.commit());
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
    "non-host can join as a plain listener (self-service create)",
    async () => {
      const db = attacker.firestore();
      const ref = doc(db, "rooms/room1/participants/attacker-uid");
      const batch = writeBatch(db);
      batch.set(ref, {
        userId: "attacker-uid",
        displayName: "Attacker",
        photoUrl: null,
        role: "listener",
        isMuted: true,
        isSpeaker: false,
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

  await check("regression: participant can raise their own hand", async () => {
    const db = attacker.firestore();
    const ref = doc(db, "rooms/room1/participants/attacker-uid");
    await assertSucceeds(
      updateDoc(ref, { isHandRaised: true, updatedAt: serverTimestamp() }),
    );
  });

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

      function loungeJoinBatch(db, uid) {
        const batch = writeBatch(db);
        batch.set(
          doc(db, `rooms/club-lounge-security/participants/${uid}`),
          {
            userId: uid,
            displayName: uid,
            photoUrl: null,
            role: "listener",
            isMuted: false,
            isSpeaker: false,
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
        loungeJoinBatch(attacker.firestore(), "attacker-uid").commit(),
      );
      await assertSucceeds(
        loungeJoinBatch(invitee.firestore(), "invitee-uid").commit(),
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

  await check("regression: user can update their own profile fields", async () => {
    const db = host.firestore();
    const ref = doc(db, "users/host-uid");
    await assertSucceeds(updateDoc(ref, { displayName: "Host renamed" }));
  });

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

  // --- handRequests (#10) ---
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

  await check("regression: raising a hand in a broadcast room works", async () => {
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

  await check("regression: raising a hand in a non-broadcast room is rejected", async () => {
    const db = attacker.firestore();
    const ref = doc(db, "rooms/communityRoom/handRequests/attacker-uid");
    await assertFails(setDoc(ref, { displayName: "Attacker", createdAt: null }));
  });

  await check(
    "SECURITY: outsider cannot read or write a private room hand queue",
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
        getDocs(
          collection(db, "rooms/privateBroadcastRoom/handRequests"),
        ),
      );
    },
  );

  // --- voiceMoments likes/comments (#7) ---
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "voiceMoments/moment1"), {
      authorId: "host-uid",
      likeCount: 0,
      commentCount: 0,
    });
  });

  await check("regression: liking a moment increments likeCount by exactly 1", async () => {
    const db = attacker.firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, "voiceMoments/moment1/likes/attacker-uid"), {
      userId: "attacker-uid",
      createdAt: null,
    });
    batch.update(doc(db, "voiceMoments/moment1"), { likeCount: 1 });
    await assertSucceeds(batch.commit());
  });

  await check("SECURITY: cannot set likeCount to an arbitrary value", async () => {
    const db = attacker.firestore();
    const ref = doc(db, "voiceMoments/moment1");
    await assertFails(updateDoc(ref, { likeCount: 9999 }));
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
  //
  // conversations/{id}/messages/{id} update was `if false` before this
  // session — editMessage/deleteMessage/toggleReaction/markConversationRead
  // in message_service.dart all call update() on this exact path, so all
  // four were silently broken in production despite correct Dart logic.
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

  await check("regression: sender can edit their own message", async () => {
    const db = host.firestore();
    const ref = doc(db, "conversations/convo-1/messages/msg-1");
    await assertSucceeds(
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
    "regression: sender can soft-delete their own message (deleteMessage's update shape)",
    async () => {
      const db = host.firestore();
      const ref = doc(db, "conversations/convo-1/messages/msg-1");
      await assertSucceeds(
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
    "regression: any participant can toggle their OWN reaction",
    async () => {
      const db = invitee.firestore();
      const ref = doc(db, "conversations/convo-1/messages/msg-1");
      await assertSucceeds(
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
    "regression: a participant can mark a message read by adding themselves to readBy",
    async () => {
      const db = invitee.firestore();
      const ref = doc(db, "conversations/convo-1/messages/msg-1");
      await assertSucceeds(
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
    "SECURITY: the recipient cannot rewrite who a notification claims is from",
    async () => {
      const db = invitee.firestore();
      const ref = doc(db, "users/invitee-uid/notifications/notif-1");
      await assertFails(updateDoc(ref, { actorId: "invitee-uid" }));
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
    "regression: a verified user can still send a message",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "conversations/convo-verified"), {
          participantIds: ["host-uid", "invitee-uid"],
        });
      });
      const db = host.firestore();
      const ref = doc(db, "conversations/convo-verified/messages/msg-1");
      await assertSucceeds(
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
  ) {
    const batch = writeBatch(db);
    batch.set(
      doc(db, `clubs/${clubId}/members/invitee-uid`),
      invitedMemberDocument(),
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
        await setDoc(
          doc(ctx.firestore(), "users/host-uid"),
          { accountType: "personal" },
          { merge: true },
        );
        await setDoc(
          doc(ctx.firestore(), "users/attacker-uid"),
          { accountType: "personal" },
          { merge: true },
        );
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

  await check(
    "FAMILY: a verified user with NO premium can create their own family room",
    async () => {
      // Ordinary clubs need premium (ADR-024); a family space does not.
      await assertSucceeds(
        setDoc(doc(parent.firestore(), FAMILY), familyDoc()),
      );
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
        status: "onMyWay",
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

  await check("ROOM META: a community room persists its own metadata", () =>
    assertSucceeds(
      createMetadataRoom(
        "meta-community",
        {
          targetAudience: "newcomers",
          topicTags: ["flutter", "dart"],
          roomGuidelines: "Be kind.",
          conversationStyle: "supportive",
          newcomerFriendly: true,
        },
      ),
    ),
  );

  await check("ROOM META: a podcast room persists its own metadata", () =>
    assertSucceeds(
      createMetadataRoom(
        "meta-podcast",
        {
          experience: "broadcast",
          targetAudience: "professionals",
          topicTags: ["interview"],
          showFormat: "panel",
        },
      ),
    ),
  );

  await check(
    "ROOM META regression: a legacy room with NO metadata still writes",
    () =>
      assertSucceeds(createMetadataRoom("meta-legacy")),
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
    "MUTE: an active mute closes every public communication path",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "users/muted-uid"), {
          uid: "muted-uid",
          displayName: "Muted",
          role: "user",
          accountType: "personal",
        });
      });
      // Baseline FIRST on a current publishing surface, so the later denial
      // is attributable to the restriction rather than retired Global Chat.
      await assertSucceeds(
        setDoc(doc(mutedUser.firestore(), "voiceMoments/mute-vm0"), {
          authorId: "muted-uid",
          caption: "baseline",
          isPublished: true,
        }),
      );

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
      // Public voice moment.
      await assertFails(
        setDoc(doc(mutedDb, "voiceMoments/mute-vm1"), {
          authorId: "muted-uid",
          caption: "x",
          isPublished: true,
        }),
      );
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
    "MUTE: an EXPIRED mute stops applying with no sweeper involved",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "restrictions/muted-uid"), {
          type: "communicationMute",
          expiresAt: Timestamp.fromMillis(Date.now() - 60_000),
        });
      });
      await assertSucceeds(
        setDoc(doc(mutedUser.firestore(), "voiceMoments/mute-vm2"), {
          authorId: "muted-uid",
          caption: "expired restriction",
          isPublished: true,
        }),
      );
    },
  );

  await check(
    "MUTE ISOLATION: a personal block is not a staff mute — a blocked "
      + "user still writes to public paths",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await deleteDoc(doc(ctx.firestore(), "restrictions/muted-uid"));
        // host blocks muted-uid: a PERSONAL act.
        await setDoc(
          doc(ctx.firestore(), "users/host-uid/blocked/muted-uid"),
          { blockedAt: serverTimestamp() },
        );
      });
      await assertSucceeds(
        setDoc(doc(mutedUser.firestore(), "voiceMoments/mute-vm3"), {
          authorId: "muted-uid",
          caption: "personal block is not a sanction",
          isPublished: true,
        }),
      );
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
    "regression: a member can read the roster and start voice in their own " +
      "private Community room",
    async () => {
      const db = communityMember.firestore();
      await assertSucceeds(
        getDocs(collection(db, "rooms/cr-private/roomMembers")),
      );
      await assertSucceeds(
        updateDoc(doc(db, "rooms/cr-private"), {
          isLive: true,
          updatedAt: serverTimestamp(),
        }),
      );
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await updateDoc(doc(ctx.firestore(), "rooms/cr-private"), {
          isLive: false,
        });
      });
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
    "regression: a host may still refresh the display identity on a " +
      "membership row, and a member their own",
    async () => {
      const host = roomAttacker.firestore();
      await assertSucceeds(
        updateDoc(doc(host, "rooms/rm-attack-room/roomMembers/rm-attacker-uid"), {
          displayName: "Renamed host",
          photoUrl: "https://example.invalid/a.jpg",
          updatedAt: serverTimestamp(),
        }),
      );
      const member = communityMember.firestore();
      await assertSucceeds(
        updateDoc(doc(member, "rooms/cr-private/roomMembers/cr-member-uid"), {
          displayName: "Renamed member",
          updatedAt: serverTimestamp(),
        }),
      );
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
      firestore: { rules: variant, host: "127.0.0.1", port: 8080 },
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

  console.log(`\n${passed} passed, ${failed} failed`);
  await testEnv.cleanup();
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
