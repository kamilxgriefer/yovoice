// Authoritative Premium Club creation and quota regressions.

const assert = require("node:assert/strict");
const { test, beforeEach, describe } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  createCommunityClub,
  createFinalizeClubMediaHandler,
} = require("../clubs/creation");

const db = getFirestore();
const run = createCommunityClub.run ?? createCommunityClub;
const P = "ccs-";
const OWNERS = [
  `${P}owner`,
  `${P}concurrent`,
  `${P}legacy`,
  `${P}denied`,
  `${P}banned`,
  `${P}media-owner`,
  `${P}media-attacker`,
  `${P}moderator`,
  `${P}super-moderator`,
  `${P}role-mismatch`,
  `${P}excluded-role`,
];

function request(uid, clubId, overrides = {}, tokenOverrides = {}) {
  return {
    auth: {
      uid,
      token: {
        email_verified: true,
        email: `${uid}@example.invalid`,
        name: "Club Owner",
        ...tokenOverrides,
      },
    },
    data: {
      clubId,
      name: "Secure Club",
      description: "Created atomically",
      privacy: "public",
      defaultLanguage: "English",
      avatarUrl: null,
      bannerUrl: null,
      ...overrides,
    },
  };
}

function entitlement(overrides = {}) {
  return {
    status: "active",
    isPremium: true,
    currentPeriodEnd: Timestamp.fromMillis(Date.now() + 86_400_000),
    premiumIdentityEnabled: true,
    canCreateClubs: true,
    maxOwnedClubs: 3,
    ...overrides,
  };
}

function mediaRequest(uid, clubId, overrides = {}) {
  return {
    auth: {
      uid,
      token: {
        email_verified: true,
        email: `${uid}@example.invalid`,
      },
    },
    data: {
      clubId,
      avatar: {
        path: `clubs/${uid}/${clubId}/avatar`,
        generation: "1001",
      },
      banner: null,
      ...overrides,
    },
  };
}

function fakeMediaBucket(objects = {}) {
  return {
    name: "yovoice-test.firebasestorage.app",
    file(path) {
      return {
        async getMetadata() {
          const metadata = objects[path];
          if (!metadata) {
            const error = new Error("missing");
            error.code = 404;
            throw error;
          }
          return [metadata];
        },
      };
    },
  };
}

function validMedia(generation = "1001", overrides = {}) {
  return {
    size: "4096",
    contentType: "image/jpeg",
    generation,
    metadata: { firebaseStorageDownloadTokens: "server-token" },
    ...overrides,
  };
}

async function deleteClub(document) {
  if (typeof db.recursiveDelete === "function") {
    await db.recursiveDelete(document.ref ?? document);
  } else {
    await (document.ref ?? document).delete();
  }
}

async function wipeOwn() {
  for (const owner of OWNERS) {
    const clubs = await db.collection("clubs").where("ownerId", "==", owner).get();
    await Promise.all(clubs.docs.map(deleteClub));
    const rooms = await db.collection("rooms").where("hostId", "==", owner).get();
    await Promise.all(rooms.docs.map(deleteClub));
    await Promise.all([
      deleteClub(db.collection("users").doc(owner)),
      db.collection("entitlements").doc(owner).delete(),
      db.collection("clubOwnershipGuards").doc(owner).delete(),
    ]);
  }
}

async function seedOwner(uid, entitlementData = entitlement(), profile = {}) {
  await Promise.all([
    db.collection("users").doc(uid).set({
      displayName: "Club Owner",
      photoUrl: null,
      ...profile,
    }),
    entitlementData === null
      ? Promise.resolve()
      : db.collection("entitlements").doc(uid).set(entitlementData),
  ]);
}

beforeEach(wipeOwn);

describe("createCommunityClub", () => {
  test("creates the complete canonical Club graph atomically", async () => {
    const uid = `${P}owner`;
    const clubId = `${P}complete`;
    await seedOwner(uid);

    const result = await run(request(uid, clubId));
    assert.equal(result.clubId, clubId);
    assert.equal(result.alreadyExisted, false);
    assert.equal(result.ownedCommunityClubs, 1);

    const club = await db.collection("clubs").doc(clubId).get();
    assert.equal(club.data().ownerId, uid);
    assert.equal(club.data().type, "community");
    assert.equal(club.data().status, "active");
    assert.equal(club.data().memberCount, 1);

    const [member, projection, channels, room, guard] = await Promise.all([
      club.ref.collection("members").doc(uid).get(),
      db.collection("users").doc(uid).collection("clubs").doc(clubId).get(),
      club.ref.collection("channels").get(),
      db.collection("rooms").doc(`club_lounge_${clubId}`).get(),
      db.collection("clubOwnershipGuards").doc(uid).get(),
    ]);
    assert.equal(member.data().role, "owner");
    assert.equal(projection.data().role, "owner");
    assert.equal(channels.size, 3);
    assert.equal(room.data().clubId, clubId);
    assert.equal(guard.data().revision, 1);
  });

  test("same idempotency key recovers one Club without consuming quota twice", async () => {
    const uid = `${P}owner`;
    const clubId = `${P}idempotent`;
    await seedOwner(uid);

    const first = await run(request(uid, clubId));
    const second = await run(request(uid, clubId, { name: "Retry payload" }));
    assert.equal(first.alreadyExisted, false);
    assert.equal(second.alreadyExisted, true);

    const owned = await db.collection("clubs").where("ownerId", "==", uid).get();
    const channels = await db
      .collection("clubs")
      .doc(clubId)
      .collection("channels")
      .get();
    assert.equal(owned.size, 1);
    assert.equal(channels.size, 3);
    assert.equal(owned.docs[0].data().name, "Secure Club");
  });

  test("concurrent devices cannot exceed maxOwnedClubs", async () => {
    const uid = `${P}concurrent`;
    await seedOwner(uid);

    const attempts = await Promise.allSettled(
      [0, 1, 2, 3].map((index) =>
        run(request(uid, `${P}race-${index}`, { name: `Race Club ${index}` })),
      ),
    );
    const fulfilled = attempts.filter((item) => item.status === "fulfilled");
    const rejected = attempts.filter((item) => item.status === "rejected");
    assert.equal(fulfilled.length, 3);
    assert.equal(rejected.length, 1);
    // Under a fully parallel Functions suite the emulator can exhaust its
    // transaction retries and surface a raw gRPC code instead of the
    // application HttpsError. The security invariant is exact: only three
    // transactions commit and one fails. The serial legacy-cap case below
    // separately pins the stable resource-exhausted application code.

    const owned = await db.collection("clubs").where("ownerId", "==", uid).get();
    assert.equal(
      owned.docs.filter((doc) => doc.data().type !== "family").length,
      3,
    );
  });

  test("legacy Clubs count, while the free Family Room does not", async () => {
    const uid = `${P}legacy`;
    await seedOwner(uid);
    await Promise.all([
      db.collection("clubs").doc(`${P}legacy-no-type`).set({ ownerId: uid }),
      db.collection("clubs").doc(`${P}legacy-community`).set({
        ownerId: uid,
        type: "community",
      }),
      db.collection("clubs").doc(`family_${uid}`).set({
        ownerId: uid,
        type: "family",
      }),
    ]);

    await run(request(uid, `${P}legacy-third`));
    await assert.rejects(
      () => run(request(uid, `${P}legacy-fourth`)),
      (error) => error?.code === "resource-exhausted",
    );
  });

  for (const [label, entitlementData] of [
    ["missing", null],
    ["disabled capability", entitlement({ canCreateClubs: false })],
    ["missing Premium identity", entitlement({ premiumIdentityEnabled: false })],
    [
      "expired",
      entitlement({
        currentPeriodEnd: Timestamp.fromMillis(Date.now() - 1_000),
      }),
    ],
  ]) {
    test(`${label} entitlement is denied`, async () => {
      const uid = `${P}denied`;
      await seedOwner(uid, entitlementData);
      await assert.rejects(
        () => run(request(uid, `${P}denied-${label.replaceAll(" ", "-")}`)),
        (error) => error?.code === "failed-precondition",
      );
    });
  }

  test("a banned profile is denied even with an active entitlement", async () => {
    const uid = `${P}banned`;
    await seedOwner(uid, entitlement(), { banned: true });
    await assert.rejects(
      () => run(request(uid, `${P}banned-club`)),
      (error) => error?.code === "permission-denied",
    );
  });

  for (const [role, uid] of [
    ["moderator", `${P}moderator`],
    ["superModerator", `${P}super-moderator`],
  ]) {
    test(`${role} creates a Club through matching claim + mirror without billing`, async () => {
      await seedOwner(uid, null, { role });
      const result = await run(
        request(uid, `${P}${role}-club`, {}, { role }),
      );
      assert.equal(result.ownedCommunityClubs, 1);
      assert.equal(result.maxOwnedClubs, 3);
      assert.equal(
        (await db.collection("entitlements").doc(uid).get()).exists,
        false,
      );
    });
  }

  test("a stale or mismatched role claim cannot use the moderator overlay", async () => {
    const uid = `${P}role-mismatch`;
    await seedOwner(uid, null, { role: "moderator" });
    for (const role of [undefined, "user", "superModerator", "superAdmin"]) {
      await assert.rejects(
        () => run(request(
          uid,
          `${P}mismatch-${role ?? "missing"}`,
          {},
          role === undefined ? {} : { role },
        )),
        (error) => error?.code === "failed-precondition",
      );
    }
  });

  test("support, auditor, guide and superAdmin roles receive no automatic Club access", async () => {
    const uid = `${P}excluded-role`;
    for (const role of ["support", "auditor", "guideMaster", "superAdmin"]) {
      await seedOwner(uid, null, { role });
      await assert.rejects(
        () => run(request(uid, `${P}excluded-${role}`, {}, { role })),
        (error) => error?.code === "failed-precondition",
      );
    }
  });

  test("an inactive, deleted or missing profile is denied with active entitlement", async () => {
    const uid = `${P}banned`;
    await seedOwner(uid, entitlement(), { disabled: true });
    await assert.rejects(
      () => run(request(uid, `${P}disabled-club`)),
      (error) => error?.code === "permission-denied",
    );

    await seedOwner(uid, entitlement(), { deleted: true });
    await assert.rejects(
      () => run(request(uid, `${P}deleted-flag-club`)),
      (error) => error?.code === "permission-denied",
    );

    await seedOwner(uid, entitlement(), { status: "deleted" });
    await assert.rejects(
      () => run(request(uid, `${P}deleted-status-club`)),
      (error) => error?.code === "permission-denied",
    );

    await db.collection("users").doc(uid).delete();
    await assert.rejects(
      () => run(request(uid, `${P}missing-profile-club`)),
      (error) => error?.code === "permission-denied",
    );
  });

  test("an unverified caller is denied", async () => {
    const uid = `${P}owner`;
    await seedOwner(uid);
    const input = request(uid, `${P}unverified`);
    input.auth.token.email_verified = false;
    await assert.rejects(
      () => run(input),
      (error) => error?.code === "failed-precondition",
    );
  });

  test("creation cannot inject arbitrary media URLs around finalize", async () => {
    const uid = `${P}owner`;
    await seedOwner(uid);
    await assert.rejects(
      () => run(request(uid, `${P}url-injection`, {
        avatarUrl: "https://evil.invalid/avatar.jpg",
      })),
      (error) => error?.code === "invalid-argument",
    );
  });
});

describe("finalizeClubMedia", () => {
  const uid = `${P}media-owner`;
  const attacker = `${P}media-attacker`;
  const clubId = `${P}media-club`;

  async function seedMediaClub() {
    await seedOwner(uid);
    await seedOwner(attacker);
    await run(request(uid, clubId));
  }

  function handler(metadataByPath) {
    return createFinalizeClubMediaHandler({
      firestore: db,
      bucket: fakeMediaBucket(metadataByPath),
    });
  }

  test("server verifies and atomically mirrors canonical media", async () => {
    await seedMediaClub();
    const path = `clubs/${uid}/${clubId}/avatar`;
    const finalize = handler({ [path]: validMedia() });

    const first = await finalize(mediaRequest(uid, clubId));
    const replay = await finalize(mediaRequest(uid, clubId));
    assert.equal(first.avatarGeneration, "1001");
    assert.equal(replay.avatarUrl, first.avatarUrl);
    assert.match(first.avatarUrl, /yovoice-test\.firebasestorage\.app/u);

    const [club, projection, lounge] = await Promise.all([
      db.collection("clubs").doc(clubId).get(),
      db.collection("users").doc(uid).collection("clubs").doc(clubId).get(),
      db.collection("rooms").doc(`club_lounge_${clubId}`).get(),
    ]);
    assert.equal(club.data().avatarUrl, first.avatarUrl);
    assert.equal(club.data().avatarGeneration, "1001");
    assert.equal(projection.data().avatarUrl, first.avatarUrl);
    assert.equal(lounge.data().imageUrl, first.avatarUrl);
  });

  test("rejects forged descriptors, URLs, generation and missing objects", async () => {
    await seedMediaClub();
    const path = `clubs/${uid}/${clubId}/avatar`;
    const finalize = handler({ [path]: validMedia() });
    for (const forged of [
      mediaRequest(uid, clubId, {
        avatar: { path: `clubs/${uid}/other/avatar`, generation: "1001" },
      }),
      mediaRequest(uid, clubId, {
        avatar: { path, generation: "1001", url: "https://evil.invalid/x" },
      }),
      {
        ...mediaRequest(uid, clubId),
        data: {
          ...mediaRequest(uid, clubId).data,
          downloadUrl:
            "https://firebasestorage.googleapis.com/v0/b/yovoice-test.firebasestorage.app/o/wrong",
        },
      },
      mediaRequest(uid, clubId, {
        avatar: { path, generation: "1002" },
      }),
    ]) {
      await assert.rejects(() => finalize(forged));
    }
    const missing = handler({});
    await assert.rejects(
      () => missing(mediaRequest(uid, clubId)),
      (error) => error?.code === "failed-precondition",
    );
  });

  test("rejects invalid MIME, size and missing canonical token", async () => {
    await seedMediaClub();
    const path = `clubs/${uid}/${clubId}/avatar`;
    for (const metadata of [
      validMedia("1001", { contentType: "image/gif" }),
      validMedia("1001", { size: "127" }),
      validMedia("1001", { size: String(8 * 1024 * 1024 + 1) }),
      validMedia("1001", { metadata: {} }),
    ]) {
      const finalize = handler({ [path]: metadata });
      await assert.rejects(
        () => finalize(mediaRequest(uid, clubId)),
        (error) => error?.code === "failed-precondition",
      );
    }
  });

  test("rejects non-owner, Family, inactive and deleting roots", async () => {
    await seedMediaClub();
    const ownerPath = `clubs/${uid}/${clubId}/avatar`;
    const attackerPath = `clubs/${attacker}/${clubId}/avatar`;
    const finalize = handler({
      [ownerPath]: validMedia(),
      [attackerPath]: validMedia(),
    });
    await assert.rejects(
      () => finalize(mediaRequest(attacker, clubId)),
      (error) => error?.code === "permission-denied",
    );

    const club = db.collection("clubs").doc(clubId);
    for (const patch of [
      { type: "family", status: "active", deletionInProgress: false },
      { type: "community", status: "suspended", deletionInProgress: false },
      { type: "community", status: "active", deletionInProgress: true },
    ]) {
      await club.update(patch);
      await assert.rejects(
        () => finalize(mediaRequest(uid, clubId)),
        (error) => error?.code === "permission-denied",
      );
    }
  });

  test("rejects sanctioned identity, role drift and malformed graph", async () => {
    await seedMediaClub();
    const path = `clubs/${uid}/${clubId}/avatar`;
    const finalize = handler({ [path]: validMedia() });
    const profile = db.collection("users").doc(uid);
    await profile.update({ banned: true });
    await assert.rejects(() => finalize(mediaRequest(uid, clubId)));
    await profile.update({ banned: false, disabled: true });
    await assert.rejects(() => finalize(mediaRequest(uid, clubId)));
    await profile.update({ disabled: false });
    await profile.delete();
    await assert.rejects(
      () => finalize(mediaRequest(uid, clubId)),
      (error) => error?.code === "permission-denied",
    );
    await profile.set({ displayName: "Club Owner", banned: false, disabled: false });

    const member = db.collection("clubs").doc(clubId).collection("members").doc(uid);
    await member.update({ role: "admin" });
    await assert.rejects(() => finalize(mediaRequest(uid, clubId)));
    await member.update({ role: "owner" });

    const projection = profile.collection("clubs").doc(clubId);
    await projection.delete();
    await assert.rejects(
      () => finalize(mediaRequest(uid, clubId)),
      (error) => error?.code === "data-loss",
    );
    await projection.set({ clubId, role: "owner" });
    await db.collection("rooms").doc(`club_lounge_${clubId}`).update({
      clubId: "wrong-club",
    });
    await assert.rejects(
      () => finalize(mediaRequest(uid, clubId)),
      (error) => error?.code === "data-loss",
    );
  });

  test("rejects unauthenticated and unverified callers before Storage", async () => {
    await seedMediaClub();
    const path = `clubs/${uid}/${clubId}/avatar`;
    const finalize = handler({ [path]: validMedia() });
    await assert.rejects(
      () => finalize({ auth: null, data: mediaRequest(uid, clubId).data }),
      (error) => error?.code === "unauthenticated",
    );
    const unverified = mediaRequest(uid, clubId);
    unverified.auth.token.email_verified = false;
    await assert.rejects(
      () => finalize(unverified),
      (error) => error?.code === "failed-precondition",
    );
  });
});
