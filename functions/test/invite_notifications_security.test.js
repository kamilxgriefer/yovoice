const assert = require("node:assert/strict");
const { test, beforeEach, after } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-fn-test";

const { initializeApp, getApps } = require("firebase-admin/app");
if (getApps().length === 0) initializeApp();

const { db } = require("../utils/firestore");
const { sendClubInvite } = require("../notifications/invites");
const { createNotificationForEvent } = require("../notifications/canonical");

const runSendClubInvite = sendClubInvite.run ?? sendClubInvite;
const P = "ins-";
const OWNER = `${P}owner`;
const INVITEE = `${P}invitee`;
const CLUB = `${P}club`;

function request(data, verified = true) {
  return {
    auth: { uid: OWNER, token: { email_verified: verified } },
    data,
  };
}

async function reset() {
  await Promise.all([
    db.recursiveDelete(db.doc(`users/${OWNER}`)),
    db.recursiveDelete(db.doc(`users/${INVITEE}`)),
    db.recursiveDelete(db.doc(`clubs/${CLUB}`)),
    db.doc(`restrictions/${OWNER}`).delete(),
    db.doc(`restrictions/${INVITEE}`).delete(),
  ]);
  const ledgers = await db.collection("notificationDeliveryEvents").get();
  await Promise.all(
    ledgers.docs
      .filter((document) => document.data().sourcePath?.includes(CLUB))
      .map((document) => document.ref.delete()),
  );
}

async function seed() {
  await Promise.all([
    db.doc(`users/${OWNER}`).set({
      uid: OWNER,
      displayName: "Canonical Owner",
      photoUrl: "https://example.invalid/owner.jpg",
      banned: false,
      disabled: false,
    }),
    db.doc(`users/${INVITEE}`).set({
      uid: INVITEE,
      displayName: "Canonical Invitee",
      banned: false,
      disabled: false,
    }),
    db.doc(`clubs/${CLUB}`).set({
      ownerId: OWNER,
      name: "Canonical Club",
      avatarUrl: "https://example.invalid/club.jpg",
      status: "active",
      deletionInProgress: false,
    }),
    db.doc(`clubs/${CLUB}/members/${OWNER}`).set({
      userId: OWNER,
      role: "owner",
      banned: false,
    }),
    db.doc(`users/${OWNER}/friends/${INVITEE}`).set({ userId: INVITEE }),
    db.doc(`users/${INVITEE}/friends/${OWNER}`).set({ userId: OWNER }),
  ]);
}

beforeEach(async () => {
  await reset();
  await seed();
});
after(reset);

test("Club invite source is canonical and callable replay is idempotent", async () => {
  const input = request({
    clubId: CLUB,
    inviteeId: INVITEE,
    clubName: "FORGED CLUB",
    inviterName: "FORGED OWNER",
  });
  const first = await runSendClubInvite(input);
  const replay = await runSendClubInvite(input);
  assert.equal(first.changed, true);
  assert.equal(replay.changed, false);

  const invite = await db.doc(`clubs/${CLUB}/invites/${INVITEE}`).get();
  assert.equal(invite.data().clubName, "Canonical Club");
  assert.equal(invite.data().inviterName, "Canonical Owner");
  assert.equal(invite.data().inviterId, OWNER);
  assert.ok(invite.data().createdAt);
});

test("Club invite rejects non-friends, blocks and active sanctions", async () => {
  await db.doc(`users/${INVITEE}/friends/${OWNER}`).delete();
  await assert.rejects(
    runSendClubInvite(request({ clubId: CLUB, inviteeId: INVITEE })),
    (error) => error.code === "permission-denied",
  );
  await db.doc(`users/${INVITEE}/friends/${OWNER}`).set({ userId: OWNER });
  await db.doc(`users/${INVITEE}/blocked/${OWNER}`).set({ userId: OWNER });
  await assert.rejects(
    runSendClubInvite(request({ clubId: CLUB, inviteeId: INVITEE })),
    (error) => error.code === "permission-denied",
  );
  await db.doc(`users/${INVITEE}/blocked/${OWNER}`).delete();
  await db.doc(`restrictions/${OWNER}`).set({
    type: "communicationMute",
    expiresAt: null,
  });
  await assert.rejects(
    runSendClubInvite(request({ clubId: CLUB, inviteeId: INVITEE })),
    (error) => error.code === "permission-denied",
  );
});

test("event ledger makes canonical invite notification exactly-once", async () => {
  await runSendClubInvite(request({ clubId: CLUB, inviteeId: INVITEE }));
  const sourcePath = `clubs/${CLUB}/invites/${INVITEE}`;
  const eventInput = {
    eventId: `${P}event-1`,
    recipientId: INVITEE,
    actorId: OWNER,
    type: "clubInvite",
    notificationId: `clubInvite_${CLUB}_${INVITEE}`,
    targetId: CLUB,
    targetLabel: "Canonical Club",
    sourcePath,
    validate: async (transaction) =>
      (await transaction.get(db.doc(sourcePath))).exists,
  };
  assert.equal(await createNotificationForEvent(eventInput), "written");
  assert.equal(await createNotificationForEvent(eventInput), "skipped:replay");

  const notification = db.doc(
    `users/${INVITEE}/notifications/clubInvite_${CLUB}_${INVITEE}`,
  );
  const payload = (await notification.get()).data();
  assert.equal(payload.actorName, "Canonical Owner");
  assert.equal(payload.targetLabel, "Canonical Club");
  assert.equal(payload.type, "clubInvite");

  await notification.delete();
  assert.equal(await createNotificationForEvent(eventInput), "skipped:replay");
  assert.equal((await notification.get()).exists, false, "must not resurrect");
});
