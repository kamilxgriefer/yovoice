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
  doc,
  getDoc,
  getDocs,
  limit,
  query,
  setDoc,
  updateDoc,
} = require('firebase/firestore');

const PROJECT = 'demo-yovoice-creator-audience-rules';
const READER = 'creator-audience-reader';
const CREATOR = 'creator-audience-owner';
const PREVIEW = 'creator-audience-preview';
const HIDDEN = 'creator-audience-hidden';
let env;

function endpoint(value, fallback) {
  const parts = (value || `127.0.0.1:${fallback}`).split(':');
  return { host: parts[0], port: Number(parts[1]) };
}

function user(uid, overrides = {}) {
  return {
    uid,
    displayName: uid,
    status: 'active',
    banned: false,
    disabled: false,
    accountType: 'personal',
    premiumIdentity: false,
    ...overrides,
  };
}

function publicProfile(uid, overrides = {}) {
  return {
    uid,
    displayName: uid,
    username: uid,
    displayNameSearch: uid,
    usernameSearch: uid,
    photoUrl: null,
    bannerUrl: null,
    bio: '',
    country: '',
    nativeLanguage: '',
    spokenLanguages: [],
    learningLanguages: [],
    website: null,
    statusMessage: '',
    accountType: 'personal',
    premiumIdentity: false,
    creatorAudienceVisible: false,
    friendCount: 0,
    followerCount: 0,
    followingCount: 0,
    schemaVersion: 1,
    updatedAt: Timestamp.now(),
    ...overrides,
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
      setDoc(doc(db, `users/${READER}`), user(READER)),
      setDoc(doc(db, `users/${CREATOR}`), user(CREATOR, {
        accountType: 'creator',
        premiumIdentity: true,
        creatorAgeVerified: true,
        creatorAudienceEnabled: true,
      })),
      setDoc(doc(db, `entitlements/${CREATOR}`), {
        status: 'active',
        isPremium: true,
        premiumIdentityEnabled: true,
        creatorEnabled: true,
        currentPeriodEnd: Timestamp.fromMillis(Date.now() + 24 * 60 * 60_000),
      }),
      setDoc(doc(db, `publicProfiles/${CREATOR}`), publicProfile(CREATOR, {
        accountType: 'creator',
        premiumIdentity: true,
        creatorAudienceVisible: true,
        followerCount: 7,
        followingCount: 2,
      })),
      setDoc(doc(db, `users/${PREVIEW}`), user(PREVIEW, {
        role: 'moderator',
        accountType: 'creator',
        premiumIdentity: false,
        creatorAgeVerified: true,
        creatorAudienceEnabled: true,
      })),
      setDoc(doc(db, `publicProfiles/${PREVIEW}`), publicProfile(PREVIEW, {
        accountType: 'creator',
        premiumIdentity: true,
        creatorAudienceVisible: true,
      })),
      setDoc(doc(db, `users/${HIDDEN}`), user(HIDDEN)),
      setDoc(doc(db, `publicProfiles/${HIDDEN}`), publicProfile(HIDDEN, {
        followerCount: 1,
      })),
      setDoc(doc(db, `users/${CREATOR}/following/${READER}`), {
        uid: READER, followedAt: Timestamp.now(),
      }),
      setDoc(doc(db, `users/${CREATOR}/followers/${READER}`), {
        uid: READER, followedAt: Timestamp.now(),
      }),
      setDoc(doc(db, `users/${HIDDEN}/following/${READER}`), {
        uid: READER, followedAt: Timestamp.now(),
      }),
      setDoc(doc(db, `users/${HIDDEN}/followers/${READER}`), {
        uid: READER, followedAt: Timestamp.now(),
      }),
    ]);
  });
});

after(async () => {
  if (env) await env.cleanup();
});

function context(uid) {
  return env.authenticatedContext(uid, { email_verified: true });
}

test('Creator audience private authority is owner-readable but never client-writable', async () => {
  const owner = context(CREATOR).firestore();
  const snapshot = await assertSucceeds(getDoc(doc(owner, `users/${CREATOR}`)));
  assert.equal(snapshot.data().creatorAgeVerified, true);
  assert.equal(snapshot.data().creatorAudienceEnabled, true);
  await assertFails(updateDoc(doc(owner, `users/${CREATOR}`), {
    creatorAgeVerified: false,
  }));
  await assertFails(updateDoc(doc(owner, `users/${CREATOR}`), {
    creatorAudienceEnabled: false,
  }));
  await assertFails(setDoc(doc(context('new-creator').firestore(), 'users/new-creator'), {
    uid: 'new-creator',
    displayName: 'New creator',
    accountType: 'personal',
    creatorAgeVerified: true,
    creatorAudienceEnabled: true,
  }));
});

test('Creator audience public projection requires paid, age-verified, opted-in authority', async () => {
  const reader = context(READER).firestore();
  const visible = await assertSucceeds(getDoc(doc(reader, `publicProfiles/${CREATOR}`)));
  assert.equal(visible.data().creatorAudienceVisible, true);
  assert.equal(visible.data().followerCount, 7);
  await assertFails(getDoc(doc(reader, `publicProfiles/${PREVIEW}`)));
  await assertFails(getDoc(doc(reader, `publicProfiles/${HIDDEN}`)));
});

test('Creator audience projection is exact, hides private verification fields and is server-written', async () => {
  const reader = context(READER).firestore();
  await env.withSecurityRulesDisabled(async (context) => {
    await updateDoc(doc(context.firestore(), `publicProfiles/${CREATOR}`), {
      creatorAgeVerified: true,
    });
  });
  await assertFails(getDoc(doc(reader, `publicProfiles/${CREATOR}`)));
  await assertFails(updateDoc(doc(context(CREATOR).firestore(), `publicProfiles/${CREATOR}`), {
    creatorAudienceVisible: false,
    followerCount: 0,
    followingCount: 0,
  }));
});

test('Follower graphs are external-readable only for the canonical visible Creator audience', async () => {
  const reader = context(READER).firestore();
  for (const edge of ['following', 'followers']) {
    await assertSucceeds(getDoc(doc(reader, `users/${CREATOR}/${edge}/${READER}`)));
    await assertSucceeds(getDocs(query(
      collection(reader, `users/${CREATOR}/${edge}`),
      limit(100),
    )));
    await assertFails(getDoc(doc(reader, `users/${HIDDEN}/${edge}/${READER}`)));
    await assertFails(getDocs(query(
      collection(reader, `users/${HIDDEN}/${edge}`),
      limit(100),
    )));

    // The owner retains the private graph needed by settings and unfollow;
    // every mutation remains server-only.
    const owner = context(HIDDEN).firestore();
    await assertSucceeds(getDoc(doc(owner, `users/${HIDDEN}/${edge}/${READER}`)));
    await assertSucceeds(getDocs(query(
      collection(owner, `users/${HIDDEN}/${edge}`),
      limit(100),
    )));
    await assertFails(updateDoc(doc(owner, `users/${HIDDEN}/${edge}/${READER}`), {
      uid: READER, followedAt: Timestamp.now(),
    }));
  }
});
