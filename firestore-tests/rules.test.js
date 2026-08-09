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
  deleteDoc,
  collection,
  collectionGroup,
  query,
  where,
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
    await setDoc(doc(ctx.firestore(), "clubs/cg-club1"), { ownerId: "host-uid" });
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
    "regression: an unrelated user can still send a friend request normally",
    async () => {
      const db = stranger.firestore();
      const ref = doc(db, "users/blocker-uid/friendRequests/stranger-uid");
      await assertSucceeds(
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
    "regression: an actor can write a notification into someone else's inbox",
    async () => {
      const db = host.firestore();
      const ref = doc(db, "users/invitee-uid/notifications/notif-1");
      await assertSucceeds(
        setDoc(ref, {
          type: "friendRequest",
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
    "notification routing: an ACTUAL FRIEND can write a bell-suppressed DM record",
    async () => {
      const db = host.firestore();
      const ref = doc(db, "users/invitee-uid/notifications/notif-dm-suppressed");
      await assertSucceeds(
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
    "notification routing: a non-friend's VISIBLE message request is allowed",
    async () => {
      const db = attacker.firestore();
      const ref = doc(db, "users/invitee-uid/notifications/notif-dm-request");
      await assertSucceeds(
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
        setDoc(ref, { platform: "ios", updatedAt: new Date() }),
      );
    },
  );

  await check(
    "SECURITY: a user cannot register an FCM token under someone else's account",
    async () => {
      const db = attacker.firestore();
      const ref = doc(db, "users/host-uid/fcmTokens/token-hijack");
      await assertFails(
        setDoc(ref, { platform: "ios", updatedAt: new Date() }),
      );
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
      });
    });
    await assertSucceeds(getDoc(doc(host.firestore(), "entitlements/host-uid")));
    await assertFails(
      getDoc(doc(attacker.firestore(), "entitlements/host-uid")),
    );
  });

  await check("club creation requires active premium", async () => {
    // host has active entitlements (seeded above); attacker has none.
    await assertSucceeds(
      setDoc(doc(host.firestore(), "clubs/premium-club"), {
        ownerId: "host-uid",
        name: "Premium Club",
        memberCount: 1,
      }),
    );
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

  await check(
    "friendAccepted notification: acceptor can write it into the " +
      "sender's feed with the exact payload notify() sends",
    async () => {
      await assertSucceeds(
        setDoc(
          doc(
            host.firestore(),
            "users/invitee-uid/notifications/friendAccepted_host-uid",
          ),
          {
            type: "friendAccepted",
            actorId: "host-uid",
            actorName: "Host",
            actorPhotoUrl: null,
            targetId: null,
            targetLabel: null,
            isRead: false,
            createdAt: new Date(),
            dedupeKey: null,
          },
        ),
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
