/**
 * RC-13: `sweepExpiredServerInvitesSchedule` failed every run from
 * 2026-09-14T06:13Z with
 *
 *   9 FAILED_PRECONDITION: The query requires a COLLECTION_GROUP_ASC index
 *   for collection serverInviteRefs and field expiresAt.
 *
 * The sweep's `collectionGroup("serverInviteRefs").where("expiresAt", "<=", …)`
 * needs a hand-declared `COLLECTION_GROUP` single-field index: automatic
 * single-field indexes are `COLLECTION` scope only. `firestore.indexes.json`
 * never declared one, so no index deploy could ever have created it.
 *
 * ADR-007 is the reason this file exists, and so is its limit. The emulator
 * does NOT enforce index requirements, so an emulator run alone can never
 * reproduce the production failure — `server_invite_notifications.test.js`
 * already drives the real sweep and stayed green through 250 production
 * failures. Both halves below are therefore required and neither is
 * sufficient alone:
 *
 *   1. the declaration test asserts `firestore.indexes.json` carries the
 *      exemption the production query needs (what the emulator cannot check);
 *   2. the emulator tests run the REAL cross-parent collection-group query,
 *      and the real sweep, against the emulator with that same index file
 *      loaded (what a declaration test cannot check).
 *
 * The override also re-declares the automatic `COLLECTION`-scope indexes: a
 * `fieldOverrides` entry REPLACES automatic single-field indexing for that
 * field rather than adding to it (docs/Firebase.md, "A `fieldOverrides` entry
 * *replaces* automatic single-field indexing"). Declaring only the
 * collection-group order would silently drop collection-scope indexing of
 * `serverInviteRefs.expiresAt`.
 */
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { readFileSync } = require("node:fs");
const path = require("node:path");
const { after, test } = require("node:test");

const enabled = /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(
  process.env.FIRESTORE_EMULATOR_HOST ?? "",
);
process.env.GCLOUD_PROJECT ||= "demo-yovoice-server-invite-sweep-index";

const { getApps, initializeApp, deleteApp } = require("firebase-admin/app");
if (getApps().length === 0) initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const { Timestamp } = require("firebase-admin/firestore");
const { db } = require("../utils/firestore");
const { sweepExpiredServerInvites } = require("../notifications/invites");

// The exact production query, kept in one place so the declaration test and
// the emulator tests cannot drift apart.
const COLLECTION_GROUP = "serverInviteRefs";
const FIELD_PATH = "expiresAt";
const expiredPointerQuery = (now, limit = 50) => db
  .collectionGroup(COLLECTION_GROUP)
  .where(FIELD_PATH, "<=", now)
  .limit(limit);

// Deliberately ancient (2001-09-09) so this fixture can never overlap the
// 2030-era timestamps other suites seed into the shared emulator database.
const SWEEP_NOW_MS = 1_000_000_000_000;
const EXPIRED_A_MS = SWEEP_NOW_MS - 60_000;
const EXPIRED_B_MS = SWEEP_NOW_MS - 30_000;
const CURRENT_MS = SWEEP_NOW_MS + 60_000;

const emulatorTest = (name, fn) => test(
  `Server invite sweep index: ${name}`,
  {
    skip: enabled
      ? false
      : "Requires explicit localhost Firestore emulator; no cloud fallback.",
    timeout: 60_000,
  },
  fn,
);

after(async () => {
  if (getApps().length > 0) await deleteApp(getApps()[0]);
});

/**
 * Two invitees, three pointers. Two expired pointers under DIFFERENT parent
 * users are what makes this a collection-group query and not a collection
 * query — a single-parent fixture would pass against a plain subcollection
 * read and prove nothing about the index this test exists for.
 */
async function fixture() {
  const token = randomUUID().replaceAll("-", "");
  const inviteeA = `sis_invitee_a_${token}`;
  const inviteeB = `sis_invitee_b_${token}`;
  const expiredServerA = `sis_server_expired_a_${token}`;
  const expiredServerB = `sis_server_expired_b_${token}`;
  const currentServer = `sis_server_current_${token}`;

  const pointer = (inviteeId, serverId) => db
    .doc(`users/${inviteeId}/${COLLECTION_GROUP}/${serverId}`);

  const expiredA = pointer(inviteeA, expiredServerA);
  const expiredB = pointer(inviteeB, expiredServerB);
  const current = pointer(inviteeA, currentServer);

  // The canonical pointer shape: exactly { serverId, generation, expiresAt }.
  await Promise.all([
    expiredA.set({
      serverId: expiredServerA,
      generation: 1,
      expiresAt: Timestamp.fromMillis(EXPIRED_A_MS),
    }),
    expiredB.set({
      serverId: expiredServerB,
      generation: 1,
      expiresAt: Timestamp.fromMillis(EXPIRED_B_MS),
    }),
    current.set({
      serverId: currentServer,
      generation: 1,
      expiresAt: Timestamp.fromMillis(CURRENT_MS),
    }),
  ]);

  return {
    inviteeA,
    inviteeB,
    expiredA,
    expiredB,
    current,
    async cleanup() {
      await Promise.all([
        db.recursiveDelete(db.doc(`users/${inviteeA}`)),
        db.recursiveDelete(db.doc(`users/${inviteeB}`)),
      ]);
    },
  };
}

test("RC-13: firestore.indexes.json declares the collection-group exemption the sweep needs", () => {
  const indexesPath = path.resolve(__dirname, "../../firestore.indexes.json");
  const config = JSON.parse(readFileSync(indexesPath, "utf8"));
  const overrides = config.fieldOverrides.filter((override) =>
    override.collectionGroup === COLLECTION_GROUP &&
    override.fieldPath === FIELD_PATH,
  );

  assert.equal(
    overrides.length,
    1,
    "exactly one serverInviteRefs.expiresAt field override must be declared",
  );
  const { indexes } = overrides[0];

  // The exemption the FAILED_PRECONDITION named. `<=` with an implicit
  // ascending order needs COLLECTION_GROUP + ASCENDING.
  assert.ok(
    indexes.some((index) =>
      index.order === "ASCENDING" && index.queryScope === "COLLECTION_GROUP"),
    "the sweep's collectionGroup(expiresAt <= now) query needs COLLECTION_GROUP ASCENDING",
  );

  // A fieldOverrides entry REPLACES automatic single-field indexing, so the
  // automatic COLLECTION-scope indexes have to be re-declared or they are
  // removed from production by this very deploy.
  for (const automatic of [
    { order: "ASCENDING", queryScope: "COLLECTION" },
    { order: "DESCENDING", queryScope: "COLLECTION" },
    { arrayConfig: "CONTAINS", queryScope: "COLLECTION" },
  ]) {
    assert.ok(
      indexes.some((index) =>
        index.queryScope === automatic.queryScope &&
        index.order === automatic.order &&
        index.arrayConfig === automatic.arrayConfig),
      `the override must preserve automatic ${JSON.stringify(automatic)} indexing`,
    );
  }

  // serverInviteRefs has no TTL policy in production; declaring one here
  // would silently create one on the next index deploy.
  assert.equal(overrides[0].ttl, undefined);
});

emulatorTest("the real cross-parent collectionGroup query returns every expired pointer", async () => {
  const value = await fixture();
  try {
    const now = Timestamp.fromMillis(SWEEP_NOW_MS);
    const snapshot = await expiredPointerQuery(now).get();
    const paths = new Set(snapshot.docs.map((document) => document.ref.path));

    // Cross-parent: the two expired pointers live under different users, so
    // only a genuine collection-group read can return both.
    assert.ok(
      paths.has(value.expiredA.path),
      "expired pointer under the first invitee must be scanned",
    );
    assert.ok(
      paths.has(value.expiredB.path),
      "expired pointer under the second invitee must be scanned",
    );
    assert.notEqual(
      value.expiredA.parent.parent.id,
      value.expiredB.parent.parent.id,
    );
    assert.ok(
      !paths.has(value.current.path),
      "a pointer that has not expired must not be scanned",
    );
  } finally {
    await value.cleanup();
  }
});

emulatorTest("the real sweep deletes only expired pointers", async () => {
  const value = await fixture();
  try {
    const outcome = await sweepExpiredServerInvites({
      database: db,
      now: Timestamp.fromMillis(SWEEP_NOW_MS),
    });

    assert.ok(outcome.scanned >= 2);
    assert.ok(outcome.pointersDeleted >= 2);
    assert.equal(outcome.failed, 0);
    assert.deepEqual(outcome.failures, []);
    assert.equal((await value.expiredA.get()).exists, false);
    assert.equal((await value.expiredB.get()).exists, false);
    assert.equal((await value.current.get()).exists, true);
  } finally {
    await value.cleanup();
  }
});
