const fs = require("fs");
const path = require("path");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
const {
  doc,
  getDoc,
  getDocs,
  collection,
  setDoc,
  updateDoc,
  writeBatch,
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
    projectId: "rules-test-yovoice",
    firestore: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });

  const host = testEnv.authenticatedContext("host-uid");
  const attacker = testEnv.authenticatedContext("attacker-uid");
  const invitee = testEnv.authenticatedContext("invitee-uid");

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
      });
      batch.set(participantRef, {
        userId: "host-uid",
        displayName: "Host",
        role: "host",
        isMuted: false,
        isSpeaker: true,
        isHandRaised: false,
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
      await assertSucceeds(
        setDoc(ref, {
          userId: "attacker-uid",
          displayName: "Attacker",
          role: "listener",
          isMuted: true,
          isSpeaker: false,
          isHandRaised: false,
        }),
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
    await assertSucceeds(updateDoc(ref, { isMuted: false }));
  });

  await check("regression: participant can raise their own hand", async () => {
    const db = attacker.firestore();
    const ref = doc(db, "rooms/room1/participants/attacker-uid");
    await assertSucceeds(updateDoc(ref, { isHandRaised: true }));
  });

  await check("regression: host can moderate (mute) another participant", async () => {
    const db = host.firestore();
    const ref = doc(db, "rooms/room1/participants/attacker-uid");
    await assertSucceeds(updateDoc(ref, { isMuted: true }));
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

  await check("regression: any joined participant can bump participantCount", async () => {
    const db = attacker.firestore();
    const ref = doc(db, "rooms/room1");
    await assertSucceeds(updateDoc(ref, { participantCount: 2 }));
  });

  await check("regression: host can update room name/description/etc", async () => {
    const db = host.firestore();
    const ref = doc(db, "rooms/room1");
    await assertSucceeds(updateDoc(ref, { name: "Renamed by host" }));
  });

  // --- Club ownership hijack (#2) ---
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "clubs/club1"), {
      ownerId: "host-uid",
      name: "Test club",
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
      setDoc(ref, { userId: "attacker-uid", role: "owner", joinedAt: null }),
    );
  });

  await check(
    "regression: real club owner can still self-appoint as owner (createClub path)",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "clubs/club2"), {
          ownerId: "host-uid",
          name: "Second club",
          memberCount: 0,
        });
      });
      const db = host.firestore();
      const ref = doc(db, "clubs/club2/members/host-uid");
      await assertSucceeds(
        setDoc(ref, { userId: "host-uid", role: "owner", joinedAt: null }),
      );
    },
  );

  await check("regression: invited user can still join as a plain member", async () => {
    const db = invitee.firestore();
    const ref = doc(db, "clubs/club1/members/invitee-uid");
    await assertSucceeds(
      setDoc(ref, { userId: "invitee-uid", role: "member", joinedAt: null }),
    );
  });

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
    "regression: follow_service can bump the OTHER user's followerCount",
    async () => {
      const db = attacker.firestore();
      const ref = doc(db, "users/host-uid");
      await assertSucceeds(updateDoc(ref, { followerCount: 1 }));
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
  await check("regression: user can create their own sentFriendRequests entry", async () => {
    const db = attacker.firestore();
    const ref = doc(db, "users/attacker-uid/sentFriendRequests/host-uid");
    await assertSucceeds(setDoc(ref, { receiverId: "host-uid", createdAt: null }));
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

  await check("regression: accepting a real friend request still works", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "users/host-uid/friendRequests/attacker-uid"), {
        senderId: "attacker-uid",
        createdAt: null,
      });
    });
    const db = host.firestore();
    const ref = doc(db, "users/host-uid/friends/attacker-uid");
    await assertSucceeds(setDoc(ref, { userId: "attacker-uid", createdAt: null }));
  });

  // --- following/followers (#10) ---
  await check("regression: user can follow someone (own following entry)", async () => {
    const db = attacker.firestore();
    const ref = doc(db, "users/attacker-uid/following/host-uid");
    await assertSucceeds(setDoc(ref, { uid: "host-uid", followedAt: null }));
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
    "regression: user can add themselves to the target's followers list",
    async () => {
      const db = attacker.firestore();
      const ref = doc(db, "users/host-uid/followers/attacker-uid");
      await assertSucceeds(setDoc(ref, { uid: "attacker-uid", followedAt: null }));
    },
  );

  // --- handRequests (#10) ---
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "rooms/broadcastRoom"), {
      hostId: "host-uid",
      experience: "broadcast",
    });
    await setDoc(doc(ctx.firestore(), "rooms/communityRoom"), {
      hostId: "host-uid",
      experience: "community",
    });
  });

  await check("regression: raising a hand in a broadcast room works", async () => {
    const db = attacker.firestore();
    const ref = doc(db, "rooms/broadcastRoom/handRequests/attacker-uid");
    await assertSucceeds(setDoc(ref, { displayName: "Attacker", createdAt: null }));
  });

  await check("regression: raising a hand in a non-broadcast room is rejected", async () => {
    const db = attacker.firestore();
    const ref = doc(db, "rooms/communityRoom/handRequests/attacker-uid");
    await assertFails(setDoc(ref, { displayName: "Attacker", createdAt: null }));
  });

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

  console.log(`\n${passed} passed, ${failed} failed`);
  await testEnv.cleanup();
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
