/**
 * Rules coverage for Premium Pages (ADR-233 §3.1), run against the real
 * ../firestore.rules with production-shaped client operations (ADR-007).
 *
 * Every Pages collection is server-written and reached through the
 * functions/pages callables. The one client path is the OWNER's `get` of
 * their own pages/{uid} document (settings and lapse notices), and only
 * while the account is active. Asserted here, for the owner, a stranger, a
 * banned owner and an unauthenticated client:
 *
 *   1. pages/{uid}: owner get succeeds; banned owner, stranger and anonymous
 *      get fail; every list shape the app or an attacker could issue fails
 *      (plain list, the owner's own `where`, the Find query, the lapse-sweep
 *      query); create / update / merge / delete fail, alone, in a batch and
 *      in a transaction.
 *   2. every other Pages collection (posts, post likes, comments, follow
 *      index, visibility index, media reservations / leases / budgets /
 *      deletion jobs, post cleanup jobs, maintenance cursors, open-report
 *      counters, staff media audit, adult refusals, the lapse-sweep cursor,
 *      evidence retention) and appConfig/pagesV1 deny get, list and every
 *      write, for the owner and for everybody else;
 *   3. a collection-group query over `likes` cannot reach Page post likes;
 *   4. (package B5) a Page report is server-written: active staff read it
 *      through the Moderation Center's own queue query, nobody else reads
 *      it, and no client can file one (the create rule has no Page branch);
 *      the owner reads and marks read the pageModeration / pageLapse rows,
 *      and nobody can forge one.
 */
const fs = require('node:fs');
const path = require('node:path');
const { after, before, test } = require('node:test');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const {
  collection,
  collectionGroup,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  runTransaction,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} = require('firebase/firestore');

const PROJECT = 'demo-yovoice-pages-rules';
const OWNER = 'pages-owner';
const BANNED = 'pages-banned-owner';
const STRANGER = 'pages-stranger';
const POST = `pp_${'a'.repeat(40)}`;
const COMMENT = `pc_${'b'.repeat(40)}`;
const MEDIA = `pm_${'c'.repeat(40)}`;
let env;

function endpoint(value, fallback) {
  const parts = (value || `127.0.0.1:${fallback}`).split(':');
  return { host: parts[0], port: Number(parts[1]) };
}

function profile(uid, extra = {}) {
  return {
    uid,
    email: `${uid}@example.com`,
    displayName: uid,
    username: uid,
    accountType: 'personal',
    ...extra,
  };
}

function pageRecord(uid) {
  const at = new Date(1_900_000_000_000);
  return {
    schemaVersion: 1,
    pageId: uid,
    ownerId: uid,
    kind: 'business',
    status: 'active',
    lapsedAt: null,
    ownerPaused: false,
    suspended: false,
    suspendedAt: null,
    suspensionReason: null,
    listed: false,
    category: 'cafe_restaurant',
    description: 'Coffee.',
    business: {
      website: null, email: null, phone: null, address: null, hours: null, legalNotice: null,
    },
    community: null,
    displayName: uid,
    nameSearch: uid,
    nameChangedAt: null,
    postCount: 0,
    lastPostAt: null,
    pinnedPostId: null,
    adultAttestedAt: at,
    adultAttestationMethod: 'self_declared_birth_date',
    consentVersion: 1,
    createdAt: at,
    updatedAt: at,
  };
}

// Every server-only Pages path, with the document the server would hold.
const SERVER_ONLY = Object.freeze([
  [`pagePosts/${POST}`, { schemaVersion: 1, postId: POST, pageId: OWNER, authorId: OWNER, status: 'published' }],
  [`pagePosts/${POST}/likes/${STRANGER}`, { schemaVersion: 1, userId: STRANGER, postId: POST }],
  [`pagePostComments/${COMMENT}`, { schemaVersion: 1, commentId: COMMENT, postId: POST, pageId: OWNER, authorId: STRANGER }],
  [`pageFollowIndex/${STRANGER}`, { schemaVersion: 1, pageIds: [OWNER] }],
  [`pageFollowCarryJobs/${OWNER}`, { schemaVersion: 1, pageId: OWNER, afterId: null }],
  ['pageVisibility/v1', { schemaVersion: 1, notViewable: {}, readOnlySince: {} }],
  [`pagePostMediaReservations/${MEDIA}`, { schemaVersion: 1, ownerId: OWNER, mediaId: MEDIA }],
  [`pagePostMediaLeases/${OWNER}`, { schemaVersion: 1, ownerId: OWNER }],
  [`pagePostBudgets/${OWNER}_20300101`, { schemaVersion: 1, pageId: OWNER, posts: 0 }],
  ['pagePostMediaDeletionJobs/job-1', { schemaVersion: 1, heldBy: null }],
  [`pagePostCleanupJobs/${POST}`, { schemaVersion: 1, postId: POST, pageId: OWNER }],
  ['pageMaintenanceState/orphanSweep', { schemaVersion: 1, pageToken: null }],
  [`pagePostOpenReports/${POST}`, { count: 1 }],
  ['pageStaffMediaAudit/audit-1', { staffUid: 'staff', postId: POST }],
  [`pageAdultRefusals/${OWNER}`, { schemaVersion: 1, refusedAt: new Date() }],
  ['pageMaintenanceState/lapseSweep', { schemaVersion: 1, phase: 'active', afterId: null }],
  [`pageEvidenceRetention/${POST}`, { schemaVersion: 1, postId: POST, pageId: OWNER, reason: 'accountDeleted' }],
  ['appConfig/pagesV1', { schemaVersion: 1, readAccess: 'all', writeAccess: 'all' }],
  // ADR-236: an owner's Page deletion, "delete all posts" and the memory of
  // a deleted Page. Keyed by the OWNER's uid, and still not the owner's.
  [`pageDeletions/${OWNER}`, { schemaVersion: 1, pageId: OWNER, state: 'pending' }],
  [`pagePostClearJobs/${OWNER}`, { schemaVersion: 1, pageId: OWNER, cursor: null }],
  [`pageMemory/${OWNER}`, { schemaVersion: 1, pageId: OWNER, suspension: null }],
]);

function client(uid) {
  return uid === null
    ? env.unauthenticatedContext().firestore()
    : env.authenticatedContext(uid, { email_verified: true }).firestore();
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
      setDoc(doc(db, `users/${OWNER}`), profile(OWNER)),
      setDoc(doc(db, `users/${BANNED}`), profile(BANNED, { banned: true })),
      setDoc(doc(db, `users/${STRANGER}`), profile(STRANGER)),
      setDoc(doc(db, `pages/${OWNER}`), pageRecord(OWNER)),
      setDoc(doc(db, `pages/${BANNED}`), pageRecord(BANNED)),
      ...SERVER_ONLY.map(([docPath, data]) => setDoc(doc(db, docPath), data)),
    ]);
  });
});

after(async () => {
  if (env) await env.cleanup();
});

test('the owner reads their own Page record; nobody else does', async () => {
  await assertSucceeds(getDoc(doc(client(OWNER), `pages/${OWNER}`)));
  await assertFails(getDoc(doc(client(BANNED), `pages/${BANNED}`)));
  await assertFails(getDoc(doc(client(STRANGER), `pages/${OWNER}`)));
  await assertFails(getDoc(doc(client(null), `pages/${OWNER}`)));
  // A missing own Page is readable as "absent" (the app's pre-create check).
  await assertSucceeds(getDoc(doc(client(STRANGER), `pages/${STRANGER}`)));
});

test('no Page list query succeeds, including the owner\'s own and the Find shapes', async () => {
  for (const uid of [OWNER, STRANGER, null]) {
    const db = client(uid);
    await assertFails(getDocs(collection(db, 'pages')));
    await assertFails(getDocs(query(collection(db, 'pages'), where('ownerId', '==', OWNER))));
    await assertFails(getDocs(query(collection(db, 'pages'), where('pageId', '==', OWNER), limit(1))));
    await assertFails(getDocs(query(
      collection(db, 'pages'),
      where('listed', '==', true),
      orderBy('lastPostAt', 'desc'),
      limit(40),
    )));
    await assertFails(getDocs(query(
      collection(db, 'pages'),
      where('listed', '==', true),
      orderBy('nameSearch'),
      limit(40),
    )));
    await assertFails(getDocs(query(
      collection(db, 'pages'),
      where('status', '==', 'readOnly'),
      orderBy('lapsedAt'),
    )));
  }
});

test('no client creates, edits or deletes a Page, alone, batched or in a transaction', async () => {
  const owner = client(OWNER);
  const stranger = client(STRANGER);
  await assertFails(setDoc(doc(stranger, `pages/${STRANGER}`), pageRecord(STRANGER)));
  await assertFails(setDoc(doc(owner, `pages/${OWNER}`), pageRecord(OWNER)));
  await assertFails(updateDoc(doc(owner, `pages/${OWNER}`), { ownerPaused: true }));
  await assertFails(updateDoc(doc(owner, `pages/${OWNER}`), { status: 'active', lapsedAt: null }));
  await assertFails(updateDoc(doc(owner, `pages/${OWNER}`), { suspended: false }));
  await assertFails(setDoc(doc(owner, `pages/${OWNER}`), { listed: true }, { merge: true }));
  await assertFails(updateDoc(doc(owner, `pages/${OWNER}`), { updatedAt: serverTimestamp() }));
  await assertFails(deleteDoc(doc(owner, `pages/${OWNER}`)));
  await assertFails(deleteDoc(doc(stranger, `pages/${OWNER}`)));

  const batch = writeBatch(owner);
  batch.update(doc(owner, `pages/${OWNER}`), { description: 'edited' });
  batch.set(doc(owner, `pageFollowIndex/${OWNER}`), { schemaVersion: 1, pageIds: [] });
  await assertFails(batch.commit());

  await assertFails(runTransaction(owner, async (transaction) => {
    const snapshot = await transaction.get(doc(owner, `pages/${OWNER}`));
    transaction.update(snapshot.ref, { postCount: 99 });
  }));
});

test('every other Pages collection and the kill switch deny every client', async () => {
  for (const uid of [OWNER, STRANGER, null]) {
    const db = client(uid);
    for (const [docPath, data] of SERVER_ONLY) {
      await assertFails(getDoc(doc(db, docPath)));
      await assertFails(setDoc(doc(db, docPath), data));
      await assertFails(setDoc(doc(db, docPath), { touched: true }, { merge: true }));
      await assertFails(deleteDoc(doc(db, docPath)));
      const parent = docPath.split('/').slice(0, -1).join('/');
      await assertFails(getDocs(collection(db, parent)));
    }
  }
  // The liker's own edge and the commenter's own comment are not client
  // paths either: callerLiked and comment lists come from callables.
  const liker = client(STRANGER);
  await assertFails(getDocs(query(
    collection(liker, `pagePosts/${POST}/likes`),
    orderBy('createdAt', 'desc'),
    limit(20),
  )));
  await assertFails(getDocs(query(
    collection(liker, 'pagePostComments'),
    where('postId', '==', POST),
    orderBy('createdAt', 'desc'),
    limit(20),
  )));
  await assertFails(getDocs(query(
    collection(liker, 'pagePosts'),
    where('pageId', 'in', [OWNER]),
    where('status', '==', 'published'),
    orderBy('createdAt', 'desc'),
    limit(21),
  )));
});

test('a collection-group query over likes cannot reach Page post likes', async () => {
  for (const uid of [OWNER, STRANGER]) {
    const db = client(uid);
    await assertFails(getDocs(query(collectionGroup(db, 'likes'), where('userId', '==', STRANGER))));
    await assertFails(getDocs(query(collectionGroup(db, 'likes'), where('postId', '==', POST), limit(5))));
  }
});

// Package B3 (ADR-233 §1.6, D12): a Page's follow edges are the ordinary
// users/{a}/following/{p} + users/{p}/followers/{a} pair and the rules are
// unchanged. A Page can never have Creator audience on (managePageV1 and
// setCreatorAudienceEnabled refuse it), so canReadCreatorAudienceEdges keeps
// its followers unlistable to everybody else, followers included. The owner
// may still read their own edges (Appendix A: v1 shows the count only; that
// is presentation, not an authorization boundary).
test('nobody but the owner lists a Page account\'s follow edges', async () => {
  const followedAt = new Date(1_900_000_000_000);
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      setDoc(doc(db, `users/${OWNER}/followers/${STRANGER}`), { uid: STRANGER, followedAt }),
      setDoc(doc(db, `users/${STRANGER}/following/${OWNER}`), { uid: OWNER, followedAt }),
    ]);
  });
  const follower = client(STRANGER);
  await assertFails(getDocs(query(collection(follower, `users/${OWNER}/followers`), limit(20))));
  await assertFails(getDoc(doc(follower, `users/${OWNER}/followers/${STRANGER}`)));
  await assertFails(getDocs(query(collection(client(null), `users/${OWNER}/followers`), limit(20))));
  await assertSucceeds(getDocs(query(collection(client(OWNER), `users/${OWNER}/followers`), limit(20))));
  // The follow edge and the index hint are server-written only.
  await assertFails(setDoc(doc(follower, `users/${STRANGER}/following/${OWNER}`), { uid: OWNER, followedAt }));
  await assertFails(setDoc(doc(follower, `pageFollowIndex/${STRANGER}`), { schemaVersion: 1, pageIds: [OWNER], updatedAt: followedAt }));
});

// Package B4 (ADR-233 §2.6): a comment writes the owner's `pagePostComment`
// bell row with the Admin SDK. The notifications rules are unchanged and
// type-agnostic; this runs the app's two real bell queries (the indexed
// VISIBLE query and the BASE query) and the mark-read update against that
// exact row shape, and proves nobody else can read, forge or rewrite it.
test('the owner reads and marks read a pagePostComment bell row; nobody else touches it', async () => {
  const rowPath = `users/${OWNER}/notifications/pagePostComment_${COMMENT}`;
  const row = {
    type: 'pagePostComment',
    actorId: STRANGER,
    actorName: 'Ola Nowak',
    actorPhotoUrl: null,
    targetId: POST,
    targetLabel: 'Ola Nowak commented on your Page post',
    isRead: false,
    createdAt: new Date(1_900_000_000_000),
    dedupeKey: `pagePostComment_${COMMENT}`,
    bellSuppressed: false,
    targetSubId: COMMENT,
    sourcePath: `pagePostComments/${COMMENT}`,
  };
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), rowPath), row);
  });
  const owner = client(OWNER);
  const own = collection(owner, `users/${OWNER}/notifications`);
  await assertSucceeds(getDocs(query(own, where('bellSuppressed', '==', false),
    orderBy('createdAt', 'desc'), limit(50))));
  await assertSucceeds(getDocs(query(own, orderBy('createdAt', 'desc'), limit(50))));
  await assertSucceeds(updateDoc(doc(owner, rowPath), { isRead: true, readAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(owner, rowPath), { targetLabel: 'Forged' }));
  await assertFails(updateDoc(doc(owner, rowPath), { sourcePath: `pagePostComments/${'c'.repeat(43)}` }));

  const stranger = client(STRANGER);
  await assertFails(getDoc(doc(stranger, rowPath)));
  await assertFails(getDocs(query(collection(stranger, `users/${OWNER}/notifications`), limit(50))));
  await assertFails(setDoc(doc(stranger, `users/${OWNER}/notifications/pagePostComment_${'d'.repeat(43)}`), row));
  await assertFails(setDoc(doc(owner, `users/${OWNER}/notifications/pagePostComment_${'e'.repeat(43)}`), row));
  // The comment and the like behind it stay server-only, for the owner too.
  await assertFails(getDoc(doc(owner, `pagePostComments/${COMMENT}`)));
  await assertFails(getDoc(doc(owner, `pagePosts/${POST}/likes/${STRANGER}`)));
  await assertSucceeds(deleteDoc(doc(owner, rowPath)));
});

// ---------------------------------------------------------------- B5

const MODERATOR = 'pages-moderator';
const PAGE_REPORT = 'd'.repeat(40);

function staffClient(uid, role) {
  return env.authenticatedContext(uid, { email_verified: true, role }).firestore();
}

test('a Page report is read by active staff through the queue query, and by nobody else', async () => {
  const report = {
    schemaVersion: 2,
    reporterId: STRANGER,
    targetType: 'pagePost',
    targetId: POST,
    reportedUserId: OWNER,
    contextPath: `pagePosts/${POST}`,
    pageId: OWNER,
    postId: POST,
    commentId: null,
    pageKind: 'business',
    pageDisplayName: OWNER,
    targetPostKind: 'text',
    targetTextSnapshot: 'Fresh bread at 7.',
    targetMedia: [],
    note: '',
    reason: 'spam',
    status: 'open',
    createdAt: new Date(1_900_000_000_000),
    updatedAt: new Date(1_900_000_000_000),
  };
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, `users/${MODERATOR}`), profile(MODERATOR, { role: 'moderator' }));
    await setDoc(doc(db, `reports/${PAGE_REPORT}`), report);
  });
  const moderator = staffClient(MODERATOR, 'moderator');
  await assertSucceeds(getDoc(doc(moderator, `reports/${PAGE_REPORT}`)));
  const queue = await assertSucceeds(getDocs(query(collection(moderator, 'reports'),
    where('status', '==', 'open'), orderBy('createdAt', 'desc'), limit(20))));
  if (!queue.docs.some((entry) => entry.id === PAGE_REPORT)) {
    throw new Error('the Page report is missing from the staff queue');
  }
  await assertSucceeds(getDocs(query(collection(moderator, 'reports'),
    where('status', '==', 'open'), where('targetType', '==', 'pagePost'),
    orderBy('createdAt', 'desc'), limit(20))));
  // Staff still cannot move it: the workflow is moderateReport only.
  await assertFails(updateDoc(doc(moderator, `reports/${PAGE_REPORT}`), { status: 'resolved' }));
  // The reporter, the reported owner and anybody else read nothing.
  for (const uid of [STRANGER, OWNER, null]) {
    await assertFails(getDoc(doc(client(uid), `reports/${PAGE_REPORT}`)));
    await assertFails(getDocs(query(collection(client(uid), 'reports'),
      where('status', '==', 'open'), orderBy('createdAt', 'desc'), limit(20))));
  }
  // A token claiming staff without the users/{uid}.role mirror reads nothing.
  await assertFails(getDoc(doc(staffClient(STRANGER, 'moderator'), `reports/${PAGE_REPORT}`)));
});

test('no client can file a Page report, even in the client report id format', async () => {
  const reporter = client(STRANGER);
  for (const [targetType, targetId, contextPath] of [
    ['pagePost', POST, `pagePosts/${POST}`],
    ['pagePostComment', COMMENT, `pagePostComments/${COMMENT}`],
    ['page', OWNER, `pages/${OWNER}`],
  ]) {
    await assertFails(setDoc(doc(reporter, `reports/${STRANGER}_${targetType}_${targetId}`), {
      reporterId: STRANGER,
      targetType,
      targetId,
      reportedUserId: OWNER,
      contextPath,
      reason: 'spam',
      note: '',
      createdAt: serverTimestamp(),
      status: 'open',
    }));
  }
});

test('the owner reads and marks read pageModeration and pageLapse rows; nobody forges one', async () => {
  const rows = {
    [`users/${OWNER}/notifications/pageModeration_${'e'.repeat(40)}`]: {
      type: 'pageModeration',
      actorId: 'yovoice-system',
      actorName: 'YO Voice',
      actorPhotoUrl: null,
      targetId: OWNER,
      targetSubId: POST,
      targetLabel: 'Your Page post was removed: spam',
      isRead: false,
      createdAt: new Date(1_900_000_000_000),
      dedupeKey: `pageModeration_${'e'.repeat(40)}`,
      bellSuppressed: false,
      moderationAction: 'postRemoved',
      moderationReason: 'spam',
    },
    [`users/${OWNER}/notifications/pageLapse_readOnly_1900000000000`]: {
      type: 'pageLapse',
      actorId: 'yovoice-system',
      actorName: 'YO Voice',
      actorPhotoUrl: null,
      targetId: OWNER,
      targetLabel: 'Your Page is read-only because YO Voice VIP ended. Nothing is deleted.',
      isRead: false,
      createdAt: new Date(1_900_000_000_001),
      dedupeKey: 'pageLapse_readOnly_1900000000000',
      bellSuppressed: false,
      lapsePhase: 'readOnly',
    },
  };
  await env.withSecurityRulesDisabled(async (context) => {
    await Promise.all(Object.entries(rows).map(([rowPath, row]) =>
      setDoc(doc(context.firestore(), rowPath), row)));
  });
  const owner = client(OWNER);
  const own = collection(owner, `users/${OWNER}/notifications`);
  await assertSucceeds(getDocs(query(own, where('bellSuppressed', '==', false),
    orderBy('createdAt', 'desc'), limit(50))));
  for (const [rowPath, row] of Object.entries(rows)) {
    await assertSucceeds(updateDoc(doc(owner, rowPath), { isRead: true, readAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(owner, rowPath), { targetLabel: 'Forged' }));
    await assertFails(getDoc(doc(client(STRANGER), rowPath)));
    await assertFails(setDoc(doc(owner, `${rowPath}_copy`), row));
    await assertFails(setDoc(doc(client(STRANGER), `${rowPath}_forged`), row));
  }
});

// Audit 2026-09-28: staff tokens WITH the users/{uid}.role mirror are the
// callers a future staff read rule would most plausibly admit. Every Pages
// collection stays server-only for them too (staff see Page content through
// the report snapshot and the audited media-access callable only).
test('active staff (superAdmin, moderator) read and write no Pages collection', async () => {
  const STAFF = [['pages-qa-super', 'superAdmin'], ['pages-qa-moderator', 'moderator'],
    ['pages-qa-supermod', 'superModerator']];
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    for (const [uid, role] of STAFF) {
      await setDoc(doc(db, `users/${uid}`), profile(uid, { role }));
    }
  });
  for (const [uid, role] of STAFF) {
    const db = staffClient(uid, role);
    for (const [docPath, data] of SERVER_ONLY) {
      await assertFails(getDoc(doc(db, docPath)));
      await assertFails(setDoc(doc(db, docPath), data));
      await assertFails(deleteDoc(doc(db, docPath)));
      const parent = docPath.split('/').slice(0, -1).join('/');
      await assertFails(getDocs(collection(db, parent)));
    }
    await assertFails(getDoc(doc(db, `pages/${OWNER}`)));
    await assertFails(getDocs(collection(db, 'pages')));
    await assertFails(getDocs(query(collection(db, 'pages'), where('listed', '==', true),
      orderBy('lastPostAt', 'desc'), limit(40))));
    await assertFails(updateDoc(doc(db, `pages/${OWNER}`), { suspended: true }));
    await assertFails(getDocs(query(collection(db, 'pageStaffMediaAudit'),
      where('staffUid', '==', uid))));
    await assertFails(getDocs(query(collectionGroup(db, 'likes'), where('postId', '==', POST))));
  }
});
