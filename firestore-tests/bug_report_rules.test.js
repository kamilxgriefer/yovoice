// In-app bug reports: the Firestore and Storage boundary.
//
//   firebase emulators:exec --only firestore,storage --project demo-yovoice \
//     'npm --prefix firestore-tests run test:bug-reports'
//
// ADR-007: no client query reads bugReports at all — the owner reads them
// through listBugReportsV1 (Admin SDK). The two query shapes that callable and
// the account-deletion sweep run, orderBy('createdAt','desc') and
// where('reporterId','==',uid), are exercised below as CLIENT queries to prove
// they are denied; no collectionGroup() query reads either collection, so none
// is needed or tested.
//
// Every object path is unique per case (a fresh report id): the Storage
// emulator's clearStorage() does not reach nested prefixes (docs/Bugs.md), so
// no case depends on another case's leftovers.
const fs = require('node:fs');
const path = require('node:path');
const { randomBytes } = require('node:crypto');
const { after, before, test } = require('node:test');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  setDoc,
  updateDoc,
  where,
} = require('firebase/firestore');
const {
  deleteObject,
  getBytes,
  listAll,
  ref,
  updateMetadata,
  uploadBytes,
} = require('firebase/storage');

// The emulator project itself: Storage rules' cross-service firestore.get()
// reads the Firestore of the project the emulators were started with.
const PROJECT = 'demo-yovoice';
const REPORTER = 'bug-reporter';
const OTHER = 'bug-other';
const OWNER = 'bug-owner';
const BANNED = 'bug-banned';
const DELETED = 'bug-deleted';
const SEEDED = 'br_' + 'a'.repeat(40);
let env;

function endpoint(value, fallback) {
  const parts = (value || ('127.0.0.1:' + fallback)).split(':');
  return { host: parts[0], port: Number(parts[1]) };
}

function newReportId() {
  return 'br_' + randomBytes(20).toString('hex');
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: {
      ...endpoint(process.env.FIRESTORE_EMULATOR_HOST, 8080),
      rules: fs.readFileSync(path.join(__dirname, '../firestore.rules'), 'utf8'),
    },
    storage: {
      ...endpoint(process.env.FIREBASE_STORAGE_EMULATOR_HOST, 9199),
      rules: fs.readFileSync(path.join(__dirname, '../storage.rules'), 'utf8'),
    },
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const entries = {
      ['users/' + REPORTER]: { displayName: REPORTER, status: 'active' },
      ['users/' + OTHER]: { displayName: OTHER, status: 'active' },
      ['users/' + OWNER]: { displayName: OWNER, status: 'active', role: 'superAdmin' },
      ['users/' + BANNED]: { displayName: BANNED, status: 'active', banned: true },
      ['users/' + DELETED]: { displayName: DELETED, status: 'deleted' },
      ['bugReports/' + SEEDED]: {
        schemaVersion: 1,
        reportId: SEEDED,
        reporterId: REPORTER,
        description: 'The send button stays grey.',
        status: 'new',
        createdAt: new Date(),
      },
      ['bugReportUploadReservations/' + SEEDED]: {
        schemaVersion: 1,
        kind: 'bugReportScreenshot',
        reportId: SEEDED,
        ownerId: REPORTER,
        contentType: 'image/jpeg',
        size: 4096,
        storagePath: 'bug_reports/' + REPORTER + '/' + SEEDED + '.jpg',
        status: 'uploading',
        createdAt: new Date(),
        expiresAt: new Date(Date.now() + 15 * 60_000),
      },
    };
    for (const [location, value] of Object.entries(entries)) {
      await setDoc(doc(db, location), value);
    }
  });
});

after(async () => {
  if (env) await env.cleanup();
});

function context(uid, { verified = true, role = null } = {}) {
  return env.authenticatedContext(uid, {
    email_verified: verified,
    ...(role ? { role } : {}),
  });
}

/** A server-issued reservation exactly as submitBugReportV1 writes it. */
async function reservation({ owner = REPORTER, reportId = newReportId(), size = 4096, overrides = {} } = {}) {
  const objectPath = 'bug_reports/' + owner + '/' + reportId + '.jpg';
  const value = {
    schemaVersion: 1,
    kind: 'bugReportScreenshot',
    reportId,
    ownerId: owner,
    contentType: 'image/jpeg',
    size,
    storagePath: objectPath,
    status: 'uploading',
    createdAt: new Date(),
    expiresAt: new Date(Date.now() + 15 * 60_000),
    ...overrides,
  };
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'bugReportUploadReservations/' + reportId), value);
  });
  return {
    reportId,
    objectPath,
    bytes: Buffer.alloc(size, 7),
    contentType: 'image/jpeg',
    metadata: { yovoiceOwnerUid: owner, yovoiceReportId: reportId },
  };
}

function upload(uid, target, {
  objectPath = target.objectPath,
  bytes = target.bytes,
  contentType = target.contentType,
  metadata = target.metadata,
  verified = true,
} = {}) {
  return uploadBytes(
    ref(context(uid, { verified }).storage(PROJECT), objectPath),
    bytes,
    { contentType, customMetadata: metadata },
  );
}

// ---------------------------------------------------------------- Firestore

test('Firestore: nobody reads a bug report — not the reporter, not staff, not the owner', async () => {
  const readers = [
    context(REPORTER),
    context(OTHER),
    context(OWNER, { role: 'superAdmin' }),
    context('bug-moderator', { role: 'moderator' }),
    env.unauthenticatedContext(),
  ];
  for (const reader of readers) {
    const db = reader.firestore();
    await assertFails(getDoc(doc(db, 'bugReports/' + SEEDED)));
    await assertFails(getDocs(collection(db, 'bugReports')));
    // The owner callable's list shape and the deletion sweep's shape, as
    // client queries: both denied.
    await assertFails(getDocs(query(collection(db, 'bugReports'), orderBy('createdAt', 'desc'), limit(25))));
    await assertFails(getDocs(query(collection(db, 'bugReports'), where('reporterId', '==', REPORTER))));
    await assertFails(getDoc(doc(db, 'bugReportUploadReservations/' + SEEDED)));
    await assertFails(getDocs(query(
      collection(db, 'bugReportUploadReservations'), where('ownerId', '==', REPORTER),
    )));
  }
});

test('Firestore: nobody writes a bug report or a reservation directly', async () => {
  for (const uid of [REPORTER, OTHER, OWNER]) {
    const db = context(uid, { role: uid === OWNER ? 'superAdmin' : null }).firestore();
    const forged = newReportId();
    await assertFails(setDoc(doc(db, 'bugReports/' + forged), {
      schemaVersion: 1, reportId: forged, reporterId: uid, description: 'Forged report text', status: 'new',
    }));
    await assertFails(updateDoc(doc(db, 'bugReports/' + SEEDED), { status: 'resolved' }));
    await assertFails(deleteDoc(doc(db, 'bugReports/' + SEEDED)));
    // A client cannot mint its own upload capability.
    await assertFails(setDoc(doc(db, 'bugReportUploadReservations/' + forged), {
      schemaVersion: 1, kind: 'bugReportScreenshot', reportId: forged, ownerId: uid,
      contentType: 'image/jpeg', size: 4096,
      storagePath: 'bug_reports/' + uid + '/' + forged + '.jpg',
      status: 'uploading', createdAt: new Date(), expiresAt: new Date(Date.now() + 60_000),
    }));
    await assertFails(updateDoc(doc(db, 'bugReportUploadReservations/' + SEEDED), { size: 1_000_000 }));
    await assertFails(deleteDoc(doc(db, 'bugReportUploadReservations/' + SEEDED)));
  }
});

// ------------------------------------------------------------------ Storage

test('Storage: the exact reserved JPEG is accepted, including from an unverified account', async () => {
  await assertSucceeds(upload(REPORTER, await reservation()));
  await assertSucceeds(upload(REPORTER, await reservation(), { verified: false }));
  // The size bounds' edges.
  await assertSucceeds(upload(REPORTER, await reservation({ size: 128 })));
  await assertSucceeds(upload(REPORTER, await reservation({ size: 1_500_000 })));
});

test('Storage: a missing, expired, used, forged or foreign reservation authorizes nothing', async () => {
  const orphan = newReportId();
  await assertFails(upload(REPORTER, {
    objectPath: 'bug_reports/' + REPORTER + '/' + orphan + '.jpg',
    bytes: Buffer.alloc(4096, 1),
    contentType: 'image/jpeg',
    metadata: { yovoiceOwnerUid: REPORTER, yovoiceReportId: orphan },
  }));
  await assertFails(upload(REPORTER, await reservation({
    overrides: { expiresAt: new Date(Date.now() - 1_000) },
  })));
  await assertFails(upload(REPORTER, await reservation({ overrides: { status: 'attached' } })));
  await assertFails(upload(REPORTER, await reservation({ overrides: { forged: true } })));
  await assertFails(upload(REPORTER, await reservation({ overrides: { kind: 'serverChannelMessageMedia' } })));
  await assertFails(upload(REPORTER, await reservation({ overrides: { ownerId: OTHER } })));
  // Another account writing into the reporter's reserved path.
  const owned = await reservation();
  await assertFails(upload(OTHER, owned));
  // The reporter writing under another uid's folder with that uid's reservation.
  const theirs = await reservation({ owner: OTHER });
  await assertFails(upload(REPORTER, theirs));
});

test('Storage: metadata, size, MIME and file name must all match the reservation', async () => {
  const target = await reservation();
  await assertFails(upload(REPORTER, target, { metadata: { ...target.metadata, extra: 'x' } }));
  await assertFails(upload(REPORTER, target, { metadata: { yovoiceReportId: target.reportId } }));
  await assertFails(upload(REPORTER, target, { metadata: { ...target.metadata, yovoiceOwnerUid: OTHER } }));
  await assertFails(upload(REPORTER, target, { bytes: Buffer.alloc(4095, 1) }));
  await assertFails(upload(REPORTER, target, { bytes: Buffer.alloc(4097, 1) }));
  await assertFails(upload(REPORTER, target, { contentType: 'image/png' }));
  await assertFails(upload(REPORTER, target, { objectPath: target.objectPath.replace(/\.jpg$/u, '.png') }));
  await assertFails(upload(REPORTER, target, {
    objectPath: 'bug_reports/' + REPORTER + '/' + newReportId() + '.jpg',
  }));
  // Outside the bounds even with a matching reservation.
  await assertFails(upload(REPORTER, await reservation({ size: 127 })));
  await assertFails(upload(REPORTER, await reservation({ size: 1_500_001 })));
  // Nothing above consumed the reservation.
  await assertSucceeds(upload(REPORTER, target));
});

test('Storage: banned and deleted accounts cannot upload, and an object is never overwritten', async () => {
  await assertFails(upload(BANNED, await reservation({ owner: BANNED })));
  await assertFails(upload(DELETED, await reservation({ owner: DELETED })));
  await assertFails(uploadBytes(
    ref(env.unauthenticatedContext().storage(PROJECT), 'bug_reports/' + REPORTER + '/' + newReportId() + '.jpg'),
    Buffer.alloc(4096, 1),
    { contentType: 'image/jpeg' },
  ));
  const once = await reservation();
  await assertSucceeds(upload(REPORTER, once));
  await assertFails(upload(REPORTER, once));
});

test('Storage: only the uploader reads back, only while reserved; no list, update or delete for anyone', async () => {
  const target = await reservation();
  await assertSucceeds(upload(REPORTER, target));
  const own = ref(context(REPORTER).storage(PROJECT), target.objectPath);
  await assertSucceeds(getBytes(own));
  for (const reader of [context(OTHER), context(OWNER, { role: 'superAdmin' }), env.unauthenticatedContext()]) {
    await assertFails(getBytes(ref(reader.storage(PROJECT), target.objectPath)));
  }
  await assertFails(updateMetadata(own, { customMetadata: { ...target.metadata, extra: 'x' } }));
  await assertFails(deleteObject(own));
  for (const prefix of ['bug_reports/' + REPORTER, 'bug_reports']) {
    await assertFails(listAll(ref(context(REPORTER).storage(PROJECT), prefix)));
    await assertFails(listAll(ref(context(OWNER, { role: 'superAdmin' }).storage(PROJECT), prefix)));
  }
  // Once attach consumes the reservation, even the uploader reads nothing.
  await env.withSecurityRulesDisabled(async (ctx) => {
    await deleteDoc(doc(ctx.firestore(), 'bugReportUploadReservations/' + target.reportId));
  });
  await assertFails(getBytes(own));
});
