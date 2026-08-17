const assert = require("node:assert/strict");
const { describe, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";
process.env.FIREBASE_STORAGE_BUCKET = process.env.FIREBASE_STORAGE_BUCKET ??
  "yovoice-fn-test.firebasestorage.app";

const { getApps, initializeApp } = require("firebase-admin/app");
const { Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) {
  initializeApp({ storageBucket: process.env.FIREBASE_STORAGE_BUCKET });
}

const {
  MAX_PUBLIC_CLUBS,
  MAX_PUBLIC_PEOPLE,
  MIN_ACTIVITY_COHORT,
  PUBLIC_SHOWCASE_SCHEMA_VERSION,
  RECENT_ACTIVITY_SECONDS,
  SHOWCASE_VALIDITY_SECONDS,
  boundedConsentDocuments,
  computePublicShowcase,
  derivePublicClub,
  derivePublicPerson,
  publishPublicShowcase,
  validClubMarketingConsent,
  validMarketingConsent,
} = require("../marketing/public_showcase");

const NOW = 1_800_000_000_000;

function consent(overrides = {}) {
  return {
    schemaVersion: 1,
    showProfileOnWebsite: true,
    showActivityOnWebsite: false,
    updatedAt: Timestamp.fromMillis(NOW - 1_000),
    ...overrides,
  };
}

function person(uid, overrides = {}) {
  return {
    uid,
    authUser: { uid, disabled: false },
    consent: consent(),
    profile: {
      uid,
      displayName: `Person ${uid}`,
      accountType: "personal",
      schemaVersion: 1,
      username: `private-${uid}`,
      photoUrl: `https://private.invalid/${uid}.jpg`,
    },
    user: {
      uid,
      email: `${uid}@private.invalid`,
      role: "user",
      banned: false,
      disabled: false,
      isOnline: false,
      presenceUpdatedAt: Timestamp.fromMillis(NOW - 10_000),
    },
    ...overrides,
  };
}

function clubConsent(clubId, ownerId, overrides = {}) {
  return {
    schemaVersion: 1,
    clubId,
    ownerId,
    showOnWebsite: true,
    updatedAt: Timestamp.fromMillis(NOW - 1_000),
    ...overrides,
  };
}

function club(clubId, ownerId = "owner", overrides = {}) {
  return {
    clubId,
    consent: clubConsent(clubId, ownerId),
    club: {
      ownerId,
      name: `Club ${clubId}`,
      type: "community",
      privacy: "public",
      status: "active",
      memberCount: 4,
      ...overrides,
    },
  };
}

describe("public showcase consent schemas", () => {
  test("account consent is exact and activity requires profile publication", () => {
    assert.equal(validMarketingConsent(consent()), true);
    assert.equal(validMarketingConsent(consent({
      showProfileOnWebsite: false,
      showActivityOnWebsite: true,
    })), false);
    assert.equal(validMarketingConsent({ ...consent(), email: "leak" }), false);
    assert.equal(validMarketingConsent({
      ...consent(),
      updatedAt: "client-time",
    }), false);
  });

  test("club consent is exact and bound to explicit club and owner ids", () => {
    assert.equal(validClubMarketingConsent(clubConsent("club-a", "owner")), true);
    assert.equal(validClubMarketingConsent({
      ...clubConsent("club-a", "owner"),
      ownerEmail: "owner@private.invalid",
    }), false);
    assert.equal(validClubMarketingConsent(clubConsent("bad/id", "owner")), false);
  });

  test("bounded scans fail loudly instead of publishing a partial rotation", () => {
    const documents = Array.from(
      { length: 201 },
      (_, index) => ({ id: `consent-${index}` }),
    );
    assert.throws(
      () => boundedConsentDocuments({ docs: documents }, 200, "Profile"),
      /refusing a partial rotation/,
    );
    assert.equal(
      boundedConsentDocuments({ docs: documents.slice(0, 200) }, 200, "Profile")
        .length,
      200,
    );
  });
});

describe("public showcase people projection", () => {
  test("publishes only consented display name, account type and honest activity", () => {
    const source = person("alice", {
      consent: consent({ showActivityOnWebsite: true }),
      profile: {
        ...person("alice").profile,
        displayName: "Alice",
        accountType: "creator",
      },
      user: {
        ...person("alice").user,
        isOnline: true,
        lastSeen: Timestamp.fromMillis(NOW - 5_000),
      },
    });
    const projected = derivePublicPerson(source, NOW);

    assert.deepEqual(Object.keys(projected).sort(), [
      "_activityValidUntilMillis",
      "_rotationKey",
      "accountType",
      "activity",
      "displayName",
    ]);
    assert.equal(projected.displayName, "Alice");
    assert.equal(projected.accountType, "creator");
    assert.equal(projected.activity, "activeRecently");
    assert.equal(
      projected._activityValidUntilMillis,
      NOW - 10_000 + (RECENT_ACTIVITY_SECONDS * 1000),
    );
    assert.equal(JSON.stringify(projected).includes("@private.invalid"), false);
    assert.equal(JSON.stringify(projected).includes("photoUrl"), false);
  });

  test("stale, future, unconsented and false presence never becomes activity", () => {
    const variants = [
      person("stale", {
        consent: consent({ showActivityOnWebsite: true }),
        user: {
          ...person("stale").user,
          isOnline: true,
          presenceUpdatedAt: Timestamp.fromMillis(
            NOW - ((RECENT_ACTIVITY_SECONDS + 1) * 1000),
          ),
        },
      }),
      person("future", {
        consent: consent({ showActivityOnWebsite: true }),
        user: {
          ...person("future").user,
          isOnline: true,
          presenceUpdatedAt: Timestamp.fromMillis(NOW + 1_000),
        },
      }),
      person("boundary", {
        consent: consent({ showActivityOnWebsite: true }),
        user: {
          ...person("boundary").user,
          isOnline: true,
          presenceUpdatedAt: Timestamp.fromMillis(
            NOW - (RECENT_ACTIVITY_SECONDS * 1000),
          ),
        },
      }),
      person("private-activity", {
        consent: consent({ showActivityOnWebsite: false }),
        user: { ...person("private-activity").user, isOnline: true },
      }),
      person("offline", {
        consent: consent({ showActivityOnWebsite: true }),
        user: { ...person("offline").user, isOnline: false },
      }),
    ];

    for (const source of variants) {
      assert.equal(derivePublicPerson(source, NOW).activity, "undisclosed");
    }
  });

  test("inactive, staff, malformed and non-consenting profiles fail closed", () => {
    const rejected = [
      person("banned", { user: { ...person("banned").user, banned: true } }),
      person("disabled", {
        user: { ...person("disabled").user, disabled: true },
      }),
      person("staff", {
        user: { ...person("staff").user, role: "moderator" },
      }),
      person("support", {
        user: { ...person("support").user, role: "support" },
      }),
      person("unknown-role", {
        user: { ...person("unknown-role").user, role: "futureStaffRole" },
      }),
      person("auth-missing", { authUser: null }),
      person("auth-disabled", {
        authUser: { uid: "auth-disabled", disabled: true },
      }),
      person("no-consent", {
        consent: consent({ showProfileOnWebsite: false }),
      }),
      person("bad-profile", {
        profile: { ...person("bad-profile").profile, uid: "somebody-else" },
      }),
      person("poisoned-consent", {
        consent: { ...consent(), email: "leak@private.invalid" },
      }),
    ];
    for (const source of rejected) {
      assert.equal(derivePublicPerson(source, NOW), null);
    }
  });

  test("active-recently is suppressed until the privacy cohort is at least three", async () => {
    assert.equal(MIN_ACTIVITY_COHORT, 3);
    const fresh = (uid) => person(uid, {
      consent: consent({ showActivityOnWebsite: true }),
      user: { ...person(uid).user, isOnline: true },
    });
    const below = await computePublicShowcase({
      nowMillis: NOW,
      loadPeople: async () => [fresh("a"), fresh("b")],
      loadClubs: async () => [],
    });
    assert.deepEqual(below.people.map(({ activity }) => activity), [
      "undisclosed",
      "undisclosed",
    ]);

    const enough = await computePublicShowcase({
      nowMillis: NOW,
      loadPeople: async () => [fresh("a"), fresh("b"), fresh("c")],
      loadClubs: async () => [],
    });
    assert.equal(
      enough.people.filter(({ activity }) => activity === "activeRecently").length,
      3,
    );
    assert.equal(
      enough.activityValidUntil.toMillis(),
      NOW - 10_000 + (RECENT_ACTIVITY_SECONDS * 1000),
    );

    const mixed = await computePublicShowcase({
      nowMillis: NOW,
      loadPeople: async () => [
        fresh("active-a"),
        fresh("active-b"),
        fresh("active-c"),
        ...Array.from({ length: 20 }, (_, index) => person(`quiet-${index}`)),
      ],
      loadClubs: async () => [],
    });
    const visibleActivity = mixed.people.filter(({ activity }) =>
      activity === "activeRecently").length;
    assert.ok(
      visibleActivity === 0 || visibleActivity >= MIN_ACTIVITY_COHORT,
      `published an identifying activity cohort of ${visibleActivity}`,
    );
  });

  test("last-seen cannot rescue a stale heartbeat", () => {
    const source = person("stale-heartbeat", {
      consent: consent({ showActivityOnWebsite: true }),
      user: {
        ...person("stale-heartbeat").user,
        isOnline: true,
        presenceUpdatedAt: Timestamp.fromMillis(
          NOW - ((RECENT_ACTIVITY_SECONDS + 1) * 1000),
        ),
        lastSeen: Timestamp.fromMillis(NOW - 1_000),
      },
    });
    assert.equal(derivePublicPerson(source, NOW).activity, "undisclosed");
  });
});

describe("public showcase club projection", () => {
  test("publishes only a consented active public community owned by the grantor", () => {
    const projected = derivePublicClub(club("club-a"));
    assert.deepEqual(projected, {
      _rotationKey: "club-a",
      name: "Club club-a",
      memberCount: 4,
    });
  });

  test("ownership transfer, family/private/inactive/deleting and malformed counts fail closed", () => {
    const rejected = [
      club("transferred", "old-owner", { ownerId: "new-owner" }),
      club("family", "owner", { type: "family" }),
      club("private", "owner", { privacy: "private" }),
      club("inactive", "owner", { status: "suspended" }),
      club("deleting", "owner", { deletionInProgress: true }),
      club("count", "owner", { memberCount: 2.5 }),
      club("string-count", "owner", { memberCount: "4" }),
    ];
    for (const source of rejected) {
      assert.equal(derivePublicClub(source), null);
    }
  });
});

describe("public showcase published document", () => {
  test("the one-minute publisher is exported for deployment", () => {
    const deployed = require("../index");
    assert.equal(typeof deployed.publishPublicShowcaseSchedule, "function");
  });

  test("is bounded, exact, time-limited and contains no identifiers/private fields", async () => {
    assert.equal(MAX_PUBLIC_PEOPLE, 4);
    assert.equal(MAX_PUBLIC_CLUBS, 4);
    let written = null;
    const showcase = await publishPublicShowcase({
      nowMillis: NOW,
      loadPeople: async () => Array.from(
        { length: 12 },
        (_, index) => {
          const uid = `private-uid-${index}`;
          return person(uid, {
            profile: {
              ...person(uid).profile,
              displayName: `Published person ${index}`,
            },
          });
        },
      ),
      loadClubs: async () => Array.from(
        { length: 9 },
        (_, index) => club(
          `private-club-id-${index}`,
          "private-owner-id",
          { name: `Published club ${index}` },
        ),
      ),
      writeShowcase: async (payload) => { written = payload; },
    });

    assert.equal(written, showcase);
    assert.deepEqual(Object.keys(showcase).sort(), [
      "activityValidUntil",
      "clubs",
      "generatedAt",
      "people",
      "schemaVersion",
      "validUntil",
    ]);
    assert.equal(showcase.schemaVersion, PUBLIC_SHOWCASE_SCHEMA_VERSION);
    assert.equal(showcase.people.length, 4);
    assert.equal(showcase.clubs.length, 4);
    assert.equal(
      showcase.activityValidUntil.toMillis(),
      NOW + (RECENT_ACTIVITY_SECONDS * 1000),
    );
    assert.equal(
      showcase.validUntil.toMillis(),
      NOW + (SHOWCASE_VALIDITY_SECONDS * 1000),
    );
    assert.ok(SHOWCASE_VALIDITY_SECONDS <= 3 * 60);

    for (const entry of showcase.people) {
      assert.deepEqual(Object.keys(entry).sort(), [
        "accountType",
        "activity",
        "displayName",
      ]);
    }
    for (const entry of showcase.clubs) {
      assert.deepEqual(Object.keys(entry).sort(), ["memberCount", "name"]);
    }
    const serialized = JSON.stringify(showcase);
    for (const forbidden of [
      "private-uid-",
      "private-club-id-",
      "username",
      "email",
      "photoUrl",
      "lastSeen",
      "presenceUpdatedAt",
      "role",
    ]) {
      assert.equal(serialized.includes(forbidden), false, forbidden);
    }
  });

  test("source failure writes nothing and preserves the previous good document", async () => {
    let writes = 0;
    await assert.rejects(() => publishPublicShowcase({
      nowMillis: NOW,
      loadPeople: async () => { throw new Error("profiles unavailable"); },
      loadClubs: async () => [],
      writeShowcase: async () => { writes += 1; },
    }), /profiles unavailable/);
    assert.equal(writes, 0);
  });

  test("empty consent sources publish honest empty arrays, never fake fallback cards", async () => {
    const showcase = await computePublicShowcase({
      nowMillis: NOW,
      loadPeople: async () => [],
      loadClubs: async () => [],
    });
    assert.deepEqual(showcase.people, []);
    assert.deepEqual(showcase.clubs, []);
  });
});
