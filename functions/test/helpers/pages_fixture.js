// Shared fixtures for the Premium Pages suites (ADR-233): the activation
// document, a canonical tester VIP grant, a canonical public profile, a Page
// owner who passes every precondition, and canonical Page documents.
const { randomBytes, randomUUID } = require("node:crypto");
const { Timestamp } = require("firebase-admin/firestore");

const { PAGES_ACTIVATION_PATH } = require("../../pages/activation");
const { newPageDocument, pageNameSearch } = require("../../pages/contract");

const DAY_MS = 24 * 60 * 60 * 1000;

function pagesActivation(overrides = {}) {
  return {
    schemaVersion: 1,
    readAccess: "all",
    writeAccess: "all",
    testerUids: [],
    lapseEnabled: true,
    revision: 1,
    ...overrides,
  };
}

function testerGrant(overrides = {}) {
  return {
    source: "testerProgram",
    expiresAt: null,
    revoked: false,
    grantedBy: "owner-console",
    ...overrides,
  };
}

function publicProfileDoc(uid, nowMs, overrides = {}) {
  return {
    accountType: "personal",
    bannerUrl: null,
    bio: "",
    country: "",
    creatorAudienceVisible: false,
    displayName: "Kawiarnia Pod Lipą",
    displayNameSearch: "kawiarnia pod lipą",
    followerCount: 0,
    followingCount: 0,
    friendCount: 0,
    learningLanguages: [],
    nativeLanguage: "",
    photoUrl: null,
    premiumIdentity: false,
    schemaVersion: 1,
    spokenLanguages: [],
    statusMessage: "",
    uid,
    updatedAt: Timestamp.fromMillis(nowMs - 60_000),
    username: "",
    usernameSearch: "",
    website: null,
    ...overrides,
  };
}

function ownerUser(uid, overrides = {}) {
  return {
    uid,
    displayName: "Kawiarnia Pod Lipą",
    status: "active",
    role: "user",
    profileVisibility: "public",
    followerCount: 0,
    creatorAudienceEnabled: false,
    ...overrides,
  };
}

function freshUid(prefix = "pg") {
  return `${prefix}-${randomUUID()}`;
}

async function setActivation(db, overrides = {}) {
  await db.doc(PAGES_ACTIVATION_PATH).set(pagesActivation(overrides));
}

async function clearActivation(db) {
  await db.doc(PAGES_ACTIVATION_PATH).delete().catch(() => {});
}

/// An account that passes every create precondition. Options switch single
/// preconditions off.
async function seedOwner(db, uid, {
  nowMs,
  user = {},
  grant = testerGrant(),
  publicDoc = {},
  mute = false,
  entitlement = null,
} = {}) {
  const writes = [
    db.doc(`users/${uid}`).set(ownerUser(uid, user)),
    db.doc(`publicProfiles/${uid}`).set(publicProfileDoc(uid, nowMs, publicDoc)),
  ];
  if (grant) writes.push(db.doc(`vipGrants/${uid}`).set(grant));
  if (entitlement) writes.push(db.doc(`entitlements/${uid}`).set(entitlement));
  if (mute) {
    writes.push(db.doc(`restrictions/${uid}`).set({
      type: "communicationMute",
      expiresAt: null,
    }));
  }
  await Promise.all(writes);
}

function businessFields(overrides = {}) {
  return {
    website: "https://example.com",
    email: null,
    phone: null,
    address: null,
    hours: null,
    legalNotice: null,
    ...overrides,
  };
}

function createInput(overrides = {}) {
  return {
    requestId: `req-${randomUUID()}`,
    op: "create",
    kind: "business",
    category: "cafe_restaurant",
    description: "Coffee and cake.",
    business: businessFields(),
    community: null,
    birthDate: "1990-05-17",
    consentVersion: 1,
    ...overrides,
  };
}

/// A canonical Page document written directly (for hook and lapse tests).
function pageDoc(uid, nowMs, overrides = {}) {
  const now = Timestamp.fromMillis(nowMs);
  const displayName = overrides.displayName ?? "Kawiarnia Pod Lipą";
  const page = newPageDocument({
    pageId: uid,
    fields: {
      kind: "business",
      category: "cafe_restaurant",
      description: "Coffee and cake.",
      business: businessFields(),
      community: null,
    },
    displayName,
    now,
  });
  return { ...page, nameSearch: pageNameSearch(displayName), ...overrides };
}

function request(uid, data, { verified = true, role = null } = {}) {
  return {
    auth: uid === null
      ? null
      : { uid, token: { email_verified: verified, ...(role ? { role } : {}) } },
    data,
  };
}

function silentLogger() {
  const entries = [];
  const record = (level) => (...args) => entries.push({ level, args });
  return {
    entries,
    debug: record("debug"),
    info: record("info"),
    log: record("log"),
    warn: record("warn"),
    error: record("error"),
  };
}

// ------------------------------------------------ posts, follows (B3)

function newPostId() {
  return `pp_${randomBytes(20).toString("hex")}`;
}

function newMediaId() {
  return `pm_${randomBytes(20).toString("hex")}`;
}

function newCommentId() {
  return `pc_${randomBytes(20).toString("hex")}`;
}

/// An exact pagePosts document (ADR-233 §1.3), published text by default.
function postDoc(pageId, postId, createdAtMs, overrides = {}) {
  return {
    schemaVersion: 1,
    postId,
    pageId,
    authorId: pageId,
    pageKind: "business",
    kind: "text",
    text: "Fresh bread at 7.",
    media: [],
    status: "published",
    evidenceHold: false,
    commentsEnabled: true,
    likeCount: 0,
    commentCount: 0,
    heldAt: null,
    removedAt: null,
    removedReason: null,
    deletedAt: null,
    moderationEvidence: null,
    createdAt: Timestamp.fromMillis(createdAtMs),
    ...overrides,
  };
}

function photoMedia(pageId, postId, count = 1) {
  return Array.from({ length: count }, () => {
    const mediaId = newMediaId();
    return {
      mediaId,
      type: "image",
      contentType: "image/jpeg",
      size: 20_000,
      width: 1600,
      height: 1200,
      storagePath: `page_posts/${pageId}/${postId}/${mediaId}.jpg`,
      generation: "1700000000000001",
    };
  });
}

function voiceMedia(pageId, postId) {
  const mediaId = newMediaId();
  return [{
    mediaId,
    type: "audio",
    contentType: "audio/mp4",
    size: 40_000,
    durationMs: 12_000,
    storagePath: `page_posts/${pageId}/${postId}/${mediaId}.m4a`,
    generation: "1700000000000002",
  }];
}

/// An exact pagePostComments document (ADR-233 §1.5).
function commentDoc(post, commentId, authorId, createdAtMs, overrides = {}) {
  return {
    schemaVersion: 1,
    commentId,
    postId: post.postId,
    pageId: post.pageId,
    authorId,
    text: "Looks great!",
    createdAt: Timestamp.fromMillis(createdAtMs),
    ...overrides,
  };
}

/// An ordinary active account with a canonical public projection.
async function seedAccount(db, uid, nowMs, { user = {}, displayName = "Ola Nowak" } = {}) {
  await Promise.all([
    db.doc(`users/${uid}`).set({
      uid,
      displayName,
      status: "active",
      role: "user",
      profileVisibility: "public",
      followerCount: 0,
      followingCount: 0,
      ...user,
    }),
    db.doc(`publicProfiles/${uid}`).set(publicProfileDoc(uid, nowMs, { displayName })),
  ]);
}

/// A running Page owned by `uid`: owner account + grant + canonical Page.
async function seedPage(db, uid, nowMs, { page = {}, user = {}, grant = testerGrant() } = {}) {
  await seedOwner(db, uid, { nowMs, user, grant });
  await db.doc(`pages/${uid}`).set(pageDoc(uid, nowMs, page));
}

/// The follow edge pair setFollow writes, plus the viewer's index hint.
async function seedFollowEdge(db, viewerId, pageId, nowMs) {
  await Promise.all([
    db.doc(`users/${viewerId}/following/${pageId}`).set({
      uid: pageId,
      followedAt: Timestamp.fromMillis(nowMs),
    }),
    db.doc(`users/${pageId}/followers/${viewerId}`).set({
      uid: viewerId,
      followedAt: Timestamp.fromMillis(nowMs),
    }),
  ]);
}

async function setFollowIndex(db, viewerId, pageIds, nowMs) {
  await db.doc(`pageFollowIndex/${viewerId}`).set({
    schemaVersion: 1,
    pageIds,
    updatedAt: Timestamp.fromMillis(nowMs),
  });
}

module.exports = {
  DAY_MS,
  commentDoc,
  newCommentId,
  newMediaId,
  newPostId,
  photoMedia,
  postDoc,
  seedAccount,
  seedFollowEdge,
  seedPage,
  setFollowIndex,
  voiceMedia,
  businessFields,
  clearActivation,
  createInput,
  freshUid,
  ownerUser,
  pageDoc,
  pagesActivation,
  publicProfileDoc,
  request,
  seedOwner,
  setActivation,
  silentLogger,
  testerGrant,
};
