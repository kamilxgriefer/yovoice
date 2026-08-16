// Authoritative Premium Club creation and quota regressions.

const assert = require("node:assert/strict");
const { test, beforeEach, describe } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const { createCommunityClub } = require("../clubs/creation");

const db = getFirestore();
const run = createCommunityClub.run ?? createCommunityClub;
const P = "ccs-";
const OWNERS = [
  `${P}owner`,
  `${P}concurrent`,
  `${P}legacy`,
  `${P}denied`,
  `${P}banned`,
];

function request(uid, clubId, overrides = {}) {
  return {
    auth: {
      uid,
      token: {
        email_verified: true,
        email: `${uid}@example.invalid`,
        name: "Club Owner",
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
    currentPeriodEnd: Timestamp.fromMillis(Date.now() + 86_400_000),
    premiumIdentityEnabled: true,
    canCreateClubs: true,
    maxOwnedClubs: 3,
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
      db.collection("users").doc(owner).delete(),
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

  test("a disabled or missing profile is denied with active entitlement", async () => {
    const uid = `${P}banned`;
    await seedOwner(uid, entitlement(), { disabled: true });
    await assert.rejects(
      () => run(request(uid, `${P}disabled-club`)),
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
});
