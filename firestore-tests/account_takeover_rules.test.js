/**
 * Rules coverage for the pre-registered account takeover remediation
 * (functions/auth/federated_takeover.js), run against the real
 * ../firestore.rules with production-shaped client operations.
 *
 * The remediation revokes refresh tokens, but an ID token already issued stays
 * valid for up to an hour. `users/{uid}.authSessionEpoch` is what makes the
 * rules refuse it. Asserted here:
 *
 *   1. a session whose sign-in (`auth_time`) predates the epoch cannot
 *      register or refresh a push token — the write the remediation's purge
 *      must not be raced by — whatever provider it signed in with;
 *   2. a session that signed in at or after the epoch can (the owner's
 *      re-sign-in), and an account without the field behaves exactly as
 *      before, however old its session;
 *   3. the stale session may still delete its own push row (sign-out cleanup);
 *   4. no client can write the epoch (create, raise, lower or remove it);
 *   5. the ledger, audit and sweep-state collections are unreachable.
 *
 * The epoch is deliberately checked only on the push-token write (and in
 * Storage isActiveUser): folding it into isActiveAccount() exceeded the
 * 1000-expression budget of an existing Servers list rule.
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
  deleteDoc,
  deleteField,
  doc,
  getDoc,
  getDocs,
  limit,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
} = require('firebase/firestore');

const PROJECT = 'demo-yovoice-account-takeover';
const OWNER = 'takeover-owner';
const CLEAN = 'takeover-clean';
const FRESH = 'takeover-fresh';
const STAFF = 'takeover-staff';
const EPOCH = 1_900_000_000;
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

// The exact claims shape Firebase Auth issues. `firebase.sign_in_provider`
// is the provider of the ORIGINAL sign-in; a refresh keeps it and keeps
// `auth_time`, which is why the epoch compares `auth_time`.
function session(uid, { authTime, provider = 'password', role } = {}) {
  return env.authenticatedContext(uid, {
    email_verified: true,
    auth_time: authTime,
    firebase: { sign_in_provider: provider, identities: {} },
    ...(role ? { role } : {}),
  }).firestore();
}

// What NotificationService.registerFcmToken writes.
function pushRow() {
  return { platform: 'android', directVideoProtocol: 1, updatedAt: serverTimestamp() };
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
      setDoc(doc(db, `users/${OWNER}`), profile(OWNER, { authSessionEpoch: EPOCH })),
      setDoc(doc(db, `users/${CLEAN}`), profile(CLEAN)),
      setDoc(doc(db, `users/${STAFF}`), profile(STAFF, {
        role: 'moderator',
        authSessionEpoch: EPOCH,
      })),
      setDoc(doc(db, `users/${OWNER}/fcmTokens/planted-device`), {
        platform: 'android',
        updatedAt: new Date(),
      }),
      setDoc(doc(db, `authPasswordLedger/${OWNER}`), { state: 'remediated' }),
      setDoc(doc(db, 'authTakeoverAudit/audit-1'), { uid: OWNER }),
      setDoc(doc(db, 'authTakeoverSweep/state'), { ledgerCursor: null }),
    ]);
  });
});

after(async () => {
  if (env) await env.cleanup();
});

test('a session older than the epoch cannot plant a push token', async () => {
  // The pre-registrant's password session, refreshed after the owner's
  // Google sign-in: email_verified is true, auth_time is the old sign-in.
  const stalePassword = session(OWNER, { authTime: EPOCH - 3600 });
  await assertFails(setDoc(
    doc(stalePassword, `users/${OWNER}/fcmTokens/attacker-device-2`),
    pushRow(),
  ));
  await assertFails(setDoc(
    doc(stalePassword, `users/${OWNER}/fcmTokens/planted-device`),
    pushRow(),
  ));

  // Provider-agnostic: a Google identity the pre-registrant linked before the
  // takeover signs in as google.com, and one second before the epoch is
  // still before it.
  const staleGoogle = session(OWNER, { authTime: EPOCH - 1, provider: 'google.com' });
  await assertFails(setDoc(
    doc(staleGoogle, `users/${OWNER}/fcmTokens/attacker-device-3`),
    pushRow(),
  ));
});

test('the owner\'s session after the epoch registers push normally', async () => {
  const atEpoch = session(OWNER, { authTime: EPOCH, provider: 'google.com' });
  await assertSucceeds(setDoc(
    doc(atEpoch, `users/${OWNER}/fcmTokens/owner-device`),
    pushRow(),
  ));
  const later = session(OWNER, { authTime: EPOCH + 600, provider: 'apple.com' });
  await assertSucceeds(setDoc(
    doc(later, `users/${OWNER}/fcmTokens/owner-device`),
    pushRow(),
  ));
});

test('an account the remediation never touched is unaffected', async () => {
  // No authSessionEpoch: a years-old password session behaves as before.
  const oldSession = session(CLEAN, { authTime: 1_000_000_000 });
  await assertSucceeds(setDoc(
    doc(oldSession, `users/${CLEAN}/fcmTokens/clean-device`),
    pushRow(),
  ));
});

test('a stale session can still remove its own push row on sign-out', async () => {
  const stale = session(OWNER, { authTime: EPOCH - 10 });
  await assertSucceeds(deleteDoc(doc(stale, `users/${OWNER}/fcmTokens/planted-device`)));
});

test('no client can write the session epoch', async () => {
  const owner = session(OWNER, { authTime: EPOCH + 60, provider: 'google.com' });
  await assertFails(updateDoc(doc(owner, `users/${OWNER}`), { authSessionEpoch: 0 }));
  await assertFails(updateDoc(doc(owner, `users/${OWNER}`), {
    authSessionEpoch: EPOCH + 10_000,
  }));
  await assertFails(updateDoc(doc(owner, `users/${OWNER}`), {
    authSessionEpoch: deleteField(),
  }));
  // An allowed profile edit still goes through beside the server field.
  await assertSucceeds(updateDoc(doc(owner, `users/${OWNER}`), { bio: 'hello' }));

  // A pre-registrant creating the profile cannot seed an epoch either (a
  // future epoch would lock the real owner out).
  const fresh = session(FRESH, { authTime: EPOCH });
  await assertFails(setDoc(doc(fresh, `users/${FRESH}`), profile(FRESH, {
    authSessionEpoch: EPOCH + 10_000,
  })));
  await assertSucceeds(setDoc(doc(fresh, `users/${FRESH}`), profile(FRESH)));
});

test('the ledger, audit and sweep state are server-only', async () => {
  const contexts = [
    session(OWNER, { authTime: EPOCH + 60, provider: 'google.com' }),
    session(CLEAN, { authTime: EPOCH + 60 }),
    session(STAFF, { authTime: EPOCH + 60, role: 'moderator' }),
    env.unauthenticatedContext().firestore(),
  ];
  const paths = [
    `authPasswordLedger/${OWNER}`,
    'authTakeoverAudit/audit-1',
    'authTakeoverSweep/state',
  ];
  for (const db of contexts) {
    for (const docPath of paths) {
      await assertFails(getDoc(doc(db, docPath)));
      await assertFails(setDoc(doc(db, docPath), { state: 'verified' }));
      await assertFails(updateDoc(doc(db, docPath), { state: 'verified' }));
      await assertFails(deleteDoc(doc(db, docPath)));
    }
    for (const name of ['authPasswordLedger', 'authTakeoverAudit', 'authTakeoverSweep']) {
      await assertFails(getDocs(query(collection(db, name), limit(5))));
    }
    // Nobody can pre-mark their own planted password as verified.
    await assertFails(setDoc(doc(db, `authPasswordLedger/${CLEAN}`), {
      state: 'verified',
    }));
  }
});
