// End-to-end smoke test for the callable social-graph bindings.
//
// Unit tests exercise the handlers directly. This script deliberately calls
// the Functions emulator over the callable HTTP protocol so a release also
// proves that the exports, region and runtime bindings are reachable.

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "demo-yovoice";

const assert = require("node:assert/strict");
const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const db = getFirestore();
const PROJECT = process.env.GCLOUD_PROJECT;
const FUNCTIONS_HOST =
  process.env.FUNCTIONS_EMULATOR_HOST ?? "127.0.0.1:5001";
const ACTOR = "smoke-social-actor";
const TARGET = "smoke-social-target";

function endpoint(name) {
  return `http://${FUNCTIONS_HOST}/${PROJECT}/europe-west1/${name}`;
}

function emulatorIdToken(uid) {
  const encode = (value) =>
    Buffer.from(JSON.stringify(value)).toString("base64url");
  const now = Math.floor(Date.now() / 1000);
  return `${encode({ alg: "none", typ: "JWT" })}.${encode({
    iss: `https://securetoken.google.com/${PROJECT}`,
    aud: PROJECT,
    sub: uid,
    user_id: uid,
    uid,
    iat: now,
    exp: now + 3600,
    auth_time: now,
    email_verified: true,
    firebase: { sign_in_provider: "custom", identities: {} },
  })}.`;
}

async function call(name, uid, data) {
  const response = await fetch(endpoint(name), {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${emulatorIdToken(uid)}`,
    },
    body: JSON.stringify({ data }),
  });
  const json = await response.json().catch(() => ({}));
  assert.equal(
    response.status,
    200,
    `${name} returned ${response.status}: ${JSON.stringify(json)}`,
  );
  return json.result;
}

async function seed() {
  await Promise.all([
    db.recursiveDelete(db.doc(`users/${ACTOR}`)),
    db.recursiveDelete(db.doc(`users/${TARGET}`)),
  ]);
  await Promise.all([
    db.doc(`users/${ACTOR}`).set({
      uid: ACTOR,
      email: "actor@smoke.invalid",
      displayName: "Smoke Actor",
      friendCount: 0,
      followerCount: 0,
      followingCount: 0,
      banned: false,
      disabled: false,
    }),
    db.doc(`users/${TARGET}`).set({
      uid: TARGET,
      email: "target@smoke.invalid",
      displayName: "Smoke Target",
      friendCount: 0,
      followerCount: 0,
      followingCount: 0,
      banned: false,
      disabled: false,
    }),
  ]);
}

async function socialNotifications(uid, type, actorId) {
  const snapshot = await db.doc(`users/${uid}`).collection("notifications").get();
  return snapshot.docs.filter((doc) => {
    const data = doc.data();
    return data.type === type && data.actorId === actorId;
  });
}

async function main() {
  await seed();

  // Cancel must retract the actionable alert, and a later request must be
  // a fresh document create (the push trigger is create-only).
  const requested = await call("sendFriendRequest", ACTOR, {
    targetUserId: TARGET,
  });
  assert.equal(requested.outcome, "requested");
  assert.equal(
    (await db.doc(`users/${TARGET}/friendRequests/${ACTOR}`).get()).exists,
    true,
    "the canonical incoming request must exist",
  );
  const firstRequestAlerts = await socialNotifications(
    TARGET,
    "friendRequest",
    ACTOR,
  );
  assert.equal(firstRequestAlerts.length, 1);
  assert.equal(firstRequestAlerts[0].data().isRead, false);
  await call("cancelFriendRequest", ACTOR, { targetUserId: TARGET });
  for (const path of [
    `users/${TARGET}/friendRequests/${ACTOR}`,
    `users/${ACTOR}/sentFriendRequests/${TARGET}`,
  ]) {
    assert.equal((await db.doc(path).get()).exists, false, path);
  }
  assert.equal(
    (await socialNotifications(TARGET, "friendRequest", ACTOR)).length,
    0,
  );

  await call("sendFriendRequest", ACTOR, { targetUserId: TARGET });
  await call("respondToFriendRequest", TARGET, {
    senderId: ACTOR,
    accept: false,
  });
  assert.equal(
    (await socialNotifications(TARGET, "friendRequest", ACTOR)).length,
    0,
  );

  await call("sendFriendRequest", ACTOR, { targetUserId: TARGET });

  const accepted = await call("respondToFriendRequest", TARGET, {
    senderId: ACTOR,
    accept: true,
  });
  assert.equal(accepted.outcome, "accepted");

  const [actorFriend, targetFriend, actorProfile, targetProfile, request] =
    await Promise.all([
      db.doc(`users/${ACTOR}/friends/${TARGET}`).get(),
      db.doc(`users/${TARGET}/friends/${ACTOR}`).get(),
      db.doc(`users/${ACTOR}`).get(),
      db.doc(`users/${TARGET}`).get(),
      db.doc(`users/${TARGET}/friendRequests/${ACTOR}`).get(),
    ]);
  assert.equal(actorFriend.exists, true, "actor mirror missing");
  assert.equal(targetFriend.exists, true, "target mirror missing");
  assert.equal(actorProfile.data().friendCount, 1);
  assert.equal(targetProfile.data().friendCount, 1);
  assert.equal(request.exists, false, "accepted request was not consumed");
  assert.equal(
    (await socialNotifications(TARGET, "friendRequest", ACTOR)).length,
    0,
    "accepted request alert was not retired",
  );

  const replay = await call("respondToFriendRequest", TARGET, {
    senderId: ACTOR,
    accept: true,
  });
  assert.equal(replay.outcome, "alreadyAccepted");
  assert.equal((await db.doc(`users/${ACTOR}`).get()).data().friendCount, 1);
  assert.equal((await db.doc(`users/${TARGET}`).get()).data().friendCount, 1);

  await call("removeFriend", ACTOR, { targetUserId: TARGET });
  assert.equal(
    (await db.doc(`users/${ACTOR}/friends/${TARGET}`).get()).exists,
    false,
  );
  assert.equal(
    (await socialNotifications(ACTOR, "friendAccepted", TARGET)).length,
    0,
    "unfriend must retire the previous acceptance activity",
  );
  assert.equal((await db.doc(`users/${ACTOR}`).get()).data().friendCount, 0);
  assert.equal((await db.doc(`users/${TARGET}`).get()).data().friendCount, 0);

  console.log(
    "OK  social callables cover send/cancel/decline/accept/replay/unfriend "
      + "with lifecycle-safe alerts and counters",
  );
}

main().catch((error) => {
  console.error("FAIL", error.stack ?? error.message);
  process.exit(1);
});
