const assert = require("node:assert/strict");
const { after, beforeEach, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-likes-visibility-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  LIKES_VISIBILITY_RATE_LIMIT,
  LIKES_VISIBILITY_RATE_SCOPE,
  createLikesVisibilityService,
  exactLikesHiddenInput,
} = require("../profile/likes_visibility");
const { likesHiddenOf } = require("../engagement/liker_audience");
const { rateLimitReference } = require("../integrity/guards");

const db = getFirestore();
const UID = "likes-visibility-user";
const BASE_MS = 1_826_000_000_000;
let nowMs = BASE_MS;

function request({ uid = UID, hidden = true, data, verified = true } = {}) {
  return {
    auth: uid === null
      ? null
      : { uid, token: { email_verified: verified } },
    data: data === undefined ? { hidden } : data,
  };
}

function service({ rateLimit = LIKES_VISIBILITY_RATE_LIMIT } = {}) {
  return createLikesVisibilityService({
    firestore: db,
    TimestampImpl: Timestamp,
    clock: () => nowMs,
    rateLimit,
  });
}

async function reset() {
  await Promise.all([
    db.doc(`users/${UID}`).delete().catch(() => {}),
    db.doc("appConfig/likersV1").delete().catch(() => {}),
    rateLimitReference(db, LIKES_VISIBILITY_RATE_SCOPE, UID)
      .delete()
      .catch(() => {}),
  ]);
}

async function seed(overrides = {}) {
  await db.doc(`users/${UID}`).set({
    uid: UID,
    displayName: "Quiet Liker",
    banned: false,
    disabled: false,
    profileVisibility: "public",
    ...overrides,
  });
}

async function profile() {
  return (await db.doc(`users/${UID}`).get()).data();
}

beforeEach(async () => {
  nowMs = BASE_MS;
  await reset();
  await seed();
});

after(reset);

test("input is exactly { hidden: boolean }", async () => {
  assert.equal(exactLikesHiddenInput({ hidden: true }), true);
  assert.equal(exactLikesHiddenInput({ hidden: false }), false);
  for (const data of [
    null,
    [],
    "true",
    {},
    { hidden: "true" },
    { hidden: 1 },
    { hidden: null },
    { hidden: true, uid: "someone-else" },
    { visible: true },
  ]) {
    await assert.rejects(
      service().setMyLikesHiddenV1(request({ data })),
      (error) => error.code === "invalid-argument",
      JSON.stringify(data),
    );
  }
  // A refused input writes nothing, not even the rate budget.
  assert.equal(
    (await rateLimitReference(db, LIKES_VISIBILITY_RATE_SCOPE, UID).get())
      .exists,
    false,
  );
  assert.equal("likesHidden" in await profile(), false);
});

test("an unauthenticated call is refused", async () => {
  await assert.rejects(
    service().setMyLikesHiddenV1(request({ uid: null })),
    (error) => error.code === "unauthenticated",
  );
});

test("hiding sets the private field and its timestamp, and unhiding reverts it", async () => {
  assert.deepEqual(
    await service().setMyLikesHiddenV1(request({ hidden: true })),
    { hidden: true, changed: true },
  );
  let stored = await profile();
  assert.equal(stored.likesHidden, true);
  assert.equal(stored.likesHiddenUpdatedAt.toMillis(), BASE_MS);
  assert.equal(likesHiddenOf(stored), true);
  // Nothing else on the private document moves.
  assert.equal(stored.displayName, "Quiet Liker");
  assert.equal(stored.profileVisibility, "public");

  nowMs += 5_000;
  assert.deepEqual(
    await service().setMyLikesHiddenV1(request({ hidden: false })),
    { hidden: false, changed: true },
  );
  stored = await profile();
  assert.equal(stored.likesHidden, false);
  assert.equal(stored.likesHiddenUpdatedAt.toMillis(), BASE_MS + 5_000);
  assert.equal(likesHiddenOf(stored), false);
});

test("the same value reports changed:false and keeps the timestamp", async () => {
  // Missing is the visible default: asking to be visible changes nothing
  // and writes nothing.
  assert.deepEqual(
    await service().setMyLikesHiddenV1(request({ hidden: false })),
    { hidden: false, changed: false },
  );
  assert.equal("likesHidden" in await profile(), false);
  assert.equal("likesHiddenUpdatedAt" in await profile(), false);

  await service().setMyLikesHiddenV1(request({ hidden: true }));
  nowMs += 10_000;
  assert.deepEqual(
    await service().setMyLikesHiddenV1(request({ hidden: true })),
    { hidden: true, changed: false },
  );
  assert.equal((await profile()).likesHiddenUpdatedAt.toMillis(), BASE_MS);
});

test("a malformed stored value is read as hidden and any request repairs it", async () => {
  for (const [malformed, hidden] of [
    ["true", true],
    ["false", false],
    [1, true],
    [null, false],
  ]) {
    await seed({ likesHidden: malformed });
    assert.equal(likesHiddenOf(await profile()), true, JSON.stringify(malformed));
    assert.deepEqual(
      await service().setMyLikesHiddenV1(request({ hidden })),
      { hidden, changed: true },
      JSON.stringify(malformed),
    );
    assert.equal((await profile()).likesHidden, hidden);
  }
});

test("an inactive or missing account is refused and nothing is written", async () => {
  for (const overrides of [
    { banned: true },
    { disabled: true },
    { deleted: true },
    { status: "deleted" },
    { authDeletedAt: Timestamp.fromMillis(BASE_MS - 1) },
  ]) {
    await seed(overrides);
    await assert.rejects(
      service().setMyLikesHiddenV1(request()),
      (error) => error.code === "permission-denied",
      JSON.stringify(overrides),
    );
    assert.equal("likesHidden" in await profile(), false);
  }
  await db.doc(`users/${UID}`).delete();
  await assert.rejects(
    service().setMyLikesHiddenV1(request()),
    (error) => error.code === "not-found",
  );
  assert.equal((await db.doc(`users/${UID}`).get()).exists, false);
});

test("an unverified e-mail may still opt out", async () => {
  assert.deepEqual(
    await service().setMyLikesHiddenV1(request({ verified: false })),
    { hidden: true, changed: true },
  );
});

test("the private rate budget is consumed before the account check", async () => {
  const limited = service({ rateLimit: { maxEvents: 2, windowMs: 60_000 } });
  await limited.setMyLikesHiddenV1(request({ hidden: true }));
  await limited.setMyLikesHiddenV1(request({ hidden: false }));
  await assert.rejects(
    limited.setMyLikesHiddenV1(request({ hidden: true })),
    (error) => error.code === "resource-exhausted",
  );
  assert.equal((await profile()).likesHidden, false);
  const rate = (await rateLimitReference(db, LIKES_VISIBILITY_RATE_SCOPE, UID)
    .get()).data();
  assert.equal(rate.scope, "likes.visibility");
  assert.equal(rate.ownerId, UID);
  assert.equal(rate.count, 2);

  nowMs += 60_000;
  assert.deepEqual(
    await limited.setMyLikesHiddenV1(request({ hidden: true })),
    { hidden: true, changed: true },
  );

  // A suspended caller still spends budget: the budget contains abuse of the
  // callable itself, not only of successful writes.
  await seed({ banned: true });
  await rateLimitReference(db, LIKES_VISIBILITY_RATE_SCOPE, UID).delete();
  await assert.rejects(
    limited.setMyLikesHiddenV1(request()),
    (error) => error.code === "permission-denied",
  );
  assert.equal(
    (await rateLimitReference(db, LIKES_VISIBILITY_RATE_SCOPE, UID).get())
      .data().count,
    1,
  );
});

test("the default budget is 20 per minute", () => {
  assert.deepEqual({ ...LIKES_VISIBILITY_RATE_LIMIT }, {
    maxEvents: 20,
    windowMs: 60_000,
  });
  assert.equal(LIKES_VISIBILITY_RATE_SCOPE, "likes.visibility");
});

test("works whether or not the likers activation switch exists", async () => {
  // Missing: the opt-out must work before any list is ever exposed.
  assert.deepEqual(
    await service().setMyLikesHiddenV1(request({ hidden: true })),
    { hidden: true, changed: true },
  );
  // Present and off, or on: the setter never consults it.
  for (const enabled of [false, true]) {
    // hidden alternates true -> false -> true, so every call is a change.
    await db.doc("appConfig/likersV1").set({
      schemaVersion: 1,
      enabled,
      serverMessagesEnabled: enabled,
      updatedAt: Timestamp.fromMillis(BASE_MS),
    });
    const hidden = enabled;
    assert.deepEqual(
      await service().setMyLikesHiddenV1(request({ hidden })),
      { hidden, changed: true },
    );
  }
});
