const assert = require("node:assert/strict");
const { after, beforeEach, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-profile-visibility-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  PROFILE_VISIBILITY_RATE_LIMIT,
  PROFILE_VISIBILITY_RATE_SCOPE,
  createProfileVisibilityService,
  normalizeProfileVisibility,
} = require("../profile/profile_visibility");
const { rateLimitReference } = require("../integrity/guards");

const db = getFirestore();
const UID = "profile-visibility-user";
let nowMs = 1_825_000_000_000;

function request({ uid = UID, visibility = "private", data } = {}) {
  return {
    auth: uid === null ? null : { uid, token: {} },
    data: data === undefined ? { visibility } : data,
  };
}

function service({ rateLimit = PROFILE_VISIBILITY_RATE_LIMIT } = {}) {
  return createProfileVisibilityService({
    firestore: db,
    TimestampImpl: Timestamp,
    clock: () => nowMs,
    rateLimit,
  });
}

async function remove(reference) {
  await reference.delete().catch(() => {});
}

async function reset() {
  await Promise.all([
    remove(db.collection("users").doc(UID)),
    remove(db.collection("marketingConsents").doc(UID)),
    remove(db.collection("publicShowcase").doc("live")),
    remove(db.collection("privateShowcaseControl").doc("live")),
    remove(rateLimitReference(db, PROFILE_VISIBILITY_RATE_SCOPE, UID)),
  ]);
}

async function seed(overrides = {}) {
  await db.collection("users").doc(UID).set({
    uid: UID,
    displayName: "Visible Voice",
    banned: false,
    disabled: false,
    ...overrides,
  });
}

beforeEach(async () => {
  nowMs = 1_825_000_000_000;
  await reset();
  await seed();
});

after(reset);

test("legacy visibility defaults public while invalid server state fails private", () => {
  assert.equal(normalizeProfileVisibility(undefined), "public");
  assert.equal(normalizeProfileVisibility(null), "public");
  assert.equal(normalizeProfileVisibility("friends"), "friends");
  assert.equal(normalizeProfileVisibility("everyone-ish"), "private");
});

test("non-public visibility atomically revokes website consent and clears people", async () => {
  await Promise.all([
    db.collection("marketingConsents").doc(UID).set({
      schemaVersion: 1,
      showProfileOnWebsite: true,
      showActivityOnWebsite: true,
      updatedAt: Timestamp.fromMillis(nowMs - 1_000),
    }),
    db.collection("publicShowcase").doc("live").set({
      schemaVersion: 1,
      people: [
        { displayName: "Visible Voice", accountType: "personal", activity: "undisclosed" },
      ],
      clubs: [{ name: "Safe club", memberCount: 3 }],
      generatedAt: Timestamp.fromMillis(nowMs - 1_000),
      activityValidUntil: Timestamp.fromMillis(nowMs + 60_000),
      validUntil: Timestamp.fromMillis(nowMs + 120_000),
    }),
  ]);

  assert.deepEqual(
    await service().setMyProfileVisibility(request({ visibility: "friends" })),
    { visibility: "friends", changed: true },
  );

  const [profile, consent, showcase, control] = await Promise.all([
    db.collection("users").doc(UID).get(),
    db.collection("marketingConsents").doc(UID).get(),
    db.collection("publicShowcase").doc("live").get(),
    db.collection("privateShowcaseControl").doc("live").get(),
  ]);
  assert.equal(profile.data().profileVisibility, "friends");
  assert.equal(profile.data().profileVisibilityUpdatedAt.toMillis(), nowMs);
  assert.deepEqual(consent.data(), {
    schemaVersion: 1,
    showProfileOnWebsite: false,
    showActivityOnWebsite: false,
    updatedAt: Timestamp.fromMillis(nowMs),
  });
  assert.deepEqual(showcase.data().people, []);
  assert.deepEqual(showcase.data().clubs, [{ name: "Safe club", memberCount: 3 }]);
  assert.equal(control.data().privacyGeneration, 1);
});

test("same non-public value repairs stale consent/showcase without moving timestamp", async () => {
  const previous = nowMs - 20_000;
  await db.collection("users").doc(UID).update({
    profileVisibility: "private",
    profileVisibilityUpdatedAt: Timestamp.fromMillis(previous),
  });
  await db.collection("marketingConsents").doc(UID).set({
    schemaVersion: 1,
    showProfileOnWebsite: true,
    showActivityOnWebsite: false,
    updatedAt: Timestamp.fromMillis(previous),
  });
  await db.collection("publicShowcase").doc("live").set({ people: [{}] });

  assert.deepEqual(await service().setMyProfileVisibility(request()), {
    visibility: "private",
    changed: false,
  });
  const profile = (await db.collection("users").doc(UID).get()).data();
  assert.equal(profile.profileVisibilityUpdatedAt.toMillis(), previous);
  assert.equal(
    (await db.collection("marketingConsents").doc(UID).get()).data()
      .showProfileOnWebsite,
    false,
  );
  assert.deepEqual(
    (await db.collection("publicShowcase").doc("live").get()).data().people,
    [],
  );
});

test("public visibility does not silently opt into or alter website showcase", async () => {
  await db.collection("marketingConsents").doc(UID).set({
    schemaVersion: 1,
    showProfileOnWebsite: false,
    showActivityOnWebsite: false,
    updatedAt: Timestamp.fromMillis(nowMs - 1_000),
  });
  await db.collection("publicShowcase").doc("live").set({ people: [{ safe: true }] });

  const result = await service().setMyProfileVisibility(
    request({ visibility: "public" }),
  );
  assert.deepEqual(result, { visibility: "public", changed: true });
  assert.equal(
    (await db.collection("marketingConsents").doc(UID).get()).data()
      .showProfileOnWebsite,
    false,
  );
  assert.deepEqual(
    (await db.collection("publicShowcase").doc("live").get()).data().people,
    [{ safe: true }],
  );
});

test("authentication, exact payload and active profile state fail closed", async () => {
  const api = service();
  await assert.rejects(
    api.setMyProfileVisibility(request({ uid: null })),
    (error) => error.code === "unauthenticated",
  );
  for (const data of [
    null,
    [],
    {},
    { visibility: "followers" },
    { visibility: "public", extra: true },
    { visibility: 1 },
  ]) {
    await assert.rejects(
      api.setMyProfileVisibility(request({ data })),
      (error) => error.code === "invalid-argument",
    );
  }

  await db.collection("users").doc(UID).update({ banned: true });
  await assert.rejects(
    api.setMyProfileVisibility(request()),
    (error) => error.code === "permission-denied",
  );
  await db.collection("users").doc(UID).delete();
  await assert.rejects(
    api.setMyProfileVisibility(request({ visibility: "friends" })),
    (error) => error.code === "not-found",
  );
});

test("private server-time quota serializes concurrent valid requests", async () => {
  const api = service({ rateLimit: { maxEvents: 2, windowMs: 1_000 } });
  const outcomes = await Promise.allSettled([
    api.setMyProfileVisibility(request({ visibility: "public" })),
    api.setMyProfileVisibility(request({ visibility: "friends" })),
    api.setMyProfileVisibility(request({ visibility: "private" })),
  ]);
  assert.equal(outcomes.filter((item) => item.status === "fulfilled").length, 2);
  const rejected = outcomes.filter((item) => item.status === "rejected");
  assert.equal(rejected.length, 1);
  assert.equal(rejected[0].reason.code, "resource-exhausted");
});
