const assert = require("node:assert/strict");
const { after, beforeEach, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  createPinnedPostsService,
  handlePinnedCreatorProfileChanged,
  handlePinnedMomentEligibilityChanged,
} = require("../creator/pinned_posts");
const {
  applyEntitlements,
  commitExpiredPremiumPage,
} = require("../premium/entitlements");
const { rateLimitReference } = require("../integrity/guards");

const db = getFirestore();
const CREATOR = "pin-creator";
const OTHER = "pin-other";
const OPAQUE_CREATOR = "opaque użytkownik";
const MOMENT = "pin-moment";
const OTHER_MOMENT = "pin-other-moment";
let nowMs = 1_820_000_000_000;

function request(uid, momentId, overrides = {}) {
  return {
    auth: {
      uid,
      token: {
        email_verified: true,
        email: `${uid}@example.invalid`,
        ...overrides,
      },
    },
    data: { momentId },
  };
}

function canonicalMoment(authorId, overrides = {}) {
  return {
    schemaVersion: 2,
    authorId,
    status: "published",
    isPublished: true,
    isDeleted: false,
    caption: "A real published Voice Moment",
    audioUrl: "https://example.invalid/moment.m4a",
    durationSeconds: 18,
    likeCount: 7,
    commentCount: 3,
    ...overrides,
  };
}

function activeEntitlement(overrides = {}) {
  return {
    status: "active",
    isPremium: true,
    creatorEnabled: true,
    premiumIdentityEnabled: true,
    currentPeriodEnd: Timestamp.fromMillis(nowMs + 86_400_000),
    ...overrides,
  };
}

function service() {
  return createPinnedPostsService({
    firestore: db,
    TimestampImpl: Timestamp,
    clock: () => nowMs,
  });
}

async function ignoreMissing(reference) {
  await reference.delete().catch(() => {});
}

async function reset() {
  for (const path of [
    `creatorPinnedPosts/${CREATOR}`,
    `creatorPinnedPosts/${OTHER}`,
    `creatorPinnedPosts/${OPAQUE_CREATOR}`,
    `voiceMoments/${MOMENT}`,
    `voiceMoments/${OTHER_MOMENT}`,
    `users/${CREATOR}`,
    `users/${OTHER}`,
    `users/${OPAQUE_CREATOR}`,
    `entitlements/${CREATOR}`,
    `entitlements/${OTHER}`,
    `entitlements/${OPAQUE_CREATOR}`,
  ]) {
    await ignoreMissing(db.doc(path));
  }
  for (const uid of [CREATOR, OTHER, OPAQUE_CREATOR]) {
    await ignoreMissing(
      rateLimitReference(db, "creator.pinnedPost.attempt", uid),
    );
  }
}

async function seedCreator({
  uid = CREATOR,
  accountType = "creator",
  profile = {},
  entitlement = activeEntitlement(),
} = {}) {
  await db.doc(`users/${uid}`).set({
    uid,
    accountType,
    banned: false,
    disabled: false,
    ...profile,
  });
  if (entitlement !== null) {
    await db.doc(`entitlements/${uid}`).set(entitlement);
  }
}

beforeEach(async () => {
  nowMs = 1_820_000_000_000;
  await reset();
  await seedCreator();
  await seedCreator({ uid: OTHER });
  await db.doc(`voiceMoments/${MOMENT}`).set(canonicalMoment(CREATOR));
  await db.doc(`voiceMoments/${OTHER_MOMENT}`).set(canonicalMoment(OTHER));
});

after(reset);

test("a Premium Creator pins only an owned published canonical Moment", async () => {
  const result = await service().setCreatorPinnedPost(
    request(CREATOR, MOMENT),
  );
  assert.deepEqual(result, { pinned: true, momentId: MOMENT });

  const snapshot = await db.doc(`creatorPinnedPosts/${CREATOR}`).get();
  assert.equal(snapshot.exists, true);
  assert.deepEqual(Object.keys(snapshot.data()).sort(), [
    "creatorId",
    "momentId",
    "pinnedAt",
    "schemaVersion",
    "updatedAt",
  ]);
  assert.equal(snapshot.data().creatorId, CREATOR);
  assert.equal(snapshot.data().momentId, MOMENT);
  assert.equal(snapshot.data().schemaVersion, 1);
});

for (const role of ["moderator", "superModerator"]) {
  test(`${role} pins through matching claim + mirror without billing`, async () => {
    await db.doc(`entitlements/${CREATOR}`).delete();
    await seedCreator({ profile: { role }, entitlement: null });
    await service().setCreatorPinnedPost(
      request(CREATOR, MOMENT, { role }),
    );
    assert.equal(
      (await db.doc(`creatorPinnedPosts/${CREATOR}`).get()).data().momentId,
      MOMENT,
    );
    assert.equal(
      (await db.doc(`entitlements/${CREATOR}`).get()).exists,
      false,
    );
  });
}

test("stale or mismatched role claims cannot invoke the moderator overlay", async () => {
  await db.doc(`entitlements/${CREATOR}`).delete();
  await seedCreator({
    profile: { role: "moderator" },
    entitlement: null,
  });
  for (const role of [undefined, "user", "superModerator", "superAdmin"]) {
    await assert.rejects(
      service().setCreatorPinnedPost(
        request(
          CREATOR,
          MOMENT,
          role === undefined ? {} : { role },
        ),
      ),
      (error) => error.code === "failed-precondition",
    );
  }
});

test("non-preview staff roles do not receive Creator access", async () => {
  await db.doc(`entitlements/${CREATOR}`).delete();
  for (const role of ["support", "auditor", "guideMaster", "superAdmin"]) {
    await seedCreator({ profile: { role }, entitlement: null });
    await assert.rejects(
      service().setCreatorPinnedPost(request(CREATOR, MOMENT, { role })),
      (error) => error.code === "failed-precondition",
    );
  }
});

test("same pin is idempotent and unpin deletes the server projection", async () => {
  const api = service();
  await api.setCreatorPinnedPost(request(CREATOR, MOMENT));
  const first = (await db.doc(`creatorPinnedPosts/${CREATOR}`).get()).data();
  nowMs += 10_000;
  await api.setCreatorPinnedPost(request(CREATOR, MOMENT));
  const replay = (await db.doc(`creatorPinnedPosts/${CREATOR}`).get()).data();
  assert.equal(replay.pinnedAt.toMillis(), first.pinnedAt.toMillis());
  assert.equal(replay.updatedAt.toMillis(), nowMs);

  assert.deepEqual(
    await api.setCreatorPinnedPost(request(CREATOR, null)),
    { pinned: false, momentId: null },
  );
  assert.equal(
    (await db.doc(`creatorPinnedPosts/${CREATOR}`).get()).exists,
    false,
  );
});

test("unpin stays idempotent after Premium expires", async () => {
  const api = service();
  await api.setCreatorPinnedPost(request(CREATOR, MOMENT));
  await seedCreator({
    accountType: "personal",
    entitlement: activeEntitlement({
      status: "expired",
      isPremium: false,
      creatorEnabled: false,
      premiumIdentityEnabled: false,
      currentPeriodEnd: Timestamp.fromMillis(nowMs - 1),
    }),
  });
  assert.deepEqual(
    await api.setCreatorPinnedPost(request(CREATOR, null)),
    { pinned: false, momentId: null },
  );
  assert.deepEqual(
    await api.setCreatorPinnedPost(request(CREATOR, null)),
    { pinned: false, momentId: null },
  );
});

for (const [label, configure, expectedCode] of [
  [
    "personal account",
    () => seedCreator({ accountType: "personal" }),
    "failed-precondition",
  ],
  [
    "expired entitlement",
    () => seedCreator({
      entitlement: activeEntitlement({
        currentPeriodEnd: Timestamp.fromMillis(nowMs - 1),
      }),
    }),
    "failed-precondition",
  ],
  [
    "disabled creator capability",
    () => seedCreator({
      entitlement: activeEntitlement({ creatorEnabled: false }),
    }),
    "failed-precondition",
  ],
  [
    "missing Premium identity",
    () => seedCreator({
      entitlement: activeEntitlement({ premiumIdentityEnabled: false }),
    }),
    "failed-precondition",
  ],
  [
    "banned profile",
    () => seedCreator({ profile: { banned: true } }),
    "permission-denied",
  ],
]) {
  test(`${label} cannot pin`, async () => {
    await configure();
    await assert.rejects(
      service().setCreatorPinnedPost(request(CREATOR, MOMENT)),
      (error) => error.code === expectedCode,
    );
    assert.equal(
      (await db.doc(`creatorPinnedPosts/${CREATOR}`).get()).exists,
      false,
    );
  });
}

test("official accounts still require the live Creator entitlement", async () => {
  await seedCreator({ accountType: "official" });
  await service().setCreatorPinnedPost(request(CREATOR, MOMENT));
  assert.equal(
    (await db.doc(`creatorPinnedPosts/${CREATOR}`).get()).data().momentId,
    MOMENT,
  );

  await seedCreator({
    accountType: "official",
    entitlement: activeEntitlement({ isPremium: false }),
  });
  await assert.rejects(
    service().setCreatorPinnedPost(request(CREATOR, MOMENT)),
    (error) => error.code === "failed-precondition",
  );
});

test("another creator's, draft, deleted, and malformed Moments are denied", async () => {
  const api = service();
  for (const [momentId, value] of [
    [OTHER_MOMENT, canonicalMoment(OTHER)],
    [MOMENT, canonicalMoment(CREATOR, { status: "uploading", isPublished: false })],
    [MOMENT, canonicalMoment(CREATOR, { status: "deleting", isPublished: false, isDeleted: true })],
    [MOMENT, canonicalMoment(CREATOR, { schemaVersion: 1 })],
    [MOMENT, canonicalMoment(CREATOR, { caption: 123 })],
  ]) {
    await db.doc(`voiceMoments/${momentId}`).set(value);
    await assert.rejects(
      api.setCreatorPinnedPost(request(CREATOR, momentId)),
      (error) => error.code === "failed-precondition",
    );
  }
});

test("input is exact and callers must be authenticated and verified", async () => {
  const api = service();
  await assert.rejects(
    api.setCreatorPinnedPost({ auth: null, data: { momentId: MOMENT } }),
    (error) => error.code === "unauthenticated",
  );
  await assert.rejects(
    api.setCreatorPinnedPost(request(CREATOR, MOMENT, { email_verified: false })),
    (error) => error.code === "failed-precondition",
  );
  await assert.rejects(
    api.setCreatorPinnedPost({
      ...request(CREATOR, MOMENT),
      data: { momentId: MOMENT, creatorId: OTHER },
    }),
    (error) => error.code === "invalid-argument",
  );
  for (const unsafeId of ["bad/path", "unicode-ę"]) {
    await assert.rejects(
      api.setCreatorPinnedPost(request(CREATOR, unsafeId)),
      (error) => error.code === "invalid-argument",
    );
  }
});

test("invalid target Moments consume a committed actor-wide attempt budget", async () => {
  const api = createPinnedPostsService({
    firestore: db,
    TimestampImpl: Timestamp,
    clock: () => nowMs,
    maxAttempts: 2,
    attemptWindowMs: 60_000,
  });
  for (const momentId of ["missing-a", "missing-b"]) {
    await assert.rejects(
      api.setCreatorPinnedPost(request(CREATOR, momentId)),
      (error) => error.code === "failed-precondition",
    );
  }
  await assert.rejects(
    api.setCreatorPinnedPost(request(CREATOR, "missing-c")),
    (error) => error.code === "resource-exhausted",
  );
  const rate = await rateLimitReference(
    db,
    "creator.pinnedPost.attempt",
    CREATOR,
  ).get();
  assert.equal(rate.data().count, 2);
});

test("admin revoke atomically removes the pin and paid Creator mode", async () => {
  await service().setCreatorPinnedPost(request(CREATOR, MOMENT));
  await applyEntitlements(CREATOR, {
    plan: "none",
    status: "expired",
    currentPeriodEnd: Timestamp.fromMillis(0),
    source: "test",
  });
  const [pin, entitlement, profile] = await db.getAll(
    db.doc(`creatorPinnedPosts/${CREATOR}`),
    db.doc(`entitlements/${CREATOR}`),
    db.doc(`users/${CREATOR}`),
  );
  assert.equal(pin.exists, false);
  assert.equal(entitlement.data().isPremium, false);
  assert.equal(entitlement.data().creatorEnabled, false);
  assert.equal(profile.data().accountType, "personal");
});

test("paid expiry preserves an active moderator pin and Creator mode", async () => {
  await seedCreator({ profile: { role: "moderator" } });
  await service().setCreatorPinnedPost(
    request(CREATOR, MOMENT, { role: "moderator" }),
  );
  await applyEntitlements(CREATOR, {
    plan: "none",
    status: "expired",
    currentPeriodEnd: Timestamp.fromMillis(0),
    source: "test",
  });
  const [pin, entitlement, profile] = await db.getAll(
    db.doc(`creatorPinnedPosts/${CREATOR}`),
    db.doc(`entitlements/${CREATOR}`),
    db.doc(`users/${CREATOR}`),
  );
  assert.equal(pin.exists, true);
  assert.equal(entitlement.data().isPremium, false);
  assert.equal(profile.data().premiumIdentity, false);
  assert.equal(profile.data().accountType, "creator");
});

test("admin revoke defers destructive cleanup during a preview role transition",
  async () => {
    const api = service();
    await seedCreator({ profile: { role: "superModerator" } });
    await api.setCreatorPinnedPost(
      request(CREATOR, MOMENT, { role: "superModerator" }),
    );
    await db.doc(`users/${CREATOR}`).update({
      role: "user",
      roleTransitionInProgress: true,
    });

    await applyEntitlements(CREATOR, {
      plan: "none",
      status: "expired",
      currentPeriodEnd: Timestamp.fromMillis(0),
      source: "test",
    });

    let [pin, entitlement, profile] = await db.getAll(
      db.doc(`creatorPinnedPosts/${CREATOR}`),
      db.doc(`entitlements/${CREATOR}`),
      db.doc(`users/${CREATOR}`),
    );
    assert.equal(entitlement.data().isPremium, false);
    assert.equal(profile.data().premiumIdentity, false);
    assert.equal(pin.exists, true);
    assert.equal(profile.data().accountType, "creator");
    assert.deepEqual(await api.clearPinForIneligibleCreator(CREATOR), {
      cleared: false,
      deferred: true,
    });

    await db.doc(`users/${CREATOR}`).update({
      role: "moderator",
      roleTransitionInProgress: false,
    });
    assert.deepEqual(await api.clearPinForIneligibleCreator(CREATOR), {
      cleared: false,
    });
    [pin, profile] = await db.getAll(
      db.doc(`creatorPinnedPosts/${CREATOR}`),
      db.doc(`users/${CREATOR}`),
    );
    assert.equal(pin.exists, true);
    assert.equal(profile.data().accountType, "creator");
  });

test("scheduled expiry atomically removes an existing Creator pin", async () => {
  await service().setCreatorPinnedPost(request(CREATOR, MOMENT));
  const entitlementRef = db.doc(`entitlements/${CREATOR}`);
  await entitlementRef.update({
    currentPeriodEnd: Timestamp.fromMillis(nowMs - 1),
  });
  const expired = await commitExpiredPremiumPage(
    [await entitlementRef.get()],
    { now: Timestamp.fromMillis(nowMs) },
  );
  const [pin, entitlement, profile] = await db.getAll(
    db.doc(`creatorPinnedPosts/${CREATOR}`),
    entitlementRef,
    db.doc(`users/${CREATOR}`),
  );
  assert.equal(expired, 1);
  assert.equal(pin.exists, false);
  assert.equal(entitlement.data().isPremium, false);
  assert.equal(profile.data().accountType, "personal");
});

test("scheduled expiry defers cleanup until a preview transition resolves",
  async () => {
    const api = service();
    await service().setCreatorPinnedPost(request(CREATOR, MOMENT));
    const entitlementRef = db.doc(`entitlements/${CREATOR}`);
    await entitlementRef.update({
      currentPeriodEnd: Timestamp.fromMillis(nowMs - 1),
    });
    await db.doc(`users/${CREATOR}`).update({
      role: "user",
      roleTransitionInProgress: true,
    });

    const expired = await commitExpiredPremiumPage(
      [await entitlementRef.get()],
      { now: Timestamp.fromMillis(nowMs) },
    );
    let [pin, profile] = await db.getAll(
      db.doc(`creatorPinnedPosts/${CREATOR}`),
      db.doc(`users/${CREATOR}`),
    );
    assert.equal(expired, 1);
    assert.equal(pin.exists, true);
    assert.equal(profile.data().accountType, "creator");

    // A final non-preview role is a real revocation; clearing the marker
    // retriggers convergence and removes both stale Creator projections.
    await db.doc(`users/${CREATOR}`).update({
      role: "support",
      roleTransitionInProgress: false,
    });
    assert.deepEqual(await api.clearPinForIneligibleCreator(CREATOR), {
      cleared: true,
      creatorId: CREATOR,
    });
    [pin, profile] = await db.getAll(
      db.doc(`creatorPinnedPosts/${CREATOR}`),
      db.doc(`users/${CREATOR}`),
    );
    assert.equal(pin.exists, false);
    assert.equal(profile.data().accountType, "personal");
  });

test("scheduled expiry never recreates a missing user profile", async () => {
  await service().setCreatorPinnedPost(request(CREATOR, MOMENT));
  const entitlementRef = db.doc(`entitlements/${CREATOR}`);
  await entitlementRef.update({
    currentPeriodEnd: Timestamp.fromMillis(nowMs - 1),
  });
  await db.doc(`users/${CREATOR}`).delete();

  const expired = await commitExpiredPremiumPage(
    [await entitlementRef.get()],
    { now: Timestamp.fromMillis(nowMs) },
  );
  const [pin, entitlement, profile] = await db.getAll(
    db.doc(`creatorPinnedPosts/${CREATOR}`),
    entitlementRef,
    db.doc(`users/${CREATOR}`),
  );

  assert.equal(expired, 1);
  assert.equal(pin.exists, false, "the orphaned pin must still be removed");
  assert.equal(entitlement.data().isPremium, false);
  assert.equal(entitlement.data().creatorEnabled, false);
  assert.equal(profile.exists, false, "expiry must not recreate the profile");
});

test("provider revoke never recreates a missing user profile", async () => {
  await service().setCreatorPinnedPost(request(CREATOR, MOMENT));
  await db.doc(`users/${CREATOR}`).delete();

  await applyEntitlements(CREATOR, {
    plan: "none",
    status: "expired",
    currentPeriodEnd: Timestamp.fromMillis(0),
    source: "test",
  });
  const [pin, entitlement, profile] = await db.getAll(
    db.doc(`creatorPinnedPosts/${CREATOR}`),
    db.doc(`entitlements/${CREATOR}`),
    db.doc(`users/${CREATOR}`),
  );

  assert.equal(pin.exists, false, "the orphaned pin must still be removed");
  assert.equal(entitlement.data().isPremium, false);
  assert.equal(profile.exists, false, "provider writes must not recreate users");
});

test("pin is automatically removed when its Moment becomes ineligible", async () => {
  const api = service();
  await api.setCreatorPinnedPost(request(CREATOR, MOMENT));
  await db.doc(`voiceMoments/${MOMENT}`).update({
    status: "deleting",
    isPublished: false,
    isDeleted: true,
  });
  assert.deepEqual(await api.clearPinForIneligibleMoment(MOMENT), {
    cleared: true,
    creatorId: CREATOR,
  });
  assert.equal(
    (await db.doc(`creatorPinnedPosts/${CREATOR}`).get()).exists,
    false,
  );
});

test("delete cleanup is race-safe and only removes a matching pin", async () => {
  const api = service();
  await api.setCreatorPinnedPost(request(CREATOR, MOMENT));
  await db.doc(`voiceMoments/${MOMENT}`).delete();
  assert.deepEqual(await api.clearDeletedMomentPin(MOMENT, CREATOR), {
    cleared: true,
    creatorId: CREATOR,
  });

  await db.doc(`creatorPinnedPosts/${CREATOR}`).set({ momentId: OTHER_MOMENT });
  assert.deepEqual(await api.clearDeletedMomentPin(MOMENT, CREATOR), {
    cleared: false,
  });
  assert.equal(
    (await db.doc(`creatorPinnedPosts/${CREATOR}`).get()).data().momentId,
    OTHER_MOMENT,
  );
});

test("entitlement/profile cleanup removes stale pins and preserves active ones", async () => {
  const api = service();
  await api.setCreatorPinnedPost(request(CREATOR, MOMENT));
  assert.deepEqual(await api.clearPinForIneligibleCreator(CREATOR), {
    cleared: false,
  });

  await db.doc(`entitlements/${CREATOR}`).update({ creatorEnabled: false });
  assert.deepEqual(await api.clearPinForIneligibleCreator(CREATOR), {
    cleared: true,
    creatorId: CREATOR,
  });
});

test("a deleted profile cannot use the transition marker to retain a pin",
  async () => {
    const api = service();
    await api.setCreatorPinnedPost(request(CREATOR, MOMENT));
    await db.doc(`users/${CREATOR}`).update({
      deleted: true,
      roleTransitionInProgress: true,
    });
    assert.deepEqual(await api.clearPinForIneligibleCreator(CREATOR), {
      cleared: true,
      creatorId: CREATOR,
    });
    assert.equal(
      (await db.doc(`creatorPinnedPosts/${CREATOR}`).get()).exists,
      false,
    );
  });

test("role demotion removes preview pin/mode unless paid access remains", async () => {
  const api = service();
  await db.doc(`entitlements/${CREATOR}`).delete();
  await seedCreator({
    profile: { role: "moderator" },
    entitlement: null,
  });
  await api.setCreatorPinnedPost(
    request(CREATOR, MOMENT, { role: "moderator" }),
  );
  await db.doc(`users/${CREATOR}`).update({ role: "user" });
  assert.deepEqual(await api.clearPinForIneligibleCreator(CREATOR), {
    cleared: true,
    creatorId: CREATOR,
  });
  const [pin, profile] = await db.getAll(
    db.doc(`creatorPinnedPosts/${CREATOR}`),
    db.doc(`users/${CREATOR}`),
  );
  assert.equal(pin.exists, false);
  assert.equal(profile.data().accountType, "personal");

  await seedCreator({
    profile: { role: "moderator" },
    entitlement: activeEntitlement(),
  });
  await api.setCreatorPinnedPost(
    request(CREATOR, MOMENT, { role: "moderator" }),
  );
  await db.doc(`users/${CREATOR}`).update({ role: "user" });
  assert.deepEqual(await api.clearPinForIneligibleCreator(CREATOR), {
    cleared: false,
  });
  assert.equal(
    (await db.doc(`creatorPinnedPosts/${CREATOR}`).get()).exists,
    true,
  );
  assert.equal(
    (await db.doc(`users/${CREATOR}`).get()).data().accountType,
    "creator",
  );
});

test("cleanup preserves an opaque Creator UID byte-for-byte", async () => {
  await seedCreator({ uid: OPAQUE_CREATOR });
  await db.doc(`creatorPinnedPosts/${OPAQUE_CREATOR}`).set({
    schemaVersion: 1,
    creatorId: OPAQUE_CREATOR,
    momentId: MOMENT,
    pinnedAt: Timestamp.fromMillis(nowMs),
    updatedAt: Timestamp.fromMillis(nowMs),
  });
  await db.doc(`entitlements/${OPAQUE_CREATOR}`).update({
    creatorEnabled: false,
  });

  assert.deepEqual(
    await service().clearPinForIneligibleCreator(OPAQUE_CREATOR),
    { cleared: true, creatorId: OPAQUE_CREATOR },
  );
  assert.equal(
    (await db.doc(`creatorPinnedPosts/${OPAQUE_CREATOR}`).get()).exists,
    false,
  );
});

test("harmless profile updates skip cleanup without repository calls", async () => {
  let calls = 0;
  const fakeService = {
    clearPinForIneligibleCreator: async () => {
      calls += 1;
      return { cleared: false };
    },
  };
  const snapshot = (data) => ({ exists: true, data: () => data });
  const outcome = await handlePinnedCreatorProfileChanged(
    {
      params: { creatorId: CREATOR },
      data: {
        before: snapshot({
          accountType: "creator",
          banned: false,
          followerCount: 10,
        }),
        after: snapshot({
          accountType: "creator",
          banned: false,
          followerCount: 11,
        }),
      },
    },
    fakeService,
  );
  assert.deepEqual(outcome, { cleared: false, skipped: true });
  assert.equal(calls, 0);
});

test("eligibility profile changes invoke cleanup exactly once", async () => {
  let calls = 0;
  const snapshot = (data) => ({ exists: true, data: () => data });
  await handlePinnedCreatorProfileChanged(
    {
      params: { creatorId: CREATOR },
      data: {
        before: snapshot({ accountType: "creator", banned: false }),
        after: snapshot({ accountType: "personal", banned: false }),
      },
    },
    {
      clearPinForIneligibleCreator: async (creatorId) => {
        calls += 1;
        assert.equal(creatorId, CREATOR);
        return { cleared: true, creatorId };
      },
    },
  );
  assert.equal(calls, 1);
});

test("role changes are Creator eligibility changes", async () => {
  let calls = 0;
  const snapshot = (data) => ({ exists: true, data: () => data });
  await handlePinnedCreatorProfileChanged(
    {
      params: { creatorId: CREATOR },
      data: {
        before: snapshot({ accountType: "creator", role: "moderator" }),
        after: snapshot({ accountType: "creator", role: "user" }),
      },
    },
    {
      clearPinForIneligibleCreator: async () => {
        calls += 1;
        return { cleared: true };
      },
    },
  );
  assert.equal(calls, 1);
});

test("the neutral role interlock defers profile-trigger cleanup", async () => {
  let calls = 0;
  const snapshot = (data) => ({ exists: true, data: () => data });
  const outcome = await handlePinnedCreatorProfileChanged(
    {
      params: { creatorId: CREATOR },
      data: {
        before: snapshot({
          accountType: "creator",
          role: "superModerator",
          roleTransitionInProgress: false,
        }),
        after: snapshot({
          accountType: "creator",
          role: "user",
          roleTransitionInProgress: true,
        }),
      },
    },
    {
      clearPinForIneligibleCreator: async () => {
        calls += 1;
        return { cleared: true };
      },
    },
  );
  assert.deepEqual(outcome, { cleared: false, deferred: true });
  assert.equal(calls, 0);
});

test("authorId change asks cleanup for the old author only", async () => {
  const calls = [];
  const snapshot = (data) => ({ exists: true, data: () => data });
  const outcome = await handlePinnedMomentEligibilityChanged(
    {
      params: { momentId: MOMENT },
      data: {
        before: snapshot(canonicalMoment(CREATOR)),
        after: snapshot(canonicalMoment(OTHER)),
      },
    },
    {
      clearDeletedMomentPin: async (momentId, creatorId) => {
        calls.push({ momentId, creatorId });
        return { cleared: true, creatorId };
      },
    },
  );
  assert.deepEqual(calls, [{ momentId: MOMENT, creatorId: CREATOR }]);
  assert.deepEqual(outcome, { cleared: true });
});
