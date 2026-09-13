const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { after, test } = require('node:test');

const enabled = /^(127[.]0[.]0[.]1|localhost):[0-9]+$/u.test(
  process.env.FIRESTORE_EMULATOR_HOST ?? '',
);
let app;
let db;
let Timestamp;
if (enabled) {
  const adminApp = require('firebase-admin/app');
  const firestore = require('firebase-admin/firestore');
  Timestamp = firestore.Timestamp;
  app = adminApp.getApps().length === 0
    ? adminApp.initializeApp({ projectId: 'demo-yovoice-creator-audience' })
    : adminApp.getApp();
  db = firestore.getFirestore(app);
}

const {
  CREATOR_AGE_CONFIRMATION_RATE_SCOPE,
  CREATOR_AUDIENCE_RATE_SCOPE,
  confirmCreatorAdultEligibility,
  confirmCreatorAdultEligibilityHandler,
  creatorAudienceVisibleFromSource,
  derivePublicProfile,
  paidCreatorAudienceEligibility,
  requireAdultBirthDate,
  setCreatorAudienceEnabled,
  setCreatorAudienceEnabledHandler,
} = require('../profile/public_profiles');
const { operationIdentity, rateLimitReference } = require('../integrity/guards');

const NOW_MS = 1_900_000_000_000;
const emulatorTest = (name, fn) => test('Creator audience: ' + name, {
  skip: enabled ? false : 'Requires explicit localhost Firestore emulator; no cloud fallback.',
  timeout: 60_000,
}, fn);
const request = (uid, data, verified = true) => ({
  auth: { uid, token: { email_verified: verified } },
  data,
});

after(async () => {
  if (app) await require('firebase-admin/app').deleteApp(app);
});

function canonicalUser(overrides = {}) {
  return {
    displayName: 'Canonical Creator',
    username: 'creator',
    status: 'active',
    accountType: 'creator',
    premiumIdentity: true,
    creatorAgeVerified: true,
    creatorAudienceEnabled: false,
    friendCount: 4,
    followerCount: 17,
    followingCount: 3,
    ...overrides,
  };
}

function canonicalEntitlement(overrides = {}) {
  return {
    status: 'active',
    isPremium: true,
    premiumIdentityEnabled: true,
    creatorEnabled: true,
    currentPeriodEnd: Timestamp.fromMillis(NOW_MS + 24 * 60 * 60_000),
    ...overrides,
  };
}

function birthDateYearsAgo(years) {
  const current = new Date(NOW_MS);
  return [
    current.getUTCFullYear() - years,
    String(current.getUTCMonth() + 1).padStart(2, '0'),
    String(current.getUTCDate()).padStart(2, '0'),
  ].join('-');
}

async function fixture(userOverrides = {}, entitlementOverrides = {}) {
  const uid = 'creator-' + randomUUID();
  await Promise.all([
    db.doc('users/' + uid).set(canonicalUser(userOverrides)),
    db.doc('entitlements/' + uid).set(canonicalEntitlement(entitlementOverrides)),
  ]);
  return uid;
}

test('public projection emits one safe boolean and zeros audience counters by default', () => {
  const hidden = derivePublicProfile('creator', canonicalUser());
  assert.equal(hidden.creatorAudienceVisible, false);
  assert.equal(hidden.followerCount, 0);
  assert.equal(hidden.followingCount, 0);
  assert.equal('creatorAgeVerified' in hidden, false);
  assert.equal('creatorAudienceEnabled' in hidden, false);

  const visible = derivePublicProfile('creator', canonicalUser({
    creatorAudienceEnabled: true,
  }));
  assert.equal(visible.creatorAudienceVisible, true);
  assert.equal(visible.followerCount, 17);
  assert.equal(visible.followingCount, 3);

  const staffOnly = canonicalUser({
    role: 'moderator',
    premiumIdentity: false,
    creatorAudienceEnabled: true,
  });
  assert.equal(derivePublicProfile('staff', staffOnly).accountType, 'creator');
  assert.equal(derivePublicProfile('staff', staffOnly).creatorAudienceVisible, false);
  assert.equal(creatorAudienceVisibleFromSource(staffOnly), false);
});

test('callable keeps App Check in the current rollout mode', () => {
  const endpoint = setCreatorAudienceEnabled.__endpoint;
  assert.deepEqual(endpoint.region, ['europe-west1']);
  assert.equal('enforceAppCheck' in endpoint.callableTrigger, false);
  assert.equal(
    'enforceAppCheck' in
      confirmCreatorAdultEligibility.__endpoint.callableTrigger,
    false,
  );
});

test('adult-date validation uses a real UTC calendar boundary', () => {
  assert.doesNotThrow(() => requireAdultBirthDate(
    birthDateYearsAgo(18),
    NOW_MS,
  ));
  assert.throws(
    () => requireAdultBirthDate(birthDateYearsAgo(17), NOW_MS),
    (error) => error.code === 'failed-precondition',
  );
  for (const invalid of ['2030-02-30', '1900-01-01', 'not-a-date']) {
    assert.throws(
      () => requireAdultBirthDate(invalid, NOW_MS),
      (error) => error.code === 'invalid-argument',
    );
  }
});

emulatorTest('paid Creator can confirm adulthood without retaining birth date', async () => {
  const uid = await fixture({ creatorAgeVerified: false });
  const data = {
    birthDate: birthDateYearsAgo(25),
    requestId: randomUUID(),
  };
  const result = await confirmCreatorAdultEligibilityHandler(
    request(uid, data),
    { database: db, now: Timestamp.fromMillis(NOW_MS) },
  );
  assert.deepEqual(result, { creatorAgeVerified: true, changed: true });
  assert.deepEqual(
    await confirmCreatorAdultEligibilityHandler(request(uid, data), {
      database: db,
      now: Timestamp.fromMillis(NOW_MS),
    }),
    result,
  );
  const identity = operationIdentity(
    'profile.creator.ageConfirmation.v1',
    uid,
    data.requestId,
    { adultEligibility: true },
  );
  const [user, profile, rate, ledger] = await Promise.all([
    db.doc('users/' + uid).get(),
    db.doc('publicProfiles/' + uid).get(),
    rateLimitReference(
      db,
      CREATOR_AGE_CONFIRMATION_RATE_SCOPE,
      uid,
    ).get(),
    db.doc('integrityOperationLedgers/' + identity.id).get(),
  ]);
  assert.equal(user.data().creatorAgeVerified, true);
  assert.equal(user.data().creatorAgeVerificationMethod, 'self_declared_birth_date');
  assert.equal(user.data().birthDate, undefined);
  assert.equal(JSON.stringify(user.data()).includes(data.birthDate), false);
  assert.equal(profile.data().creatorAudienceVisible, false);
  assert.equal('creatorAgeVerified' in profile.data(), false);
  assert.equal(rate.data().count, 1);
  assert.equal(JSON.stringify(ledger.data()).includes(data.birthDate), false);
  assert.equal('birthDate' in ledger.data(), false);

  const enabled = await setCreatorAudienceEnabledHandler(request(uid, {
    enabled: true,
    requestId: randomUUID(),
  }), { database: db, now: Timestamp.fromMillis(NOW_MS) });
  assert.equal(enabled.creatorAudienceVisible, true);
  assert.equal(
    (await db.doc('publicProfiles/' + uid).get()).data().creatorAudienceVisible,
    true,
  );
});

emulatorTest('underage and non-paid profiles cannot create age authority', async () => {
  const underageUid = await fixture({ creatorAgeVerified: false });
  await assert.rejects(
    confirmCreatorAdultEligibilityHandler(request(underageUid, {
      birthDate: birthDateYearsAgo(17),
      requestId: randomUUID(),
    }), { database: db, now: Timestamp.fromMillis(NOW_MS) }),
    (error) => error.code === 'failed-precondition',
  );
  assert.equal(
    (await db.doc('users/' + underageUid).get()).data().creatorAgeVerified,
    false,
  );

  const freeUid = await fixture(
    { creatorAgeVerified: false },
    { isPremium: false, status: 'expired' },
  );
  await assert.rejects(
    confirmCreatorAdultEligibilityHandler(request(freeUid, {
      birthDate: birthDateYearsAgo(25),
      requestId: randomUUID(),
    }), { database: db, now: Timestamp.fromMillis(NOW_MS) }),
    (error) => error.code === 'failed-precondition',
  );
  assert.equal(
    (await db.doc('users/' + freeUid).get()).data().creatorAgeVerified,
    false,
  );
});

emulatorTest('paid eligibility is exact and staff preview never substitutes', async () => {
  const entitlement = canonicalEntitlement();
  assert.equal(paidCreatorAudienceEligibility(canonicalUser(), entitlement, NOW_MS), true);
  assert.equal(paidCreatorAudienceEligibility(
    canonicalUser({ role: 'moderator', premiumIdentity: false }),
    null,
    NOW_MS,
  ), false);
  assert.equal(paidCreatorAudienceEligibility(
    canonicalUser(),
    canonicalEntitlement({ currentPeriodEnd: Timestamp.fromMillis(NOW_MS) }),
    NOW_MS,
  ), false);
  assert.equal(paidCreatorAudienceEligibility(
    canonicalUser({ creatorAgeVerified: false }),
    entitlement,
    NOW_MS,
  ), false);
});

emulatorTest('enable is exact, atomically projected and replay-identical', async () => {
  const uid = await fixture();
  const data = { enabled: true, requestId: randomUUID() };
  const first = await setCreatorAudienceEnabledHandler(request(uid, data), {
    database: db,
    now: Timestamp.fromMillis(NOW_MS),
  });
  assert.deepEqual(first, {
    creatorAudienceEnabled: true,
    creatorAudienceVisible: true,
    changed: true,
  });
  assert.deepEqual(await setCreatorAudienceEnabledHandler(request(uid, data), {
    database: db,
    now: Timestamp.fromMillis(NOW_MS),
  }), first);
  assert.equal((await rateLimitReference(
    db,
    CREATOR_AUDIENCE_RATE_SCOPE,
    uid,
  ).get()).data().count, 1, 'the exact replay does not consume another slot');
  const [user, publicProfile] = await Promise.all([
    db.doc('users/' + uid).get(),
    db.doc('publicProfiles/' + uid).get(),
  ]);
  assert.equal(user.data().creatorAudienceEnabled, true);
  assert.equal(user.data().creatorAgeVerified, true);
  assert.equal(publicProfile.data().creatorAudienceVisible, true);
  assert.equal(publicProfile.data().followerCount, 17);
  assert.equal('creatorAgeVerified' in publicProfile.data(), false);
  assert.equal('creatorAudienceEnabled' in publicProfile.data(), false);
  await assert.rejects(
    setCreatorAudienceEnabledHandler(request(uid, {
      enabled: false,
      requestId: data.requestId,
    }), { database: db, now: Timestamp.fromMillis(NOW_MS) }),
    (error) => error.code === 'already-exists',
  );
  await assert.rejects(
    setCreatorAudienceEnabledHandler(request(uid, {
      ...data,
      unknown: true,
    }), { database: db, now: Timestamp.fromMillis(NOW_MS) }),
    (error) => error.code === 'invalid-argument',
  );
});

emulatorTest('distinct operations consume a bounded shared quota while exact replay is free', async () => {
  const uid = await fixture();
  const now = Timestamp.fromMillis(NOW_MS);
  const rateLimit = { maxEvents: 2, windowMs: 60_000 };
  const firstData = { enabled: true, requestId: randomUUID() };
  const first = await setCreatorAudienceEnabledHandler(request(uid, firstData), {
    database: db,
    now,
    rateLimit,
  });
  assert.deepEqual(await setCreatorAudienceEnabledHandler(request(uid, firstData), {
    database: db,
    now,
    rateLimit,
  }), first);
  const rateRef = rateLimitReference(db, CREATOR_AUDIENCE_RATE_SCOPE, uid);
  assert.equal((await rateRef.get()).data().count, 1);

  const secondData = { enabled: true, requestId: randomUUID() };
  assert.deepEqual(await setCreatorAudienceEnabledHandler(request(uid, secondData), {
    database: db,
    now,
    rateLimit,
  }), {
    creatorAudienceEnabled: true,
    creatorAudienceVisible: true,
    changed: false,
  });
  assert.equal((await rateRef.get()).data().count, 2);

  const refusedData = { enabled: false, requestId: randomUUID() };
  await assert.rejects(
    setCreatorAudienceEnabledHandler(request(uid, refusedData), {
      database: db,
      now,
      rateLimit,
    }),
    (error) => error.code === 'resource-exhausted' &&
      error.message === 'Too many requests. Please try again later.',
  );
  assert.equal((await rateRef.get()).data().count, 2);
  assert.equal((await db.doc('integrityOperationLedgers/' + operationIdentity(
    'profile.creator.audience.v1',
    uid,
    refusedData.requestId,
    { enabled: false },
  ).id).get()).exists, false);
  assert.equal((await db.doc('users/' + uid).get()).data().creatorAudienceEnabled, true);
});

emulatorTest('enable fails closed for every missing authority without exposing which one', async () => {
  const scenarios = [
    [canonicalUser({ accountType: 'personal' }), canonicalEntitlement()],
    [canonicalUser({ premiumIdentity: false }), canonicalEntitlement()],
    [canonicalUser({ creatorAgeVerified: false }), canonicalEntitlement()],
    [canonicalUser(), canonicalEntitlement({ isPremium: false })],
    [canonicalUser(), canonicalEntitlement({ status: 'canceled' })],
    [canonicalUser(), canonicalEntitlement({ premiumIdentityEnabled: false })],
    [canonicalUser(), canonicalEntitlement({ creatorEnabled: false })],
    [canonicalUser({ role: 'moderator', premiumIdentity: false }), null],
  ];
  for (const [user, entitlement] of scenarios) {
    const uid = 'creator-gate-' + randomUUID();
    await db.doc('users/' + uid).set(user);
    if (entitlement) await db.doc('entitlements/' + uid).set(entitlement);
    await assert.rejects(
      setCreatorAudienceEnabledHandler(request(uid, {
        enabled: true,
        requestId: randomUUID(),
      }), { database: db, now: Timestamp.fromMillis(NOW_MS) }),
      (error) => error.code === 'failed-precondition' &&
        error.message === 'Creator audience is unavailable for this account.',
    );
    assert.notEqual((await db.doc('users/' + uid).get()).data().creatorAudienceEnabled, true);
    assert.equal((await db.doc('publicProfiles/' + uid).get()).exists, false);
  }
});

emulatorTest('opt-out remains available after Premium or age authority is lost', async () => {
  const uid = await fixture({ creatorAudienceEnabled: true });
  await Promise.all([
    db.doc('users/' + uid).update({
      premiumIdentity: false,
      creatorAgeVerified: false,
    }),
    db.doc('entitlements/' + uid).delete(),
  ]);
  const result = await setCreatorAudienceEnabledHandler(request(uid, {
    enabled: false,
    requestId: randomUUID(),
  }), { database: db, now: Timestamp.fromMillis(NOW_MS) });
  assert.deepEqual(result, {
    creatorAudienceEnabled: false,
    creatorAudienceVisible: false,
    changed: true,
  });
  const publicProfile = (await db.doc('publicProfiles/' + uid).get()).data();
  assert.equal(publicProfile.creatorAudienceVisible, false);
  assert.equal(publicProfile.followerCount, 0);
  assert.equal(publicProfile.followingCount, 0);
});
