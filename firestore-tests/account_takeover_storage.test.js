/**
 * Storage half of the pre-registered account takeover epoch
 * (functions/auth/federated_takeover.js; firestore.rules
 * sessionPredatesAuthEpoch). `isActiveUser()` reads the caller's own
 * users/{uid} document, so a session whose sign-in predates
 * `authSessionEpoch` must be refused there too — for uploads and for reads of
 * the account's private media — while the owner's post-epoch session and an
 * untouched account behave exactly as before.
 *
 * Run (repo root):
 *   firebase emulators:exec --only firestore,storage --project demo-yovoice \
 *     'npm --prefix firestore-tests run test:storage'
 */
const fs = require('node:fs');
const path = require('node:path');
const { after, before, test } = require('node:test');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const { doc, setDoc } = require('firebase/firestore');
const { getBytes, ref, uploadBytes } = require('firebase/storage');

const PROJECT = 'demo-yovoice';
const OWNER = 'storage-takeover-owner';
const CLEAN = 'storage-takeover-clean';
const EPOCH = 1_900_000_000;
const image = new Uint8Array(64 * 1024);
let env;

function endpoint(value, fallback) {
  const separator = value?.lastIndexOf(':') ?? -1;
  return separator > 0
    ? { host: value.slice(0, separator), port: Number(value.slice(separator + 1)) }
    : { host: '127.0.0.1', port: fallback };
}

function storageFor(uid, authTime, provider = 'password') {
  return env.authenticatedContext(uid, {
    email_verified: true,
    auth_time: authTime,
    firebase: { sign_in_provider: provider, identities: {} },
  }).storage();
}

// The exact reservation reserveProfileMediaUpload writes before an avatar
// upload, and the object path/metadata the client then uses.
async function reserveAvatar(ownerId, uploadId) {
  const storagePath = `users/${ownerId}/profile/avatar_${uploadId}.jpg`;
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), `profileMediaUploadReservations/${ownerId}/uploads/${uploadId}`),
      {
        schemaVersion: 1,
        ownerId,
        uploadId,
        kind: 'avatar',
        contentType: 'image/jpeg',
        size: image.length,
        storagePath,
        baseRevision: 0,
        status: 'uploading',
        createdAt: new Date(),
        expiresAt: new Date(Date.now() + 10 * 60 * 1000),
      },
    );
  });
  return {
    storagePath,
    metadata: {
      contentType: 'image/jpeg',
      customMetadata: { ownerId, profileKind: 'avatar', uploadId },
    },
  };
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
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, `users/${OWNER}`), {
      uid: OWNER,
      displayName: OWNER,
      authSessionEpoch: EPOCH,
    });
    await setDoc(doc(db, `users/${CLEAN}`), { uid: CLEAN, displayName: CLEAN });
  });
});

after(async () => {
  if (env) await env.cleanup();
});

test('a session older than the epoch cannot upload or read private media', async () => {
  const owned = await reserveAvatar(OWNER, 'a'.repeat(32));
  // Uploaded by the owner's post-epoch session so there is something to read.
  await assertSucceeds(uploadBytes(
    ref(storageFor(OWNER, EPOCH + 5, 'google.com'), owned.storagePath),
    image,
    owned.metadata,
  ));

  const stale = storageFor(OWNER, EPOCH - 3600);
  await assertFails(getBytes(ref(stale, owned.storagePath)));

  const second = await reserveAvatar(OWNER, 'b'.repeat(32));
  await assertFails(uploadBytes(ref(stale, second.storagePath), image, second.metadata));
  await assertFails(uploadBytes(
    ref(storageFor(OWNER, EPOCH - 1, 'google.com'), second.storagePath),
    image,
    second.metadata,
  ));

  // The owner's own session after the epoch keeps full access.
  const fresh = storageFor(OWNER, EPOCH, 'google.com');
  await assertSucceeds(getBytes(ref(fresh, owned.storagePath)));
  await assertSucceeds(uploadBytes(ref(fresh, second.storagePath), image, second.metadata));
});

test('an account without an epoch is unaffected however old its session', async () => {
  const clean = await reserveAvatar(CLEAN, 'c'.repeat(32));
  await assertSucceeds(uploadBytes(
    ref(storageFor(CLEAN, 1_000_000_000), clean.storagePath),
    image,
    clean.metadata,
  ));
});
