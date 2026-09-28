// Premium Pages D13 in direct messaging (ADR-233 §2.3), against the
// Firestore emulator: following a Page is choosing what to READ, so under
// "People you follow" a follow edge to an account with a pages/{uid}
// document never lets that account message you; and a Page account may start
// at most 10 conversations with non-friends per 24 h (dm.pageOutbound).
const assert = require("node:assert/strict");
const { test } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

if (getApps().length === 0) initializeApp();

const {
  DEFAULT_LIMITS,
  DIRECT_MESSAGE_PRIVACY_REFERENCE_COUNT,
  PAGE_OUTBOUND_SCOPE,
  createDirectMessagingService,
  directMessagePrivacyAllows,
} = require("../messaging/direct_integrity");
const {
  freshUid,
  pageDoc,
  publicProfileDoc,
  request,
} = require("./helpers/pages_fixture");

const db = getFirestore();
const NOW_MS = 1_800_000_000_000;

function service(limits = {}) {
  return createDirectMessagingService({
    db,
    Timestamp,
    clock: () => NOW_MS,
    limits: {
      ...DEFAULT_LIMITS,
      open: { maxEvents: 100, windowMs: 60_000 },
      send: { maxEvents: 100, windowMs: 60_000 },
      ...limits,
    },
  });
}

async function account(prefix, user = {}) {
  const uid = freshUid(prefix);
  await Promise.all([
    db.doc(`users/${uid}`).set({ uid, displayName: `Name ${prefix}`, ...user }),
    db.doc(`publicProfiles/${uid}`).set(publicProfileDoc(uid, NOW_MS, {
      displayName: `Name ${prefix}`,
    })),
  ]);
  return uid;
}

async function pageAccount(pageOverrides = {}) {
  const uid = await account("dmpage");
  await db.doc(`pages/${uid}`).set(pageDoc(uid, NOW_MS, pageOverrides));
  return uid;
}

async function recipientFollows(recipient, followed) {
  await db.doc(`users/${recipient}/following/${followed}`).set({
    uid: followed,
    followedAt: Timestamp.fromMillis(NOW_MS),
  });
}

async function befriend(first, second) {
  for (const [owner, friend] of [[first, second], [second, first]]) {
    await db.doc(`friendshipGuards/${owner}/friends/${friend}`).set({
      ownerId: owner,
      friendId: friend,
      schemaVersion: 1,
      establishedAt: Timestamp.fromMillis(NOW_MS),
    });
  }
}

let counter = 0;
function open(dm, actor, target) {
  counter += 1;
  return dm.openDirectConversation(request(actor, {
    requestId: `pages-dm-open-${String(counter).padStart(6, "0")}`,
    targetUserId: target,
  }));
}

function refusedByPrivacy(error) {
  assert.equal(error.code, "permission-denied");
  assert.equal(error.message, "This person is not accepting direct messages from you.");
  return true;
}

test("the privacy references carry the actor's Page as the fourth read", () => {
  assert.equal(DIRECT_MESSAGE_PRIVACY_REFERENCE_COUNT, 4);
  assert.equal(PAGE_OUTBOUND_SCOPE, "dm.pageOutbound");
  assert.deepEqual(DEFAULT_LIMITS.pageOutbound, { maxEvents: 10, windowMs: 24 * 60 * 60_000 });
  const snap = (data) => ({ exists: data !== null, data: () => data });
  const edge = snap({ uid: "actor", followedAt: Timestamp.fromMillis(NOW_MS) });
  const base = {
    actorId: "actor",
    recipientId: "recipient",
    recipientProfile: snap({ messagePrivacy: "peopleYouFollow" }),
    recipientFollowsActor: edge,
    actorFriendGuard: snap(null),
    recipientFriendGuard: snap(null),
  };
  assert.equal(directMessagePrivacyAllows({ ...base, actorPage: snap(null) }), true);
  assert.equal(directMessagePrivacyAllows({ ...base, actorPage: snap({}) }), false);
  assert.equal(directMessagePrivacyAllows({ ...base,
    recipientProfile: snap({ messagePrivacy: "bogus" }) }), false);
});

test("following a Page never lets the Page owner message you under People you follow", async () => {
  const dm = service();
  const page = await pageAccount();
  const person = await account("dmperson");
  const recipient = await account("dmrecipient", { messagePrivacy: "peopleYouFollow" });
  await recipientFollows(recipient, page);
  await recipientFollows(recipient, person);
  await assert.rejects(open(dm, page, recipient), refusedByPrivacy);
  // The same edge to an ordinary account still counts.
  assert.equal((await open(dm, person, recipient)).created, true);

  // Any Page state counts: paused, lapsed, even a malformed document.
  const paused = await pageAccount({ ownerPaused: true });
  await recipientFollows(recipient, paused);
  await assert.rejects(open(dm, paused, recipient), refusedByPrivacy);
  const broken = await account("dmbroken");
  await db.doc(`pages/${broken}`).set({ junk: true });
  await recipientFollows(recipient, broken);
  await assert.rejects(open(dm, broken, recipient), refusedByPrivacy);

  // A conversation opened while the recipient accepted everyone cannot be
  // continued by the Page once they narrow it to People you follow.
  const later = await account("dmlater");
  const conversation = await open(dm, page, later);
  await db.doc(`users/${later}`).update({ messagePrivacy: "peopleYouFollow" });
  await recipientFollows(later, page);
  await assert.rejects(dm.sendDirectMessage(request(page, {
    conversationId: conversation.conversationId,
    requestId: "pages-dm-send-after-narrowing",
    text: "hello",
  })), refusedByPrivacy);
  // Friends still reach each other, Page or not.
  await db.doc(`users/${later}`).update({ messagePrivacy: "friends" });
  await befriend(page, later);
  const sent = await dm.sendDirectMessage(request(page, {
    conversationId: conversation.conversationId,
    requestId: "pages-dm-send-to-friend",
    text: "hello friend",
  }));
  assert.equal(typeof sent.messageId, "string");
});

test("a Page account starts at most 10 conversations with non-friends per 24 h", async () => {
  const dm = service();
  const page = await pageAccount();
  const first = [];
  for (let index = 0; index < 10; index += 1) {
    const target = await account(`dmout${index}`);
    first.push(target);
    assert.equal((await open(dm, page, target)).created, true);
  }
  const eleventh = await account("dmout10");
  await assert.rejects(open(dm, page, eleventh), (error) => {
    assert.equal(error.code, "resource-exhausted");
    return true;
  });
  // Reopening an existing conversation is free.
  assert.equal((await open(dm, page, first[0])).created, false);
  // Starting a conversation with a friend is free.
  const friend = await account("dmfriend");
  await befriend(page, friend);
  assert.equal((await open(dm, page, friend)).created, true);
  // Ordinary accounts have no such limit.
  const person = await account("dmordinary");
  for (let index = 0; index < 11; index += 1) {
    const target = await account(`dmord${index}`);
    assert.equal((await open(dm, person, target)).created, true);
  }
});
