/**
 * Rules coverage for the comment/@mention/Server notification slice
 * (ADR-213), run against the real ../firestore.rules.
 *
 * Two boundaries are asserted here:
 *
 *   1. `commentMentions/{id}` — who a comment @-mentions — is server-only in
 *      both directions. This is the whole reason the list is NOT a field on
 *      the comment: a Voice Moment comment is readable by the Moment's
 *      audience, so a mention list stored there would be published to every
 *      reader of the thread. If this collection ever became readable, the
 *      same leak would exist one document over.
 *   2. a notification row carrying the new optional fields is still exactly
 *      as locked down as before: the owner reads and deletes it, nobody
 *      creates one, and the owner's update allowlist cannot touch the
 *      routing fields (`targetSubId`, `sourcePath`) or the identity ones.
 */
const fs = require('node:fs');
const path = require('node:path');
const { after, before, test } = require('node:test');
const assert = require('node:assert/strict');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const {
  Timestamp,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  limit,
  query,
  setDoc,
  updateDoc,
} = require('firebase/firestore');

const PROJECT = 'demo-yovoice-notification-engagement';
const OWNER = 'engagement-owner';
const OTHER = 'engagement-other';
const MOMENT = 'engagement-moment';
const COMMENT = 'engagement-comment';
const MENTION_ID = `moment_${MOMENT}_${COMMENT}`;
let env;

function endpoint(value, fallback) {
  const parts = (value || `127.0.0.1:${fallback}`).split(':');
  return { host: parts[0], port: Number(parts[1]) };
}

function user(uid) {
  return {
    uid,
    displayName: uid,
    status: 'active',
    banned: false,
    disabled: false,
    accountType: 'personal',
  };
}

function notificationRow() {
  return {
    type: 'momentComment',
    actorId: OTHER,
    actorName: 'Canonical other',
    actorPhotoUrl: null,
    targetId: MOMENT,
    targetSubId: COMMENT,
    sourcePath: `voiceMoments/${MOMENT}/comments/${COMMENT}`,
    targetLabel: null,
    isRead: false,
    bellSuppressed: false,
    dedupeKey: `momentComment_${COMMENT}`,
    createdAt: Timestamp.now(),
  };
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: {
      ...endpoint(process.env.FIRESTORE_EMULATOR_HOST, 8080),
      rules: fs.readFileSync(path.join(__dirname, '../firestore.rules'), 'utf8'),
    },
  });
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      setDoc(doc(db, `users/${OWNER}`), user(OWNER)),
      setDoc(doc(db, `users/${OTHER}`), user(OTHER)),
      // Exactly what the comment callable writes beside the comment.
      setDoc(doc(db, `commentMentions/${MENTION_ID}`), {
        schemaVersion: 1,
        kind: 'moment',
        parentId: MOMENT,
        commentId: COMMENT,
        actorId: OTHER,
        mentionUserIds: [OWNER],
        createdAt: Timestamp.now(),
      }),
      // Exactly what the comment trigger writes into the author's inbox.
      setDoc(
        doc(db, `users/${OWNER}/notifications/momentComment_${COMMENT}`),
        notificationRow(),
      ),
    ]);
  });
});

after(async () => {
  if (env) await env.cleanup();
});

const context = (uid) => env.authenticatedContext(uid, { email_verified: true });

test('the comment mention record is server-only for everybody', async () => {
  for (const uid of [OWNER, OTHER]) {
    const db = context(uid).firestore();
    await assertFails(getDoc(doc(db, `commentMentions/${MENTION_ID}`)));
    await assertFails(getDocs(query(
      collection(db, 'commentMentions'),
      limit(10),
    )));
    await assertFails(setDoc(doc(db, `commentMentions/forged_${uid}`), {
      schemaVersion: 1,
      kind: 'moment',
      parentId: MOMENT,
      commentId: COMMENT,
      actorId: uid,
      mentionUserIds: [OWNER],
      createdAt: Timestamp.now(),
    }));
    await assertFails(updateDoc(doc(db, `commentMentions/${MENTION_ID}`), {
      mentionUserIds: [uid],
    }));
    await assertFails(deleteDoc(doc(db, `commentMentions/${MENTION_ID}`)));
  }
  // An unauthenticated client has no wider reach.
  const anonymous = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(anonymous, `commentMentions/${MENTION_ID}`)));
});

test('an engagement notification row stays owner-read, server-write', async () => {
  const owner = context(OWNER).firestore();
  const other = context(OTHER).firestore();
  const rowPath = `users/${OWNER}/notifications/momentComment_${COMMENT}`;

  const read = await assertSucceeds(getDoc(doc(owner, rowPath)));
  // The new optional routing fields are readable by their owner — that is
  // how the bell deep-links to the exact comment.
  assert.equal(read.data().targetSubId, COMMENT);
  assert.equal(
    read.data().sourcePath,
    `voiceMoments/${MOMENT}/comments/${COMMENT}`,
  );
  await assertFails(getDoc(doc(other, rowPath)));

  // Acknowledging stays allowed; rewriting the routing or identity fields
  // does not, so a client cannot point its own row at somebody else's
  // Moment or forge who commented.
  await assertSucceeds(updateDoc(doc(owner, rowPath), {
    isRead: true,
    readAt: Timestamp.now(),
  }));
  await assertFails(updateDoc(doc(owner, rowPath), { targetSubId: 'other' }));
  await assertFails(updateDoc(doc(owner, rowPath), {
    sourcePath: 'voiceMoments/someone-elses/comments/x',
  }));
  await assertFails(updateDoc(doc(owner, rowPath), { actorId: OWNER }));
  await assertFails(updateDoc(doc(owner, rowPath), { type: 'system' }));

  // Nobody creates a notification, including for themselves.
  await assertFails(setDoc(
    doc(owner, `users/${OWNER}/notifications/forged`),
    notificationRow(),
  ));
  await assertFails(setDoc(
    doc(other, `users/${OWNER}/notifications/forged-by-other`),
    notificationRow(),
  ));

  // The owner may still delete their own row.
  await assertSucceeds(deleteDoc(doc(owner, rowPath)));
});

test('a Server event and its opt-in responses stay callable-owned', async () => {
  // Reminder opt-ins are read by the scheduler through the Admin SDK. A
  // client can never write one, so nobody can subscribe themselves — or
  // anybody else — to a reminder for a Server they are not in.
  const outsider = context(OTHER).firestore();
  const eventPath =
    'clubs/engagement-server/channels/engagement-channel/events/engagement-event';
  await assertFails(setDoc(doc(outsider, eventPath), {
    schemaVersion: 1,
    status: 'scheduled',
    reminderOptInEnabled: true,
  }));
  await assertFails(setDoc(doc(outsider, `${eventPath}/responses/${OTHER}`), {
    schemaVersion: 1,
    userId: OTHER,
    reminderRequested: true,
  }));
  await assertFails(getDoc(doc(outsider, eventPath)));
});
