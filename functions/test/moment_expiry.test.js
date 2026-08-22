// The scheduled sweep that retires a Voice Moment once its deadline is up.
//
// The two properties worth more than all the others: it must EXPIRE a
// published Moment whose deadline has passed while changing nothing else on
// the document, and it must NEVER touch a Moment that is still inside its
// availability window, has no deadline at all (permanent availability, and
// the legacy pre-expiry documents that share the shape), or stopped being a
// published Moment between the scan and the write. Every test below is one
// of those.

const assert = require("node:assert/strict");
const { test, beforeEach, describe } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

// ITS OWN FIRESTORE NAMESPACE, AND IT HAS TO BE. This suite's SUBJECT is a
// query over the whole `voiceMoments` collection, and moment_integrity.test.js
// runs beside it in the same `node --test test/*.test.js` invocation, seeding
// published Moments of its own. Sharing the default project id would make
// `scanned` and `expired` read whatever the machine's scheduling did that
// morning. The Firestore emulator keeps one database per project id, so
// deriving a distinct id buys full isolation (and lets `wipeMoments()` clear
// the collection outright) — the same reasoning as room_liveness_sweeper's.
const BASE_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";
const EXPIRY_PROJECT = `${BASE_PROJECT}-moment-expiry`;
process.env.GCLOUD_PROJECT = EXPIRY_PROJECT;

if (getApps().length === 0) initializeApp({ projectId: EXPIRY_PROJECT });

const {
  MAX_EXPIRED_MOMENT_SCAN,
  expireMomentIfStillPastDeadline,
  expireVoiceMoments,
} = require("../moments/expiry");

const db = getFirestore();
const P = "vme-";
const AUTHOR = `${P}author`;

// A fixed clock. The sweep dates every Moment against this, so "past" and
// "future" below are exact rather than dependent on how long the suite runs.
const NOW_MILLIS = 1_820_000_000_000;
const now = () => Timestamp.fromMillis(NOW_MILLIS);
const DAY_MS = 24 * 60 * 60 * 1000;
const PAST_DEADLINE = Timestamp.fromMillis(NOW_MILLIS - 60_000);
const FUTURE_DEADLINE = Timestamp.fromMillis(NOW_MILLIS + 8 * 60 * 60_000);

/// The exact document finalizeMomentDraft leaves behind, aged past its
/// deadline: published, engagement counters non-zero (so "touches nothing
/// else" is provable), createdAt/expiresAt exactly 24h apart.
function publishedMoment(momentId, overrides = {}) {
  const createdAt = Timestamp.fromMillis(NOW_MILLIS - DAY_MS - 60_000);
  return {
    schemaVersion: 2,
    authorId: AUTHOR,
    authorName: "Expiry Author",
    authorPhotoUrl: null,
    caption: "A story with a shelf life",
    audioUrl: "https://storage.example.invalid/voice.m4a",
    storagePath: `voice_moments/${AUTHOR}/${momentId}.m4a`,
    durationSeconds: 12,
    likeCount: 3,
    commentCount: 1,
    replyToMomentId: null,
    isPublished: true,
    isDeleted: false,
    status: "published",
    mediaGeneration: "1001",
    mediaSize: 4096,
    mediaContentType: "audio/mp4",
    createdAt,
    updatedAt: createdAt,
    publishedAt: Timestamp.fromMillis(createdAt.toMillis() + 30_000),
    expiresAt: PAST_DEADLINE,
    ...overrides,
  };
}

async function seedMoment(momentId, overrides = {}) {
  await db.doc(`voiceMoments/${momentId}`).set(publishedMoment(momentId, overrides));
}

// The whole collection, not a prefix: this suite owns its own project (see
// the header), and a leftover published Moment from an earlier test is
// precisely what would corrupt the global counters these tests assert on.
async function wipeMoments() {
  const moments = await db.collection("voiceMoments").get();
  await Promise.all(
    moments.docs.map((document) => db.recursiveDelete(document.ref)),
  );
}

function readMoment(momentId) {
  return db.doc(`voiceMoments/${momentId}`).get();
}

beforeEach(wipeMoments);

describe("voice moment expiry sweep", () => {
  test("flips a past-deadline Moment to expired and touches nothing else", async () => {
    const momentId = `${P}due`;
    const seeded = publishedMoment(momentId);
    await db.doc(`voiceMoments/${momentId}`).set(seeded);
    await db.doc(`voiceMoments/${momentId}/comments/c1`).set({
      type: "text",
      authorId: `${P}commenter`,
      text: "still here after expiry",
    });

    const outcome = await expireVoiceMoments({ now });

    assert.equal(outcome.expired, 1);
    assert.deepEqual(outcome.expiredMomentIds, [momentId]);
    assert.equal(outcome.failed, 0);
    assert.equal(outcome.truncated, false);

    const moment = (await readMoment(momentId)).data();
    assert.equal(moment.isPublished, false);
    assert.equal(moment.status, "expired");
    assert.ok(moment.updatedAt instanceof Timestamp, "updatedAt is stamped");
    assert.notEqual(
      moment.updatedAt.toMillis(),
      seeded.updatedAt.toMillis(),
      "updatedAt moved",
    );
    // NOTHING else changed: audio, engagement, identity and both anchor
    // timestamps survive the flip untouched.
    for (const key of Object.keys(seeded)) {
      if (["isPublished", "status", "updatedAt"].includes(key)) continue;
      const before = seeded[key];
      const after = moment[key];
      if (before instanceof Timestamp) {
        assert.equal(after.toMillis(), before.toMillis(), key);
      } else {
        assert.equal(after, before, key);
      }
    }
    const comment = await db.doc(`voiceMoments/${momentId}/comments/c1`).get();
    assert.equal(comment.exists, true, "comments stay after expiry");
  });

  test("ANTI-TRAP: a Moment still inside its 24 hours is left alone", async () => {
    const momentId = `${P}fresh`;
    await seedMoment(momentId, { expiresAt: FUTURE_DEADLINE });

    const outcome = await expireVoiceMoments({ now });

    assert.equal(outcome.scanned, 0);
    assert.equal(outcome.expired, 0);
    const moment = (await readMoment(momentId)).data();
    assert.equal(moment.isPublished, true);
    assert.equal(moment.status, "published");
  });

  test("ANTI-TRAP: a Moment with no expiresAt is skipped, not expired", async () => {
    // No deadline now MEANS permanent (operator-chosen availability,
    // 2026-08, amending ADR-101): finalizeMomentDraft writes no expiresAt
    // for a "permanent" publish, and the legacy pre-expiry documents share
    // the exact same shape. Both stay published until their author deletes
    // them. A range filter never matches a document missing the field, so
    // they are structurally invisible to the sweep.
    const momentId = `${P}legacy`;
    const legacy = publishedMoment(momentId);
    delete legacy.expiresAt;
    await db.doc(`voiceMoments/${momentId}`).set(legacy);

    const outcome = await expireVoiceMoments({ now });

    assert.equal(outcome.scanned, 0);
    assert.equal(outcome.expired, 0);
    const moment = (await readMoment(momentId)).data();
    assert.equal(moment.isPublished, true);
    assert.equal(moment.status, "published");
  });

  test("ANTI-TRAP: even handed a permanent Moment directly, the flip refuses it", async () => {
    // The query above can never surface a document without expiresAt, but
    // the per-document transaction is a defence of its own: a caller (or a
    // future refactor) that hands expireMomentIfStillPastDeadline a
    // permanent Moment's reference must get "changed", never a retirement.
    // Permanent means published-until-deleted; no code path may age it out.
    const momentId = `${P}permanent`;
    const permanent = publishedMoment(momentId);
    delete permanent.expiresAt;
    await db.doc(`voiceMoments/${momentId}`).set(permanent);

    const outcome = await expireMomentIfStillPastDeadline(
      db.doc(`voiceMoments/${momentId}`),
      now(),
    );

    assert.equal(outcome, "changed");
    const moment = (await readMoment(momentId)).data();
    assert.equal(moment.isPublished, true);
    assert.equal(moment.status, "published");
    assert.equal(
      Object.prototype.hasOwnProperty.call(moment, "expiresAt"),
      false,
      "no deadline was backfilled",
    );
  });

  test("drafts, deleted and already-expired Moments are not candidates", async () => {
    await seedMoment(`${P}draft`, {
      isPublished: false,
      status: "uploading",
      audioUrl: null,
      mediaGeneration: null,
      mediaSize: null,
      mediaContentType: null,
      publishedAt: null,
    });
    await seedMoment(`${P}deleted`, {
      isPublished: false,
      isDeleted: true,
      status: "deleting",
    });
    await seedMoment(`${P}already`, { isPublished: false, status: "expired" });

    const outcome = await expireVoiceMoments({ now });

    assert.equal(outcome.scanned, 0);
    assert.equal(outcome.expired, 0);
    assert.equal((await readMoment(`${P}draft`)).data().status, "uploading");
    assert.equal((await readMoment(`${P}deleted`)).data().status, "deleting");
    assert.equal((await readMoment(`${P}already`)).data().status, "expired");
  });

  test("the transaction re-decides: a Moment that stopped being published is skipped", async () => {
    // Matches the SCAN (isPublished true, expiresAt past) but is not a
    // canonical published document by the time the transaction looks — the
    // same shape a concurrent delete or a corrupt writer would produce.
    // The per-document transaction must report it as changed, not flip it.
    const momentId = `${P}mutated`;
    await seedMoment(momentId, { status: "deleting", isDeleted: true, isPublished: true });

    const outcome = await expireVoiceMoments({ now });

    assert.equal(outcome.scanned, 1);
    assert.equal(outcome.expired, 0);
    assert.equal(outcome.skippedChanged, 1);
    const moment = (await readMoment(momentId)).data();
    assert.equal(moment.status, "deleting", "the delete in flight is preserved");
  });

  test("one failing Moment does not stop the others from expiring", async () => {
    const healthy = `${P}healthy`;
    const doomed = `${P}doomed`;
    // Order matters for determinism: the sweep processes by expiresAt
    // ascending, so give the failing document the earlier deadline.
    await seedMoment(doomed, {
      expiresAt: Timestamp.fromMillis(NOW_MILLIS - 120_000),
    });
    await seedMoment(healthy);

    const expireOne = (reference, cutoff) => {
      if (reference.id === doomed) {
        throw new Error("transaction unavailable");
      }
      return expireMomentIfStillPastDeadline(reference, cutoff);
    };

    await assert.rejects(
      expireVoiceMoments({ now, expireOne }),
      (error) => {
        assert.match(error.message, /1 of 2/u);
        assert.equal(error.outcome.expired, 1);
        assert.deepEqual(error.outcome.expiredMomentIds, [healthy]);
        assert.equal(error.outcome.failed, 1);
        return true;
      },
    );

    assert.equal((await readMoment(healthy)).data().status, "expired");
    assert.equal((await readMoment(doomed)).data().status, "published");
  });

  test("the scan bound truncates loudly and the next run finishes the job", async () => {
    for (let index = 0; index < 3; index += 1) {
      await seedMoment(`${P}backlog-${index}`, {
        expiresAt: Timestamp.fromMillis(NOW_MILLIS - (index + 1) * 60_000),
      });
    }

    const first = await expireVoiceMoments({ now, maxMoments: 2 });
    assert.equal(first.truncated, true);
    assert.equal(first.expired, 2);

    const second = await expireVoiceMoments({ now, maxMoments: 2 });
    assert.equal(second.truncated, false);
    assert.equal(second.expired, 1);

    for (let index = 0; index < 3; index += 1) {
      assert.equal(
        (await readMoment(`${P}backlog-${index}`)).data().status,
        "expired",
      );
    }
  });

  test("a run with an empty backlog does nothing and says so", async () => {
    const outcome = await expireVoiceMoments({ now });
    assert.deepEqual(outcome, {
      scanned: 0,
      expired: 0,
      expiredMomentIds: [],
      skippedChanged: 0,
      failed: 0,
      truncated: false,
    });
  });

  test("the scan bound is a real constant the schedule can be reasoned about with", () => {
    assert.equal(Number.isSafeInteger(MAX_EXPIRED_MOMENT_SCAN), true);
    assert.ok(MAX_EXPIRED_MOMENT_SCAN >= 100);
  });
});
