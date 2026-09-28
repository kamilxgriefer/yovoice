// Premium Pages post media (ADR-233 §1.10, §3.2, package B2): the Storage
// boundary, against the real ../storage.rules and ../firestore.rules.
//
//   firebase emulators:exec --only firestore,storage --project demo-yovoice \
//     'npm --prefix firestore-tests run test:pages-storage'
//
// The capability is ONE live reservation pagePostMediaReservations/{mediaId},
// written as reservePagePostMediaV1 writes it; Storage rules read it with a
// cross-service firestore.get(). Asserted: the exact reserved jpeg and m4a
// upload; a missing, expired, claimed ("expiring") or foreign reservation
// authorizes nothing; the rev. 2 bounds (jpeg only 128 B-4 MiB, m4a 512 B-4
// MiB, the name and extension of the reserved media id); exact custom
// metadata; unverified, banned and other accounts are refused; NOBODY reads
// (the uploader included: no durable download token can be minted), lists,
// updates or deletes. The object's HTTP headers are checked by
// publishPagePostV1, not the rules (functions/test/pages_posts.test.js).
//
// No collectionGroup() query reads any Pages collection (ADR-233 Appendix
// A); the Firestore side of these collections is covered by
// pages_rules.test.js. Every object path is unique per case (a fresh media
// id), because the Storage emulator's clearStorage() does not reach nested
// prefixes (docs/Bugs.md).
const fs = require('node:fs');
const path = require('node:path');
const { randomBytes } = require('node:crypto');
const { after, before, test } = require('node:test');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const { deleteDoc, doc, setDoc, updateDoc } = require('firebase/firestore');
const {
  deleteObject,
  getBytes,
  getDownloadURL,
  listAll,
  ref,
  updateMetadata,
  uploadBytes,
} = require('firebase/storage');

// Storage rules' cross-service firestore.get() reads the Firestore of the
// project the emulators were started with.
const PROJECT = 'demo-yovoice';
const OWNER = 'pgs-owner';
const OTHER = 'pgs-other';
const BANNED = 'pgs-banned';
let env;

function endpoint(value, fallback) {
  const parts = (value || ('127.0.0.1:' + fallback)).split(':');
  return { host: parts[0], port: Number(parts[1]) };
}

function hex40() {
  return randomBytes(20).toString('hex');
}

const MEDIA = {
  jpg: { type: 'image', contentType: 'image/jpeg', size: 815, durationMs: null, width: 32, height: 24 },
  m4a: { type: 'audio', contentType: 'audio/mp4', size: 10068, durationMs: 3000, width: null, height: null },
};

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
    await setDoc(doc(db, 'users/' + OWNER), { displayName: OWNER, status: 'active', disabled: false });
    await setDoc(doc(db, 'users/' + OTHER), { displayName: OTHER, status: 'active', disabled: false });
    await setDoc(doc(db, 'users/' + BANNED), { displayName: BANNED, status: 'active', banned: true });
  });
});

after(async () => {
  if (env) await env.cleanup();
});

function context(uid, verified = true) {
  return env.authenticatedContext(uid, { email_verified: verified });
}

/**
 * A reservation exactly as reservePagePostMediaV1 writes it, and the exact
 * upload identity for it.
 */
async function reservation({
  ext = 'jpg',
  owner = OWNER,
  postId = 'pp_' + hex40(),
  mediaId = 'pm_' + hex40(),
  overrides = {},
} = {}) {
  const shape = MEDIA[ext];
  const objectPath = 'page_posts/' + owner + '/' + postId + '/' + mediaId + '.' + ext;
  const value = {
    schemaVersion: 1,
    kind: 'pagePostMedia',
    pageId: owner,
    ownerId: owner,
    postId,
    mediaId,
    index: 0,
    type: shape.type,
    contentType: shape.contentType,
    size: shape.size,
    durationMs: shape.durationMs,
    width: shape.width,
    height: shape.height,
    storagePath: objectPath,
    requestId: 'reserve-' + mediaId.slice(3, 15),
    status: 'uploading',
    createdAt: new Date(),
    expiresAt: new Date(Date.now() + 15 * 60_000),
    ...overrides,
  };
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'pagePostMediaReservations/' + mediaId), value);
  });
  return {
    mediaId,
    postId,
    objectPath,
    bytes: Buffer.alloc(value.size, 7),
    contentType: value.contentType,
    metadata: {
      yovoicePageId: owner,
      yovoicePostId: postId,
      yovoiceMediaId: mediaId,
      yovoiceMediaType: shape.type,
    },
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
    ref(context(uid, verified).storage(), objectPath),
    bytes,
    { contentType, customMetadata: metadata },
  );
}

async function setReservation(mediaId, patch) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), 'pagePostMediaReservations/' + mediaId), patch);
  });
}

test('Storage: the exact reserved photo and voice clip upload', async () => {
  await assertSucceeds(upload(OWNER, await reservation({ ext: 'jpg' })));
  await assertSucceeds(upload(OWNER, await reservation({ ext: 'm4a' })));
});

test('Storage: a missing, expired, claimed or foreign reservation authorizes nothing', async () => {
  // No reservation at all.
  const postId = 'pp_' + hex40();
  const mediaId = 'pm_' + hex40();
  await assertFails(upload(OWNER, {
    objectPath: 'page_posts/' + OWNER + '/' + postId + '/' + mediaId + '.jpg',
    bytes: Buffer.alloc(815, 1),
    contentType: 'image/jpeg',
    metadata: {
      yovoicePageId: OWNER, yovoicePostId: postId, yovoiceMediaId: mediaId, yovoiceMediaType: 'image',
    },
  }));
  // Expired.
  const expired = await reservation({ overrides: { expiresAt: new Date(Date.now() - 1000) } });
  await assertFails(upload(OWNER, expired));
  // Claimed by the expiry worker.
  const claimed = await reservation();
  await setReservation(claimed.mediaId, { status: 'expiring' });
  await assertFails(upload(OWNER, claimed));
  // Consumed by publish (deleted).
  const consumed = await reservation();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await deleteDoc(doc(ctx.firestore(), 'pagePostMediaReservations/' + consumed.mediaId));
  });
  await assertFails(upload(OWNER, consumed));
  // Somebody else's reservation, uploaded by another account to the owner's
  // path or to their own.
  const owners = await reservation();
  await assertFails(upload(OTHER, owners));
  await assertFails(upload(OTHER, owners, {
    objectPath: owners.objectPath.replace(OWNER, OTHER),
    metadata: { ...owners.metadata, yovoicePageId: OTHER },
  }));
  // A reservation for another post, or a non-exact one.
  const foreignPost = await reservation({ overrides: { postId: 'pp_' + hex40() } });
  await assertFails(upload(OWNER, foreignPost));
  const extraKey = await reservation({ overrides: { note: 'x' } });
  await assertFails(upload(OWNER, extraKey));
  const wrongKind = await reservation({ overrides: { kind: 'serverChannelMessageMedia' } });
  await assertFails(upload(OWNER, wrongKind));
});

test('Storage: rev. 2 bounds, types and names', async () => {
  // A JPEG under 128 B or over 4 MiB, even with a matching reservation.
  const tiny = await reservation({ overrides: { size: 127 } });
  await assertFails(upload(OWNER, tiny, { bytes: Buffer.alloc(127, 1) }));
  const huge = await reservation({ overrides: { size: 4 * 1024 * 1024 + 1 } });
  await assertFails(upload(OWNER, huge, { bytes: Buffer.alloc(4 * 1024 * 1024 + 1, 1) }));
  const edge = await reservation({ overrides: { size: 4 * 1024 * 1024 } });
  await assertSucceeds(upload(OWNER, edge, { bytes: Buffer.alloc(4 * 1024 * 1024, 1) }));
  // PNG and WebP are not Page photo types.
  const png = await reservation({ overrides: { contentType: 'image/png' } });
  await assertFails(upload(OWNER, png, { contentType: 'image/png' }));
  const webp = await reservation({ overrides: { contentType: 'image/webp' } });
  await assertFails(upload(OWNER, webp, { contentType: 'image/webp' }));
  // A voice clip under 512 B, or not audio/mp4.
  const shortClip = await reservation({ ext: 'm4a', overrides: { size: 511 } });
  await assertFails(upload(OWNER, shortClip, { bytes: Buffer.alloc(511, 1) }));
  const mp3 = await reservation({ ext: 'm4a', overrides: { contentType: 'audio/mpeg' } });
  await assertFails(upload(OWNER, mp3, { contentType: 'audio/mpeg' }));
  // The declared size must be the reserved one.
  const sized = await reservation();
  await assertFails(upload(OWNER, sized, { bytes: Buffer.alloc(816, 1) }));
  // Names: the extension of the media type, the media id of the metadata.
  const named = await reservation();
  await assertFails(upload(OWNER, named, { objectPath: named.objectPath.replace('.jpg', '.jpeg') }));
  await assertFails(upload(OWNER, named, { objectPath: named.objectPath.replace('.jpg', '.m4a') }));
  const swapped = await reservation();
  await assertFails(upload(OWNER, swapped, {
    metadata: { ...swapped.metadata, yovoiceMediaType: 'audio' },
  }));
});

test('Storage: exact custom metadata only', async () => {
  const target = await reservation();
  await assertFails(upload(OWNER, target, { metadata: { ...target.metadata, extra: '1' } }));
  const { yovoiceMediaType, ...missing } = target.metadata;
  await assertFails(upload(OWNER, target, { metadata: missing }));
  await assertFails(upload(OWNER, target, {
    metadata: { ...target.metadata, yovoicePostId: 'pp_' + hex40() },
  }));
  await assertFails(upload(OWNER, target, {
    metadata: { ...target.metadata, yovoicePageId: OTHER },
  }));
  await assertSucceeds(upload(OWNER, target));
});

test('Storage: unverified, banned and signed-out uploads are refused', async () => {
  const target = await reservation();
  await assertFails(upload(OWNER, target, { verified: false }));
  const banned = await reservation({ owner: BANNED });
  await assertFails(upload(BANNED, banned));
  await assertFails(uploadBytes(
    ref(env.unauthenticatedContext().storage(), target.objectPath),
    target.bytes,
    { contentType: target.contentType, customMetadata: target.metadata },
  ));
});

test('Storage: nobody reads, lists, updates or deletes, the uploader included', async () => {
  const target = await reservation();
  await assertSucceeds(upload(OWNER, target));
  const own = ref(context(OWNER).storage(), target.objectPath);
  // Not even while the reservation is live: a read would let the uploader
  // mint a durable download token (getDownloadURL).
  await assertFails(getBytes(own));
  await assertFails(getDownloadURL(own));
  await assertFails(getBytes(ref(context(OTHER).storage(), target.objectPath)));
  await assertFails(getBytes(ref(env.unauthenticatedContext().storage(), target.objectPath)));
  await assertFails(listAll(ref(context(OWNER).storage(), 'page_posts/' + OWNER + '/' + target.postId)));
  await assertFails(listAll(ref(context(OWNER).storage(), 'page_posts/' + OWNER)));
  await assertFails(updateMetadata(own, { customMetadata: { ...target.metadata, yovoiceMediaType: 'audio' } }));
  await assertFails(updateMetadata(own, { cacheControl: 'public, max-age=31536000' }));
  await assertFails(deleteObject(own));
  // An overwrite is a create on an existing object: refused.
  await assertFails(upload(OWNER, target));
  await env.withSecurityRulesDisabled(async (ctx) => {
    await deleteDoc(doc(ctx.firestore(), 'pagePostMediaReservations/' + target.mediaId));
  });
  await assertFails(getBytes(own));
  await assertFails(deleteObject(own));
});
