// Pre-registered account takeover, Phase 1 (functions/auth/federated_takeover.js).
//
// Every attack step here is the production-shaped client call: the
// pre-registrant and the owner talk to the Identity Toolkit REST API of the
// Auth emulator exactly as a stock client or a script with the public API key
// would, and push tokens are planted through the Firestore REST API with the
// caller's own ID token, so the REAL firestore.rules (loaded by
// `emulators:exec` from firebase.json) decide. Only the owner's callable and
// the sweeper run in-process.
//
//   firebase emulators:exec --only auth,firestore --project demo-yovoice \
//     'cd functions && node --test --test-concurrency=1 test/federated_takeover.test.js'
//
// EMULATOR LIMIT, stated once: firebase-tools 15.29.0's Auth emulator does not
// enforce refresh-token revocation (lib/emulator/auth/state.js
// validateRefreshToken checks only that the user exists). Production refuses a
// refresh of any session older than `tokensValidAfterTime`. The tests
// therefore prove revocation the way production evaluates it — the account's
// `tokensValidAfterTime` is after the pre-registrant's sign-in, and Admin
// `verifyIdToken(…, true)` rejects every ID token of that session — and, for
// whatever the emulator still mints, that the rules refuse it anyway.
//
// A SECOND EMULATOR ARTEFACT: the emulator stamps every token it mints, a
// refresh included, with the ACCOUNT's latest sign-in as `auth_time`
// (operations.js getAuthTime -> user.lastLoginAt). Production keeps the
// session's own sign-in time across refreshes (utils/auth.js relies on that
// for privileged re-authentication). So the pre-registrant's refreshed token
// here carries the owner's sign-in second. The tests let that second pass
// before the remediation runs — as it does in reality, where the owner's
// client calls after its sign-in completes — so the emulator's second-granular
// revocation can see the difference.

const assert = require("node:assert/strict");
const { describe, test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST =
  process.env.FIREBASE_AUTH_EMULATOR_HOST ?? "127.0.0.1:9099";
// The REST calls below land in the emulator's own project (the one
// `emulators:exec --project` names, exported as GCLOUD_PROJECT). The Admin SDK
// must look at the same one, not at FIREBASE_CONFIG's production project id.
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "demo-yovoice";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp({ projectId: process.env.GCLOUD_PROJECT });

const {
  AUDIT_COLLECTION,
  LEDGER_COLLECTION,
  STALE_UNVERIFIED_REPORT_AGE_MS,
  SWEEP_STATE_COLLECTION,
  callerMayKeepDevice,
  createFederatedTakeoverService,
  onAuthUserCreated,
  planRemediation,
  secureFederatedSignInV1,
  sweepFederatedTakeoverSchedule,
} = require("../auth/federated_takeover");

const PROJECT = process.env.GCLOUD_PROJECT;
const AUTH = `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`;
const FIRESTORE = `http://${process.env.FIRESTORE_EMULATOR_HOST}`;
const API_KEY = "fake-api-key";
const RUN = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;

const auth = getAuth();
const db = getFirestore();

// ----- production-shaped client calls ---------------------------------------

async function identityToolkit(method, body) {
  const response = await fetch(
    `${AUTH}/identitytoolkit.googleapis.com/v1/${method}?key=${API_KEY}`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    },
  );
  return { status: response.status, body: await response.json() };
}

function claims(idToken) {
  return JSON.parse(Buffer.from(idToken.split(".")[1], "base64url").toString());
}

/** createUserWithEmailAndPassword. */
async function registerWithPassword(email) {
  const result = await identityToolkit("accounts:signUp", {
    email,
    password: "pre-registrant-password",
    returnSecureToken: true,
  });
  assert.equal(result.status, 200, JSON.stringify(result.body));
  return {
    uid: result.body.localId,
    idToken: result.body.idToken,
    refreshToken: result.body.refreshToken,
  };
}

/** signInWithCredential / signInWithPopup for Google or Apple. */
async function signInWithProvider(email, providerId, sub) {
  const credential = JSON.stringify({ sub, email, email_verified: true });
  const result = await identityToolkit("accounts:signInWithIdp", {
    postBody: `id_token=${encodeURIComponent(credential)}&providerId=${providerId}`,
    requestUri: "http://localhost",
    returnSecureToken: true,
  });
  assert.equal(result.status, 200, JSON.stringify(result.body));
  return {
    uid: result.body.localId,
    idToken: result.body.idToken,
    refreshToken: result.body.refreshToken,
    isNewUser: result.body.isNewUser === true,
  };
}

/** The SDK's background token refresh. */
async function refresh(refreshToken) {
  const response = await fetch(
    `${AUTH}/securetoken.googleapis.com/v1/token?key=${API_KEY}`,
    {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: `grant_type=refresh_token&refresh_token=${encodeURIComponent(refreshToken)}`,
    },
  );
  const body = await response.json();
  return { status: response.status, idToken: body.id_token ?? null };
}

/** The owner opens the verification e-mail's link. */
async function verifyEmailThroughLink(idToken, email) {
  const sent = await identityToolkit("accounts:sendOobCode", {
    requestType: "VERIFY_EMAIL",
    idToken,
  });
  assert.equal(sent.status, 200, JSON.stringify(sent.body));
  const codes = await (await fetch(
    `${AUTH}/emulator/v1/projects/${PROJECT}/oobCodes`,
  )).json();
  const code = codes.oobCodes
    .filter((entry) => entry.email === email && entry.requestType === "VERIFY_EMAIL")
    .at(-1);
  assert.ok(code, "the verification e-mail was sent");
  const applied = await identityToolkit("accounts:update", { oobCode: code.oobCode });
  assert.equal(applied.status, 200, JSON.stringify(applied.body));
}

async function commit(idToken, write) {
  const response = await fetch(
    `${FIRESTORE}/v1/projects/${PROJECT}/databases/(default)/documents:commit`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${idToken}`,
      },
      body: JSON.stringify({ writes: [write] }),
    },
  );
  return response.status;
}

const documentName = (path) =>
  `projects/${PROJECT}/databases/(default)/documents/${path}`;

/** The app's first-open profile bootstrap (allowlisted create). */
async function createOwnProfile(idToken, uid, email) {
  return commit(idToken, {
    update: {
      name: documentName(`users/${uid}`),
      fields: {
        uid: { stringValue: uid },
        email: { stringValue: email },
        displayName: { stringValue: `Name ${uid.slice(0, 6)}` },
        username: { stringValue: `name${uid.slice(0, 6)}` },
      },
    },
    currentDocument: { exists: false },
  });
}

/** NotificationService.registerFcmToken, byte for byte. */
async function registerPushToken(idToken, uid, tokenId) {
  return commit(idToken, {
    update: {
      name: documentName(`users/${uid}/fcmTokens/${tokenId}`),
      fields: {
        platform: { stringValue: "android" },
        directVideoProtocol: { integerValue: "1" },
      },
    },
    updateTransforms: [{ fieldPath: "updatedAt", setToServerValue: "REQUEST_TIME" }],
  });
}

// ----- helpers ----------------------------------------------------------------

function capturingLog() {
  const entries = [];
  const record = (level) => (message, data) => entries.push({ level, message, data });
  return { entries, info: record("info"), warn: record("warn"), error: record("error") };
}

function newService(log = capturingLog()) {
  return createFederatedTakeoverService({ auth, db, log });
}

/** What the deployed onCreate trigger does at account creation. */
async function deliverCreateTrigger(uid) {
  return newService().recordPasswordAccountOrigin(await auth.getUser(uid));
}

async function ownerCallsSecureSignIn(idToken, data = {}) {
  const decoded = await auth.verifyIdToken(idToken);
  return secureFederatedSignInV1.run({ auth: { uid: decoded.uid, token: decoded }, data });
}

async function pushTokenIds(uid) {
  const snapshot = await db.collection(`users/${uid}/fcmTokens`).get();
  return snapshot.docs.map((entry) => entry.id).sort();
}

async function auditsFor(uid) {
  const snapshot = await db.collection(AUDIT_COLLECTION).where("uid", "==", uid).get();
  return snapshot.docs.map((entry) => entry.data());
}

async function ledgerState(uid) {
  const snapshot = await db.collection(LEDGER_COLLECTION).doc(uid).get();
  return snapshot.exists ? snapshot.get("state") : null;
}

// Firebase revocation has one-second resolution: a session that started in
// the very second the refresh tokens are revoked survives it. A real
// pre-registration precedes the owner's sign-in by far more than that; the
// tests let one whole second pass so they model it, and the rules epoch
// (remediation second + 1) covers the same-second edge on its own.
async function letPreRegistrationAge() {
  const next = (Math.floor(Date.now() / 1000) + 1) * 1000 + 50;
  while (Date.now() < next) {
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
}

async function waitUntilEpochSecond(epoch) {
  while (Date.now() < epoch * 1000 + 50) {
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
}

async function sessionIsRevoked(idToken) {
  try {
    await auth.verifyIdToken(idToken, true);
    return false;
  } catch (error) {
    return error.code === "auth/id-token-revoked";
  }
}

/** Runs sweeps until a full listUsers pass has completed, from scratch. */
async function sweepUntilWalkPassCompletes(service) {
  await db.collection(SWEEP_STATE_COLLECTION).doc("state").delete();
  for (let attempt = 0; attempt < 50; attempt += 1) {
    const outcome = await service.runSweep();
    if (outcome.walkPassReport) return outcome;
  }
  throw new Error("listUsers walk did not complete");
}

// ----- the attack, and each trigger closing it ---------------------------------

describe("Google takeover closed by the owner's own client (trigger A)", () => {
  test("the pre-registrant loses the session, the password and every planted push token", async () => {
    const email = `victim-a-${RUN}@gmail.com`;

    // 1. The pre-registrant registers the owner's address, bootstraps the
    //    profile and plants push, all while unverified.
    const attacker = await registerWithPassword(email);
    await deliverCreateTrigger(attacker.uid);
    assert.equal(await ledgerState(attacker.uid), "pending");
    assert.equal(await createOwnProfile(attacker.idToken, attacker.uid, email), 200);
    assert.equal(await registerPushToken(attacker.idToken, attacker.uid, `attacker-${RUN}`), 200);
    await letPreRegistrationAge();

    // 2. The owner signs in with Google: same uid, password gone.
    const owner = await signInWithProvider(email, "google.com", `google-a-${RUN}`);
    assert.equal(owner.uid, attacker.uid);
    assert.equal(owner.isNewUser, false);

    // 3. Regression anchor — the bug: the pre-registrant's refresh still
    //    works and the new token says the address is verified.
    const stolen = await refresh(attacker.refreshToken);
    assert.equal(stolen.status, 200);
    assert.equal(claims(stolen.idToken).email_verified, true);
    assert.equal(claims(stolen.idToken).firebase.sign_in_provider, "password");
    await letPreRegistrationAge();

    // 4. Trigger A.
    const result = await ownerCallsSecureSignIn(owner.idToken);
    assert.deepEqual(result, { status: "remediated", reauthenticate: true });

    // The pre-registrant's session is revoked (production refuses the
    // refresh; Admin refuses every ID token of it) ...
    const user = await auth.getUser(attacker.uid);
    const revokedAfter = Date.parse(user.tokensValidAfterTime) / 1000;
    assert.ok(revokedAfter > claims(stolen.idToken).auth_time);
    assert.equal(await sessionIsRevoked(stolen.idToken), true);
    assert.equal(await sessionIsRevoked(attacker.idToken), true);
    const lookup = await identityToolkit("accounts:lookup", { idToken: stolen.idToken });
    assert.equal(lookup.body.error?.message, "TOKEN_EXPIRED");

    // ... only Google remains ...
    assert.deepEqual(user.providerData.map((p) => p.providerId), ["google.com"]);

    // ... the planted push token is gone ...
    assert.deepEqual(await pushTokenIds(attacker.uid), []);

    // ... and whatever the (non-revoking) emulator still mints for that
    // session is refused by the rules when it tries to plant again.
    const epoch = (await db.doc(`users/${attacker.uid}`).get()).get("authSessionEpoch");
    assert.ok(Number.isSafeInteger(epoch));
    const replay = await refresh(attacker.refreshToken);
    if (replay.status === 200) {
      assert.ok(claims(replay.idToken).auth_time < epoch);
      assert.equal(await sessionIsRevoked(replay.idToken), true);
      assert.equal(
        await registerPushToken(replay.idToken, attacker.uid, `attacker-again-${RUN}`),
        403,
      );
    }
    assert.equal(
      await registerPushToken(stolen.idToken, attacker.uid, `attacker-again-${RUN}`),
      403,
    );
    assert.deepEqual(await pushTokenIds(attacker.uid), []);

    // The old password cannot sign in either.
    const passwordSignIn = await identityToolkit("accounts:signInWithPassword", {
      email,
      password: "pre-registrant-password",
      returnSecureToken: true,
    });
    assert.equal(passwordSignIn.status, 400);

    // The audit record exists and says what happened; the ledger is closed.
    const audits = await auditsFor(attacker.uid);
    assert.equal(audits.length, 1);
    assert.equal(audits[0].trigger, "ownerSignIn");
    assert.equal(audits[0].reason, "unverifiedPasswordReplacedByFederated");
    assert.deepEqual(audits[0].providersKept, ["google.com"]);
    assert.equal(audits[0].fcmTokensDeleted, 1);
    assert.equal(audits[0].sessionEpoch, epoch);
    assert.equal(await ledgerState(attacker.uid), "remediated");

    // The owner signs in once more and has a working account: that session
    // is after the epoch, so push registers normally.
    await waitUntilEpochSecond(epoch);
    const again = await signInWithProvider(email, "google.com", `google-a-${RUN}`);
    assert.ok(claims(again.idToken).auth_time >= epoch);
    assert.equal(await registerPushToken(again.idToken, again.uid, `owner-${RUN}`), 200);
    assert.equal((await refresh(again.refreshToken)).status, 200);
    assert.equal(await sessionIsRevoked(again.idToken), false);

    // Idempotent: the next returning sign-in changes nothing.
    assert.deepEqual(await ownerCallsSecureSignIn(again.idToken), {
      status: "clean",
      reauthenticate: false,
    });
    assert.equal((await auditsFor(attacker.uid)).length, 1);
    assert.deepEqual(await pushTokenIds(attacker.uid), [`owner-${RUN}`]);
  });

  test("the owner's calling device keeps its push row; nothing else survives", async () => {
    const email = `victim-keep-${RUN}@gmail.com`;
    const attacker = await registerWithPassword(email);
    await deliverCreateTrigger(attacker.uid);
    assert.equal(await createOwnProfile(attacker.idToken, attacker.uid, email), 200);
    assert.equal(await registerPushToken(attacker.idToken, attacker.uid, `attacker-${RUN}`), 200);

    const owner = await signInWithProvider(email, "google.com", `google-keep-${RUN}`);
    assert.equal(await registerPushToken(owner.idToken, owner.uid, `owner-device-${RUN}`), 200);

    const result = await ownerCallsSecureSignIn(owner.idToken, {
      fcmToken: `owner-device-${RUN}`,
    });
    assert.equal(result.status, "remediated");
    assert.deepEqual(await pushTokenIds(owner.uid), [`owner-device-${RUN}`]);
    const [audit] = await auditsFor(owner.uid);
    assert.equal(audit.callerDeviceKept, true);
    assert.equal(audit.fcmTokensDeleted, 1);
  });
});

describe("Apple takeover closed by the sweeper (trigger B)", () => {
  test("no client call is needed; every token, including the owner's pre-epoch one, is purged", async () => {
    const email = `victim-b-${RUN}@icloud.com`;
    const attacker = await registerWithPassword(email);
    await deliverCreateTrigger(attacker.uid);
    assert.equal(await createOwnProfile(attacker.idToken, attacker.uid, email), 200);
    assert.equal(await registerPushToken(attacker.idToken, attacker.uid, `attacker-${RUN}`), 200);
    await letPreRegistrationAge();

    // The owner uses the website (no trigger A yet) with Apple.
    const owner = await signInWithProvider(email, "apple.com", `apple-b-${RUN}`);
    assert.equal(owner.uid, attacker.uid);
    assert.equal(await registerPushToken(owner.idToken, owner.uid, `owner-web-${RUN}`), 200);
    const stolen = await refresh(attacker.refreshToken);
    assert.equal(claims(stolen.idToken).email_verified, true);
    await letPreRegistrationAge();

    const log = capturingLog();
    const outcome = await newService(log).runSweep();
    assert.ok(outcome.remediated >= 1);

    const user = await auth.getUser(attacker.uid);
    assert.deepEqual(user.providerData.map((p) => p.providerId), ["apple.com"]);
    assert.equal(await sessionIsRevoked(stolen.idToken), true);
    assert.deepEqual(await pushTokenIds(attacker.uid), []);
    assert.equal(await registerPushToken(stolen.idToken, attacker.uid, `again-${RUN}`), 403);

    const audits = await auditsFor(attacker.uid);
    assert.equal(audits.length, 1);
    assert.equal(audits[0].trigger, "sweeper");
    assert.equal(audits[0].fcmTokensDeleted, 2);
    assert.equal(audits[0].callerDeviceKept, false);
    assert.equal(await ledgerState(attacker.uid), "remediated");
    assert.ok(log.entries.some((entry) =>
      entry.message === "federated takeover remediated" && entry.data.uid === attacker.uid));

    // A second sweep does nothing more.
    await newService().runSweep();
    assert.equal((await auditsFor(attacker.uid)).length, 1);
  });

  test("an unverified password still linked beside a Google identity on the same address is unlinked", async () => {
    // The state the brief names literally. Firebase's own takeover removes the
    // password (see the tests above); this covers a project or provider where
    // it would stay linked.
    const email = `victim-linked-${RUN}@gmail.com`;
    const attacker = await registerWithPassword(email);
    await auth.updateUser(attacker.uid, {
      providerToLink: { providerId: "google.com", uid: `google-linked-${RUN}`, email },
    });
    const before = await auth.getUser(attacker.uid);
    assert.equal(before.emailVerified, false);
    assert.deepEqual(before.providerData.map((p) => p.providerId).sort(), ["google.com", "password"]);
    assert.equal(planRemediation(before, null).verdict, "takeover");
    await letPreRegistrationAge();

    await sweepUntilWalkPassCompletes(newService());

    const after = await auth.getUser(attacker.uid);
    assert.deepEqual(after.providerData.map((p) => p.providerId), ["google.com"]);
    assert.equal(await sessionIsRevoked(attacker.idToken), true);
    const [audit] = await auditsFor(attacker.uid);
    assert.equal(audit.reason, "unverifiedPasswordBesideFederated");
    assert.deepEqual(audit.providersUnlinked, ["password"]);
  });
});

describe("legitimate accounts are never touched", () => {
  test("a verified password plus Google keeps both, its sessions and its push", async () => {
    const email = `legit-${RUN}@gmail.com`;
    const member = await registerWithPassword(email);
    await deliverCreateTrigger(member.uid);
    assert.equal(await createOwnProfile(member.idToken, member.uid, email), 200);
    assert.equal(await registerPushToken(member.idToken, member.uid, `phone-${RUN}`), 200);
    await verifyEmailThroughLink(member.idToken, email);
    const validBefore = (await auth.getUser(member.uid)).tokensValidAfterTime;

    // Google sign-in before any sweep has seen the verification: the ledger
    // row is still "pending" — the race that must NOT look like a takeover.
    const google = await signInWithProvider(email, "google.com", `google-legit-${RUN}`);
    assert.equal(google.uid, member.uid);
    assert.equal(await ledgerState(member.uid), "pending");

    assert.deepEqual(await ownerCallsSecureSignIn(google.idToken), {
      status: "clean",
      reauthenticate: false,
    });
    await newService().runSweep();

    const user = await auth.getUser(member.uid);
    assert.deepEqual(user.providerData.map((p) => p.providerId).sort(), ["google.com", "password"]);
    assert.equal(user.tokensValidAfterTime, validBefore);
    assert.equal((await refresh(member.refreshToken)).status, 200);
    assert.equal(await sessionIsRevoked(member.idToken), false);
    assert.deepEqual(await pushTokenIds(member.uid), [`phone-${RUN}`]);
    assert.deepEqual(await auditsFor(member.uid), []);
    assert.equal((await db.doc(`users/${member.uid}`).get()).get("authSessionEpoch"), undefined);
    assert.equal(await ledgerState(member.uid), "verified");
    const password = await identityToolkit("accounts:signInWithPassword", {
      email,
      password: "pre-registrant-password",
      returnSecureToken: true,
    });
    assert.equal(password.status, 200);
  });

  test("a verified password-only account is left alone and stops being watched", async () => {
    const email = `password-only-${RUN}@example.com`;
    const member = await registerWithPassword(email);
    await deliverCreateTrigger(member.uid);
    assert.equal(await createOwnProfile(member.idToken, member.uid, email), 200);
    assert.equal(await registerPushToken(member.idToken, member.uid, `laptop-${RUN}`), 200);
    await verifyEmailThroughLink(member.idToken, email);
    const validBefore = (await auth.getUser(member.uid)).tokensValidAfterTime;

    await newService().runSweep();

    const user = await auth.getUser(member.uid);
    assert.deepEqual(user.providerData.map((p) => p.providerId), ["password"]);
    assert.equal(user.tokensValidAfterTime, validBefore);
    assert.deepEqual(await pushTokenIds(member.uid), [`laptop-${RUN}`]);
    assert.deepEqual(await auditsFor(member.uid), []);
    assert.equal(await ledgerState(member.uid), "verified");
  });

  test("an account created with Google is never recorded or touched", async () => {
    const google = await signInWithProvider(`native-${RUN}@gmail.com`, "google.com", `google-native-${RUN}`);
    assert.equal(google.isNewUser, true);
    assert.deepEqual(await deliverCreateTrigger(google.uid), { recorded: false });
    assert.equal(await ledgerState(google.uid), null);
    assert.deepEqual(await ownerCallsSecureSignIn(google.idToken), {
      status: "clean",
      reauthenticate: false,
    });
    assert.equal(await sessionIsRevoked(google.idToken), false);
  });
});

describe("report only: never-verified password-only accounts", () => {
  test("older than 7 days are logged, seeded for watching, and not deleted", async () => {
    const uid = `stale-${RUN}`;
    const created = new Date(Date.now() - STALE_UNVERIFIED_REPORT_AGE_MS - 24 * 60 * 60 * 1000);
    const imported = await auth.importUsers([{
      uid,
      email: `stale-${RUN}@example.com`,
      emailVerified: false,
      passwordHash: Buffer.from(`hash-${RUN}`),
      passwordSalt: Buffer.from(`salt-${RUN}`),
      metadata: { creationTime: created.toUTCString(), lastSignInTime: created.toUTCString() },
    }], { hash: { algorithm: "HMAC_SHA256", key: Buffer.from("test-key") } });
    assert.equal(imported.failureCount, 0);
    const fresh = await registerWithPassword(`fresh-${RUN}@example.com`);

    const log = capturingLog();
    const outcome = await sweepUntilWalkPassCompletes(newService(log));
    const sampled = outcome.walkPassReport.staleSample.map((entry) => entry.uid);
    assert.ok(sampled.includes(uid) || outcome.walkPassReport.stalePasswordOnly > 100);
    assert.ok(!sampled.includes(fresh.uid));
    assert.ok(log.entries.some((entry) =>
      entry.level === "warn" &&
      entry.message === "never-verified password-only accounts older than 7 days"));

    // Report only: both accounts still exist, untouched, and are now watched.
    const stale = await auth.getUser(uid);
    assert.deepEqual(stale.providerData.map((p) => p.providerId), ["password"]);
    await auth.getUser(fresh.uid);
    assert.equal(await ledgerState(uid), "pending");
    assert.equal(await ledgerState(fresh.uid), "pending");
    assert.deepEqual(await auditsFor(uid), []);
  });
});

describe("boundaries of trigger A", () => {
  test("refuses unauthenticated callers and unexpected input; ignores password sessions", async () => {
    await assert.rejects(
      secureFederatedSignInV1.run({ auth: null, data: {} }),
      (error) => error.code === "unauthenticated",
    );

    const email = `boundary-${RUN}@gmail.com`;
    const attacker = await registerWithPassword(email);
    await deliverCreateTrigger(attacker.uid);
    const passwordToken = await auth.verifyIdToken(attacker.idToken);
    for (const data of [{ uid: "someone-else" }, [], "x", { fcmToken: "a/b" }, { fcmToken: 7 }]) {
      await assert.rejects(
        secureFederatedSignInV1.run({ auth: { uid: attacker.uid, token: passwordToken }, data }),
        (error) => error.code === "invalid-argument",
      );
    }
    // The pre-registrant cannot use trigger A for anything.
    assert.deepEqual(
      await secureFederatedSignInV1.run({ auth: { uid: attacker.uid, token: passwordToken }, data: {} }),
      { status: "notApplicable", reauthenticate: false },
    );
    assert.equal(await sessionIsRevoked(attacker.idToken), false);
    assert.equal(await ledgerState(attacker.uid), "pending");
  });

  test("a stale Google session of the pre-registrant cannot keep its own device", async () => {
    // Pure check: the decision a pre-linked identity would face.
    const now = 2_000_000_000;
    const user = {
      providerData: [{ providerId: "google.com", uid: "owner-sub", email: "o@gmail.com" }],
      metadata: { lastSignInTime: new Date(now * 1000 - 5_000).toUTCString() },
    };
    const plan = { keepProviders: ["google.com"] };
    const token = (overrides) => ({
      token: {
        auth_time: now - 5,
        firebase: { sign_in_provider: "google.com", identities: { "google.com": ["owner-sub"] } },
        ...overrides,
      },
    });
    assert.equal(callerMayKeepDevice(token(), user, plan, now), true);
    // Signed in before the owner's latest sign-in (the takeover).
    assert.equal(callerMayKeepDevice(token({ auth_time: now - 3600 }), user, plan, now), false);
    // A different Google identity.
    assert.equal(callerMayKeepDevice(token({
      firebase: { sign_in_provider: "google.com", identities: { "google.com": ["attacker-sub"] } },
    }), user, plan, now), false);
    // A password session.
    assert.equal(callerMayKeepDevice(token({
      firebase: { sign_in_provider: "password", identities: {} },
    }), user, plan, now), false);
  });
});

describe("the ledger", () => {
  test("a row whose account no longer exists is dropped by the sweeper", async () => {
    const attacker = await registerWithPassword(`gone-${RUN}@gmail.com`);
    await deliverCreateTrigger(attacker.uid);
    await auth.deleteUser(attacker.uid);
    await newService().runSweep();
    assert.equal(await ledgerState(attacker.uid), null);
  });

  test("a retried create delivery is a no-op", async () => {
    const member = await registerWithPassword(`retry-${RUN}@example.com`);
    assert.deepEqual(await deliverCreateTrigger(member.uid), { recorded: true });
    assert.deepEqual(await deliverCreateTrigger(member.uid), { recorded: false });
    assert.equal(await ledgerState(member.uid), "pending");
  });
});

describe("planRemediation", () => {
  const account = (providers, emailVerified, email = "a@gmail.com") => ({
    email,
    emailVerified,
    providerData: providers.map(([providerId, providerEmail = email]) => ({
      providerId,
      email: providerEmail,
      uid: `${providerId}-sub`,
    })),
  });
  const pending = { state: "pending" };

  test("acts only on an unverified password next to the owner's own Google/Apple identity", () => {
    assert.equal(planRemediation(account([["google.com"]], true), pending).verdict, "takeover");
    assert.equal(planRemediation(account([["apple.com"]], true), pending).verdict, "takeover");
    assert.equal(planRemediation(account([["password"], ["google.com"]], false), null).verdict, "takeover");

    assert.equal(planRemediation(account([["google.com"]], true), null).verdict, "clean");
    assert.equal(planRemediation(account([["google.com"]], true), { state: "remediated" }).verdict, "clean");
    assert.equal(planRemediation(account([["password"], ["google.com"]], true), pending).verdict, "ambiguous");
    assert.equal(planRemediation(account([["password"], ["google.com"]], true), null).verdict, "clean");
    assert.equal(planRemediation(account([["password"]], true), pending).verdict, "verified");
    assert.equal(planRemediation(account([["password"]], false), null).verdict, "unverifiedPassword");
    // A foreign-address Google identity is not the owner's and cannot anchor a takeover.
    assert.equal(
      planRemediation(account([["google.com", "someone@gmail.com"]], true), pending).verdict,
      "clean",
    );
  });

  test("keeps only the owner's identities and unlinks everything else", () => {
    const plan = planRemediation(
      account([["password"], ["google.com"], ["apple.com", "relay@privaterelay.appleid.com"], ["phone", ""]], false),
      pending,
    );
    assert.deepEqual(plan.keepProviders, ["google.com"]);
    assert.deepEqual(plan.unlinkProviders.sort(), ["apple.com", "password", "phone"]);

    // An Apple identity without an address (a repeat authorization omits the
    // e-mail claim) is not the one that took the account over: stripped.
    const silent = planRemediation(account([["google.com"], ["apple.com", ""]], true), pending);
    assert.deepEqual(silent.keepProviders, ["google.com"]);
    assert.deepEqual(silent.unlinkProviders, ["apple.com"]);
    // And it can never anchor a takeover on its own.
    assert.equal(planRemediation(account([["apple.com", ""]], true), pending).verdict, "clean");
  });
});

test("deployment metadata", () => {
  assert.deepEqual(secureFederatedSignInV1.__endpoint.region, ["europe-west1"]);
  assert.ok(secureFederatedSignInV1.__endpoint.callableTrigger);
  const schedule = sweepFederatedTakeoverSchedule.__endpoint;
  assert.equal(schedule.maxInstances, 1);
  assert.equal(schedule.scheduleTrigger.schedule, "every 5 minutes");
  assert.deepEqual(schedule.region, ["europe-west1"]);
  const trigger = onAuthUserCreated.__endpoint;
  assert.equal(trigger.eventTrigger.eventType, "providers/firebase.auth/eventTypes/user.create");
  assert.equal(trigger.eventTrigger.retry, true);
  assert.deepEqual(trigger.region, ["europe-west1"]);
});
