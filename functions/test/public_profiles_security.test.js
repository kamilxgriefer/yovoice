const assert = require("node:assert/strict");
const { createHash } = require("node:crypto");
const { test, beforeEach, describe } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "demo-yovoice";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  PUBLIC_PROFILE_FIELDS,
  SOCIAL_PRESENCE_FIELDS,
  derivePublicProfile,
  canonicalUid,
  syncPrivacyProjectionsForUser,
  handleAuthUserDeleted,
  onAuthUserDeleted,
  onUserPrivacySourceChanged,
  searchPublicProfiles,
  consumeSearchRateLimit,
  SEARCH_MINUTE_MS,
} = require("../profile/public_profiles");
const { backfill } = require("../scripts/backfill_public_profiles");
const {
  applyEntitlements,
  commitExpiredPremiumPage,
} = require("../premium/entitlements");

const db = getFirestore();
const runSearch = searchPublicProfiles.run ?? searchPublicProfiles;
const P = "pp-security-";
const CALLER = `${P}caller`;
const VISIBLE = `${P}visible`;
const BLOCKED = `${P}blocked`;
const REVERSE_BLOCKED = `${P}reverse-blocked`;

function syncExistingAuthUser(uid, options = {}) {
  return syncPrivacyProjectionsForUser(uid, {
    authUser: { uid },
    ...options,
  });
}

function rateLimitId(uid) {
  return `searchPublicProfiles_${createHash("sha256").update(uid).digest("hex")}`;
}

async function wipe() {
  const uids = [
    CALLER,
    VISIBLE,
    BLOCKED,
    REVERSE_BLOCKED,
    `${P}inactive`,
    `${P}creator`,
    `${P}official`,
  ];
  const backfillUsers = [`${P}backfill-a`, `${P}backfill-b`];
  const unrelatedBlocked = Array.from(
    { length: 75 },
    (_, index) => `${P}unrelated-${index}`,
  );
  await Promise.all([
    ...[...uids, ...backfillUsers].flatMap((uid) => [
      db.collection("users").doc(uid).delete(),
      db.collection("publicProfiles").doc(uid).delete(),
      db.collection("socialPresence").doc(uid).delete(),
      db.collection("entitlements").doc(uid).delete(),
      db
        .collection("users")
        .doc(CALLER)
        .collection("blocked")
        .doc(uid)
        .delete(),
      db
        .collection("users")
        .doc(uid)
        .collection("blocked")
        .doc(CALLER)
        .delete(),
      db.collection("privateRateLimits").doc(rateLimitId(uid)).delete(),
    ]),
    ...unrelatedBlocked.map((uid) =>
      db
        .collection("users")
        .doc(CALLER)
        .collection("blocked")
        .doc(uid)
        .delete(),
    ),
  ]);
}

beforeEach(wipe);

describe("public profile derivation", () => {
  test("keeps canonical uid bytes and rejects aliases instead of normalizing", () => {
    assert.equal(canonicalUid("Case Sensitive UID "), "Case Sensitive UID ");
    assert.equal(canonicalUid(""), null);
    assert.equal(canonicalUid("a/b"), null);
    assert.equal(canonicalUid("x".repeat(129)), null);
  });

  test("publishes an exact safe schema and excludes every private field", () => {
    const profile = derivePublicProfile(VISIBLE, {
      email: "private@example.com",
      displayName: " Visible Voice ",
      username: "VisibleVoice",
      photoUrl: "https://cdn.example/avatar.jpg",
      bannerUrl: "javascript:alert(1)",
      bio: "Hello",
      country: "Poland",
      nativeLanguage: "Polish",
      spokenLanguages: ["English", "English", 42],
      learningLanguages: ["Spanish"],
      website: "https://example.com",
      statusMessage: "Voice first",
      accountType: "creator",
      premiumIdentity: true,
      friendCount: 4,
      followerCount: 8,
      followingCount: 2,
      isOnline: true,
      lastSeen: Timestamp.now(),
      notificationPreferences: { directMessage: false },
      role: "superAdmin",
      banned: false,
      disabled: false,
      fcmTokens: ["secret"],
    });

    assert.ok(profile);
    assert.deepEqual(
      Object.keys(profile).sort(),
      [...PUBLIC_PROFILE_FIELDS].filter((key) => key !== "updatedAt").sort(),
    );
    assert.equal(profile.displayName, "Visible Voice");
    assert.equal(profile.bannerUrl, null);
    assert.equal(
      derivePublicProfile(VISIBLE, {
        displayName: "Visible Voice",
        photoUrl: "http://cdn.example/avatar.jpg",
        website: "http://example.com",
      }).photoUrl,
      null,
    );
    assert.equal(
      derivePublicProfile(VISIBLE, {
        displayName: "Visible Voice",
        photoUrl: "http://cdn.example/avatar.jpg",
        website: "http://example.com",
      }).website,
      null,
    );
    assert.deepEqual(profile.spokenLanguages, ["English"]);
    for (const forbidden of [
      "email",
      "isOnline",
      "lastSeen",
      "notificationPreferences",
      "role",
      "banned",
      "disabled",
      "fcmTokens",
    ]) {
      assert.equal(forbidden in profile, false, forbidden);
    }
  });

  test("inactive and deleted accounts have no public projection", () => {
    assert.equal(derivePublicProfile(VISIBLE, null), null);
    assert.equal(derivePublicProfile(VISIBLE, { banned: true }), null);
    assert.equal(derivePublicProfile(VISIBLE, { disabled: true }), null);
  });
});

describe("privacy projection trigger", () => {
  test("is retryable and converges to exact profile/presence documents", async () => {
    assert.equal(
      onUserPrivacySourceChanged.__endpoint.eventTrigger.retry,
      true,
    );
    const lastSeen = Timestamp.fromMillis(1_770_000_000_000);
    await db
      .collection("users")
      .doc(VISIBLE)
      .set({
        email: "never-publish@example.com",
        displayName: "Visible Voice",
        username: "visible",
        bio: "Public bio",
        isOnline: true,
        lastSeen,
        role: "moderator",
        notificationPreferences: { directMessage: false },
      });
    await db.collection("publicProfiles").doc(VISIBLE).set({
      displayName: "stale",
      email: "leaked@example.com",
      updatedAt: Timestamp.now(),
    });

    const outcome = await syncExistingAuthUser(VISIBLE);
    assert.equal(outcome.profile, "updated");
    assert.equal(outcome.presence, "created");

    const [profileSnapshot, presenceSnapshot] = await db.getAll(
      db.collection("publicProfiles").doc(VISIBLE),
      db.collection("socialPresence").doc(VISIBLE),
    );
    const profile = profileSnapshot.data();
    const presence = presenceSnapshot.data();
    assert.deepEqual(
      Object.keys(profile).sort(),
      [...PUBLIC_PROFILE_FIELDS].sort(),
    );
    assert.deepEqual(
      Object.keys(presence).sort(),
      [...SOCIAL_PRESENCE_FIELDS].sort(),
    );
    assert.equal("email" in profile, false);
    assert.equal("role" in profile, false);
    assert.equal("isOnline" in profile, false);
    assert.equal(presence.isOnline, true);
    assert.equal(presence.lastSeen.toMillis(), lastSeen.toMillis());

    const replay = await syncExistingAuthUser(VISIBLE);
    assert.equal(replay.profile, "unchanged");
    assert.equal(replay.presence, "unchanged");
  });

  test("ban or disable removes both projections idempotently", async () => {
    await db.collection("users").doc(VISIBLE).set({
      displayName: "Visible Voice",
      banned: false,
    });
    await syncExistingAuthUser(VISIBLE);
    await db.collection("users").doc(VISIBLE).update({ banned: true });
    const first = await syncExistingAuthUser(VISIBLE);
    const replay = await syncExistingAuthUser(VISIBLE);
    assert.equal(first.profile, "removed");
    assert.equal(first.presence, "removed");
    assert.equal(replay.profile, "absent");
    assert.equal(replay.presence, "absent");
  });

  test("an Auth-disabled account cannot retain or recreate projections", async () => {
    await db.collection("users").doc(VISIBLE).set({
      displayName: "Disabled in Auth",
      banned: false,
      disabled: false,
      isOnline: true,
    });
    await syncExistingAuthUser(VISIBLE);

    const outcome = await syncPrivacyProjectionsForUser(VISIBLE, {
      database: db,
      authUser: { uid: VISIBLE, disabled: true },
    });
    assert.equal(outcome.profile, "removed");
    assert.equal(outcome.presence, "removed");
  });

  test("an older sync cannot overwrite a newer source revision", async () => {
    let markFirstRead;
    const firstRead = new Promise((resolve) => {
      markFirstRead = resolve;
    });
    let releaseFirst;
    const release = new Promise((resolve) => {
      releaseFirst = resolve;
    });
    let paused = false;

    await db.collection("users").doc(VISIBLE).set({
      displayName: "Revision one",
      bio: "Old bio",
      isOnline: true,
    });
    const olderSync = syncExistingAuthUser(VISIBLE, {
      database: db,
      afterRead: async () => {
        if (paused) return;
        paused = true;
        markFirstRead();
        await release;
      },
    });
    await firstRead;

    const sourceUpdate = db.collection("users").doc(VISIBLE).update({
      displayName: "Revision two",
      bio: "Current bio",
      isOnline: false,
    });
    releaseFirst();
    await Promise.all([sourceUpdate, olderSync]);
    await syncExistingAuthUser(VISIBLE, { database: db });

    const [profile, presence] = await db.getAll(
      db.collection("publicProfiles").doc(VISIBLE),
      db.collection("socialPresence").doc(VISIBLE),
    );
    assert.equal(profile.data().displayName, "Revision two");
    assert.equal(profile.data().bio, "Current bio");
    assert.equal(presence.data().isOnline, false);
  });

  test("Auth deletion immediately retires every identity projection", async () => {
    assert.equal(onAuthUserDeleted.__endpoint.eventTrigger.retry, true);
    await db.collection("users").doc(VISIBLE).set({
      displayName: "Deleted Auth account",
      isOnline: true,
    });
    await Promise.all([
      db.collection("publicProfiles").doc(VISIBLE).set({ uid: VISIBLE }),
      db.collection("socialPresence").doc(VISIBLE).set({ uid: VISIBLE }),
      db.collection("publicBadges").doc(VISIBLE).set({ staffRole: "user" }),
      db.collection("userDirectory").doc(VISIBLE).set({ email: "old@invalid" }),
      db.collection("marketingConsents").doc(VISIBLE).set({
        schemaVersion: 1,
        showProfileOnWebsite: true,
        showActivityOnWebsite: true,
      }),
    ]);

    const outcome = await handleAuthUserDeleted(VISIBLE, { database: db });
    assert.equal(outcome.outcome, "retired");
    const [source, profile, presence, badge, directory, marketingConsent] =
      await db.getAll(
        db.collection("users").doc(VISIBLE),
        db.collection("publicProfiles").doc(VISIBLE),
        db.collection("socialPresence").doc(VISIBLE),
        db.collection("publicBadges").doc(VISIBLE),
        db.collection("userDirectory").doc(VISIBLE),
        db.collection("marketingConsents").doc(VISIBLE),
      );
    assert.equal(source.data().disabled, true);
    assert.equal(source.data().isOnline, false);
    assert.ok(source.data().authDeletedAt);
    assert.equal(profile.exists, false);
    assert.equal(presence.exists, false);
    assert.equal(badge.exists, false);
    assert.equal(directory.exists, false);
    assert.equal(marketingConsent.exists, false);

    const replay = await syncPrivacyProjectionsForUser(VISIBLE, {
      database: db,
      authUser: null,
    });
    assert.equal(replay.profile, "absent");
    assert.equal(replay.presence, "absent");
  });
});

describe("public profile search", () => {
  async function seedSearchWorld() {
    await db.collection("users").doc(CALLER).set({
      displayName: "Caller",
      banned: false,
    });
    for (const [uid, displayName, username] of [
      [VISIBLE, "Voice Friend", "voice.friend"],
      [BLOCKED, "Voice Blocked", "voice.blocked"],
      [REVERSE_BLOCKED, "Voice Hidden", "voice.hidden"],
    ]) {
      await db.collection("users").doc(uid).set({
        displayName,
        username,
        banned: false,
      });
      await db
        .collection("publicProfiles")
        .doc(uid)
        .set({
          ...derivePublicProfile(uid, {
            displayName,
            username,
            photoUrl: "https://cdn.example/avatar.jpg",
            email: `${uid}@private.invalid`,
            isOnline: true,
            role: "moderator",
          }),
          updatedAt: Timestamp.now(),
          // Even a poisoned stored projection must not widen the response.
          email: `${uid}@leaked.invalid`,
          role: "moderator",
        });
    }
    await Promise.all([
      db
        .collection("users")
        .doc(CALLER)
        .collection("blocked")
        .doc(BLOCKED)
        .set({}),
      db
        .collection("users")
        .doc(REVERSE_BLOCKED)
        .collection("blocked")
        .doc(CALLER)
        .set({}),
    ]);
  }

  test("returns bounded name/username prefixes, filters blocks, never email", async () => {
    await seedSearchWorld();
    const response = await runSearch({
      auth: { uid: CALLER, token: { email_verified: true } },
      data: { query: "@voice", limit: 20 },
    });
    assert.equal(response.profiles.length, 1);
    assert.deepEqual(response.profiles[0], {
      uid: VISIBLE,
      displayName: "Voice Friend",
      username: "voice.friend",
      photoUrl: "https://cdn.example/avatar.jpg",
      bio: "",
      statusMessage: "",
      accountType: "personal",
      premiumIdentity: false,
      followerCount: 0,
    });
  });

  test("creator directory returns only requested canonical account types", async () => {
    await seedSearchWorld();
    await Promise.all([
      db.collection("users").doc(`${P}creator`).set({
        displayName: "Voice Creator",
        username: "voice.creator",
        accountType: "creator",
        banned: false,
      }),
      db.collection("users").doc(`${P}official`).set({
        displayName: "Voice Official",
        username: "voice.official",
        accountType: "official",
        banned: false,
      }),
    ]);
    await db.collection("entitlements").doc(`${P}creator`).set({
      status: "active",
      isPremium: true,
      creatorEnabled: true,
      premiumIdentityEnabled: true,
      currentPeriodEnd: Timestamp.fromMillis(Date.now() + 60_000),
    });
    await Promise.all([
      db.collection("publicProfiles").doc(`${P}creator`).set(
        derivePublicProfile(`${P}creator`, {
          displayName: "Voice Creator",
          username: "voice.creator",
          accountType: "creator",
          bio: "Makes rooms about design.",
          followerCount: 12,
        }),
      ),
      db.collection("publicProfiles").doc(`${P}official`).set(
        derivePublicProfile(`${P}official`, {
          displayName: "Voice Official",
          username: "voice.official",
          accountType: "official",
        }),
      ),
    ]);

    const response = await runSearch({
      auth: { uid: CALLER, token: { email_verified: true } },
      data: {
        query: "voice",
        limit: 20,
        accountTypes: ["creator", "official"],
      },
    });

    assert.deepEqual(
      response.profiles.map((profile) => profile.accountType).sort(),
      ["creator", "official"],
    );
    assert.equal(
      response.profiles.some((profile) => profile.uid === VISIBLE),
      false,
    );
    const creator = response.profiles.find(
      (profile) => profile.uid === `${P}creator`,
    );
    assert.equal(creator.bio, "Makes rooms about design.");
    assert.equal(creator.followerCount, 12);

    await assert.rejects(
      runSearch({
        auth: { uid: CALLER, token: { email_verified: true } },
        data: { query: "voice", accountTypes: ["creator", "staff"] },
      }),
      (error) => error.code === "invalid-argument",
    );
  });

  test("creator directory fails closed for stale identity and expired Premium", async () => {
    await seedSearchWorld();
    const staleCreator = `${P}creator`;
    const staleOfficial = `${P}official`;
    await Promise.all([
      db.collection("users").doc(staleCreator).set({
        displayName: "Voice Former Creator",
        username: "voice.former.creator",
        accountType: "creator",
        premiumIdentity: true,
        banned: false,
      }),
      db.collection("users").doc(staleOfficial).set({
        displayName: "Voice Former Official",
        username: "voice.former.official",
        accountType: "personal",
        banned: false,
      }),
      db.collection("entitlements").doc(staleCreator).set({
        status: "expired",
        isPremium: false,
        creatorEnabled: false,
        premiumIdentityEnabled: false,
        currentPeriodEnd: Timestamp.fromMillis(Date.now() - 60_000),
      }),
      db.collection("publicProfiles").doc(staleCreator).set(
        derivePublicProfile(staleCreator, {
          displayName: "Voice Former Creator",
          username: "voice.former.creator",
          accountType: "creator",
          premiumIdentity: true,
        }),
      ),
      db.collection("publicProfiles").doc(staleOfficial).set(
        derivePublicProfile(staleOfficial, {
          displayName: "Voice Former Official",
          username: "voice.former.official",
          accountType: "official",
        }),
      ),
    ]);

    const response = await runSearch({
      auth: { uid: CALLER, token: { email_verified: true } },
      data: {
        query: "voice",
        accountTypes: ["creator", "official"],
      },
    });
    assert.equal(
      response.profiles.some(
        (profile) => profile.uid === staleCreator || profile.uid === staleOfficial,
      ),
      false,
    );

    await applyEntitlements(staleCreator, {
      plan: "none",
      status: "expired",
      currentPeriodEnd: Timestamp.now(),
      source: "test",
    });
    const downgraded = await db.collection("users").doc(staleCreator).get();
    assert.equal(downgraded.data().accountType, "personal");
    assert.equal(downgraded.data().premiumIdentity, false);
  });

  test("scheduled Premium expiry atomically removes Creator account mode", async () => {
    const uid = `${P}creator`;
    const now = Timestamp.now();
    await Promise.all([
      db.collection("users").doc(uid).set({
        accountType: "creator",
        premiumIdentity: true,
      }),
      db.collection("entitlements").doc(uid).set({
        status: "active",
        isPremium: true,
        creatorEnabled: true,
        canCreateClubs: true,
        premiumIdentityEnabled: true,
        currentPeriodEnd: Timestamp.fromMillis(now.toMillis() - 1),
      }),
    ]);
    const expired = await db.collection("entitlements").doc(uid).get();

    assert.equal(await commitExpiredPremiumPage([expired], { now }), 1);
    const [userAfter, entitlementAfter] = await Promise.all([
      db.collection("users").doc(uid).get(),
      db.collection("entitlements").doc(uid).get(),
    ]);
    assert.equal(userAfter.data().accountType, "personal");
    assert.equal(userAfter.data().premiumIdentity, false);
    assert.equal(entitlementAfter.data().isPremium, false);
    assert.equal(entitlementAfter.data().creatorEnabled, false);
  });

  test("does not enumerate an attacker-inflated block list", async () => {
    await seedSearchWorld();
    const unrelatedWrites = [];
    for (let index = 0; index < 75; index += 1) {
      unrelatedWrites.push(
        db
          .collection("users")
          .doc(CALLER)
          .collection("blocked")
          .doc(`${P}unrelated-${index}`)
          .set({ createdAt: Timestamp.now() }),
      );
    }
    await Promise.all(unrelatedWrites);

    const response = await runSearch({
      auth: { uid: CALLER, token: { email_verified: true } },
      data: { query: "@voice", limit: 20 },
    });
    assert.deepEqual(
      response.profiles.map((profile) => profile.uid),
      [VISIBLE],
    );
  });

  test("inactive callers and unauthenticated callers fail closed", async () => {
    await db.collection("users").doc(`${P}inactive`).set({ banned: true });
    await assert.rejects(
      runSearch({
        auth: { uid: `${P}inactive`, token: {} },
        data: { query: "voice" },
      }),
      (error) => error.code === "permission-denied",
    );
    assert.equal(
      (
        await db
          .collection("privateRateLimits")
          .doc(rateLimitId(`${P}inactive`))
          .get()
      ).exists,
      true,
    );
    await assert.rejects(
      runSearch({ auth: null, data: { query: "voice" } }),
      (error) => error.code === "unauthenticated",
    );
  });

  test("an active but unverified caller cannot enumerate profiles", async () => {
    await seedSearchWorld();
    await assert.rejects(
      runSearch({
        auth: { uid: CALLER, token: { email_verified: false } },
        data: { query: "voice" },
      }),
      (error) => error.code === "failed-precondition",
    );
  });

  test("transactional quota rejects a concurrent burst and resets by server window", async () => {
    const now = Timestamp.fromMillis(1_770_000_000_000);
    const attempts = await Promise.allSettled([
      consumeSearchRateLimit(CALLER, { now, minuteLimit: 1, hourLimit: 3 }),
      consumeSearchRateLimit(CALLER, { now, minuteLimit: 1, hourLimit: 3 }),
    ]);
    assert.equal(
      attempts.filter((result) => result.status === "fulfilled").length,
      1,
    );
    const rejection = attempts.find((result) => result.status === "rejected");
    assert.equal(rejection.reason.code, "resource-exhausted");

    const reset = await consumeSearchRateLimit(CALLER, {
      now: Timestamp.fromMillis(now.toMillis() + SEARCH_MINUTE_MS),
      minuteLimit: 1,
      hourLimit: 3,
    });
    assert.deepEqual(reset, { minuteCount: 1, hourCount: 2 });
  });
});

describe("bounded public-profile backfill", () => {
  test("dry-run writes nothing and apply exposes a resumable cursor", async () => {
    for (const suffix of ["a", "b"]) {
      await db
        .collection("users")
        .doc(`${P}backfill-${suffix}`)
        .set({
          displayName: `Backfill ${suffix.toUpperCase()}`,
        });
    }
    const args = {
      apply: false,
      batchSize: 1,
      maxUsers: 1,
      startAfter: null,
      uidPrefix: `${P}backfill-`,
    };
    const fetchAuthUser = async (uid) => ({ uid });
    const dry = await backfill({ db, args, fetchAuthUser });
    assert.equal(dry.scannedUsers, 1);
    assert.equal(dry.appliedWrites, 0);
    assert.ok(dry.peakPlannedOperations <= 400);
    assert.ok(dry.nextCursor);
    assert.equal(
      (await db.collection("publicProfiles").doc(`${P}backfill-a`).get())
        .exists,
      false,
    );

    const first = await backfill({
      db,
      args: { ...args, apply: true },
      fetchAuthUser,
    });
    assert.equal(first.appliedWrites, 2);
    assert.ok(first.peakPlannedOperations <= 400);
    const second = await backfill({
      db,
      args: { ...args, apply: true, startAfter: first.nextCursor },
      fetchAuthUser,
    });
    assert.equal(second.appliedWrites, 2);
    assert.equal(
      (await db.collection("publicProfiles").doc(`${P}backfill-b`).get())
        .exists,
      true,
    );
  });

  test("apply re-reads source transactionally instead of committing a stale plan", async () => {
    const uid = `${P}backfill-a`;
    await db.collection("users").doc(uid).set({
      displayName: "Planned old name",
      bio: "Old bio",
    });
    let changed = false;
    await backfill({
      db,
      args: {
        apply: true,
        batchSize: 1,
        maxUsers: 1,
        startAfter: null,
        uidPrefix: `${P}backfill-`,
      },
      afterPagePlanned: async () => {
        if (changed) return;
        changed = true;
        await db.collection("users").doc(uid).update({
          displayName: "Current name",
          bio: "Current bio",
        });
        await syncExistingAuthUser(uid, { database: db });
      },
      fetchAuthUser: async (candidateUid) => ({ uid: candidateUid }),
    });

    const profile = await db.collection("publicProfiles").doc(uid).get();
    assert.equal(profile.data().displayName, "Current name");
    assert.equal(profile.data().bio, "Current bio");
  });

  test("backfill deletes projections for a Firestore user missing in Auth", async () => {
    const uid = `${P}backfill-a`;
    await Promise.all([
      db.collection("users").doc(uid).set({
        displayName: "Orphan source",
        banned: false,
      }),
      db.collection("publicProfiles").doc(uid).set({
        uid,
        displayName: "Stale public identity",
      }),
      db.collection("socialPresence").doc(uid).set({
        uid,
        isOnline: true,
      }),
    ]);

    const report = await backfill({
      db,
      args: {
        apply: true,
        batchSize: 1,
        maxUsers: 1,
        startAfter: null,
        uidPrefix: uid,
      },
      fetchAuthUser: async () => null,
    });
    assert.equal(report.authOrphans, 1);
    assert.equal(
      (await db.collection("publicProfiles").doc(uid).get()).exists,
      false,
    );
    assert.equal(
      (await db.collection("socialPresence").doc(uid).get()).exists,
      false,
    );
  });

  test("backfill removes projections for an Auth-disabled account", async () => {
    const uid = `${P}backfill-a`;
    await Promise.all([
      db.collection("users").doc(uid).set({
        displayName: "Auth disabled source",
        banned: false,
        disabled: false,
      }),
      db.collection("publicProfiles").doc(uid).set({
        uid,
        displayName: "Stale public identity",
      }),
      db.collection("socialPresence").doc(uid).set({
        uid,
        isOnline: true,
      }),
    ]);

    const report = await backfill({
      db,
      args: {
        apply: true,
        batchSize: 1,
        maxUsers: 1,
        startAfter: null,
        uidPrefix: uid,
      },
      fetchAuthUser: async () => ({ uid, disabled: true }),
    });
    assert.equal(report.inactiveUsers, 1);
    assert.equal(
      (await db.collection("publicProfiles").doc(uid).get()).exists,
      false,
    );
    assert.equal(
      (await db.collection("socialPresence").doc(uid).get()).exists,
      false,
    );
  });
});
