/**
 * Rules coverage for ADR-237, run against the real ../firestore.rules.
 *
 * Two boundaries are asserted here:
 *
 *   1. `users/{uid}.appLanguage` — the language the owner's app is shown in,
 *      which Cloud Functions read to write a push in the recipient's
 *      language. The owner may write it directly (create, merge and update),
 *      but ONLY as one of the 43 selectable locale keys: the push boundary
 *      treats the field as a closed enum. Nobody else can write it or read
 *      it, and holding it never stops an older client's update of another
 *      field.
 *   2. `pagePostFanoutOutbox/{id}` — the durable cursor of "a Page you follow
 *      published a post" — is server-only in both directions, like the
 *      room-live outbox it is modelled on.
 *
 *   firebase emulators:exec --only firestore --project demo-yovoice \
 *     'npm --prefix firestore-tests run test:notify-follow'
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
  deleteField,
  doc,
  getDoc,
  getDocs,
  limit,
  query,
  setDoc,
  updateDoc,
} = require('firebase/firestore');

const PROJECT = 'demo-yovoice-notify-follow';
const OWNER = 'language-owner';
const OTHER = 'language-other';
const FRESH = 'language-fresh';
const LEGACY = 'language-legacy';
// lib/core/localization/app_language.dart: every selectable `localeKey`.
const LOCALE_KEYS = [
  'en', 'pl', 'de', 'es', 'pt', 'pt_BR', 'fr', 'it', 'uk', 'ru',
  'cs', 'sk', 'bg', 'nl', 'ro', 'tr', 'el', 'hu', 'hr', 'sr',
  'sv', 'da', 'nb', 'fi', 'lt', 'lv', 'et', 'id', 'vi', 'zh_CN',
  'zh_TW', 'ja', 'ko', 'ar', 'hi', 'bn', 'ur', 'th', 'ms', 'fil',
  'he', 'fa', 'sw',
];
let env;

function endpoint(value, fallback) {
  const parts = (value || `127.0.0.1:${fallback}`).split(':');
  return { host: parts[0], port: Number(parts[1]) };
}

function user(uid, extra = {}) {
  return {
    uid,
    displayName: uid,
    status: 'active',
    banned: false,
    disabled: false,
    accountType: 'personal',
    ...extra,
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
      // An account that already stored its language (build 42+).
      setDoc(doc(db, `users/${LEGACY}`), user(LEGACY, { appLanguage: 'de' })),
      // Exactly what the outbox trigger keeps.
      setDoc(doc(db, 'pagePostFanoutOutbox/page_post_probe'), {
        schemaVersion: 1,
        postId: `pp_${'a'.repeat(40)}`,
        pageId: OTHER,
        sourcePath: `pagePosts/pp_${'a'.repeat(40)}`,
        sourceGeneration: '1:2',
        targetLabel: 'New post from a Page you follow: Other',
        postPreview: 'Hello',
        pageKind: 'business',
        afterId: null,
        status: 'pending',
        stoppedReason: null,
        followers: 0,
        pages: 0,
        written: 0,
        createdAt: Timestamp.now(),
        updatedAt: Timestamp.now(),
        expiresAt: Timestamp.now(),
      }),
    ]);
  });
});

after(async () => {
  if (env) await env.cleanup();
});

const context = (uid) => env.authenticatedContext(uid, { email_verified: true });

test('the allowlist in the rules is exactly the 43 app languages', () => {
  assert.equal(LOCALE_KEYS.length, 43);
  assert.equal(new Set(LOCALE_KEYS).size, 43);
  const rules = fs.readFileSync(path.join(__dirname, '../firestore.rules'), 'utf8');
  const block = rules.slice(
    rules.indexOf('function appLanguageValueAllowed()'),
    rules.indexOf('function userCreateAllowed('),
  );
  const allowed = [...block.matchAll(/'([A-Za-z_]+)'/g)]
    .map((match) => match[1])
    .filter((value) => value !== 'appLanguage');
  assert.deepEqual([...allowed].sort(), [...LOCALE_KEYS].sort());
});

test('the owner stores any of the 43 languages, by update and by merge', async () => {
  const db = context(OWNER).firestore();
  const own = doc(db, `users/${OWNER}`);
  for (const key of LOCALE_KEYS) {
    await assertSucceeds(updateDoc(own, { appLanguage: key }));
  }
  // The client's real write: a merge set of this one field.
  await assertSucceeds(setDoc(own, { appLanguage: 'pt_BR' }, { merge: true }));
  await assertSucceeds(setDoc(own, { appLanguage: 'zh_TW' }, { merge: true }));
  const stored = (await getDoc(own)).data();
  assert.equal(stored.appLanguage, 'zh_TW');
  // Nothing else moved.
  assert.equal(stored.displayName, OWNER);
  assert.equal(stored.accountType, 'personal');
});

test('anything that is not one of the 43 keys is refused', async () => {
  const db = context(OWNER).firestore();
  const own = doc(db, `users/${OWNER}`);
  for (const value of [
    'system', 'xx', 'PL', 'pl ', ' pl', 'pt-BR', 'pt_br', 'zh', 'zh-Hant',
    'english', '', 'pl'.repeat(60), 42, true, null, ['pl'], { key: 'pl' },
  ]) {
    await assertFails(updateDoc(own, { appLanguage: value }));
    await assertFails(setDoc(own, { appLanguage: value }, { merge: true }));
  }
  // A valid language does not smuggle a forbidden field along with it.
  await assertFails(updateDoc(own, { appLanguage: 'pl', premiumIdentity: true }));
  await assertFails(updateDoc(own, { appLanguage: 'pl', role: 'superAdmin' }));
  await assertFails(updateDoc(own, { appLanguage: 'pl', disabled: false, banned: false,
    status: 'deleted' }));
  await assertFails(updateDoc(own, { appLanguage: 'pl', followerCount: 10 }));
});

test('a first write may be the language alone, and only a valid one', async () => {
  const db = context(FRESH).firestore();
  const own = doc(db, `users/${FRESH}`);
  // The profile document does not exist yet (the same first-write race the
  // presence heartbeat has): a merge set of the language creates it.
  await assertFails(setDoc(own, { appLanguage: 'klingon' }, { merge: true }));
  await assertFails(setDoc(own, { appLanguage: 'pl', role: 'superAdmin' }, { merge: true }));
  await assertSucceeds(setDoc(own, { appLanguage: 'pl' }, { merge: true }));
  assert.deepEqual((await getDoc(own)).data(), { appLanguage: 'pl' });
});

test('nobody else writes or reads it', async () => {
  const other = context(OTHER).firestore();
  await assertFails(updateDoc(doc(other, `users/${OWNER}`), { appLanguage: 'de' }));
  await assertFails(setDoc(doc(other, `users/${OWNER}`), { appLanguage: 'de' }, { merge: true }));
  await assertFails(getDoc(doc(other, `users/${OWNER}`)));
  const anonymous = env.unauthenticatedContext().firestore();
  await assertFails(updateDoc(doc(anonymous, `users/${OWNER}`), { appLanguage: 'de' }));
  await assertFails(getDoc(doc(anonymous, `users/${OWNER}`)));
  // The owner reads their own.
  await assertSucceeds(getDoc(doc(context(OWNER).firestore(), `users/${OWNER}`)));
});

test('holding a language never blocks another update, and it can be removed', async () => {
  const db = context(LEGACY).firestore();
  const own = doc(db, `users/${LEGACY}`);
  // What every build writes: presence, preferences, profile fields.
  await assertSucceeds(updateDoc(own, { 'notificationPreferences.pagePostPublished': false }));
  await assertSucceeds(updateDoc(own, { 'notificationPreferences.liveStarted': true }));
  await assertSucceeds(setDoc(own, { isOnline: true, lastSeen: Timestamp.now() }, { merge: true }));
  await assertSucceeds(updateDoc(own, { bio: 'Hello' }));
  assert.equal((await getDoc(own)).data().appLanguage, 'de');
  // Removing it is harmless: pushes fall back to English.
  await assertSucceeds(updateDoc(own, { appLanguage: deleteField() }));
  assert.equal(Object.hasOwn((await getDoc(own)).data(), 'appLanguage'), false);
});

test('the Page post fan-out outbox is server-only for everybody', async () => {
  for (const uid of [OWNER, OTHER]) {
    const db = context(uid).firestore();
    const row = doc(db, 'pagePostFanoutOutbox/page_post_probe');
    await assertFails(getDoc(row));
    await assertFails(getDocs(query(collection(db, 'pagePostFanoutOutbox'), limit(10))));
    await assertFails(setDoc(doc(db, `pagePostFanoutOutbox/forged_${uid}`), {
      schemaVersion: 1,
      status: 'pending',
      pageId: uid,
    }));
    // Rewinding the cursor would replay a page; completing it would drop one.
    await assertFails(updateDoc(row, { afterId: null }));
    await assertFails(updateDoc(row, { status: 'complete' }));
    await assertFails(deleteDoc(row));
  }
  const moderator = env.authenticatedContext('staff-probe', {
    email_verified: true,
    role: 'superAdmin',
  }).firestore();
  await assertFails(getDoc(doc(moderator, 'pagePostFanoutOutbox/page_post_probe')));
  const anonymous = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(anonymous, 'pagePostFanoutOutbox/page_post_probe')));
});
