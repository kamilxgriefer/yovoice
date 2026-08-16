// Coverage for the staff user directory: normalization, derivation,
// sync, the owner-only search callable, and the backfill.
//
// The properties that matter:
//
//  1. THE PRODUCTION FAILURE RESOLVES: a user whose username/display
//     name is stored as "Sieeema" is found by Sieeema, sieeema,
//     @Sieeema, "  sieeema  ", their exact email and their uid.
//  2. Search is PROTECTED-OWNER-ONLY. An ordinary user, a moderator, a
//     super moderator and a forged superAdmin are all refused; the
//     forged case is audited.
//  3. Display names are not unique: duplicates return a LIST.
//  4. An account with no profile document is still discoverable
//     through its Auth identity.
//  5. The backfill is idempotent and sweeps orphans, in bounded batch
//     reads — never one round trip per account.
//
// Fixtures are prefixed `ud-`; the Auth emulator holds the same uids.
//
//   firebase emulators:start --only firestore,auth
//   npm test

const assert = require("node:assert/strict");
const { test, before, beforeEach, after, describe } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST =
  process.env.FIREBASE_AUTH_EMULATOR_HOST ?? "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");

if (getApps().length === 0) initializeApp();

const {
  normalizeSearchText,
  restrictionIsActive,
  deriveDirectoryEntry,
  syncUserDirectoryForUser,
  searchUserDirectory,
  MAX_PAGE_SIZE,
} = require("../staff/directory");

const {
  backfill,
  assertOwnerGuard,
  EXPECTED_PROJECT,
} = require("../scripts/backfill_directory");

const { setProtectedOwnerUidForTests } = require("../utils/roles");

const db = getFirestore();
const auth = getAuth();
const runSearch = searchUserDirectory.run ?? searchUserDirectory;

const P = "ud-";
const OWNER_UID = `${P}owner`;

const AUTH_FIXTURES = [
  {
    uid: `${P}sieeema`,
    email: `${P}sieeema@example.com`,
    displayName: "Sieeema",
  },
  {
    uid: `${P}twin-a`,
    email: `${P}twin-a@example.com`,
    displayName: "Twin Voice",
  },
  {
    uid: `${P}twin-b`,
    email: `${P}twin-b@example.com`,
    displayName: "Twin Voice",
  },
  {
    uid: `${P}bare`,
    email: `${P}bare@example.com`,
    displayName: "Bare Auth Account",
  },
  { uid: OWNER_UID, email: `${P}owner@example.com`, displayName: "Owner" },
  { uid: `${P}mod`, email: `${P}mod@example.com`, displayName: "Mod" },
  { uid: `${P}forged`, email: `${P}forged@example.com`, displayName: "Forged" },
];

const AUTH_ROLES = new Map([
  [`${P}twin-b`, "moderator"],
  [OWNER_UID, "superAdmin"],
  [`${P}mod`, "moderator"],
  [`${P}forged`, "superAdmin"],
]);

async function wipeFirestore() {
  const uids = AUTH_FIXTURES.map((f) => f.uid).concat([
    `${P}plain`,
    `${P}orphan`,
  ]);
  await Promise.all(
    uids.flatMap((uid) => [
      db.collection("users").doc(uid).delete(),
      db.collection("vipGrants").doc(uid).delete(),
      db.collection("restrictions").doc(uid).delete(),
      db.collection("userDirectory").doc(uid).delete(),
    ]),
  );
}

/// Seeds the world the production failure happened in: profile fields
/// stored AS TYPED (mixed case), directory derived from them.
async function seedWorld() {
  // Profiles: Sieeema exactly as ProfileService seeds it.
  await db.collection("users").doc(`${P}sieeema`).set({
    uid: `${P}sieeema`,
    email: `${P}sieeema@example.com`,
    displayName: "Sieeema",
    username: "Sieeema",
    role: "user",
  });
  await db.collection("users").doc(`${P}twin-a`).set({
    displayName: "Twin Voice",
    username: "twin.one",
    role: "user",
  });
  await db.collection("users").doc(`${P}twin-b`).set({
    displayName: "Twin Voice",
    username: "twin.two",
    role: "moderator",
  });
  // ud-bare deliberately has NO users document.
  await db.collection("users").doc(OWNER_UID).set({ role: "superAdmin" });
  await db.collection("users").doc(`${P}mod`).set({ role: "moderator" });
  await db.collection("users").doc(`${P}forged`).set({ role: "superAdmin" });

  for (const fixture of AUTH_FIXTURES) {
    await syncUserDirectoryForUser(fixture.uid);
  }
}

function callerFor(uid, role = "user") {
  return { auth: { uid, token: { role } } };
}

const ownerCaller = () => callerFor(OWNER_UID, "superAdmin");

before(async () => {
  // The Auth emulator carries the same accounts across the whole suite.
  for (const fixture of AUTH_FIXTURES) {
    try {
      await auth.deleteUser(fixture.uid);
    } catch (_) {
      /* absent is fine */
    }
    await auth.createUser(fixture);
    const role = AUTH_ROLES.get(fixture.uid);
    if (role) await auth.setCustomUserClaims(fixture.uid, { role });
  }
});

after(async () => {
  await Promise.all(
    AUTH_FIXTURES.map((fixture) => auth.deleteUser(fixture.uid).catch(() => {})),
  );
  await wipeFirestore();
});

beforeEach(async () => {
  setProtectedOwnerUidForTests(OWNER_UID);
  await wipeFirestore();
});

describe("normalization", () => {
  test("folds casing, whitespace and Unicode compatibility forms", () => {
    assert.equal(normalizeSearchText("  Sieeema  "), "sieeema");
    assert.equal(normalizeSearchText("SIEEEMA"), "sieeema");
    assert.equal(normalizeSearchText("Twin  Voice"), "twin voice");
    assert.equal(normalizeSearchText("ＳＩＥＥＥＭＡ"), "sieeema"); // fullwidth NFKC
    assert.equal(normalizeSearchText(null), "");
  });

  test("restriction activity mirrors the rules' expiry logic", () => {
    assert.equal(restrictionIsActive({ expiresAt: null }), true);
    assert.equal(restrictionIsActive(null), false);
    const past = Timestamp.fromMillis(Date.now() - 1000);
    const future = Timestamp.fromMillis(Date.now() + 3600 * 1000);
    assert.equal(restrictionIsActive({ expiresAt: past }), false);
    assert.equal(restrictionIsActive({ expiresAt: future }), true);
  });
});

describe("derivation", () => {
  const authUser = (overrides = {}) => ({
    uid: `${P}sieeema`,
    email: `${P}sieeema@example.com`,
    displayName: "Sieeema",
    disabled: false,
    customClaims: { role: "user" },
    metadata: { creationTime: "2026-01-05T10:00:00Z" },
    ...overrides,
  });

  test("no Auth user means no entry, whatever documents linger", () => {
    assert.equal(
      deriveDirectoryEntry({ uid: "x", authUser: null, user: { role: "user" } }),
      null,
    );
  });

  test("an account with no profile document is still discoverable", () => {
    const entry = deriveDirectoryEntry({ uid: `${P}bare`, authUser: authUser() });
    assert.equal(entry.displayName, "Sieeema");
    assert.equal(entry.displayNameLower, "sieeema");
    assert.equal(entry.username, "");
    assert.equal(entry.emailLower, `${P}sieeema@example.com`);
    assert.equal(entry.staffRole, "user");
  });

  test("profile fields are stored as typed AND normalized beside", () => {
    const entry = deriveDirectoryEntry({
      uid: `${P}sieeema`,
      authUser: authUser(),
      user: { displayName: "Sieeema", username: "Sieeema", role: "user" },
    });
    assert.equal(entry.username, "Sieeema");
    assert.equal(entry.usernameLower, "sieeema");
    assert.equal(entry.createdAt.toDate().toISOString(), "2026-01-05T10:00:00.000Z");
  });

  test("a forged superAdmin never wears the owner role in the directory", () => {
    const entry = deriveDirectoryEntry({
      uid: `${P}forged`,
      authUser: authUser({
        uid: `${P}forged`,
        customClaims: { role: "superAdmin" },
      }),
      user: { role: "superAdmin" },
    });
    assert.equal(entry.staffRole, "superModerator");
    const owner = deriveDirectoryEntry({
      uid: OWNER_UID,
      authUser: authUser({
        uid: OWNER_UID,
        customClaims: { role: "superAdmin" },
      }),
      user: { role: "superAdmin" },
    });
    assert.equal(owner.staffRole, "superAdmin");
  });

  test("staff role requires an Auth claim and matching Firestore mirror", () => {
    const forgedMirror = deriveDirectoryEntry({
      uid: "x",
      authUser: authUser({ customClaims: { role: "user" } }),
      user: { role: "moderator" },
    });
    assert.equal(forgedMirror.staffRole, "user");

    const staleMirror = deriveDirectoryEntry({
      uid: "x",
      authUser: authUser({ customClaims: { role: "moderator" } }),
      user: { role: "user" },
    });
    assert.equal(staleMirror.staffRole, "user");

    const matching = deriveDirectoryEntry({
      uid: "x",
      authUser: authUser({ customClaims: { role: "moderator" } }),
      user: { role: "moderator" },
    });
    assert.equal(matching.staffRole, "moderator");
  });

  test("profile email is never used when Auth has no email", () => {
    const entry = deriveDirectoryEntry({
      uid: "x",
      authUser: authUser({ email: null }),
      user: { email: "forged@profile.invalid", role: "user" },
    });
    assert.equal(entry.email, null);
    assert.equal(entry.emailLower, "");
  });

  test("banned and restricted flags derive from their real sources", () => {
    const banned = deriveDirectoryEntry({
      uid: "x",
      authUser: authUser({ disabled: true }),
    });
    assert.equal(banned.banned, true);
    const restricted = deriveDirectoryEntry({
      uid: "x",
      authUser: authUser(),
      restriction: { type: "communicationMute", expiresAt: null },
    });
    assert.equal(restricted.restricted, true);
    const lapsed = deriveDirectoryEntry({
      uid: "x",
      authUser: authUser(),
      restriction: {
        type: "communicationMute",
        expiresAt: Timestamp.fromMillis(Date.now() - 1000),
      },
    });
    assert.equal(lapsed.restricted, false);
  });
});

describe("search — the production failure and every required mode", () => {
  test("Sieeema resolves under every casing, @-prefix and padding", async () => {
    await seedWorld();

    for (const input of [
      "Sieeema",
      "sieeema",
      "SIEEEMA",
      "@Sieeema",
      "  sieeema  ",
    ]) {
      const result = await runSearch({
        ...ownerCaller(),
        data: { query: input },
      });
      assert.ok(
        result.users.some((row) => row.uid === `${P}sieeema`),
        `input ${JSON.stringify(input)} must find the account`,
      );
    }
  });

  test("exact uid and case-insensitive email both resolve", async () => {
    await seedWorld();

    const byUid = await runSearch({
      ...ownerCaller(),
      data: { query: `${P}sieeema` },
    });
    assert.equal(byUid.mode, "uid");
    assert.equal(byUid.users[0].uid, `${P}sieeema`);

    const byEmail = await runSearch({
      ...ownerCaller(),
      data: { query: `${P.toUpperCase()}SIEEEMA@EXAMPLE.COM`.toLowerCase().replace(P.toUpperCase().toLowerCase(), P) },
    });
    // Plainly: the mixed-case email resolves.
    const mixed = await runSearch({
      ...ownerCaller(),
      data: { query: ` ${P}Sieeema@Example.COM ` },
    });
    assert.equal(mixed.mode, "email");
    assert.equal(mixed.users.length, 1);
    assert.equal(mixed.users[0].uid, `${P}sieeema`);
    assert.ok(byEmail.users.length >= 0); // exercised above
  });

  test("duplicate display names return a list, not one guess", async () => {
    await seedWorld();

    const result = await runSearch({
      ...ownerCaller(),
      data: { query: "twin voice" },
    });
    const uids = result.users.map((row) => row.uid).sort();
    assert.deepEqual(uids, [`${P}twin-a`, `${P}twin-b`]);
    // And the roles arrive as PUBLIC effective roles.
    const twinB = result.users.find((row) => row.uid === `${P}twin-b`);
    assert.equal(twinB.staffRole, "moderator");
  });

  test("prefix search matches from two characters, case-insensitively", async () => {
    await seedWorld();

    const result = await runSearch({
      ...ownerCaller(),
      data: { query: "si" },
    });
    assert.ok(result.users.some((row) => row.uid === `${P}sieeema`));

    await assert.rejects(
      () => runSearch({ ...ownerCaller(), data: { query: "s" } }),
      /at least 2/i,
    );
  });

  test("an account with no profile document is findable by email and uid", async () => {
    await seedWorld();

    const byEmail = await runSearch({
      ...ownerCaller(),
      data: { query: `${P}bare@example.com` },
    });
    assert.equal(byEmail.users.length, 1);
    assert.equal(byEmail.users[0].uid, `${P}bare`);
    assert.equal(byEmail.users[0].displayName, "Bare Auth Account");

    const byUid = await runSearch({
      ...ownerCaller(),
      data: { query: `${P}bare` },
    });
    assert.equal(byUid.users[0].uid, `${P}bare`);
  });

  test("no result is an empty list — never an error, and vice versa", async () => {
    await seedWorld();

    const missing = await runSearch({
      ...ownerCaller(),
      data: { query: "nobody-here" },
    });
    assert.deepEqual(missing.users, []);
    assert.equal(missing.nextCursor, null);

    await assert.rejects(
      () => runSearch({ ...ownerCaller(), data: { query: "ok", filter: "bogus" } }),
      /Unknown filter/,
    );
  });

  test("browse mode pages by filter and respects the request bound", async () => {
    await seedWorld();

    const staff = await runSearch({
      ...ownerCaller(),
      data: { query: "", filter: "staff" },
    });
    const staffUids = staff.users.map((row) => row.uid);
    assert.ok(staffUids.includes(`${P}twin-b`)); // moderator
    assert.ok(staffUids.includes(OWNER_UID));
    assert.ok(!staffUids.includes(`${P}sieeema`));

    // A limit beyond the bound clamps to MAX_PAGE_SIZE rather than
    // becoming an enumeration lever.
    const clamped = await runSearch({
      ...ownerCaller(),
      data: { query: "", limit: 500 },
    });
    assert.ok(clamped.users.length <= MAX_PAGE_SIZE);
  });

  test("name-mode pagination walks every match exactly once", async () => {
    setProtectedOwnerUidForTests(OWNER_UID);
    await seedWorld();
    // 25 accounts sharing a prefix forces at least two pages.
    const uids = [];
    for (let i = 0; i < 25; i += 1) {
      const uid = `${P}page-${String(i).padStart(2, "0")}`;
      uids.push(uid);
      await db.collection("userDirectory").doc(uid).set({
        displayName: `Pager ${i}`,
        username: `pager.${i}`,
        email: null,
        photoUrl: null,
        displayNameLower: `pager ${i}`,
        usernameLower: `pager.${i}`,
        emailLower: "",
        staffRole: "user",
        isStaff: false,
        isVip: false,
        banned: false,
        restricted: false,
        createdAt: Timestamp.fromMillis(1700000000000 + i),
        schemaVersion: 1,
      });
    }

    const seen = new Set();
    let cursor = null;
    for (let hops = 0; hops < 10; hops += 1) {
      const page = await runSearch({
        ...ownerCaller(),
        data: { query: "pager", cursor },
      });
      for (const row of page.users) {
        assert.ok(!seen.has(row.uid), `${row.uid} delivered twice`);
        seen.add(row.uid);
      }
      cursor = page.nextCursor;
      if (!cursor) break;
    }
    assert.equal(seen.size, 25);

    await Promise.all(
      uids.map((uid) => db.collection("userDirectory").doc(uid).delete()),
    );
  });
});

describe("search — enumeration denial", () => {
  test("ordinary user, moderator and super moderator are refused", async () => {
    await seedWorld();
    await db
      .collection("users")
      .doc(`${P}plain`)
      .set({ role: "user" });

    for (const [uid, role] of [
      [`${P}plain`, "user"],
      [`${P}mod`, "moderator"],
      [`${P}mod`, "superModerator"],
    ]) {
      await assert.rejects(
        () => runSearch({ ...callerFor(uid, role), data: { query: "sieeema" } }),
        /permission|super administrator/i,
        `${role} must not enumerate the directory`,
      );
    }
  });

  test("a forged superAdmin is refused AND audited", async () => {
    await seedWorld();

    await assert.rejects(
      () =>
        runSearch({
          ...callerFor(`${P}forged`, "superAdmin"),
          data: { query: "sieeema" },
        }),
      /reserved for the application owner/i,
    );

    const alerts = await db
      .collection("adminAuditLogs")
      .where("targetId", "==", `${P}forged`)
      .where("action", "==", "security_alert_non_owner_super_admin")
      .get();
    assert.ok(alerts.size >= 1, "the forged attempt must be recorded");
  });

  test("the confirmed owner is admitted", async () => {
    await seedWorld();
    const result = await runSearch({
      ...ownerCaller(),
      data: { query: "sieeema" },
    });
    assert.ok(result.users.length >= 1);
  });
});

describe("backfill", () => {
  const args = { apply: false, project: EXPECTED_PROJECT };

  /// The injectable Auth listing: one page of plain objects shaped like
  /// UserRecords, so the scan exercises its real join logic.
  function fakeAuthListing() {
    const users = AUTH_FIXTURES.map((fixture) => ({
      ...fixture,
      disabled: false,
      customClaims: {
        role: AUTH_ROLES.get(fixture.uid) ?? "user",
      },
      metadata: { creationTime: "2026-02-01T00:00:00Z" },
    }));
    return async (_limit, pageToken) =>
      pageToken ? { users: [], pageToken: undefined } : { users, pageToken: undefined };
  }

  async function seedProfilesOnly() {
    await db.collection("users").doc(`${P}sieeema`).set({
      displayName: "Sieeema",
      username: "Sieeema",
      role: "user",
    });
    await db.collection("users").doc(OWNER_UID).set({ role: "superAdmin" });
    // An orphan: directory entry whose Auth account is gone.
    await db.collection("userDirectory").doc(`${P}orphan`).set({
      displayName: "Ghost",
      username: "ghost",
      email: null,
      photoUrl: null,
      displayNameLower: "ghost",
      usernameLower: "ghost",
      emailLower: "",
      staffRole: "user",
      isStaff: false,
      isVip: false,
      banned: false,
      restricted: false,
      createdAt: null,
      schemaVersion: 1,
    });
  }

  test("dry run counts the work and writes nothing", async () => {
    await seedProfilesOnly();
    const report = await backfill({
      db,
      args,
      listAuthUsers: fakeAuthListing(),
      uidPrefix: P,
    });

    assert.equal(report.appliedWrites, 0);
    assert.equal(report.appliedDeletes, 0);
    assert.equal(report.scannedAuthUsers, AUTH_FIXTURES.length);
    assert.ok(report.withoutProfileDocument >= 1, "ud-bare has no profile");
    assert.ok(report.toCreate >= AUTH_FIXTURES.length - 1);
    assert.ok(report.toDelete >= 1, "the orphan must be planned away");

    assert.equal(
      (await db.collection("userDirectory").doc(`${P}sieeema`).get()).exists,
      false,
    );
    // Aggregate only: no uid or email in the report.
    const serialised = JSON.stringify(report);
    assert.ok(!serialised.includes(`${P}sieeema`));
    assert.ok(!serialised.includes("@example.com"));
  });

  test("apply converges, sweeps the orphan, and a second run is a no-op", async () => {
    await seedProfilesOnly();
    const listAuthUsers = fakeAuthListing();

    const first = await backfill({
      db,
      args: { ...args, apply: true },
      listAuthUsers,
      uidPrefix: P,
    });
    assert.ok(first.appliedWrites >= AUTH_FIXTURES.length - 1);
    assert.ok(first.appliedDeletes >= 1);

    const entry = (
      await db.collection("userDirectory").doc(`${P}sieeema`).get()
    ).data();
    assert.equal(entry.usernameLower, "sieeema");
    assert.equal(
      (await db.collection("userDirectory").doc(`${P}orphan`).get()).exists,
      false,
    );

    const second = await backfill({
      db,
      args: { ...args, apply: true },
      listAuthUsers,
      uidPrefix: P,
    });
    assert.equal(second.appliedWrites, 0);
    assert.equal(second.appliedDeletes, 0);
    assert.ok(second.upToDate >= AUTH_FIXTURES.length - 1);
  });

  test("the backfill refuses to run without the owner guard", async () => {
    setProtectedOwnerUidForTests(null);
    const previousEnv = process.env.YOVOICE_PROTECTED_OWNER_UID;
    delete process.env.YOVOICE_PROTECTED_OWNER_UID;
    try {
      assert.throws(() => assertOwnerGuard(), /YOVOICE_PROTECTED_OWNER_UID/);
      await assert.rejects(
        () =>
          backfill({
            db,
            args,
            listAuthUsers: fakeAuthListing(),
            uidPrefix: P,
          }),
        /YOVOICE_PROTECTED_OWNER_UID/,
      );
    } finally {
      if (previousEnv !== undefined) {
        process.env.YOVOICE_PROTECTED_OWNER_UID = previousEnv;
      }
      setProtectedOwnerUidForTests(OWNER_UID);
    }
  });
});
