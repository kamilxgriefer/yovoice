const assert = require("node:assert/strict");
const { after, beforeEach, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-display-name-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  DISPLAY_NAME_COOLDOWN_MS,
  DISPLAY_NAME_RATE_LIMIT,
  createDisplayNameService,
  syncAuthDisplayName,
} = require("../profile/display_name");
const {
  CANONICAL_DISPLAY_NAME_MAX,
  canonicalPublicProfile,
  rateLimitReference,
} = require("../integrity/guards");
const { derivePublicProfile } = require("../profile/public_profiles");

const db = getFirestore();
const UID = "display-name-user";
const OPAQUE_UID = "display name użytkownik";
let nowMs = 1_825_000_000_000;

function callableRequest({
  uid = UID,
  displayName = "New Voice",
  data = undefined,
  verified = true,
} = {}) {
  return {
    auth: uid === null
      ? null
      : {
          uid,
          token: { email_verified: verified },
        },
    data: data === undefined ? { displayName } : data,
  };
}

function service(
  syncAuthDisplayName = async () => {},
  { rateLimit = DISPLAY_NAME_RATE_LIMIT } = {},
) {
  return createDisplayNameService({
    firestore: db,
    TimestampImpl: Timestamp,
    clock: () => nowMs,
    syncAuthDisplayName,
    rateLimit,
  });
}

async function remove(reference) {
  await reference.delete().catch(() => {});
}

async function reset() {
  const rateRef = rateLimitReference(db, "profile.displayName", UID);
  const opaqueRateRef = rateLimitReference(
    db,
    "profile.displayName",
    OPAQUE_UID,
  );
  await Promise.all([
    remove(db.collection("users").doc(UID)),
    remove(db.collection("users").doc(OPAQUE_UID)),
    remove(rateRef),
    remove(opaqueRateRef),
  ]);
}

async function seed(uid = UID, overrides = {}) {
  await db.collection("users").doc(uid).set({
    uid,
    displayName: "Original Voice",
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

test("Auth sync reads first and writes only when the mirror differs", async () => {
  const writes = [];
  const equalAuth = {
    getUser: async (uid) => ({ uid, displayName: "Canonical Voice" }),
    updateUser: async (...arguments_) => writes.push(arguments_),
  };
  await syncAuthDisplayName(equalAuth, UID, "Canonical Voice");
  assert.deepEqual(writes, []);

  const staleAuth = {
    getUser: async (uid) => ({ uid, displayName: "Stale Voice" }),
    updateUser: async (...arguments_) => writes.push(arguments_),
  };
  await syncAuthDisplayName(staleAuth, UID, "Canonical Voice");
  assert.deepEqual(writes, [[UID, { displayName: "Canonical Voice" }]]);
});

test("a verified active account changes its canonical name and starts 30 days", async () => {
  const authWrites = [];
  const result = await service(async (uid, displayName) => {
    authWrites.push({ uid, displayName });
  }).updateMyDisplayName(callableRequest({ displayName: "  New Voice  " }));

  assert.deepEqual(result, {
    displayName: "New Voice",
    changed: true,
    displayNameChangedAtMs: nowMs,
    nextDisplayNameChangeAtMs: nowMs + DISPLAY_NAME_COOLDOWN_MS,
    canChange: false,
  });
  assert.deepEqual(authWrites, [{ uid: UID, displayName: "New Voice" }]);

  const profile = (await db.collection("users").doc(UID).get()).data();
  assert.equal(profile.displayName, "New Voice");
  assert.equal(profile.displayNameChangedAt.toMillis(), nowMs);
  assert.equal(profile.profileUpdatedAt.toMillis(), nowMs);
});

test("same-name retry repairs Auth after a transient failure without moving cooldown", async () => {
  let attempts = 0;
  const api = service(async () => {
    attempts += 1;
    if (attempts === 1) throw new Error("transient Auth failure");
  });

  await assert.rejects(
    api.updateMyDisplayName(callableRequest()),
    (error) => {
      assert.equal(error.code, "unavailable");
      assert.deepEqual(error.details, {
        reason: "auth-display-name-sync-pending",
        displayName: "New Voice",
        displayNameChangedAtMs: nowMs,
        nextDisplayNameChangeAtMs: nowMs + DISPLAY_NAME_COOLDOWN_MS,
      });
      return true;
    },
  );
  const first = (await db.collection("users").doc(UID).get()).data();

  nowMs += 10_000;
  assert.deepEqual(await api.updateMyDisplayName(callableRequest()), {
    displayName: "New Voice",
    changed: false,
    displayNameChangedAtMs: first.displayNameChangedAt.toMillis(),
    nextDisplayNameChangeAtMs:
      first.displayNameChangedAt.toMillis() + DISPLAY_NAME_COOLDOWN_MS,
    canChange: false,
  });
  const replay = (await db.collection("users").doc(UID).get()).data();
  assert.equal(replay.displayNameChangedAt.toMillis(), first.displayNameChangedAt.toMillis());
  assert.equal(replay.profileUpdatedAt.toMillis(), first.profileUpdatedAt.toMillis());
  assert.equal(attempts, 2);
});

test("server-time quota serializes bursts and still permits one Auth retry", async () => {
  let authAttempts = 0;
  const api = service(
    async () => {
      authAttempts += 1;
      if (authAttempts === 1) throw new Error("transient Auth failure");
    },
    { rateLimit: { maxEvents: 2, windowMs: 1_000 } },
  );

  await assert.rejects(
    api.updateMyDisplayName(callableRequest()),
    (error) => error.code === "unavailable",
  );
  assert.equal(
    (await api.updateMyDisplayName(callableRequest())).changed,
    false,
  );
  await assert.rejects(
    api.updateMyDisplayName(callableRequest()),
    (error) => error.code === "resource-exhausted",
  );
  assert.equal(authAttempts, 2);

  nowMs += 1_000;
  assert.equal(
    (await api.updateMyDisplayName(callableRequest())).changed,
    false,
  );
  assert.equal(authAttempts, 3);
});

test("concurrent same-name burst cannot overrun the private quota", async () => {
  const api = service(
    async () => {},
    { rateLimit: { maxEvents: 2, windowMs: 1_000 } },
  );
  const outcomes = await Promise.allSettled([
    api.updateMyDisplayName(
      callableRequest({ displayName: "Original Voice" }),
    ),
    api.updateMyDisplayName(
      callableRequest({ displayName: "Original Voice" }),
    ),
    api.updateMyDisplayName(
      callableRequest({ displayName: "Original Voice" }),
    ),
  ]);

  assert.equal(outcomes.filter((item) => item.status === "fulfilled").length, 2);
  const rejected = outcomes.filter((item) => item.status === "rejected");
  assert.equal(rejected.length, 1);
  assert.equal(rejected[0].reason.code, "resource-exhausted");
});

test("rejected profile decisions still consume quota but local validation does not", async () => {
  const changedAtMs = nowMs - 1_000;
  await db.collection("users").doc(UID).update({
    displayNameChangedAt: Timestamp.fromMillis(changedAtMs),
  });
  const api = service(
    async () => {},
    { rateLimit: { maxEvents: 2, windowMs: 1_000 } },
  );

  await assert.rejects(
    api.updateMyDisplayName(callableRequest({ displayName: "x" })),
    (error) => error.code === "invalid-argument",
  );
  for (const displayName of ["First Refused", "Second Refused"]) {
    await assert.rejects(
      api.updateMyDisplayName(callableRequest({ displayName })),
      (error) =>
        error.code === "failed-precondition" &&
        error.details.reason === "display-name-cooldown",
    );
  }
  await assert.rejects(
    api.updateMyDisplayName(callableRequest({ displayName: "Third Refused" })),
    (error) => error.code === "resource-exhausted",
  );
});

test("cooldown fails with an exact retry time and unlocks at the boundary", async () => {
  const changedAtMs = nowMs - (DISPLAY_NAME_COOLDOWN_MS - 1_500);
  await db.collection("users").doc(UID).update({
    displayNameChangedAt: Timestamp.fromMillis(changedAtMs),
  });

  await assert.rejects(
    service().updateMyDisplayName(callableRequest()),
    (error) => {
      assert.equal(error.code, "failed-precondition");
      assert.deepEqual(error.details, {
        reason: "display-name-cooldown",
        nextDisplayNameChangeAtMs: changedAtMs + DISPLAY_NAME_COOLDOWN_MS,
        retryAfterSeconds: 2,
      });
      return true;
    },
  );
  assert.equal(
    (await db.collection("users").doc(UID).get()).data().displayName,
    "Original Voice",
  );

  nowMs = changedAtMs + DISPLAY_NAME_COOLDOWN_MS;
  const result = await service().updateMyDisplayName(callableRequest());
  assert.equal(result.changed, true);
  assert.equal(result.displayNameChangedAtMs, nowMs);
});

test("concurrent different names serialize and only one wins the window", async () => {
  const api = service();
  const outcomes = await Promise.allSettled([
    api.updateMyDisplayName(callableRequest({ displayName: "First Voice" })),
    api.updateMyDisplayName(callableRequest({ displayName: "Second Voice" })),
  ]);
  assert.equal(outcomes.filter((item) => item.status === "fulfilled").length, 1);
  assert.equal(outcomes.filter((item) => item.status === "rejected").length, 1);
  const rejected = outcomes.find((item) => item.status === "rejected");
  assert.equal(rejected.reason.code, "failed-precondition");
  assert.equal(rejected.reason.details.reason, "display-name-cooldown");

  const stored = (await db.collection("users").doc(UID).get()).data();
  assert.ok(["First Voice", "Second Voice"].includes(stored.displayName));
  assert.equal(stored.displayNameChangedAt.toMillis(), nowMs);
});

test("legacy profiles may change immediately and unchanged legacy state stays available", async () => {
  assert.deepEqual(
    await service().updateMyDisplayName(
      callableRequest({ displayName: "Original Voice" }),
    ),
    {
      displayName: "Original Voice",
      changed: false,
      displayNameChangedAtMs: null,
      nextDisplayNameChangeAtMs: null,
      canChange: true,
    },
  );
  assert.equal(
    (await service().updateMyDisplayName(callableRequest())).changed,
    true,
  );
});

test("trimming a legacy stored name is a real canonical change", async () => {
  await db.collection("users").doc(UID).update({
    displayName: "  New Voice  ",
  });

  const result = await service().updateMyDisplayName(callableRequest());
  assert.equal(result.changed, true);
  assert.equal(result.displayNameChangedAtMs, nowMs);

  const profile = (await db.collection("users").doc(UID).get()).data();
  assert.equal(profile.displayName, "New Voice");
  assert.equal(profile.displayNameChangedAt.toMillis(), nowMs);
});

test("opaque Auth UIDs and visible Unicode display names are preserved", async () => {
  await seed(OPAQUE_UID);
  const result = await service().updateMyDisplayName(
    callableRequest({ uid: OPAQUE_UID, displayName: "Głos 🙂" }),
  );
  assert.equal(result.displayName, "Głos 🙂");
  assert.equal(
    (await db.collection("users").doc(OPAQUE_UID).get()).data().displayName,
    "Głos 🙂",
  );
});

test("payload, Unicode length and invisible controls are validated exactly", async () => {
  const invalidRequests = [
    callableRequest({ data: null }),
    callableRequest({ data: [] }),
    callableRequest({ data: { displayName: "Valid", extra: true } }),
    callableRequest({ data: { displayName: 123 } }),
    callableRequest({ displayName: "x" }),
    callableRequest({ displayName: "x".repeat(121) }),
    callableRequest({ displayName: "Line\nBreak" }),
    callableRequest({ displayName: "Zero\u200bWidth" }),
    callableRequest({ displayName: "A\u2028B" }),
  ];
  for (const request of invalidRequests) {
    await assert.rejects(
      service().updateMyDisplayName(request),
      (error) => error.code === "invalid-argument",
    );
  }

  const emojiName = "🙂".repeat(120);
  const result = await service().updateMyDisplayName(
    callableRequest({ displayName: emojiName }),
  );
  assert.equal([...result.displayName].length, 120);
});

test("authentication, verification, profile existence and active state fail closed", async () => {
  await assert.rejects(
    service().updateMyDisplayName(callableRequest({ uid: null })),
    (error) => error.code === "unauthenticated",
  );
  await assert.rejects(
    service().updateMyDisplayName(callableRequest({ verified: false })),
    (error) => {
      assert.equal(error.code, "failed-precondition");
      assert.deepEqual(error.details, {
        reason: "email-verification-required",
      });
      return true;
    },
  );

  await remove(db.collection("users").doc(UID));
  await assert.rejects(
    service().updateMyDisplayName(callableRequest()),
    (error) => error.code === "not-found",
  );

  for (const inactive of [
    { banned: true },
    { disabled: true },
    { deleted: true },
    { status: "deleted" },
  ]) {
    await seed(UID, inactive);
    await assert.rejects(
      service().updateMyDisplayName(callableRequest()),
      (error) => error.code === "permission-denied",
    );
  }
});

test("malformed server-owned cooldown fails closed", async () => {
  await db.collection("users").doc(UID).update({
    displayNameChangedAt: "client-shaped timestamp",
  });
  await assert.rejects(
    service().updateMyDisplayName(callableRequest()),
    (error) => {
      assert.equal(error.code, "failed-precondition");
      assert.deepEqual(error.details, {
        reason: "display-name-state-invalid",
      });
      return true;
    },
  );
  assert.equal(
    (await db.collection("users").doc(UID).get()).data().displayName,
    "Original Voice",
  );
});

test("a missing Auth account is surfaced without rolling back canonical Firestore", async () => {
  const missing = Object.assign(new Error("missing"), {
    code: "auth/user-not-found",
  });
  await assert.rejects(
    service(async () => {
      throw missing;
    }).updateMyDisplayName(callableRequest()),
    (error) => {
      assert.equal(error.code, "failed-precondition");
      assert.deepEqual(error.details, {
        reason: "auth-account-missing",
        displayName: "New Voice",
        displayNameChangedAtMs: nowMs,
        nextDisplayNameChangeAtMs: nowMs + DISPLAY_NAME_COOLDOWN_MS,
      });
      return true;
    },
  );
  assert.equal(
    (await db.collection("users").doc(UID).get()).data().displayName,
    "New Voice",
  );
});

// RC-8. `canonicalPublicProfile` accepts a display name of 1-120 characters and
// stores `slice(0, 80)` of it. For a name whose 80th character is whitespace
// that cut used to produce an UNTRIMMED string, and the strict readers of the
// value it writes — validateReservation, validatePublishedReel and
// validateReelVoiceCommentReservation — all assert `value === value.trim()` and
// refuse with `data-loss` otherwise. The reservation was written successfully
// and every later finalize of that draft failed forever.
function canonicalProfileSnapshot(uid, displayName) {
  return {
    exists: true,
    data: () => ({
      accountType: "personal",
      bannerUrl: null,
      bio: "",
      country: "",
      creatorAudienceVisible: false,
      displayName,
      displayNameSearch: displayName.toLowerCase(),
      followerCount: 0,
      followingCount: 0,
      friendCount: 0,
      learningLanguages: [],
      nativeLanguage: "",
      photoUrl: null,
      premiumIdentity: false,
      schemaVersion: 1,
      spokenLanguages: [],
      statusMessage: "",
      uid,
      updatedAt: Timestamp.fromMillis(1_825_000_000_000),
      username: uid,
      usernameSearch: uid,
      website: null,
    }),
  };
}

test("an 81-120 character display name still yields a trimmed canonical name",
  () => {
    assert.equal(CANONICAL_DISPLAY_NAME_MAX, 80);
    const names = [
      // The 80th character is the only space, so the cut lands on it.
      `${"A".repeat(79)} ${"B".repeat(20)}`,
      // A run of spaces straddling the cut.
      `${"A".repeat(70)}${" ".repeat(20)}${"B".repeat(30)}`,
      // Exactly 81 characters with the 80th a space.
      `${"A".repeat(79)} B`,
    ];
    for (const displayName of names) {
      assert.equal(displayName, displayName.trim());
      assert.ok(displayName.length > 80 && displayName.length <= 120);

      const identity = canonicalPublicProfile(
        canonicalProfileSnapshot(UID, displayName),
        UID,
      );
      // The exact invariant every strict reader asserts on the stored value.
      assert.equal(identity.displayName, identity.displayName.trim());
      assert.ok(identity.displayName.length >= 1);
      assert.ok(identity.displayName.length <= 80);
      assert.equal(identity.photoUrl, null);
    }
  });

test("an 80-character or shorter canonical name is returned unchanged", () => {
  for (const displayName of [
    "Ada",
    "A".repeat(80),
    `${"A".repeat(40)} ${"B".repeat(39)}`,
    "Głos 🙂",
  ]) {
    assert.equal(
      canonicalPublicProfile(
        canonicalProfileSnapshot(UID, displayName),
        UID,
      ).displayName,
      displayName,
    );
  }
});

// Gate blocker G-1 (SEC-1). `updateMyDisplayName` bounds a name at 120 Unicode
// CODE POINTS; `derivePublicProfile` — the single writer of
// `publicProfiles.displayName` — cuts at 120 UTF-16 CODE UNITS. One astral
// character costs two units, so the writer's cut can land on a space inside a
// name a user may legitimately set, and `canonicalPublicProfile` used to refuse
// the result outright with `data-loss` BEFORE `canonicalStoredDisplayName` ever
// ran. That refusal is permanent for the account and reaches every consumer of
// the guard: reserveReelDraftV2/finalizeReelDraftV2, openDirectConversation
// (which canonicalises BOTH parties, so nobody can start a chat with them) and
// the Voice Moments feed's per-item swallow (their Moments simply vanish).
const BREAKING_DISPLAY_NAME = `${"😀".repeat(10)}${"B".repeat(99)} 😀`;

test("a display name a user may set today survives its own projection", () => {
  assert.equal([...BREAKING_DISPLAY_NAME].length, 111);
  assert.equal(BREAKING_DISPLAY_NAME.length, 122);
  assert.equal(BREAKING_DISPLAY_NAME, BREAKING_DISPLAY_NAME.trim());

  // Exactly what the writer stored before this round: trim, then cut at 120
  // UTF-16 units. Rows in this shape may already exist, so the READER has to
  // repair them — a writer-only fix would need a backfill.
  const legacyProjection = BREAKING_DISPLAY_NAME.trim().slice(0, 120);
  assert.equal(legacyProjection.length, 120);
  assert.equal(legacyProjection.charCodeAt(119), 0x20);
  assert.notEqual(legacyProjection, legacyProjection.trim());

  const identity = canonicalPublicProfile(
    canonicalProfileSnapshot(UID, legacyProjection),
    UID,
  );
  assert.equal(identity.displayName, `${"😀".repeat(10)}${"B".repeat(60)}`);
  assert.equal(identity.displayName, identity.displayName.trim());
  assert.equal(identity.displayName.length, CANONICAL_DISPLAY_NAME_MAX);

  // And the writer no longer produces a projection in that shape at all.
  const projected = derivePublicProfile(UID, {
    displayName: BREAKING_DISPLAY_NAME,
    username: UID,
  });
  assert.equal(projected.displayName, projected.displayName.trim());
  assert.ok(projected.displayName.length <= 120);
  assert.equal(
    canonicalPublicProfile(
      canonicalProfileSnapshot(UID, projected.displayName),
      UID,
    ).displayName,
    identity.displayName,
  );
});

// SEC-8, closed in the same edit. Both cuts are measured in UTF-16 units, so
// either can fall between a surrogate pair. The lone high surrogate that leaves
// is not representable in UTF-8: @protobufjs/utf8 (the encoder under the
// Firestore client) writes replacement bytes for it, so the value the guard
// checked is not the value the row would hold, and the next read refuses.
test("neither canonical cut ever splits a surrogate pair", () => {
  // "A" plus 40 astral characters is 81 UTF-16 units, so the 80-unit cut lands
  // between the 40th character's high and low surrogate.
  const eightyUnitSplit = `A${"😀".repeat(40)}`;
  assert.equal(eightyUnitSplit.length, 81);
  // 61 astral characters is 122 units, so the writer's 120-unit cut splits the
  // 61st the same way.
  const oneTwentyUnitSplit = "😀".repeat(61);
  assert.equal(oneTwentyUnitSplit.length, 122);

  for (const raw of [eightyUnitSplit, oneTwentyUnitSplit]) {
    const projected = derivePublicProfile(UID, {
      displayName: raw,
      username: UID,
    }).displayName;
    const canonical = canonicalPublicProfile(
      canonicalProfileSnapshot(UID, projected),
      UID,
    ).displayName;
    for (const value of [projected, canonical]) {
      assert.ok(value.length >= 1);
      // A lone surrogate does not survive a UTF-8 round trip; a whole code
      // point does. This is the property the Firestore encoder depends on.
      assert.equal(
        Buffer.from(value, "utf8").toString("utf8"),
        value,
        `lone surrogate in ${JSON.stringify(value)}`,
      );
      assert.equal([...value].join(""), value);
    }
  }
  assert.equal(
    canonicalPublicProfile(
      canonicalProfileSnapshot(UID, eightyUnitSplit),
      UID,
    ).displayName,
    `A${"😀".repeat(39)}`,
  );
});
