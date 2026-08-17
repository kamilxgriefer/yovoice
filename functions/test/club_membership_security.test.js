// Security regressions for Club member removal and ownership transfer.

const assert = require("node:assert/strict");
const { test, beforeEach, afterEach, describe } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  removeClubMemberSelf,
  setMemberLiveKitControlForTests,
} = require("../clubs/members");
const {
  setOwnershipLiveKitControlForTests,
  transferClubOwnershipSelf,
} = require("../clubs/ownership");
const {
  adminDeleteClub,
  removeClubMember: removeClubMemberAdmin,
  setClubLiveKitControlForTests,
  setClubStorageBucketForTests,
  transferClubOwnership: transferClubOwnershipAdmin,
} = require("../admin/clubs");
const { setProtectedOwnerUidForTests } = require("../utils/roles");

const db = getFirestore();
const runRemove = removeClubMemberSelf.run ?? removeClubMemberSelf;
const runTransfer =
  transferClubOwnershipSelf.run ?? transferClubOwnershipSelf;
const runAdminRemove = removeClubMemberAdmin.run ?? removeClubMemberAdmin;
const runAdminTransfer =
  transferClubOwnershipAdmin.run ?? transferClubOwnershipAdmin;
const runAdminDelete = adminDeleteClub.run ?? adminDeleteClub;

const P = "cms-";
const IDS = {
  owner: `${P}owner`,
  next: `${P}next`,
  target: `${P}target`,
  equal: `${P}equal`,
  staleAdmin: `${P}stale-admin`,
  bannedAdmin: `${P}banned-admin`,
  activeAdmin: `${P}active-admin`,
  staleMod: `${P}stale-mod`,
  bannedMod: `${P}banned-mod`,
};

function callableRequest(uid, role, data) {
  return { auth: { uid, token: { role } }, data };
}

function activeEntitlement() {
  return {
    status: "active",
    currentPeriodEnd: Timestamp.fromMillis(Date.now() + 86_400_000),
    premiumIdentityEnabled: true,
    canCreateClubs: true,
    maxOwnedClubs: 3,
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
  const [clubs, rooms] = await Promise.all([
    db.collection("clubs").get(),
    db.collection("rooms").get(),
  ]);
  await Promise.all(
    [
      ...clubs.docs.filter((doc) => doc.id.startsWith(P)),
      ...rooms.docs.filter((doc) =>
        doc.id.includes(P) || String(doc.data().clubId ?? "").startsWith(P),
      ),
    ].map((doc) => recursiveDelete(doc.ref)),
  );
  for (const uid of Object.values(IDS)) {
    await Promise.all([
      recursiveDelete(db.collection("users").doc(uid)),
      recursiveDelete(db.collection("activeVoiceSessions").doc(uid)),
      db.collection("entitlements").doc(uid).delete(),
      db.collection("clubOwnershipGuards").doc(uid).delete(),
    ]);
  }
  const logs = await db
    .collection("adminAuditLogs")
    .where("targetType", "==", "club")
    .get();
  await Promise.all(
    logs.docs
      .filter((doc) => String(doc.data().targetId ?? "").startsWith(P))
      .map((doc) => doc.ref.delete()),
  );
}

async function seedMember(clubId, uid, role, { online = true } = {}) {
  const joinedAt = Timestamp.now();
  await Promise.all([
    db.collection("users").doc(uid).set({
      displayName: uid,
      banned: false,
      disabled: false,
    }, { merge: true }),
    db.collection("clubs").doc(clubId).collection("members").doc(uid).set({
      userId: uid,
      displayName: uid,
      photoUrl: null,
      role,
      isOnline: online,
      joinedAt,
      invitedBy: role === "owner" ? null : IDS.owner,
    }),
    db.collection("users").doc(uid).collection("clubs").doc(clubId).set({
      clubId,
      name: "Membership Club",
      avatarUrl: null,
      role,
      joinedAt,
    }),
  ]);
}

let ownershipControlCalls = [];
let memberControlCalls = [];
let clubControlCalls = [];
let clubStorageCalls = [];

beforeEach(async () => {
  await wipeOwn();
  ownershipControlCalls = [];
  memberControlCalls = [];
  clubControlCalls = [];
  clubStorageCalls = [];
  setOwnershipLiveKitControlForTests({
    async endRoom(roomId) {
      ownershipControlCalls.push(roomId);
    },
  });
  setMemberLiveKitControlForTests({
    async revokeParticipant(roomId, userId) {
      memberControlCalls.push([roomId, userId]);
    },
  });
  setClubLiveKitControlForTests({
    async endRoom(roomId) {
      clubControlCalls.push(["endRoom", roomId]);
    },
    async revokeParticipant(roomId, userId) {
      clubControlCalls.push(["revokeParticipant", roomId, userId]);
    },
  });
  setClubStorageBucketForTests({
    name: "yovoice-test.firebasestorage.app",
    async deleteFiles(options) {
      clubStorageCalls.push(["deleteFiles", options]);
    },
    file(objectPath) {
      return {
        async delete(options) {
          clubStorageCalls.push(["delete", objectPath, options]);
        },
      };
    },
  });
});

afterEach(() => {
  setClubLiveKitControlForTests(null);
  setClubStorageBucketForTests(null);
  setMemberLiveKitControlForTests(null);
  setOwnershipLiveKitControlForTests(null);
  setProtectedOwnerUidForTests(null);
});

describe("removeClubMemberSelf", () => {
  test("removes the canonical member and mirror and adjusts exact counters", async () => {
    const clubId = `${P}remove`;
    await db.collection("clubs").doc(clubId).set({
      ownerId: IDS.owner,
      type: "community",
      status: "active",
      memberCount: 2,
      onlineCount: 2,
    });
    await seedMember(clubId, IDS.owner, "owner");
    await seedMember(clubId, IDS.target, "member");
    const roomId = `${P}remove-room`;
    await Promise.all([
      db.collection("rooms").doc(roomId).set({
        clubId,
        participantCount: 1,
      }),
      db.collection("rooms").doc(roomId).collection("participants")
        .doc(IDS.target).set({ userId: IDS.target }),
      db.collection("activeVoiceSessions").doc(IDS.target)
        .collection("rooms").doc(roomId).set({
          userId: IDS.target,
          roomId,
          participantIdentity: IDS.target,
          expiresAt: Timestamp.fromMillis(Date.now() + 300_000),
        }),
    ]);

    await runRemove(
      callableRequest(IDS.owner, "user", { clubId, memberId: IDS.target }),
    );

    const [club, member, projection] = await Promise.all([
      db.collection("clubs").doc(clubId).get(),
      db.collection("clubs").doc(clubId).collection("members").doc(IDS.target).get(),
      db.collection("users").doc(IDS.target).collection("clubs").doc(clubId).get(),
    ]);
    assert.equal(member.exists, false);
    assert.equal(projection.exists, false);
    assert.equal(club.data().memberCount, 1);
    assert.equal(club.data().onlineCount, 1);
    assert.deepEqual(memberControlCalls, [[roomId, IDS.target]]);
    assert.equal(
      (await db.collection("activeVoiceSessions").doc(IDS.target)
        .collection("rooms").doc(roomId).get()).exists,
      false,
    );
  });

  test("cannot remove self, owner, or an equal/higher role", async () => {
    const clubId = `${P}hierarchy`;
    await db.collection("clubs").doc(clubId).set({
      ownerId: IDS.owner,
      type: "community",
      status: "active",
      memberCount: 3,
      onlineCount: 3,
    });
    await seedMember(clubId, IDS.owner, "owner");
    await seedMember(clubId, IDS.target, "moderator");
    await seedMember(clubId, IDS.equal, "moderator");

    await assert.rejects(
      () => runRemove(callableRequest(IDS.target, "user", {
        clubId,
        memberId: IDS.target,
      })),
      (error) => error?.code === "failed-precondition",
    );
    await assert.rejects(
      () => runRemove(callableRequest(IDS.target, "user", {
        clubId,
        memberId: IDS.owner,
      })),
      (error) => error?.code === "permission-denied",
    );
    await assert.rejects(
      () => runRemove(callableRequest(IDS.target, "user", {
        clubId,
        memberId: IDS.equal,
      })),
      (error) => error?.code === "permission-denied",
    );
  });

  test("fails closed on a non-canonical actor role or target identity", async () => {
    const clubId = `${P}canonical-removal`;
    await db.collection("clubs").doc(clubId).set({
      ownerId: IDS.owner,
      type: "community",
      status: "active",
      memberCount: 2,
      onlineCount: 2,
    });
    await seedMember(clubId, IDS.owner, "owner");
    await seedMember(clubId, IDS.target, "member");
    await db.collection("clubs").doc(clubId).collection("members")
      .doc(IDS.target).update({ userId: IDS.equal });
    await assert.rejects(
      () => runRemove(callableRequest(IDS.owner, "user", {
        clubId,
        memberId: IDS.target,
      })),
      (error) => error?.code === "failed-precondition",
    );

    await db.collection("clubs").doc(clubId).collection("members")
      .doc(IDS.target).update({ userId: IDS.target });
    await db.collection("clubs").doc(clubId).collection("members")
      .doc(IDS.owner).update({ role: "coOwner" });
    await assert.rejects(
      () => runRemove(callableRequest(IDS.owner, "user", {
        clubId,
        memberId: IDS.target,
      })),
      (error) => error?.code === "failed-precondition",
    );
  });
});

describe("transferClubOwnershipSelf", () => {
  async function seedTransfer(clubId, type = "community") {
    await Promise.all([
      db.collection("clubs").doc(clubId).set({
        ownerId: IDS.owner,
        ownerName: "Old owner",
        name: "Transfer Club",
        avatarUrl: null,
        type,
        status: "active",
        memberCount: 2,
        loungeRoomId: `club_lounge_${clubId}`,
      }),
      db.collection("entitlements").doc(IDS.next).set(activeEntitlement()),
      db.collection("users").doc(IDS.owner).set({
        displayName: "Old owner",
        banned: false,
      }),
      db.collection("users").doc(IDS.next).set({
        displayName: "New owner",
        banned: false,
      }),
      db.collection("rooms").doc(`club_lounge_${clubId}`).set({
        hostId: IDS.owner,
        hostName: "Old owner",
        clubId,
        roomKind: "clubLounge",
      }),
    ]);
    await seedMember(clubId, IDS.owner, "owner");
    await seedMember(clubId, IDS.next, "member");
  }

  test("updates root, canonical roles, both mirrors and both guards", async () => {
    const clubId = `${P}transfer`;
    await seedTransfer(clubId);
    await db.collection("clubMarketingConsents").doc(clubId).set({
      schemaVersion: 1,
      clubId,
      ownerId: IDS.owner,
      showOnWebsite: true,
    });
    await runTransfer(
      callableRequest(IDS.owner, "user", { clubId, newOwnerId: IDS.next }),
    );

    const [
      club,
      oldMember,
      newMember,
      oldMirror,
      newMirror,
      oldGuard,
      newGuard,
      lounge,
    ] =
      await Promise.all([
        db.collection("clubs").doc(clubId).get(),
        db.collection("clubs").doc(clubId).collection("members").doc(IDS.owner).get(),
        db.collection("clubs").doc(clubId).collection("members").doc(IDS.next).get(),
        db.collection("users").doc(IDS.owner).collection("clubs").doc(clubId).get(),
        db.collection("users").doc(IDS.next).collection("clubs").doc(clubId).get(),
        db.collection("clubOwnershipGuards").doc(IDS.owner).get(),
        db.collection("clubOwnershipGuards").doc(IDS.next).get(),
        db.collection("rooms").doc(`club_lounge_${clubId}`).get(),
      ]);
    assert.equal(club.data().ownerId, IDS.next);
    assert.equal(oldMember.data().role, "coOwner");
    assert.equal(newMember.data().role, "owner");
    assert.equal(oldMirror.data().role, "coOwner");
    assert.equal(newMirror.data().role, "owner");
    assert.equal(oldGuard.data().revision, 1);
    assert.equal(newGuard.data().revision, 1);
    assert.equal(lounge.data().hostId, IDS.next);
    assert.equal(lounge.data().isLive, false);
    assert.deepEqual(ownershipControlCalls, [`club_lounge_${clubId}`]);
    assert.equal(club.data().ownershipVoiceResetPending, false);
    assert.equal(
      (await db.collection("clubMarketingConsents").doc(clubId).get()).exists,
      false,
    );

    const retry = await runTransfer(
      callableRequest(IDS.owner, "user", { clubId, newOwnerId: IDS.next }),
    );
    assert.equal(retry.alreadyExisted, true);
    assert.deepEqual(ownershipControlCalls, [`club_lounge_${clubId}`]);
    assert.equal(
      (await db.collection("clubs").doc(clubId).get()).data().ownerId,
      IDS.next,
    );
  });

  test("recipient Premium capacity is enforced without partial transfer", async () => {
    const clubId = `${P}transfer-cap`;
    await seedTransfer(clubId);
    for (let index = 0; index < 3; index += 1) {
      await db.collection("clubs").doc(`${P}owned-${index}`).set({
        ownerId: IDS.next,
        type: "community",
      });
    }

    await assert.rejects(
      () => runTransfer(callableRequest(IDS.owner, "user", {
        clubId,
        newOwnerId: IDS.next,
      })),
      (error) => error?.code === "resource-exhausted",
    );
    const [club, oldMember, newMember] = await Promise.all([
      db.collection("clubs").doc(clubId).get(),
      db.collection("clubs").doc(clubId).collection("members").doc(IDS.owner).get(),
      db.collection("clubs").doc(clubId).collection("members").doc(IDS.next).get(),
    ]);
    assert.equal(club.data().ownerId, IDS.owner);
    assert.equal(oldMember.data().role, "owner");
    assert.equal(newMember.data().role, "member");
  });

  test("Family ownership transfer is always refused", async () => {
    const clubId = `${P}family-transfer`;
    await seedTransfer(clubId, "family");
    await assert.rejects(
      () => runTransfer(callableRequest(IDS.owner, "user", {
        clubId,
        newOwnerId: IDS.next,
      })),
      (error) => error?.code === "failed-precondition",
    );
  });

  test("banned current or recipient accounts cannot transfer ownership", async () => {
    const recipientClub = `${P}banned-recipient`;
    await seedTransfer(recipientClub);
    await db.collection("users").doc(IDS.next).update({ banned: true });
    await assert.rejects(
      () => runTransfer(callableRequest(IDS.owner, "user", {
        clubId: recipientClub,
        newOwnerId: IDS.next,
      })),
      (error) => error?.code === "permission-denied",
    );

    const ownerClub = `${P}banned-owner`;
    await seedTransfer(ownerClub);
    await db.collection("users").doc(IDS.owner).update({ banned: true });
    await assert.rejects(
      () => runTransfer(callableRequest(IDS.owner, "user", {
        clubId: ownerClub,
        newOwnerId: IDS.next,
      })),
      (error) => error?.code === "permission-denied",
    );
  });
});

describe("admin Club mutation authorization", () => {
  beforeEach(async () => {
    await Promise.all([
      db.collection("users").doc(IDS.staleAdmin).set({ role: "moderator" }),
      db.collection("users").doc(IDS.bannedAdmin).set({
        role: "superAdmin",
        banned: true,
      }),
      db.collection("users").doc(IDS.activeAdmin).set({ role: "superAdmin" }),
      db.collection("users").doc(IDS.staleMod).set({ role: "user" }),
      db.collection("users").doc(IDS.bannedMod).set({
        role: "moderator",
        banned: true,
      }),
    ]);
  });

  test("revoked or banned superAdmin claims cannot transfer ownership", async () => {
    const data = {
      clubId: `${P}does-not-matter`,
      newOwnerId: IDS.next,
      reason: "security regression",
    };
    for (const uid of [IDS.staleAdmin, IDS.bannedAdmin]) {
      await assert.rejects(
        () => runAdminTransfer(callableRequest(uid, "superAdmin", data)),
        (error) => error?.code === "permission-denied",
      );
    }
  });

  test("revoked or banned moderator claims cannot remove members", async () => {
    const data = {
      clubId: `${P}does-not-matter`,
      userId: IDS.target,
      reason: "security regression",
    };
    for (const uid of [IDS.staleMod, IDS.bannedMod]) {
      await assert.rejects(
        () => runAdminRemove(callableRequest(uid, "moderator", data)),
        (error) => error?.code === "permission-denied",
      );
    }
  });

  test("active superAdmin transfer preserves exact ownership graph", async () => {
    const clubId = `${P}admin-transfer`;
    const roomId = `club_lounge_${clubId}`;
    await Promise.all([
      db.collection("clubs").doc(clubId).set({
        ownerId: IDS.owner,
        ownerName: "Old owner",
        name: "Admin Transfer Club",
        avatarUrl: null,
        type: "community",
        status: "active",
        memberCount: 2,
        loungeRoomId: roomId,
      }),
      db.collection("entitlements").doc(IDS.next).set(activeEntitlement()),
      db.collection("rooms").doc(roomId).set({
        hostId: IDS.owner,
        clubId,
        roomKind: "clubLounge",
        isLive: true,
        participantCount: 2,
      }),
    ]);
    await seedMember(clubId, IDS.owner, "owner");
    await seedMember(clubId, IDS.next, "member");
    await db.collection("clubMarketingConsents").doc(clubId).set({
      schemaVersion: 1,
      clubId,
      ownerId: IDS.owner,
      showOnWebsite: true,
    });

    const result = await runAdminTransfer(
      callableRequest(IDS.activeAdmin, "superAdmin", {
        clubId,
        newOwnerId: IDS.next,
        reason: "security regression",
      }),
    );
    assert.equal(result.alreadyExisted, false);
    const [club, oldMember, newMember, oldProjection, newProjection] =
      await Promise.all([
        db.collection("clubs").doc(clubId).get(),
        db.collection("clubs").doc(clubId).collection("members")
          .doc(IDS.owner).get(),
        db.collection("clubs").doc(clubId).collection("members")
          .doc(IDS.next).get(),
        db.collection("users").doc(IDS.owner).collection("clubs")
          .doc(clubId).get(),
        db.collection("users").doc(IDS.next).collection("clubs")
          .doc(clubId).get(),
      ]);
    assert.equal(club.data().ownerId, IDS.next);
    assert.equal(club.data().ownershipVoiceResetPending, false);
    assert.equal(oldMember.data().role, "member");
    assert.equal(newMember.data().role, "owner");
    assert.equal(oldProjection.data().role, "member");
    assert.equal(newProjection.data().role, "owner");
    assert.deepEqual(clubControlCalls, [["endRoom", roomId]]);
    assert.equal(
      (await db.collection("clubMarketingConsents").doc(clubId).get()).exists,
      false,
    );
  });

  test("active staff removal cleans membership, projection and voice", async () => {
    const clubId = `${P}admin-remove`;
    const roomId = `${P}admin-remove-room`;
    await Promise.all([
      db.collection("clubs").doc(clubId).set({
        ownerId: IDS.owner,
        type: "community",
        status: "active",
        memberCount: 2,
        onlineCount: 2,
      }),
      db.collection("rooms").doc(roomId).set({
        clubId,
        participantCount: 1,
      }),
    ]);
    await seedMember(clubId, IDS.owner, "owner");
    await seedMember(clubId, IDS.target, "member");
    await db.collection("rooms").doc(roomId).collection("participants")
      .doc(IDS.target).set({ userId: IDS.target });

    const result = await runAdminRemove(
      callableRequest(IDS.activeAdmin, "superAdmin", {
        clubId,
        userId: IDS.target,
        reason: "security regression",
      }),
    );
    assert.equal(result.alreadyExisted, false);
    assert.equal(
      (await db.collection("clubs").doc(clubId).collection("members")
        .doc(IDS.target).get()).exists,
      false,
    );
    assert.equal(
      (await db.collection("users").doc(IDS.target).collection("clubs")
        .doc(clubId).get()).exists,
      false,
    );
    assert.deepEqual(
      clubControlCalls,
      [["revokeParticipant", roomId, IDS.target]],
    );
  });
});

describe("admin Club deletion lifecycle", () => {
  test("disconnects rooms and removes canonical, nested, and legacy projections", async () => {
    const clubId = `${P}delete`;
    const roomId = `club_lounge_${clubId}`;
    const calls = [];
    setProtectedOwnerUidForTests(IDS.activeAdmin);
    setClubLiveKitControlForTests({
      async endRoom(id) {
        calls.push(id);
      },
    });
    await Promise.all([
      db.collection("users").doc(IDS.activeAdmin).set({
        role: "superAdmin",
        banned: false,
      }),
      db.collection("clubs").doc(clubId).set({
        ownerId: IDS.owner,
        ownerName: "Owner",
        name: "Delete Club",
        type: "community",
        memberCount: 2,
        avatarUrl:
          `gs://yovoice-test.firebasestorage.app/clubs/${IDS.owner}/${clubId}/avatar`,
      }),
      db.collection("rooms").doc(roomId).set({
        hostId: IDS.owner,
        clubId,
        roomKind: "clubLounge",
        status: "active",
        isLive: true,
      }),
      db.collection("clubMarketingConsents").doc(clubId).set({
        schemaVersion: 1,
        clubId,
        ownerId: IDS.owner,
        showOnWebsite: true,
      }),
    ]);
    await Promise.all([
      seedMember(clubId, IDS.owner, "owner"),
      seedMember(clubId, IDS.target, "member"),
      db.collection("users").doc(IDS.equal)
        .collection("clubs").doc(clubId).set({
          clubId,
          role: "member",
        }),
      db.collection("rooms").doc(roomId)
        .collection("participants").doc(IDS.target).set({
          userId: IDS.target,
        }),
    ]);

    const result = await runAdminDelete(
      callableRequest(IDS.activeAdmin, "superAdmin", {
        clubId,
        confirmation: clubId,
        reason: "security lifecycle regression",
      }),
    );
    assert.equal(result.success, true);
    assert.deepEqual(calls, [roomId]);
    assert.deepEqual(clubStorageCalls, [
      [
        "deleteFiles",
        { prefix: `room_images/${roomId}/`, force: true },
      ],
      [
        "delete",
        `clubs/${IDS.owner}/${clubId}/avatar`,
        { ignoreNotFound: true },
      ],
    ]);
    const [club, room, ownerProjection, memberProjection, ghostProjection] =
      await Promise.all([
        db.collection("clubs").doc(clubId).get(),
        db.collection("rooms").doc(roomId).get(),
        db.collection("users").doc(IDS.owner)
          .collection("clubs").doc(clubId).get(),
        db.collection("users").doc(IDS.target)
          .collection("clubs").doc(clubId).get(),
        db.collection("users").doc(IDS.equal)
          .collection("clubs").doc(clubId).get(),
      ]);
    assert.equal(club.exists, false);
    assert.equal(room.exists, false);
    assert.equal(ownerProjection.exists, false);
    assert.equal(memberProjection.exists, false);
    assert.equal(ghostProjection.exists, false);
    assert.equal(
      (await db.collection("clubMarketingConsents").doc(clubId).get()).exists,
      false,
    );
    assert.equal(
      (await db.collection("adminAuditLogs")
        .doc(`delete_club_${clubId}`).get()).exists,
      true,
    );
  });
});
