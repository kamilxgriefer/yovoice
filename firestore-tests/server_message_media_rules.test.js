// Servers V1 channel photo/video messages and reactions: the Storage and
// Firestore boundary.
//
//   firebase emulators:exec --only firestore,storage --project demo-yovoice \
//     'npm --prefix firestore-tests run test:server-message-media'
//
// ADR-007: the messages collection is read by the app with a per-channel
// query — query(collection(db, 'clubs/{s}/channels/{c}/messages'),
// orderBy('sentAt', 'desc'), limit(250)) (ClubChatService.watchMessages) —
// and that exact shape is exercised below. No collectionGroup() query reads
// server channel messages or any collection introduced here, so none is
// needed or tested.
//
// Every object path is unique per case (a fresh message id): the Storage
// emulator's clearStorage() does not reach nested prefixes (docs/Bugs.md), so
// no case depends on another case's leftovers.
const fs = require('node:fs');
const path = require('node:path');
const { randomBytes } = require('node:crypto');
const { after, before, test } = require('node:test');
const assert = require('node:assert/strict');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  setDoc,
  updateDoc,
} = require('firebase/firestore');
const {
  deleteObject,
  getBytes,
  listAll,
  ref,
  updateMetadata,
  uploadBytes,
} = require('firebase/storage');

// The emulator project itself (as storage.test.js and family-media.test.js
// use): Storage rules' cross-service firestore.get() reads the Firestore of
// the project the emulators were started with, so a different project id
// would make every reservation invisible and every upload a false denial.
const PROJECT = 'demo-yovoice';
const OWNER = 'smm-owner';
const MODERATOR = 'smm-moderator';
const MEMBER = 'smm-member';
const SECOND = 'smm-second';
const OUTSIDER = 'smm-outsider';
const BANNED = 'smm-banned';
const DELETED = 'smm-deleted';
const SERVER = 'smm-server';
const OTHER_SERVER = 'smm-other-server';
const CHANNEL = 'smm-general';
const OTHER_CHANNEL = 'smm-other';
const RESTRICTED = 'smm-restricted';
const COLLECTIONS = [
  'serverMessageMediaUploadReservations',
  'serverMessageMediaUploadLeases',
  'serverMessageMediaUploadBudgets',
  'serverMessageMediaDeletionJobs',
  'serverMessageMediaObjects',
];
const MEDIA = {
  jpg: { type: 'image', contentType: 'image/jpeg', size: 200, durationSeconds: null },
  png: { type: 'image', contentType: 'image/png', size: 300, durationSeconds: null },
  webp: { type: 'image', contentType: 'image/webp', size: 400, durationSeconds: null },
  mp4: { type: 'video', contentType: 'video/mp4', size: 2048, durationSeconds: 12 },
  mov: { type: 'video', contentType: 'video/quicktime', size: 4096, durationSeconds: 60 },
  webm: { type: 'video', contentType: 'video/webm', size: 1024, durationSeconds: 1 },
};
let env;

function endpoint(value, fallback) {
  const parts = (value || ('127.0.0.1:' + fallback)).split(':');
  return { host: parts[0], port: Number(parts[1]) };
}

function newMessageId() {
  return 'cm_' + randomBytes(20).toString('hex');
}

function server(ownerId) {
  return {
    serverSchemaVersion: 1,
    serverType: 'community',
    templateVersion: 1,
    serverActivationState: 'active',
    revision: 1,
    status: 'active',
    type: 'community',
    ownerId,
    privacy: 'inviteOnly',
    name: 'Messaging parity',
    description: '',
    memberCount: 4,
    onlineCount: 0,
    defaultLanguage: 'English',
  };
}

function member(uid, role) {
  return {
    userId: uid,
    role,
    displayName: uid,
    photoUrl: null,
    authorizationRevision: 1,
    joinedAt: new Date(0),
    isOnline: false,
  };
}

function channel(serverId, restricted = false) {
  return {
    serverSchemaVersion: 1,
    serverId,
    kind: 'text',
    type: 'chat',
    revision: 1,
    aclRevision: 1,
    status: 'active',
    name: 'general',
    position: 0,
    roomId: null,
    activeSessionId: null,
    experience: null,
    mediaMode: null,
    isPrivate: restricted,
    accessMode: restricted ? 'restricted' : 'members',
    accessPolicy: restricted
      ? { accessMode: 'restricted', roleIds: ['owner'], userIds: [MEMBER, SECOND].sort() }
      : { accessMode: 'members', roleIds: [], userIds: [] },
  };
}

function message(senderId, channelId, extra = {}) {
  return {
    clubId: SERVER,
    channelId,
    senderId,
    senderName: senderId,
    senderPhotoUrl: null,
    content: 'Photo',
    sentAt: new Date(),
    editedAt: null,
    isDeleted: false,
    ...extra,
  };
}

function mediaFields(messageId, channelId, ownerId) {
  const storagePath = 'server_message_media/' + SERVER + '/' + channelId + '/' + ownerId + '/' + messageId + '.jpg';
  return {
    type: 'image',
    mediaUrl: 'gs://demo-bucket/' + storagePath,
    media: {
      schemaVersion: 1,
      storagePath,
      generation: '1',
      contentType: 'image/jpeg',
      size: 200,
      durationSeconds: null,
    },
    reactions: { [MEMBER]: '❤️', [OWNER]: '👍' },
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
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const entries = {
      ['users/' + OWNER]: { displayName: OWNER, status: 'active', disabled: false },
      ['users/' + MODERATOR]: { displayName: MODERATOR, status: 'active', disabled: false },
      ['users/' + MEMBER]: { displayName: MEMBER, status: 'active', disabled: false },
      ['users/' + SECOND]: { displayName: SECOND, status: 'active', disabled: false },
      ['users/' + OUTSIDER]: { displayName: OUTSIDER, status: 'active', disabled: false },
      ['users/' + BANNED]: { displayName: BANNED, status: 'active', banned: true },
      ['users/' + DELETED]: { displayName: DELETED, status: 'deleted' },
      ['clubs/' + SERVER]: server(OWNER),
      ['clubs/' + SERVER + '/members/' + OWNER]: member(OWNER, 'owner'),
      ['clubs/' + SERVER + '/members/' + MODERATOR]: member(MODERATOR, 'moderator'),
      ['clubs/' + SERVER + '/members/' + MEMBER]: member(MEMBER, 'member'),
      ['clubs/' + SERVER + '/members/' + SECOND]: member(SECOND, 'member'),
      ['clubs/' + SERVER + '/channels/' + CHANNEL]: channel(SERVER),
      ['clubs/' + SERVER + '/channels/' + RESTRICTED]: channel(SERVER, true),
      ['clubs/' + SERVER + '/channels/' + RESTRICTED + '/accessGrants/' + MEMBER]: {
        schemaVersion: 1,
        userId: MEMBER,
        serverId: SERVER,
        channelId: RESTRICTED,
        aclRevision: 1,
        membershipRevision: 1,
        capabilities: {
          read: true, write: true, manage: false, moderate: false,
          joinVoice: false, startSession: false,
        },
        updatedAt: new Date(0),
      },
    };
    for (const [location, value] of Object.entries(entries)) {
      await setDoc(doc(db, location), value);
    }
    for (const channelId of [CHANNEL, RESTRICTED]) {
      const plain = channelId + '-text';
      await setDoc(doc(db, 'clubs/' + SERVER + '/channels/' + channelId + '/messages/' + plain),
        message(OWNER, channelId, { content: 'hello', reactions: { [MEMBER]: '😂' } }));
      const media = newMessageId();
      await setDoc(doc(db, 'clubs/' + SERVER + '/channels/' + channelId + '/messages/' + media),
        message(MEMBER, channelId, mediaFields(media, channelId, MEMBER)));
    }
    for (const name of COLLECTIONS) {
      await setDoc(doc(db, name + '/seeded'), { ownerId: MEMBER, serverId: SERVER });
    }
  });
});

after(async () => {
  if (env) await env.cleanup();
});

function context(uid, verified = true) {
  return env.authenticatedContext(uid, { email_verified: verified });
}

/**
 * A server-issued reservation, written as the reserve callable writes it,
 * and the matching exact upload identity.
 */
async function reservation({
  ext = 'jpg',
  owner = MEMBER,
  serverId = SERVER,
  channelId = CHANNEL,
  messageId = newMessageId(),
  overrides = {},
} = {}) {
  const shape = MEDIA[ext];
  const objectPath = 'server_message_media/' + serverId + '/' + channelId + '/' + owner + '/' + messageId + '.' + ext;
  const value = {
    schemaVersion: 1,
    kind: 'serverChannelMessageMedia',
    serverId,
    channelId,
    messageId,
    ownerId: owner,
    requestId: 'request-' + messageId.slice(3, 15),
    type: shape.type,
    contentType: shape.contentType,
    size: shape.size,
    durationSeconds: shape.durationSeconds,
    storagePath: objectPath,
    status: 'uploading',
    createdAt: new Date(),
    expiresAt: new Date(Date.now() + 15 * 60_000),
    ...overrides,
  };
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'serverMessageMediaUploadReservations/' + messageId), value);
  });
  return {
    messageId,
    objectPath,
    bytes: Buffer.alloc(value.size, 7),
    contentType: value.contentType,
    metadata: {
      yovoiceServerId: serverId,
      yovoiceChannelId: channelId,
      yovoiceOwnerUid: owner,
      yovoiceMessageId: messageId,
      yovoiceMessagePath: 'clubs/' + serverId + '/channels/' + channelId + '/messages/' + messageId,
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
    ref(context(uid, verified).storage(PROJECT), objectPath),
    bytes,
    { contentType, customMetadata: metadata },
  );
}

test('Storage: the exact reserved jpeg, png, webp, mp4, mov and webm are accepted', async () => {
  for (const ext of Object.keys(MEDIA)) {
    const target = await reservation({ ext });
    await assertSucceeds(upload(MEMBER, target));
  }
});

test('Storage: a missing, expired, used or foreign reservation authorizes nothing', async () => {
  // No reservation at all: a well-formed path and metadata are not a key.
  const orphan = newMessageId();
  const orphanPath = 'server_message_media/' + SERVER + '/' + CHANNEL + '/' + MEMBER + '/' + orphan + '.jpg';
  await assertFails(upload(MEMBER, {
    objectPath: orphanPath,
    bytes: Buffer.alloc(200, 1),
    contentType: 'image/jpeg',
    metadata: {
      yovoiceServerId: SERVER,
      yovoiceChannelId: CHANNEL,
      yovoiceOwnerUid: MEMBER,
      yovoiceMessageId: orphan,
      yovoiceMessagePath: 'clubs/' + SERVER + '/channels/' + CHANNEL + '/messages/' + orphan,
      yovoiceMediaType: 'image',
    },
  }));
  const expired = await reservation({ overrides: { expiresAt: new Date(Date.now() - 1_000) } });
  await assertFails(upload(MEMBER, expired));
  for (const status of ['expiring', 'finalized']) {
    await assertFails(upload(MEMBER, await reservation({ overrides: { status } })));
  }
  // A reservation for another channel, server or message.
  const otherChannel = await reservation({ overrides: { channelId: OTHER_CHANNEL } });
  await assertFails(upload(MEMBER, otherChannel));
  const otherServer = await reservation({ overrides: { serverId: OTHER_SERVER } });
  await assertFails(upload(MEMBER, otherServer));
  const otherMessage = await reservation({ overrides: { messageId: newMessageId() } });
  await assertFails(upload(MEMBER, otherMessage));
  // An extra key on the reservation is not the callable's shape.
  await assertFails(upload(MEMBER, await reservation({ overrides: { forged: true } })));
});

test('Storage: owner, metadata, size, MIME and extension must all match the reservation', async () => {
  // Another member uploading to the reserved owner's path.
  const owned = await reservation();
  await assertFails(upload(SECOND, owned));
  // The reserved owner writing under another uid's folder.
  const elsewhere = await reservation({ owner: SECOND });
  await assertFails(upload(MEMBER, elsewhere, {
    metadata: { ...elsewhere.metadata, yovoiceOwnerUid: MEMBER },
  }));
  // yovoiceOwnerUid different from the path uid.
  const target = await reservation();
  await assertFails(upload(MEMBER, target, {
    metadata: { ...target.metadata, yovoiceOwnerUid: SECOND },
  }));
  // One extra and one missing metadata key.
  await assertFails(upload(MEMBER, target, {
    metadata: { ...target.metadata, forged: 'true' },
  }));
  const { yovoiceMessagePath: _path, ...missing } = target.metadata;
  await assertFails(upload(MEMBER, target, { metadata: missing }));
  // A media type the reservation does not carry.
  await assertFails(upload(MEMBER, target, {
    metadata: { ...target.metadata, yovoiceMediaType: 'video' },
  }));
  // Size off by one in both directions.
  await assertFails(upload(MEMBER, target, { bytes: Buffer.alloc(199, 1) }));
  await assertFails(upload(MEMBER, target, { bytes: Buffer.alloc(201, 1) }));
  // MIME and extension disagree with each other or with the reservation.
  await assertFails(upload(MEMBER, target, { contentType: 'image/png' }));
  await assertFails(upload(MEMBER, target, {
    objectPath: target.objectPath.replace(/\.jpg$/u, '.png'),
  }));
  const video = await reservation({ ext: 'mp4' });
  await assertFails(upload(MEMBER, video, { contentType: 'video/webm' }));
  await assertFails(upload(MEMBER, video, {
    objectPath: video.objectPath.replace(/\.mp4$/u, '.mov'),
  }));
  // The exact upload still works afterwards: nothing above consumed it.
  await assertSucceeds(upload(MEMBER, target));
});

test('Storage: the direct-message byte and duration bounds hold even with a matching reservation', async () => {
  const tinyImage = await reservation({ overrides: { size: 127 } });
  await assertFails(upload(MEMBER, tinyImage, { bytes: Buffer.alloc(127, 1) }));
  const bigImage = await reservation({ overrides: { size: 8 * 1024 * 1024 + 1 } });
  await assertFails(upload(MEMBER, bigImage, { bytes: Buffer.alloc(8 * 1024 * 1024 + 1, 1) }));
  const edgeImage = await reservation({ overrides: { size: 8 * 1024 * 1024 } });
  await assertSucceeds(upload(MEMBER, edgeImage, { bytes: Buffer.alloc(8 * 1024 * 1024, 1) }));
  const tinyVideo = await reservation({ ext: 'mp4', overrides: { size: 1023 } });
  await assertFails(upload(MEMBER, tinyVideo, { bytes: Buffer.alloc(1023, 1) }));
  const bigVideo = await reservation({ ext: 'mp4', overrides: { size: 64 * 1024 * 1024 + 1 } });
  await assertFails(upload(MEMBER, bigVideo, { bytes: Buffer.alloc(64 * 1024 * 1024 + 1, 1) }));
  for (const durationSeconds of [0, 61, 12.5, null]) {
    const video = await reservation({ ext: 'mp4', overrides: { durationSeconds } });
    await assertFails(upload(MEMBER, video));
  }
  const imageWithDuration = await reservation({ overrides: { durationSeconds: 3 } });
  await assertFails(upload(MEMBER, imageWithDuration));
});

test('Storage: unverified, banned and deleted accounts cannot upload, and an object is never overwritten', async () => {
  const unverified = await reservation();
  await assertFails(upload(MEMBER, unverified, { verified: false }));
  await assertFails(upload(BANNED, await reservation({ owner: BANNED })));
  await assertFails(upload(DELETED, await reservation({ owner: DELETED })));
  const once = await reservation();
  await assertSucceeds(upload(MEMBER, once));
  await assertFails(upload(MEMBER, once));
});

test('Storage: only the uploader reads back, only while the reservation is live; no list, update or delete', async () => {
  const target = await reservation();
  await assertSucceeds(upload(MEMBER, target));
  const own = ref(context(MEMBER).storage(PROJECT), target.objectPath);
  await assertSucceeds(getBytes(own));
  for (const uid of [SECOND, OWNER, MODERATOR, OUTSIDER]) {
    await assertFails(getBytes(ref(context(uid).storage(PROJECT), target.objectPath)));
  }
  await assertFails(getBytes(ref(env.unauthenticatedContext().storage(PROJECT), target.objectPath)));
  await assertFails(updateMetadata(own, { customMetadata: { ...target.metadata, yovoiceMediaType: 'video' } }));
  await assertFails(deleteObject(own));
  await assertFails(deleteObject(ref(context(OWNER).storage(PROJECT), target.objectPath)));
  for (const prefix of [
    'server_message_media/' + SERVER + '/' + CHANNEL + '/' + MEMBER,
    'server_message_media/' + SERVER + '/' + CHANNEL,
    'server_message_media/' + SERVER,
  ]) {
    await assertFails(listAll(ref(context(MEMBER).storage(PROJECT), prefix)));
    await assertFails(listAll(ref(context(OWNER).storage(PROJECT), prefix)));
  }
  // After finalize the reservation is gone: even the uploader reads nothing.
  await env.withSecurityRulesDisabled(async (ctx) => {
    await deleteDoc(doc(ctx.firestore(), 'serverMessageMediaUploadReservations/' + target.messageId));
  });
  await assertFails(getBytes(own));
});

test('Firestore: the five Admin-only collections deny every client read and write', async () => {
  for (const uid of [OWNER, MEMBER, OUTSIDER]) {
    const db = context(uid).firestore();
    for (const name of COLLECTIONS) {
      await assertFails(getDoc(doc(db, name + '/seeded')));
      await assertFails(getDocs(collection(db, name)));
      await assertFails(getDocs(query(collection(db, name), limit(1))));
      await assertFails(setDoc(doc(db, name + '/forged-' + uid), { ownerId: uid, serverId: SERVER }));
      await assertFails(updateDoc(doc(db, name + '/seeded'), { ownerId: uid }));
      await assertFails(deleteDoc(doc(db, name + '/seeded')));
    }
  }
});

test('Firestore: reactions and media stay Admin-SDK-only on a V1 message', async () => {
  const plain = 'clubs/' + SERVER + '/channels/' + CHANNEL + '/messages/' + CHANNEL + '-text';
  for (const uid of [MEMBER, MODERATOR, OWNER]) {
    const db = context(uid).firestore();
    await assertFails(updateDoc(doc(db, plain), { ['reactions.' + uid]: '❤️' }));
    await assertFails(updateDoc(doc(db, plain), { reactions: { [uid]: '❤️' } }));
    const forged = newMessageId();
    await assertFails(updateDoc(doc(db, plain), mediaFields(forged, CHANNEL, uid)));
    await assertFails(updateDoc(doc(db, plain), { mediaUrl: 'gs://demo-bucket/x' }));
    await assertFails(setDoc(
      doc(db, 'clubs/' + SERVER + '/channels/' + CHANNEL + '/messages/' + forged),
      message(uid, CHANNEL, mediaFields(forged, CHANNEL, uid)),
    ));
    await assertFails(deleteDoc(doc(db, plain)));
  }
});

test('Firestore: the production thread query reads reactions and media through the channel ACL', async () => {
  const thread = (uid, channelId) => getDocs(query(
    collection(context(uid).firestore(), 'clubs/' + SERVER + '/channels/' + channelId + '/messages'),
    orderBy('sentAt', 'desc'),
    limit(250),
  ));
  const members = await assertSucceeds(thread(MEMBER, CHANNEL));
  assert.equal(members.size, 2);
  const withMedia = members.docs.find((row) => row.data().type === 'image');
  assert.equal(withMedia.data().reactions[MEMBER], '❤️');
  assert.equal(typeof withMedia.data().media.storagePath, 'string');
  await assertSucceeds(thread(OWNER, CHANNEL));
  await assertFails(thread(OUTSIDER, CHANNEL));
  // Restricted: a current grant reads, a named member without one does not.
  const restricted = await assertSucceeds(thread(MEMBER, RESTRICTED));
  assert.equal(restricted.size, 2);
  await assertFails(thread(SECOND, RESTRICTED));
  await assertFails(thread(OUTSIDER, RESTRICTED));
});
