// Firebase Storage hardening regression suite.
//
// Run (repo root):
//   firebase emulators:exec --only firestore,storage --project demo-yovoice \
//     'npm --prefix firestore-tests run test:storage'
const fs = require("fs");
const path = require("path");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
const { deleteDoc, doc, setDoc } = require("firebase/firestore");
const {
  ref,
  uploadBytes,
  getBytes,
  getDownloadURL,
  updateMetadata,
  deleteObject,
  listAll,
} = require("firebase/storage");

const FIRESTORE_RULES = path.resolve(__dirname, "../firestore.rules");
const STORAGE_RULES = path.resolve(__dirname, "../storage.rules");

// Emulator ports are test-harness state, not product behavior. Firebase CLI
// injects the combined *_EMULATOR_HOST variables; the split variables remain
// useful for an explicitly managed emulator in CI or a parallel local run.
function emulatorEndpoint(
  combinedValue,
  explicitHost,
  explicitPort,
  fallbackPort,
) {
  const separator = combinedValue?.lastIndexOf(":") ?? -1;
  const combinedHost = separator > 0 ? combinedValue.slice(0, separator) : null;
  const combinedPort =
    separator > 0 ? combinedValue.slice(separator + 1) : null;
  return {
    host: explicitHost ?? combinedHost ?? "127.0.0.1",
    port: Number(explicitPort ?? combinedPort ?? fallbackPort),
  };
}

const firestoreEndpoint = emulatorEndpoint(
  process.env.FIRESTORE_EMULATOR_HOST,
  process.env.FIRESTORE_EMULATOR_ADDRESS,
  process.env.FIRESTORE_EMULATOR_PORT,
  8080,
);
const storageEndpoint = emulatorEndpoint(
  process.env.FIREBASE_STORAGE_EMULATOR_HOST,
  process.env.STORAGE_EMULATOR_ADDRESS,
  process.env.STORAGE_EMULATOR_PORT,
  9199,
);
const EMULATOR_HOST = firestoreEndpoint.host;
const FIRESTORE_PORT = firestoreEndpoint.port;
const STORAGE_HOST = storageEndpoint.host;
const STORAGE_PORT = storageEndpoint.port;

for (const [name, port] of [
  ["FIRESTORE_EMULATOR_PORT", FIRESTORE_PORT],
  ["STORAGE_EMULATOR_PORT", STORAGE_PORT],
]) {
  if (!Number.isInteger(port) || port <= 0) {
    throw new Error(`${name} is not a port: ${process.env[name]}`);
  }
}

let passed = 0;
let failed = 0;

async function check(name, fn) {
  try {
    await fn();
    passed += 1;
    console.log(`  OK  ${name}`);
  } catch (error) {
    failed += 1;
    console.log(`FAIL  ${name}`);
    console.log(`      ${error.message.split("\n")[0]}`);
  }
}

const jpeg = { contentType: "image/jpeg" };
const png = { contentType: "image/png" };
const webp = { contentType: "image/webp" };
const pdf = { contentType: "application/pdf" };
const audio = { contentType: "audio/mp4" };
const legacyAudio = { contentType: "audio/m4a" };

const smallImage = new Uint8Array(64 * 1024);
const tooSmallImage = new Uint8Array(1);
const overProfileCap = new Uint8Array(2 * 1024 * 1024 + 1);
const smallAudio = new Uint8Array(128 * 1024);
const smallVideo = new Uint8Array(256 * 1024);
const tooSmallAudio = new Uint8Array(1000);
const oversizeAudio = new Uint8Array(12 * 1024 * 1024 + 1);

const ALICE = "alice-uid";
const BOB = "bob-uid";
const MALLORY = "mallory-uid";
const NEWBIE = "newbie-uid";
const BANNED = "banned-uid";
const DISABLED = "disabled-uid";
const MOMENT = "abcdef0123456789abcd";
const LEGACY_MIXED_MOMENT = "AbCdEfGhIjKlMnOpQrSt";
const PARENT = "1234567890abcdefabcd";
const COMMENT = "fedcba0987654321fedc";
const REPLY_CONTRACT = "aaaaaaaaaaaaaaaaaaaa";
const REPLY_ORPHAN = "bbbbbbbbbbbbbbbbbbbb";
const LEGACY_REPLY = "AbCdEfGhIjKlMnOpQrSt";
const LEGACY_REPLY_NEW = "ZyXwVuTsRqPoNmLkJiHg";
const LEGACY_REPLY_M4A = "LmNoPqRsTuVwXyZaBcDe";
const DIRECT_CONVERSATION = "dm_storage_test";
const DIRECT_IMAGE_MESSAGE = `m_${"a".repeat(40)}`;
const DIRECT_CONTRACT_IMAGE = `m_${"d".repeat(40)}`;
const DIRECT_VOICE_MESSAGE = `m_${"e".repeat(40)}`;
const DIRECT_VIDEO_MESSAGE = `m_${"9".repeat(40)}`;
const DIRECT_UNVERIFIED_MESSAGE = `m_${"f".repeat(40)}`;
const DIRECT_EXPIRED_MESSAGE = `m_${"0".repeat(40)}`;
const STORAGE_TEST_BUCKET = "demo-yovoice";
const REEL_IMAGE = "reel-image-1";
const REEL_VIDEO = "reel-video-1";
const REEL_EXPIRED = "reel-expired-1";
const REEL_UNVERIFIED = "reel-unverified-1";

function momentMetadata(authorId, momentId, extra = {}) {
  return {
    contentType: "audio/mp4",
    customMetadata: { authorId, momentId, ...extra },
  };
}

function replyMetadata(authorId, momentId, commentId, extra = {}) {
  return {
    contentType: "audio/mp4",
    customMetadata: { authorId, momentId, commentId, ...extra },
  };
}

function voiceReplyReservation(ownerId, momentId, commentId, overrides = {}) {
  return {
    schemaVersion: 1,
    kind: "voiceMomentComment",
    ownerId,
    momentId,
    commentId,
    storagePath: `voice_replies/${ownerId}/${momentId}/${commentId}.m4a`,
    durationSeconds: 7,
    text: "Reserved voice reply",
    authorName: "Reserved author",
    authorPhotoUrl: null,
    status: "uploading",
    createdAt: new Date(),
    expiresAt: new Date(Date.now() + 10 * 60 * 1000),
    ...overrides,
  };
}

function directMetadata(ownerId, conversationId, messageId, type, extra = {}) {
  return {
    contentType: type === "image"
      ? "image/jpeg"
      : type === "video" ? "video/mp4" : "audio/mp4",
    customMetadata: {
      yovoiceConversationId: conversationId,
      yovoiceMessageId: messageId,
      yovoiceMessagePath: `conversations/${conversationId}/messages/${messageId}`,
      yovoiceMediaType: type,
      yovoiceOwnerUid: ownerId,
      ...extra,
    },
  };
}

function directMessage(ownerId, conversationId, messageId, type, extension) {
  return {
    schemaVersion: 2,
    sequence: 1,
    conversationId,
    senderId: ownerId,
    type,
    content: type === "video" ? "Video" : "",
    mediaUrl:
      `gs://${STORAGE_TEST_BUCKET}/message_attachments/${ownerId}/` +
      `${conversationId}/${messageId}.${extension}`,
    durationSeconds: type === "image" ? null : 7,
    sentAt: new Date(),
    readBy: [ownerId],
    reactions: {},
    isDeleted: false,
    editedAt: null,
    replyToMessageId: null,
    replyToSenderId: null,
    replyToContent: null,
  };
}

function reelMetadata(ownerId, reelId, assetKind, contentType) {
  return {
    contentType,
    customMetadata: { ownerId, reelId, assetKind },
  };
}

async function seedReelReservation(
  testEnv,
  {
    reelId,
    ownerId = ALICE,
    mediaKind = "image",
    mediaContentType = "image/jpeg",
    mediaSize = smallImage.length,
    mediaFileName = "media.jpg",
    hasBackingAudio = false,
    audioContentType = null,
    audioSize = null,
    audioFileName = null,
    expiresAt = new Date(Date.now() + 10 * 60 * 1000),
  },
) {
  const mediaStoragePath = `reels/${ownerId}/${reelId}/${mediaFileName}`;
  const backingAudioStoragePath = audioFileName == null
    ? null
    : `reels/${ownerId}/${reelId}/${audioFileName}`;
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `reelUploadReservations/${reelId}`), {
      schemaVersion: 1,
      reelId,
      ownerId,
      status: "uploading",
      mediaKind,
      mediaContentType,
      mediaSize,
      mediaStoragePath,
      hasBackingAudio,
      audioContentType,
      audioSize,
      backingAudioStoragePath,
      createdAt: new Date(),
      expiresAt,
    });
  });
  return { mediaStoragePath, backingAudioStoragePath };
}

// `testEnv.clearStorage()` deletes only what a single `listAll()` at the
// bucket root returns, and `listAll()` does not recurse. Every object this
// suite writes lives under a prefix — `users/`, `room_images/`, `clubs/`,
// `message_attachments/`, `voice_moments/`, `voice_replies/` — so that call
// removes nothing at all here. Objects then survive into the next run
// against the same emulator, where the create-only paths
// (`allow create: if resource == null`)
// correctly deny the re-upload — green checks turn red with no rule having
// changed, in the one suite that gates a `storage.rules` deploy.
//
// Walk the prefix tree instead, so a re-run starts from the same empty bucket
// a brand-new emulator would hand it. Verify the bucket really is empty
// afterwards: if this ever stops keeping up with the paths under test, that
// must surface as one loud, explicit failure here rather than as scattered
// authorization failures further down.
async function clearStorage(testEnv) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    async function objectsUnder(dir) {
      const { items, prefixes } = await listAll(dir);
      const nested = await Promise.all(prefixes.map((p) => objectsUnder(p)));
      return items.concat(...nested);
    }

    const root = ref(ctx.storage());
    await Promise.all(
      (await objectsUnder(root)).map((item) => deleteObject(item)),
    );

    const remaining = await objectsUnder(root);
    if (remaining.length > 0) {
      throw new Error(
        `Storage emulator still holds ${remaining.length} object(s) after ` +
          `clearing: ${remaining.map((item) => item.fullPath).join(", ")}. ` +
          "The create-only paths below would deny re-uploading them and report " +
          "a rules regression that is not one.",
      );
    }
  });
}

async function revokeEmulatorDownloadToken(testEnv, objectPath) {
  let tokenUrl;
  let beforeStatus;
  let afterStatus;
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const object = ref(ctx.storage(), objectPath);
    tokenUrl = await getDownloadURL(object);
    beforeStatus = (await fetch(tokenUrl)).status;
    const token = new URL(tokenUrl).searchParams.get("token");
    if (!token) {
      throw new Error("Storage emulator did not issue a download token.");
    }
    const revokeUrl = new URL(tokenUrl);
    revokeUrl.search = "";
    revokeUrl.searchParams.set("delete_token", token);
    const response = await fetch(revokeUrl, {
      method: "POST",
      headers: { Authorization: "Bearer owner" },
    });
    if (!response.ok) {
      throw new Error(`Storage emulator token revocation failed: ${response.status}`);
    }
    await updateMetadata(object, {
      customMetadata: { yovoiceFinalized: "true" },
    });
  });
  afterStatus = (await fetch(tokenUrl)).status;
  return { beforeStatus, afterStatus, tokenUrl };
}

async function seed(testEnv) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const uid of [ALICE, BOB, MALLORY, NEWBIE]) {
      await setDoc(doc(db, `users/${uid}`), {
        uid,
        banned: false,
        disabled: false,
      });
    }
    await setDoc(doc(db, `users/${BANNED}`), { uid: BANNED, banned: true });
    await setDoc(doc(db, `users/${DISABLED}`), {
      uid: DISABLED,
      disabled: true,
    });

    await setDoc(doc(db, "rooms/active-room"), {
      hostId: ALICE,
      status: "active",
      deletionInProgress: false,
    });
    await setDoc(doc(db, "rooms/suspended-room"), {
      hostId: ALICE,
      status: "suspended",
    });
    await setDoc(doc(db, "rooms/deleting-room"), {
      hostId: ALICE,
      status: "active",
      deletionInProgress: true,
    });

    await setDoc(doc(db, "clubs/club-owned"), {
      ownerId: ALICE,
      status: "active",
      deletionInProgress: false,
    });
    await setDoc(doc(db, `clubs/club-owned/members/${ALICE}`), {
      userId: ALICE,
      role: "owner",
      banned: false,
    });
    await setDoc(doc(db, `clubs/club-owned/members/${BOB}`), {
      userId: BOB,
      role: "admin",
      banned: false,
    });
    await setDoc(doc(db, `clubs/club-owned/members/${MALLORY}`), {
      userId: MALLORY,
      role: "member",
      banned: false,
    });

    // The path still contains the old owner, but canonical ownership and the
    // role mirror have moved to Bob. Alice must no longer control this object.
    await setDoc(doc(db, "clubs/transferred-club"), {
      ownerId: BOB,
      status: "active",
      deletionInProgress: false,
    });
    await setDoc(doc(db, `clubs/transferred-club/members/${ALICE}`), {
      userId: ALICE,
      role: "member",
      banned: false,
    });
    await setDoc(doc(db, `clubs/transferred-club/members/${BOB}`), {
      userId: BOB,
      role: "owner",
      banned: false,
    });

    await setDoc(doc(db, "clubs/suspended-club"), {
      ownerId: ALICE,
      status: "suspended",
    });
    await setDoc(doc(db, `clubs/suspended-club/members/${ALICE}`), {
      userId: ALICE,
      role: "owner",
    });
    await setDoc(doc(db, `clubs/family_${ALICE}`), {
      ownerId: ALICE,
      type: "family",
      status: "active",
      deletionInProgress: false,
    });
    await setDoc(doc(db, `clubs/family_${ALICE}/members/${ALICE}`), {
      userId: ALICE,
      role: "owner",
      banned: false,
    });
    await setDoc(doc(db, `clubs/family_${ALICE}/members/${BOB}`), {
      userId: BOB,
      role: "member",
      banned: false,
    });

    await setDoc(doc(db, `voiceMoments/${MOMENT}`), {
      schemaVersion: 2,
      authorId: ALICE,
      audioUrl: null,
      storagePath: `voice_moments/${ALICE}/${MOMENT}.m4a`,
      durationSeconds: 30,
      isPublished: false,
      isDeleted: false,
      status: "uploading",
      publishedAt: null,
      mediaGeneration: null,
      mediaSize: null,
      mediaContentType: null,
    });
    await setDoc(doc(db, `voiceMoments/${LEGACY_MIXED_MOMENT}`), {
      schemaVersion: 2,
      authorId: ALICE,
      audioUrl: null,
      storagePath: `voice_moments/${ALICE}/${LEGACY_MIXED_MOMENT}.m4a`,
      durationSeconds: 30,
      isPublished: false,
      isDeleted: false,
      status: "uploading",
      publishedAt: null,
      mediaGeneration: null,
      mediaSize: null,
      mediaContentType: null,
    });
    await setDoc(doc(db, `voiceMoments/${PARENT}`), {
      authorId: BOB,
      isPublished: true,
    });
    await setDoc(
      doc(db, `voiceMomentUploadReservations/${COMMENT}`),
      voiceReplyReservation(ALICE, PARENT, COMMENT),
    );
    await setDoc(doc(db, "voiceMoments/UnpublishedParent01"), {
      authorId: BOB,
      isPublished: false,
    });
    await setDoc(doc(db, `conversations/${DIRECT_CONVERSATION}`), {
      schemaVersion: 2,
      participantIds: [ALICE, BOB],
    });
    await setDoc(
      doc(db, `directMessageUploadReservations/${DIRECT_IMAGE_MESSAGE}`),
      {
        schemaVersion: 1,
        ownerId: ALICE,
        conversationId: DIRECT_CONVERSATION,
        messageId: DIRECT_IMAGE_MESSAGE,
        recipientId: BOB,
        type: "image",
        contentType: "image/jpeg",
        durationSeconds: null,
        storagePath: `message_attachments/${ALICE}/${DIRECT_CONVERSATION}/${DIRECT_IMAGE_MESSAGE}.jpg`,
        status: "uploading",
        createdAt: new Date(),
        expiresAt: new Date(Date.now() + 10 * 60 * 1000),
      },
    );
    await setDoc(
      doc(db, `directMessageUploadReservations/${DIRECT_CONTRACT_IMAGE}`),
      {
        schemaVersion: 1,
        ownerId: ALICE,
        conversationId: DIRECT_CONVERSATION,
        messageId: DIRECT_CONTRACT_IMAGE,
        recipientId: BOB,
        type: "image",
        contentType: "image/jpeg",
        durationSeconds: null,
        storagePath: `message_attachments/${ALICE}/${DIRECT_CONVERSATION}/${DIRECT_CONTRACT_IMAGE}.jpg`,
        status: "uploading",
        createdAt: new Date(),
        expiresAt: new Date(Date.now() + 10 * 60 * 1000),
      },
    );
    await setDoc(
      doc(db, `directMessageUploadReservations/${DIRECT_VOICE_MESSAGE}`),
      {
        schemaVersion: 1,
        ownerId: ALICE,
        conversationId: DIRECT_CONVERSATION,
        messageId: DIRECT_VOICE_MESSAGE,
        recipientId: BOB,
        type: "voice",
        contentType: "audio/mp4",
        durationSeconds: 7,
        storagePath: `message_attachments/${ALICE}/${DIRECT_CONVERSATION}/${DIRECT_VOICE_MESSAGE}.m4a`,
        status: "uploading",
        createdAt: new Date(),
        expiresAt: new Date(Date.now() + 10 * 60 * 1000),
      },
    );
    await setDoc(
      doc(db, `directMessageUploadReservations/${DIRECT_VIDEO_MESSAGE}`),
      {
        schemaVersion: 1,
        ownerId: ALICE,
        conversationId: DIRECT_CONVERSATION,
        messageId: DIRECT_VIDEO_MESSAGE,
        recipientId: BOB,
        type: "video",
        contentType: "video/mp4",
        durationSeconds: 12,
        storagePath: `message_attachments/${ALICE}/${DIRECT_CONVERSATION}/${DIRECT_VIDEO_MESSAGE}.mp4`,
        status: "uploading",
        createdAt: new Date(),
        expiresAt: new Date(Date.now() + 10 * 60 * 1000),
      },
    );
    await setDoc(
      doc(db, `directMessageUploadReservations/${DIRECT_UNVERIFIED_MESSAGE}`),
      {
        schemaVersion: 1,
        ownerId: NEWBIE,
        conversationId: DIRECT_CONVERSATION,
        messageId: DIRECT_UNVERIFIED_MESSAGE,
        recipientId: BOB,
        type: "voice",
        contentType: "audio/mp4",
        durationSeconds: 7,
        storagePath: `message_attachments/${NEWBIE}/${DIRECT_CONVERSATION}/${DIRECT_UNVERIFIED_MESSAGE}.m4a`,
        status: "uploading",
        createdAt: new Date(),
        expiresAt: new Date(Date.now() + 10 * 60 * 1000),
      },
    );
    await setDoc(
      doc(db, `directMessageUploadReservations/${DIRECT_EXPIRED_MESSAGE}`),
      {
        schemaVersion: 1,
        ownerId: ALICE,
        conversationId: DIRECT_CONVERSATION,
        messageId: DIRECT_EXPIRED_MESSAGE,
        recipientId: BOB,
        type: "voice",
        contentType: "audio/mp4",
        durationSeconds: 7,
        storagePath: `message_attachments/${ALICE}/${DIRECT_CONVERSATION}/${DIRECT_EXPIRED_MESSAGE}.m4a`,
        status: "uploading",
        createdAt: new Date(Date.now() - 20 * 60 * 1000),
        expiresAt: new Date(Date.now() - 10 * 60 * 1000),
      },
    );
    await Promise.all([
      setDoc(
        doc(
          db,
          `conversations/${DIRECT_CONVERSATION}/messages/${DIRECT_IMAGE_MESSAGE}`,
        ),
        directMessage(
          ALICE,
          DIRECT_CONVERSATION,
          DIRECT_IMAGE_MESSAGE,
          "image",
          "jpg",
        ),
      ),
      setDoc(
        doc(
          db,
          `conversations/${DIRECT_CONVERSATION}/messages/${DIRECT_VOICE_MESSAGE}`,
        ),
        directMessage(
          ALICE,
          DIRECT_CONVERSATION,
          DIRECT_VOICE_MESSAGE,
          "voice",
          "m4a",
        ),
      ),
      setDoc(
        doc(
          db,
          `conversations/${DIRECT_CONVERSATION}/messages/${DIRECT_VIDEO_MESSAGE}`,
        ),
        directMessage(
          ALICE,
          DIRECT_CONVERSATION,
          DIRECT_VIDEO_MESSAGE,
          "video",
          "mp4",
        ),
      ),
    ]);
  });
}

async function seedRoomCoverReservation(
  testEnv,
  {
    reservationId,
    ownerId = ALICE,
    roomId = "active-room",
    storagePath,
    contentType = "image/jpeg",
    size = smallImage.length,
    expiresAt = new Date(Date.now() + 10 * 60 * 1000),
  },
) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(
      doc(ctx.firestore(), `roomCoverUploadReservations/${reservationId}`),
      {
        schemaVersion: 1,
        reservationId,
        ownerId,
        roomId,
        requestId: `storage-test-${reservationId}`,
        storagePath,
        contentType,
        size,
        status: "uploading",
        createdAt: new Date(),
        expiresAt,
      },
    );
  });
}

async function seedProfileMediaReservation(
  testEnv,
  {
    ownerId = ALICE,
    uploadId,
    kind = "avatar",
    contentType = "image/jpeg",
    size = smallImage.length,
    expiresAt = new Date(Date.now() + 10 * 60 * 1000),
  },
) {
  const extension =
    contentType === "image/png"
      ? "png"
      : contentType === "image/webp"
        ? "webp"
        : "jpg";
  const storagePath = `users/${ownerId}/profile/${kind}_${uploadId}.${extension}`;
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(
      doc(
        ctx.firestore(),
        `profileMediaUploadReservations/${ownerId}/uploads/${uploadId}`,
      ),
      {
        schemaVersion: 1,
        ownerId,
        uploadId,
        kind,
        contentType,
        size,
        storagePath,
        baseRevision: 0,
        status: "uploading",
        createdAt: new Date(),
        expiresAt,
      },
    );
  });
  return storagePath;
}

function profileMetadata(
  ownerId,
  uploadId,
  kind = "avatar",
  contentType = "image/jpeg",
) {
  return {
    contentType,
    customMetadata: { ownerId, profileKind: kind, uploadId },
  };
}

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: "demo-yovoice",
    firestore: {
      rules: fs.readFileSync(FIRESTORE_RULES, "utf8"),
      host: EMULATOR_HOST,
      port: FIRESTORE_PORT,
    },
    storage: {
      rules: fs.readFileSync(STORAGE_RULES, "utf8"),
      host: STORAGE_HOST,
      port: STORAGE_PORT,
    },
  });

  await testEnv.clearFirestore();
  await clearStorage(testEnv);
  await seed(testEnv);

  const storageFor = (uid, verified = true) =>
    testEnv.authenticatedContext(uid, { email_verified: verified }).storage();
  const alice = storageFor(ALICE);
  const bob = storageFor(BOB);
  const mallory = storageFor(MALLORY);
  const newbie = storageFor(NEWBIE, false);
  const banned = storageFor(BANNED);
  const disabled = storageFor(DISABLED);
  const anon = testEnv.unauthenticatedContext().storage();

  // --- Direct messages: exact server reservation + participant-only reads. ---
  const directImagePath = `message_attachments/${ALICE}/${DIRECT_CONVERSATION}/${DIRECT_IMAGE_MESSAGE}.jpg`;
  await check("reserved direct image uploads with exact identity", async () => {
    await assertSucceeds(
      uploadBytes(
        ref(alice, directImagePath),
        smallImage,
        directMetadata(
          ALICE,
          DIRECT_CONVERSATION,
          DIRECT_IMAGE_MESSAGE,
          "image",
        ),
      ),
    );
    // Build 18 created the canonical message document but did not add the
    // server-owned finalization marker. Keep that historical shape denied
    // until the trusted migration has revoked its bearer token, re-probed the
    // exact generation and added the marker. Message existence alone is not a
    // safe substitute because it would reopen the publish/metadata race.
    await assertFails(getBytes(ref(alice, directImagePath)));
    await assertFails(getBytes(ref(bob, directImagePath)));
    const revoked = await revokeEmulatorDownloadToken(
      testEnv,
      directImagePath,
    );
    if (revoked.beforeStatus !== 200 || revoked.afterStatus === 200) {
      throw new Error(
        `durable token status did not change from 200: ` +
          `${revoked.beforeStatus} -> ${revoked.afterStatus}`,
      );
    }
    if (!revoked.tokenUrl.includes("token=")) {
      throw new Error("emulator did not issue a bearer-token download URL");
    }
  });
  await check(
    "only conversation participants can read private attachments",
    async () => {
      await assertSucceeds(getBytes(ref(alice, directImagePath)));
      await assertSucceeds(getBytes(ref(bob, directImagePath)));
      await assertFails(getBytes(ref(mallory, directImagePath)));
      await assertFails(getBytes(ref(anon, directImagePath)));
    },
  );
  await check(
    "disabled participants and deleted conversations lose direct reads",
    async () => {
      try {
        await testEnv.withSecurityRulesDisabled(async (ctx) => {
          await setDoc(
            doc(ctx.firestore(), `users/${BOB}`),
            { disabled: true },
            { merge: true },
          );
        });
        await assertFails(getBytes(ref(bob, directImagePath)));
      } finally {
        await testEnv.withSecurityRulesDisabled(async (ctx) => {
          await setDoc(
            doc(ctx.firestore(), `users/${BOB}`),
            { disabled: false },
            { merge: true },
          );
        });
      }

      try {
        await testEnv.withSecurityRulesDisabled(async (ctx) => {
          await deleteDoc(
            doc(ctx.firestore(), `conversations/${DIRECT_CONVERSATION}`),
          );
        });
        await assertFails(getBytes(ref(bob, directImagePath)));
      } finally {
        await testEnv.withSecurityRulesDisabled(async (ctx) => {
          await setDoc(
            doc(ctx.firestore(), `conversations/${DIRECT_CONVERSATION}`),
            { schemaVersion: 2, participantIds: [ALICE, BOB] },
          );
        });
      }
    },
  );
  await check(
    "direct attachments are point-readable only after finalization and never listable",
    async () => {
      const unfinalizedPath =
        `message_attachments/${ALICE}/${DIRECT_CONVERSATION}/` +
        `${DIRECT_CONTRACT_IMAGE}.jpg`;
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await uploadBytes(
          ref(ctx.storage(), unfinalizedPath),
          smallImage,
          directMetadata(
            ALICE,
            DIRECT_CONVERSATION,
            DIRECT_CONTRACT_IMAGE,
            "image",
          ),
        );
      });

      await assertSucceeds(getBytes(ref(bob, directImagePath)));
      await assertFails(getBytes(ref(bob, unfinalizedPath)));
      await assertFails(
        listAll(
          ref(
            bob,
            `message_attachments/${ALICE}/${DIRECT_CONVERSATION}`,
          ),
        ),
      );
      await assertFails(
        listAll(ref(alice, `message_attachments/${ALICE}`)),
      );
    },
  );
  await check(
    "direct attachment objects are immutable to clients",
    async () => {
      await assertFails(
        uploadBytes(
          ref(alice, directImagePath),
          smallImage,
          directMetadata(
            ALICE,
            DIRECT_CONVERSATION,
            DIRECT_IMAGE_MESSAGE,
            "image",
          ),
        ),
      );
      await assertFails(deleteObject(ref(alice, directImagePath)));
    },
  );
  await check("forged or missing direct reservations fail closed", async () => {
    const forgedMessage = `m_${"b".repeat(40)}`;
    await assertFails(
      uploadBytes(
        ref(
          alice,
          `message_attachments/${ALICE}/${DIRECT_CONVERSATION}/${forgedMessage}.jpg`,
        ),
        smallImage,
        directMetadata(ALICE, DIRECT_CONVERSATION, forgedMessage, "image"),
      ),
    );
    const wrongPathMessage = `m_${"c".repeat(40)}`;
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(
          ctx.firestore(),
          `directMessageUploadReservations/${wrongPathMessage}`,
        ),
        {
          schemaVersion: 1,
          ownerId: ALICE,
          conversationId: DIRECT_CONVERSATION,
          messageId: wrongPathMessage,
          recipientId: BOB,
          type: "image",
          contentType: "image/jpeg",
          durationSeconds: null,
          storagePath: "message_attachments/forged/path.jpg",
          status: "uploading",
          createdAt: new Date(),
          expiresAt: new Date(Date.now() + 10 * 60 * 1000),
        },
      );
    });
    await assertFails(
      uploadBytes(
        ref(
          alice,
          `message_attachments/${ALICE}/${DIRECT_CONVERSATION}/${wrongPathMessage}.jpg`,
        ),
        smallImage,
        directMetadata(ALICE, DIRECT_CONVERSATION, wrongPathMessage, "image"),
      ),
    );
  });
  await check(
    "direct image MIME, extension and byte bounds cannot be spoofed",
    async () => {
      const path = `message_attachments/${ALICE}/${DIRECT_CONVERSATION}/${DIRECT_CONTRACT_IMAGE}.jpg`;
      await assertFails(
        uploadBytes(
          ref(alice, path),
          smallImage,
          directMetadata(
            ALICE,
            DIRECT_CONVERSATION,
            DIRECT_CONTRACT_IMAGE,
            "image",
            { yovoiceFinalized: "true" },
          ),
        ),
      );
      await assertFails(
        uploadBytes(ref(alice, path), smallImage, {
          ...directMetadata(
            ALICE,
            DIRECT_CONVERSATION,
            DIRECT_CONTRACT_IMAGE,
            "image",
          ),
          contentType: "image/png",
        }),
      );
      await assertFails(
        uploadBytes(
          ref(alice, path),
          oversizeAudio,
          directMetadata(
            ALICE,
            DIRECT_CONVERSATION,
            DIRECT_CONTRACT_IMAGE,
            "image",
          ),
        ),
      );
      await assertFails(
        uploadBytes(
          ref(alice, path),
          tooSmallImage,
          directMetadata(
            ALICE,
            DIRECT_CONVERSATION,
            DIRECT_CONTRACT_IMAGE,
            "image",
          ),
        ),
      );
    },
  );
  await check(
    "reserved direct voice media is private and enforces the 12 MB cap",
    async () => {
      const path = `message_attachments/${ALICE}/${DIRECT_CONVERSATION}/${DIRECT_VOICE_MESSAGE}.m4a`;
      await assertFails(
        uploadBytes(
          ref(alice, path),
          oversizeAudio,
          directMetadata(
            ALICE,
            DIRECT_CONVERSATION,
            DIRECT_VOICE_MESSAGE,
            "voice",
          ),
        ),
      );
      await assertSucceeds(
        uploadBytes(
          ref(alice, path),
          smallAudio,
          directMetadata(
            ALICE,
            DIRECT_CONVERSATION,
            DIRECT_VOICE_MESSAGE,
            "voice",
          ),
        ),
      );
      await assertFails(getBytes(ref(alice, path)));
      await assertFails(getBytes(ref(bob, path)));
      const revoked = await revokeEmulatorDownloadToken(testEnv, path);
      if (revoked.beforeStatus !== 200 || revoked.afterStatus === 200) {
        throw new Error(
          `legacy voice token status did not change from 200: ` +
            `${revoked.beforeStatus} -> ${revoked.afterStatus}`,
        );
      }
      await assertSucceeds(getBytes(ref(alice, path)));
      await assertSucceeds(getBytes(ref(bob, path)));
      await assertFails(getBytes(ref(mallory, path)));
    },
  );
  await check(
    "reserved direct video is private and binds MIME to its extension",
    async () => {
      const path = `message_attachments/${ALICE}/${DIRECT_CONVERSATION}/${DIRECT_VIDEO_MESSAGE}.mp4`;
      await assertFails(
        uploadBytes(ref(alice, path), smallVideo, {
          ...directMetadata(
            ALICE,
            DIRECT_CONVERSATION,
            DIRECT_VIDEO_MESSAGE,
            "video",
          ),
          contentType: "video/quicktime",
        }),
      );
      await assertSucceeds(
        uploadBytes(
          ref(alice, path),
          smallVideo,
          directMetadata(
            ALICE,
            DIRECT_CONVERSATION,
            DIRECT_VIDEO_MESSAGE,
            "video",
          ),
        ),
      );
      await revokeEmulatorDownloadToken(testEnv, path);
      await assertSucceeds(getBytes(ref(alice, path)));
      await assertSucceeds(getBytes(ref(bob, path)));
      await assertFails(getBytes(ref(mallory, path)));
    },
  );
  await check(
    "unverified and expired direct upload sessions fail closed",
    async () => {
      const unverifiedPath = `message_attachments/${NEWBIE}/${DIRECT_CONVERSATION}/${DIRECT_UNVERIFIED_MESSAGE}.m4a`;
      await assertFails(
        uploadBytes(
          ref(newbie, unverifiedPath),
          smallAudio,
          directMetadata(
            NEWBIE,
            DIRECT_CONVERSATION,
            DIRECT_UNVERIFIED_MESSAGE,
            "voice",
          ),
        ),
      );
      const expiredPath = `message_attachments/${ALICE}/${DIRECT_CONVERSATION}/${DIRECT_EXPIRED_MESSAGE}.m4a`;
      await assertFails(
        uploadBytes(
          ref(alice, expiredPath),
          smallAudio,
          directMetadata(
            ALICE,
            DIRECT_CONVERSATION,
            DIRECT_EXPIRED_MESSAGE,
            "voice",
          ),
        ),
      );
    },
  );

  // --- Reels: exact reservation-bound media, uploader recovery only. ---
  const reelImage = await seedReelReservation(testEnv, {
    reelId: REEL_IMAGE,
  });
  await check(
    "verified Reel author can upload and recover the exact reserved image",
    async () => {
      await assertSucceeds(
        uploadBytes(
          ref(alice, reelImage.mediaStoragePath),
          smallImage,
          reelMetadata(ALICE, REEL_IMAGE, "media", "image/jpeg"),
        ),
      );
      await assertSucceeds(getBytes(ref(alice, reelImage.mediaStoragePath)));
      await assertFails(getBytes(ref(bob, reelImage.mediaStoragePath)));
      await assertFails(getBytes(ref(anon, reelImage.mediaStoragePath)));
      await assertFails(listAll(ref(alice, `reels/${ALICE}/${REEL_IMAGE}`)));
      await assertFails(deleteObject(ref(alice, reelImage.mediaStoragePath)));
      await assertFails(
        uploadBytes(
          ref(alice, reelImage.mediaStoragePath),
          smallImage,
          reelMetadata(ALICE, REEL_IMAGE, "media", "image/jpeg"),
        ),
      );
    },
  );

  const reelVideo = await seedReelReservation(testEnv, {
    reelId: REEL_VIDEO,
    mediaKind: "video",
    mediaContentType: "video/mp4",
    mediaSize: smallVideo.length,
    mediaFileName: "media.mp4",
    hasBackingAudio: true,
    audioContentType: "audio/mp4",
    audioSize: smallAudio.length,
    audioFileName: "backing-audio.m4a",
  });
  await check(
    "Reel video and licensed backing audio bind type, path and metadata",
    async () => {
      await assertFails(
        uploadBytes(
          ref(alice, reelVideo.mediaStoragePath),
          smallVideo,
          reelMetadata(ALICE, REEL_VIDEO, "media", "video/quicktime"),
        ),
      );
      await assertFails(
        uploadBytes(
          ref(alice, reelVideo.mediaStoragePath),
          smallVideo,
          reelMetadata(BOB, REEL_VIDEO, "media", "video/mp4"),
        ),
      );
      await assertSucceeds(
        uploadBytes(
          ref(alice, reelVideo.mediaStoragePath),
          smallVideo,
          reelMetadata(ALICE, REEL_VIDEO, "media", "video/mp4"),
        ),
      );
      await assertSucceeds(
        uploadBytes(
          ref(alice, reelVideo.backingAudioStoragePath),
          smallAudio,
          reelMetadata(ALICE, REEL_VIDEO, "backingAudio", "audio/mp4"),
        ),
      );
    },
  );

  const expiredReel = await seedReelReservation(testEnv, {
    reelId: REEL_EXPIRED,
    expiresAt: new Date(Date.now() - 60 * 1000),
  });
  const unverifiedReel = await seedReelReservation(testEnv, {
    reelId: REEL_UNVERIFIED,
    ownerId: NEWBIE,
  });
  await check(
    "expired, unverified and forged Reel uploads fail closed",
    async () => {
      await assertFails(
        uploadBytes(
          ref(alice, expiredReel.mediaStoragePath),
          smallImage,
          reelMetadata(ALICE, REEL_EXPIRED, "media", "image/jpeg"),
        ),
      );
      await assertFails(
        uploadBytes(
          ref(newbie, unverifiedReel.mediaStoragePath),
          smallImage,
          reelMetadata(NEWBIE, REEL_UNVERIFIED, "media", "image/jpeg"),
        ),
      );
      await assertFails(
        uploadBytes(
          ref(alice, `reels/${ALICE}/missing-reel/media.jpg`),
          smallImage,
          reelMetadata(ALICE, "missing-reel", "media", "image/jpeg"),
        ),
      );
    },
  );

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(
      doc(ctx.firestore(), `reelUploadReservations/${REEL_IMAGE}`),
      { status: "published" },
      { merge: true },
    );
  });
  await check(
    "published Reel bytes are never exposed through direct Storage reads",
    async () => {
      await assertFails(getBytes(ref(alice, reelImage.mediaStoragePath)));
      await assertFails(getBytes(ref(bob, reelImage.mediaStoragePath)));
    },
  );

  // --- Profile: verified owner + exact live reservation, private/immutable. ---
  const profileUploadId = "1".repeat(32);
  const profilePath = await seedProfileMediaReservation(testEnv, {
    uploadId: profileUploadId,
  });
  await check(
    "verified active owner can upload an exactly reserved image",
    () =>
      assertSucceeds(
        uploadBytes(
          ref(alice, profilePath),
          smallImage,
          profileMetadata(ALICE, profileUploadId),
        ),
      ),
  );
  await check(
    "profile object is owner-readable only while reservation is live",
    async () => {
      await assertSucceeds(getBytes(ref(alice, profilePath)));
      await assertFails(getBytes(ref(bob, profilePath)));
      await assertFails(getBytes(ref(anon, profilePath)));
    },
  );
  await check(
    "profile object is immutable and cannot be client-deleted",
    async () => {
      await assertFails(
        uploadBytes(
          ref(alice, profilePath),
          smallImage,
          profileMetadata(ALICE, profileUploadId),
        ),
      );
      await assertFails(deleteObject(ref(alice, profilePath)));
    },
  );
  await check(
    "unreserved and malformed profile uploads fail closed",
    async () => {
      const missingId = "2".repeat(32);
      await assertFails(
        uploadBytes(
          ref(alice, `users/${ALICE}/profile/avatar_${missingId}.jpg`),
          smallImage,
          profileMetadata(ALICE, missingId),
        ),
      );

      const mismatchId = "3".repeat(32);
      const mismatchPath = await seedProfileMediaReservation(testEnv, {
        uploadId: mismatchId,
      });
      await assertFails(
        uploadBytes(
          ref(alice, mismatchPath),
          smallImage,
          profileMetadata(ALICE, mismatchId, "banner"),
        ),
      );
      await assertFails(
        uploadBytes(
          ref(alice, mismatchPath),
          smallImage,
          profileMetadata(ALICE, mismatchId, "avatar", "image/png"),
        ),
      );

      const wrongSizeId = "4".repeat(32);
      const wrongSizePath = await seedProfileMediaReservation(testEnv, {
        uploadId: wrongSizeId,
        size: smallImage.length + 1,
      });
      await assertFails(
        uploadBytes(
          ref(alice, wrongSizePath),
          smallImage,
          profileMetadata(ALICE, wrongSizeId),
        ),
      );
    },
  );
  await check(
    "profile image bounds and content type are reservation-bound",
    async () => {
      const tinyId = "5".repeat(32);
      const tinyPath = await seedProfileMediaReservation(testEnv, {
        uploadId: tinyId,
        size: tooSmallImage.length,
      });
      await assertFails(
        uploadBytes(
          ref(alice, tinyPath),
          tooSmallImage,
          profileMetadata(ALICE, tinyId),
        ),
      );

      const largeId = "6".repeat(32);
      const largePath = await seedProfileMediaReservation(testEnv, {
        uploadId: largeId,
        size: overProfileCap.length,
      });
      await assertFails(
        uploadBytes(
          ref(alice, largePath),
          overProfileCap,
          profileMetadata(ALICE, largeId),
        ),
      );

      const pdfId = "7".repeat(32);
      const pdfPath = await seedProfileMediaReservation(testEnv, {
        uploadId: pdfId,
        contentType: "application/pdf",
      });
      await assertFails(
        uploadBytes(
          ref(alice, pdfPath),
          smallImage,
          profileMetadata(ALICE, pdfId, "avatar", "application/pdf"),
        ),
      );
    },
  );
  await check(
    "unverified, other, banned, disabled and anonymous profile uploads fail",
    async () => {
      for (const [ownerId, uploadId] of [
        [NEWBIE, "8".repeat(32)],
        [BANNED, "9".repeat(32)],
        [DISABLED, "a".repeat(32)],
      ]) {
        await seedProfileMediaReservation(testEnv, { ownerId, uploadId });
      }
      await assertFails(
        uploadBytes(
          ref(newbie, `users/${NEWBIE}/profile/avatar_${"8".repeat(32)}.jpg`),
          smallImage,
          profileMetadata(NEWBIE, "8".repeat(32)),
        ),
      );
      await assertFails(
        uploadBytes(
          ref(mallory, profilePath),
          smallImage,
          profileMetadata(ALICE, profileUploadId),
        ),
      );
      await assertFails(
        uploadBytes(
          ref(banned, `users/${BANNED}/profile/avatar_${"9".repeat(32)}.jpg`),
          smallImage,
          profileMetadata(BANNED, "9".repeat(32)),
        ),
      );
      await assertFails(
        uploadBytes(
          ref(
            disabled,
            `users/${DISABLED}/profile/avatar_${"a".repeat(32)}.jpg`,
          ),
          smallImage,
          profileMetadata(DISABLED, "a".repeat(32)),
        ),
      );
      await assertFails(
        uploadBytes(
          ref(anon, profilePath),
          smallImage,
          profileMetadata(ALICE, profileUploadId),
        ),
      );
    },
  );
  await check("profile reads fail after reservation retirement", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await deleteDoc(
        doc(
          ctx.firestore(),
          `profileMediaUploadReservations/${ALICE}/uploads/${profileUploadId}`,
        ),
      );
    });
    await assertFails(getBytes(ref(alice, profilePath)));
  });

  // --- Room: existing active Room, canonical host and no overwrite. ---
  const roomReservationId = "1".repeat(40);
  const roomImage = `room_images/active-room/${ALICE}_${"a".repeat(32)}.jpg`;
  const roomJpeg = {
    contentType: "image/jpeg",
    customMetadata: {
      ownerId: ALICE,
      roomId: "active-room",
      reservationId: roomReservationId,
    },
  };
  await seedRoomCoverReservation(testEnv, {
    reservationId: roomReservationId,
    storagePath: roomImage,
  });
  await check("verified active host can create a Room cover", () =>
    assertSucceeds(uploadBytes(ref(alice, roomImage), smallImage, roomJpeg)),
  );
  await check("Room cover overwrite is rejected", () =>
    assertFails(uploadBytes(ref(alice, roomImage), smallImage, roomJpeg)),
  );
  await check(
    "Room cover get and prefix list are denied even to host and anonymous",
    async () => {
      await assertFails(getBytes(ref(alice, roomImage)));
      await assertFails(getBytes(ref(anon, roomImage)));
      await assertFails(listAll(ref(alice, "room_images/active-room")));
      await assertFails(listAll(ref(anon, "room_images/active-room")));
    },
  );
  await check("non-host cannot create or delete a Room cover", async () => {
    await assertFails(
      uploadBytes(
        ref(bob, `room_images/active-room/${BOB}_1.jpg`),
        smallImage,
        {
          contentType: "image/jpeg",
          customMetadata: {
            ownerId: BOB,
            roomId: "active-room",
            reservationId: "2".repeat(40),
          },
        },
      ),
    );
    await assertFails(deleteObject(ref(bob, roomImage)));
  });
  await check(
    "missing, suspended and deleting Rooms reject covers",
    async () => {
      await assertFails(
        uploadBytes(
          ref(alice, `room_images/missing-room/${ALICE}_1.jpg`),
          smallImage,
          {
            contentType: "image/jpeg",
            customMetadata: { ownerId: ALICE, roomId: "missing-room" },
          },
        ),
      );
      await assertFails(
        uploadBytes(
          ref(alice, `room_images/suspended-room/${ALICE}_1.jpg`),
          smallImage,
          {
            contentType: "image/jpeg",
            customMetadata: { ownerId: ALICE, roomId: "suspended-room" },
          },
        ),
      );
      await assertFails(
        uploadBytes(
          ref(alice, `room_images/deleting-room/${ALICE}_1.jpg`),
          smallImage,
          {
            contentType: "image/jpeg",
            customMetadata: { ownerId: ALICE, roomId: "deleting-room" },
          },
        ),
      );
    },
  );
  await check(
    "Room filename and MIME must match the current client format",
    async () => {
      await assertFails(
        uploadBytes(
          ref(alice, `room_images/active-room/${ALICE}_${"b".repeat(32)}.jpg`),
          smallImage,
          roomJpeg,
        ),
      );
      await assertFails(
        uploadBytes(
          ref(alice, `room_images/active-room/${ALICE}_${"c".repeat(32)}.png`),
          smallImage,
          roomJpeg,
        ),
      );
    },
  );
  await check(
    "Room cover custom metadata is exact and host-bound",
    async () => {
      await assertFails(
        uploadBytes(
          ref(alice, `room_images/active-room/${ALICE}_${"d".repeat(32)}.jpg`),
          smallImage,
          {
            contentType: "image/jpeg",
            customMetadata: {
              ownerId: BOB,
              roomId: "active-room",
              reservationId: roomReservationId,
            },
          },
        ),
      );
      await assertFails(
        uploadBytes(
          ref(alice, `room_images/active-room/${ALICE}_${"e".repeat(32)}.jpg`),
          smallImage,
          {
            contentType: "image/jpeg",
            customMetadata: {
              ownerId: ALICE,
              roomId: "active-room",
              reservationId: roomReservationId,
              firebaseStorageDownloadTokens: "attacker-token",
            },
          },
        ),
      );
    },
  );
  await check("unverified Room host is rejected", () =>
    assertFails(
      uploadBytes(
        ref(
          testEnv
            .authenticatedContext(ALICE, { email_verified: false })
            .storage(),
          `room_images/active-room/${ALICE}_${"f".repeat(32)}.jpg`,
        ),
        smallImage,
        roomJpeg,
      ),
    ),
  );
  const expiredReservationId = "3".repeat(40);
  const expiredRoomImage = `room_images/active-room/${ALICE}_${"3".repeat(32)}.jpg`;
  await seedRoomCoverReservation(testEnv, {
    reservationId: expiredReservationId,
    storagePath: expiredRoomImage,
    expiresAt: new Date(Date.now() - 1000),
  });
  await check("expired Room upload reservation is rejected", () =>
    assertFails(
      uploadBytes(ref(alice, expiredRoomImage), smallImage, {
        contentType: "image/jpeg",
        customMetadata: {
          ownerId: ALICE,
          roomId: "active-room",
          reservationId: expiredReservationId,
        },
      }),
    ),
  );
  await check(
    "Room reservation cannot authorize a second name or mismatched size",
    async () => {
      await assertFails(
        uploadBytes(
          ref(alice, `room_images/active-room/${ALICE}_${"9".repeat(32)}.jpg`),
          smallImage,
          roomJpeg,
        ),
      );
      const sizeReservationId = "4".repeat(40);
      const sizePath = `room_images/active-room/${ALICE}_${"4".repeat(32)}.jpg`;
      await seedRoomCoverReservation(testEnv, {
        reservationId: sizeReservationId,
        storagePath: sizePath,
        size: smallImage.length + 1,
      });
      await assertFails(
        uploadBytes(ref(alice, sizePath), smallImage, {
          contentType: "image/jpeg",
          customMetadata: {
            ownerId: ALICE,
            roomId: "active-room",
            reservationId: sizeReservationId,
          },
        }),
      );
    },
  );
  await check("active verified Room host can delete the cover", () =>
    assertSucceeds(deleteObject(ref(alice, roomImage))),
  );

  // --- Club: root-first bounded upload, live canonical authority. ---
  const preRootAvatar = `clubs/${ALICE}/new-club/avatar`;
  await check("pre-root Club media cannot create orphan objects", async () => {
    for (let attempt = 0; attempt < 12; attempt += 1) {
      await assertFails(
        uploadBytes(
          ref(alice, `clubs/${ALICE}/unreserved-${attempt}/avatar`),
          smallImage,
          jpeg,
        ),
      );
    }
    await assertFails(uploadBytes(ref(alice, preRootAvatar), smallImage, jpeg));
    await assertFails(deleteObject(ref(alice, preRootAvatar)));
  });
  await check(
    "pre-root upload is limited to own path and avatar/banner names",
    async () => {
      await assertFails(
        uploadBytes(
          ref(mallory, `clubs/${ALICE}/other-new-club/avatar`),
          smallImage,
          jpeg,
        ),
      );
      await assertFails(
        uploadBytes(
          ref(alice, `clubs/${ALICE}/other-new-club/random`),
          smallImage,
          jpeg,
        ),
      );
    },
  );

  const ownedAvatar = `clubs/${ALICE}/club-owned/avatar`;
  const transferredAvatar = `clubs/${ALICE}/transferred-club/avatar`;
  await check(
    "current owner can create and update canonical Club media",
    async () => {
      await assertSucceeds(
        uploadBytes(ref(alice, ownedAvatar), smallImage, jpeg),
      );
      await assertSucceeds(getBytes(ref(anon, ownedAvatar)));
      await assertSucceeds(
        uploadBytes(ref(alice, ownedAvatar), smallImage, png),
      );
    },
  );
  await check(
    "current admin can update and delete existing Club media",
    async () => {
      await assertSucceeds(
        uploadBytes(ref(bob, ownedAvatar), smallImage, webp),
      );
      await assertSucceeds(deleteObject(ref(bob, ownedAvatar)));
    },
  );
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await uploadBytes(ref(ctx.storage(), transferredAvatar), smallImage, jpeg);
  });
  await check(
    "former owner cannot take over media through their historical path",
    async () => {
      await assertFails(
        uploadBytes(ref(alice, transferredAvatar), smallImage, jpeg),
      );
      await assertFails(deleteObject(ref(alice, transferredAvatar)));
    },
  );
  await check(
    "canonical new owner can update/delete the historical object",
    async () => {
      await assertSucceeds(
        uploadBytes(ref(bob, transferredAvatar), smallImage, jpeg),
      );
      await assertSucceeds(deleteObject(ref(bob, transferredAvatar)));
    },
  );
  await check(
    "ordinary or banned Club members cannot manage media",
    async () => {
      await assertFails(
        uploadBytes(
          ref(mallory, `clubs/${ALICE}/club-owned/banner`),
          smallImage,
          jpeg,
        ),
      );
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), `clubs/club-owned/members/${BOB}`), {
          userId: BOB,
          role: "admin",
          banned: true,
        });
      });
      await assertFails(
        uploadBytes(
          ref(bob, `clubs/${ALICE}/club-owned/banner`),
          smallImage,
          jpeg,
        ),
      );
    },
  );
  await check("inactive Club rejects owner media", () =>
    assertFails(
      uploadBytes(
        ref(alice, `clubs/${ALICE}/suspended-club/avatar`),
        smallImage,
        jpeg,
      ),
    ),
  );
  await check(
    "Club media accepts only exact names, exact MIME and bounded image bytes",
    async () => {
      await assertFails(
        uploadBytes(
          ref(alice, `clubs/${ALICE}/club-owned/avatar.jpg`),
          smallImage,
          jpeg,
        ),
      );
      await assertFails(
        uploadBytes(
          ref(alice, `clubs/${ALICE}/club-owned/avatar`),
          smallImage,
          pdf,
        ),
      );
      await assertFails(
        uploadBytes(
          ref(alice, `clubs/${ALICE}/club-owned/avatar`),
          tooSmallImage,
          jpeg,
        ),
      );
    },
  );

  // The client build live in production uploads Club media as
  // `{kind}_{millisecondsSinceEpoch}.{ext}`; the build in this tree uploads
  // the deterministic `{kind}`. The deploy sequence has a window where both
  // are talking to the same ruleset, so both names have to be accepted —
  // with the same name/MIME pairing the profile path already enforces.
  await check(
    "new timestamped Club objects are rejected to bound object count",
    async () => {
      await assertFails(
        uploadBytes(
          ref(alice, `clubs/${ALICE}/club-owned/avatar_1755300000000.jpg`),
          smallImage,
          jpeg,
        ),
      );
      await assertFails(
        uploadBytes(
          ref(alice, `clubs/${ALICE}/club-owned/banner_1755300000001.png`),
          smallImage,
          png,
        ),
      );
      await assertFails(
        uploadBytes(
          ref(alice, `clubs/${ALICE}/club-owned/avatar_1755300000002.webp`),
          smallImage,
          webp,
        ),
      );
      await assertFails(
        uploadBytes(
          ref(alice, `clubs/${ALICE}/club-owned/banner_1755300000003.jpeg`),
          smallImage,
          jpeg,
        ),
      );
    },
  );
  await check("timestamped pre-root Club media is rejected", async () => {
    const preRootTimestamped = `clubs/${ALICE}/new-club-2/banner_1755300000004.jpg`;
    await assertFails(
      uploadBytes(ref(alice, preRootTimestamped), smallImage, jpeg),
    );
  });
  const familyAvatar = `clubs/${ALICE}/family_${ALICE}/avatar`;
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await uploadBytes(ref(ctx.storage(), familyAvatar), smallImage, jpeg);
  });
  await check(
    "Family media is private-by-absence for every client",
    async () => {
      for (const client of [anon, alice, bob, mallory]) {
        await assertFails(getBytes(ref(client, familyAvatar)));
      }
      await assertFails(
        uploadBytes(ref(alice, familyAvatar), smallImage, jpeg),
      );
      await assertFails(uploadBytes(ref(bob, familyAvatar), smallImage, jpeg));
      await assertFails(deleteObject(ref(alice, familyAvatar)));
    },
  );
  await check(
    "timestamped Club media keeps every other Club guarantee",
    async () => {
      // Not a Club manager.
      await assertFails(
        uploadBytes(
          ref(mallory, `clubs/${ALICE}/club-owned/avatar_1755300000005.jpg`),
          smallImage,
          jpeg,
        ),
      );
      // Extension must agree with the declared MIME, as on the profile path.
      await assertFails(
        uploadBytes(
          ref(alice, `clubs/${ALICE}/club-owned/avatar_1755300000006.jpg`),
          smallImage,
          png,
        ),
      );
      // Only avatar/banner, only image extensions, only a numeric suffix.
      await assertFails(
        uploadBytes(
          ref(alice, `clubs/${ALICE}/club-owned/logo_1755300000007.jpg`),
          smallImage,
          jpeg,
        ),
      );
      await assertFails(
        uploadBytes(
          ref(alice, `clubs/${ALICE}/club-owned/avatar_1755300000008.svg`),
          smallImage,
          jpeg,
        ),
      );
      await assertFails(
        uploadBytes(
          ref(alice, `clubs/${ALICE}/club-owned/avatar_notatimestamp.jpg`),
          smallImage,
          jpeg,
        ),
      );
      // The pattern must match the WHOLE name, not appear inside it —
      // otherwise any prefix or suffix rides in on a legitimate-looking core.
      await assertFails(
        uploadBytes(
          ref(
            alice,
            `clubs/${ALICE}/club-owned/not-an-avatar_1755300000011.jpg`,
          ),
          smallImage,
          jpeg,
        ),
      );
      await assertFails(
        uploadBytes(
          ref(alice, `clubs/${ALICE}/club-owned/avatar_1755300000012.jpg.html`),
          smallImage,
          jpeg,
        ),
      );
      // Size bounds are unchanged.
      await assertFails(
        uploadBytes(
          ref(alice, `clubs/${ALICE}/club-owned/avatar_1755300000009.jpg`),
          tooSmallImage,
          jpeg,
        ),
      );
      // A suspended Club still refuses media under either name.
      await assertFails(
        uploadBytes(
          ref(alice, `clubs/${ALICE}/suspended-club/avatar_1755300000010.jpg`),
          smallImage,
          jpeg,
        ),
      );
    },
  );

  // --- Main Voice Moment: existing unpublished exact draft, create-only. ---
  const momentPath = `voice_moments/${ALICE}/${MOMENT}.m4a`;
  await check(
    "verified active author can upload their exact unpublished draft",
    () =>
      assertSucceeds(
        uploadBytes(
          ref(alice, momentPath),
          smallAudio,
          momentMetadata(ALICE, MOMENT),
        ),
      ),
  );
  await check("Voice Moment overwrite is rejected", () =>
    assertFails(
      uploadBytes(
        ref(alice, momentPath),
        smallAudio,
        momentMetadata(ALICE, MOMENT),
      ),
    ),
  );
  await check("missing draft cannot allocate an orphan Voice Moment", () =>
    assertFails(
      uploadBytes(
        ref(alice, `voice_moments/${ALICE}/${COMMENT}.m4a`),
        smallAudio,
        momentMetadata(ALICE, COMMENT),
      ),
    ),
  );
  await check(
    "draft path, author and custom metadata must match exactly",
    async () => {
      await assertFails(
        uploadBytes(
          ref(bob, `voice_moments/${BOB}/${MOMENT}.m4a`),
          smallAudio,
          momentMetadata(BOB, MOMENT),
        ),
      );
      await assertFails(
        uploadBytes(
          ref(alice, `voice_moments/${ALICE}/${MOMENT}.m4a`),
          smallAudio,
          momentMetadata(ALICE, MOMENT, { extra: "x" }),
        ),
      );
    },
  );
  await check(
    "Voice Moment requires exact filename, audio MIME and size bounds",
    async () => {
      await assertFails(
        uploadBytes(
          ref(alice, `voice_moments/${ALICE}/${MOMENT}.wav`),
          smallAudio,
          momentMetadata(ALICE, MOMENT),
        ),
      );
      await assertFails(
        uploadBytes(
          ref(alice, `voice_moments/${ALICE}/${MOMENT}.m4a`),
          smallImage,
          { ...jpeg, customMetadata: { authorId: ALICE, momentId: MOMENT } },
        ),
      );
      await assertFails(
        uploadBytes(
          ref(alice, `voice_moments/${ALICE}/${MOMENT}.m4a`),
          tooSmallAudio,
          momentMetadata(ALICE, MOMENT),
        ),
      );
      await assertFails(
        uploadBytes(
          ref(alice, `voice_moments/${ALICE}/${MOMENT}.m4a`),
          oversizeAudio,
          momentMetadata(ALICE, MOMENT),
        ),
      );
    },
  );
  await check(
    "an unpublished Voice Moment object is private to its author",
    async () => {
      await assertSucceeds(getBytes(ref(alice, momentPath)));
      await assertFails(getBytes(ref(mallory, momentPath)));
      await assertFails(getBytes(ref(anon, momentPath)));
    },
  );
  await check(
    "clients cannot delete a canonical uploading Voice Moment draft",
    async () => {
      await assertFails(deleteObject(ref(mallory, momentPath)));
      await assertFails(deleteObject(ref(alice, momentPath)));
    },
  );
  await check(
    "published Voice Moment media denies every direct SDK read",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), `voiceMoments/${MOMENT}`),
          {
            isPublished: true,
            status: "published",
          },
          { merge: true },
        );
      });
      await assertFails(getBytes(ref(alice, momentPath)));
      await assertFails(getBytes(ref(mallory, momentPath)));
      await assertFails(getBytes(ref(anon, momentPath)));
    },
  );
  await check(
    "neither owner nor outsider can delete published Moment audio",
    async () => {
      await assertFails(deleteObject(ref(mallory, momentPath)));
      await assertFails(deleteObject(ref(alice, momentPath)));
    },
  );
  await check("expired Voice Moment media remains server-only", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `voiceMoments/${MOMENT}`),
        {
          isPublished: false,
          status: "expired",
        },
        { merge: true },
      );
    });
    await assertFails(getBytes(ref(alice, momentPath)));
    await assertFails(getBytes(ref(mallory, momentPath)));
    await assertFails(
      deleteObject(ref(alice, momentPath)),
      "expired media cleanup remains server authority",
    );
  });

  const legacyMixedPath = `voice_moments/${ALICE}/${LEGACY_MIXED_MOMENT}.m4a`;
  await check(
    "legacy mixed-case Moment IDs remain readable and client-delete-proof",
    async () => {
      // New reservations are generated as lowercase hex and creation stays
      // pinned to that canonical namespace.
      await assertFails(
        uploadBytes(
          ref(alice, legacyMixedPath),
          smallAudio,
          momentMetadata(ALICE, LEGACY_MIXED_MOMENT),
        ),
      );

      // Model an object produced by a legacy client before lowercase IDs
      // became canonical. Existing-object checks still bind its exact path,
      // metadata and Firestore root.
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await uploadBytes(
          ref(ctx.storage(), legacyMixedPath),
          smallAudio,
          momentMetadata(ALICE, LEGACY_MIXED_MOMENT),
        );
      });
      await assertSucceeds(getBytes(ref(alice, legacyMixedPath)));
      await assertFails(getBytes(ref(mallory, legacyMixedPath)));
      await assertFails(deleteObject(ref(mallory, legacyMixedPath)));
      await assertFails(deleteObject(ref(alice, legacyMixedPath)));
    },
  );
  await check(
    "mixed-case draft deletion rejects extra or mismatched author metadata",
    async () => {
      // Broadening the legacy ID alphabet must not broaden object identity:
      // an existing object with attacker-added custom metadata stays denied
      // for both reads and owner cleanup.
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await uploadBytes(
          ref(ctx.storage(), legacyMixedPath),
          smallAudio,
          momentMetadata(ALICE, LEGACY_MIXED_MOMENT, { extra: "forged" }),
        );
      });
      await assertFails(getBytes(ref(alice, legacyMixedPath)));
      await assertFails(deleteObject(ref(alice, legacyMixedPath)));
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await deleteObject(ref(ctx.storage(), legacyMixedPath));
        await uploadBytes(
          ref(ctx.storage(), legacyMixedPath),
          smallAudio,
          momentMetadata(BOB, LEGACY_MIXED_MOMENT),
        );
      });
      await assertFails(deleteObject(ref(alice, legacyMixedPath)));
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await deleteObject(ref(ctx.storage(), legacyMixedPath));
      });
    },
  );
  await check(
    "mixed-case draft deletion requires the exact canonical Firestore root",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await uploadBytes(
          ref(ctx.storage(), legacyMixedPath),
          smallAudio,
          momentMetadata(ALICE, LEGACY_MIXED_MOMENT),
        );
        await setDoc(
          doc(ctx.firestore(), `voiceMoments/${LEGACY_MIXED_MOMENT}`),
          {
            storagePath: `voice_moments/${ALICE}/different.m4a`,
          },
          { merge: true },
        );
      });
      await assertFails(deleteObject(ref(alice, legacyMixedPath)));

      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), `voiceMoments/${LEGACY_MIXED_MOMENT}`),
          {
            authorId: BOB,
            storagePath: legacyMixedPath,
          },
          { merge: true },
        );
      });
      await assertFails(deleteObject(ref(alice, legacyMixedPath)));

      // Even with `status: uploading`, a draft that already carries finalized
      // media state is not client-deletable.
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), `voiceMoments/${LEGACY_MIXED_MOMENT}`),
          {
            schemaVersion: 2,
            authorId: ALICE,
            audioUrl: "https://attacker.invalid/already-finalized.m4a",
            storagePath: legacyMixedPath,
            durationSeconds: 30,
            isPublished: false,
            isDeleted: false,
            status: "uploading",
            publishedAt: null,
            mediaGeneration: null,
            mediaSize: null,
            mediaContentType: null,
          },
          { merge: true },
        );
      });
      await assertFails(deleteObject(ref(alice, legacyMixedPath)));

      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await deleteObject(ref(ctx.storage(), legacyMixedPath));
        await setDoc(
          doc(ctx.firestore(), `voiceMoments/${LEGACY_MIXED_MOMENT}`),
          {
            authorId: ALICE,
            audioUrl: null,
            storagePath: legacyMixedPath,
          },
          { merge: true },
        );
      });
    },
  );
  await check(
    "published mixed-case legacy audio is direct-read denied and server-delete-only",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await uploadBytes(
          ref(ctx.storage(), legacyMixedPath),
          smallAudio,
          momentMetadata(ALICE, LEGACY_MIXED_MOMENT),
        );
        await setDoc(
          doc(ctx.firestore(), `voiceMoments/${LEGACY_MIXED_MOMENT}`),
          {
            isPublished: true,
            status: "published",
          },
          { merge: true },
        );
      });
      await assertFails(getBytes(ref(alice, legacyMixedPath)));
      await assertFails(getBytes(ref(mallory, legacyMixedPath)));
      await assertFails(getBytes(ref(anon, legacyMixedPath)));
      await assertFails(deleteObject(ref(mallory, legacyMixedPath)));
      await assertFails(deleteObject(ref(alice, legacyMixedPath)));

      // The Firestore root must name this exact object; an author-matching
      // published root cannot act as a read token for a different path.
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), `voiceMoments/${LEGACY_MIXED_MOMENT}`),
          {
            storagePath: `voice_moments/${ALICE}/different.m4a`,
          },
          { merge: true },
        );
      });
      await assertFails(getBytes(ref(alice, legacyMixedPath)));
      await assertFails(getBytes(ref(mallory, legacyMixedPath)));
    },
  );

  // --- Voice replies: exact server reservation + immutable published media. ---
  const replyPath = `voice_replies/${ALICE}/${PARENT}/${COMMENT}.m4a`;
  await check(
    "verified active author can upload an exactly reserved reply",
    () =>
      assertSucceeds(
        uploadBytes(
          ref(alice, replyPath),
          smallAudio,
          replyMetadata(ALICE, PARENT, COMMENT),
        ),
      ),
  );
  await check("reply overwrite is rejected", () =>
    assertFails(
      uploadBytes(
        ref(alice, replyPath),
        smallAudio,
        replyMetadata(ALICE, PARENT, COMMENT),
      ),
    ),
  );

  await check("clients cannot delete a still-reserved reply", async () => {
    await assertFails(deleteObject(ref(bob, replyPath)));
    await assertFails(deleteObject(ref(alice, replyPath)));
  });

  await check(
    "a finalized reply is direct-read denied and client-delete-proof",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(ctx.firestore(), `voiceMoments/${PARENT}/comments/${COMMENT}`),
          {
            schemaVersion: 2,
            type: "voice",
            authorId: ALICE,
            storagePath: replyPath,
          },
        );
        // finalizeVoiceCommentDraft removes this in the same transaction that
        // creates the comment.
        await deleteDoc(
          doc(ctx.firestore(), `voiceMomentUploadReservations/${COMMENT}`),
        );
      });
      await assertFails(getBytes(ref(alice, replyPath)));
      await assertFails(getBytes(ref(bob, replyPath)));
      await assertFails(getBytes(ref(anon, replyPath)));
      await assertFails(deleteObject(ref(alice, replyPath)));
      await assertFails(deleteObject(ref(bob, replyPath)));
    },
  );

  await check(
    "a missing reservation cannot be used as an orphan reply store",
    () =>
      assertFails(
        uploadBytes(
          ref(alice, `voice_replies/${ALICE}/${PARENT}/${REPLY_ORPHAN}.m4a`),
          smallAudio,
          replyMetadata(ALICE, PARENT, REPLY_ORPHAN),
        ),
      ),
  );

  const contractReplyPath = `voice_replies/${ALICE}/${PARENT}/${REPLY_CONTRACT}.m4a`;
  await check(
    "reply reservation identity and lifecycle are exact",
    async () => {
      const writeReservation = (overrides = {}) =>
        testEnv.withSecurityRulesDisabled((ctx) =>
          setDoc(
            doc(
              ctx.firestore(),
              `voiceMomentUploadReservations/${REPLY_CONTRACT}`,
            ),
            voiceReplyReservation(ALICE, PARENT, REPLY_CONTRACT, overrides),
          ),
        );
      const canonicalUpload = () =>
        uploadBytes(
          ref(alice, contractReplyPath),
          smallAudio,
          replyMetadata(ALICE, PARENT, REPLY_CONTRACT),
        );

      for (const overrides of [
        { schemaVersion: 2 },
        { kind: "forgedKind" },
        { status: "finalized" },
        { ownerId: BOB },
        { momentId: MOMENT },
        { commentId: COMMENT },
        { storagePath: `voice_replies/${ALICE}/${PARENT}/different.m4a` },
        { durationSeconds: 0 },
        { durationSeconds: 61 },
        { durationSeconds: "7" },
        { expiresAt: new Date(Date.now() - 60 * 1000) },
      ]) {
        await writeReservation(overrides);
        await assertFails(canonicalUpload());
      }

      await writeReservation();
      await assertFails(
        uploadBytes(
          ref(alice, contractReplyPath),
          smallAudio,
          replyMetadata(ALICE, PARENT, REPLY_CONTRACT, { extra: "forged" }),
        ),
      );
      await assertFails(
        uploadBytes(
          ref(alice, contractReplyPath),
          smallAudio,
          replyMetadata(BOB, PARENT, REPLY_CONTRACT),
        ),
      );
      await assertFails(
        uploadBytes(
          ref(alice, contractReplyPath),
          smallAudio,
          replyMetadata(ALICE, MOMENT, REPLY_CONTRACT),
        ),
      );
      await assertFails(
        uploadBytes(ref(alice, contractReplyPath), smallAudio, {
          ...pdf,
          customMetadata: replyMetadata(ALICE, PARENT, REPLY_CONTRACT)
            .customMetadata,
        }),
      );
      await assertFails(
        uploadBytes(
          ref(alice, contractReplyPath),
          tooSmallAudio,
          replyMetadata(ALICE, PARENT, REPLY_CONTRACT),
        ),
      );
      await assertSucceeds(
        uploadBytes(ref(alice, contractReplyPath), smallAudio, {
          ...legacyAudio,
          customMetadata: replyMetadata(ALICE, PARENT, REPLY_CONTRACT)
            .customMetadata,
        }),
      );
      await assertSucceeds(getBytes(ref(alice, contractReplyPath)));
      await assertFails(getBytes(ref(bob, contractReplyPath)));

      // Delete remains denied regardless of reservation or finalize state.
      await writeReservation({ ownerId: BOB });
      await assertFails(deleteObject(ref(alice, contractReplyPath)));
      await writeReservation({ storagePath: "voice_replies/wrong/path.m4a" });
      await assertFails(deleteObject(ref(alice, contractReplyPath)));
      await writeReservation();
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(
          doc(
            ctx.firestore(),
            `voiceMoments/${PARENT}/comments/${REPLY_CONTRACT}`,
          ),
          { type: "voice", authorId: ALICE, storagePath: contractReplyPath },
        );
      });
      await assertFails(deleteObject(ref(alice, contractReplyPath)));
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await deleteDoc(
          doc(
            ctx.firestore(),
            `voiceMoments/${PARENT}/comments/${REPLY_CONTRACT}`,
          ),
        );
      });
      await assertFails(deleteObject(ref(alice, contractReplyPath)));
    },
  );

  await check(
    "legacy mixed-case replies remain direct-read denied",
    async () => {
      const legacyPath = `voice_replies/${ALICE}/${PARENT}/${LEGACY_REPLY}.m4a`;
      const legacyM4aPath = `voice_replies/${ALICE}/${PARENT}/${LEGACY_REPLY_M4A}.m4a`;
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await uploadBytes(
          ref(ctx.storage(), legacyPath),
          smallAudio,
          replyMetadata(ALICE, PARENT, LEGACY_REPLY),
        );
        await uploadBytes(ref(ctx.storage(), legacyM4aPath), smallAudio, {
          ...legacyAudio,
          customMetadata: replyMetadata(ALICE, PARENT, LEGACY_REPLY_M4A)
            .customMetadata,
        });
        await setDoc(
          doc(ctx.firestore(), `voiceMomentUploadReservations/${LEGACY_REPLY}`),
          voiceReplyReservation(ALICE, PARENT, LEGACY_REPLY),
        );
        await setDoc(
          doc(
            ctx.firestore(),
            `voiceMomentUploadReservations/${LEGACY_REPLY_NEW}`,
          ),
          voiceReplyReservation(ALICE, PARENT, LEGACY_REPLY_NEW),
        );
      });
      await assertFails(getBytes(ref(alice, legacyPath)));
      await assertFails(getBytes(ref(bob, legacyPath)));
      await assertFails(getBytes(ref(alice, legacyM4aPath)));
      await assertFails(getBytes(ref(bob, legacyM4aPath)));
      await assertFails(getBytes(ref(anon, legacyPath)));
      await assertFails(deleteObject(ref(alice, legacyPath)));
      await assertFails(deleteObject(ref(alice, legacyM4aPath)));
      await assertFails(
        uploadBytes(
          ref(
            alice,
            `voice_replies/${ALICE}/${PARENT}/${LEGACY_REPLY_NEW}.m4a`,
          ),
          smallAudio,
          replyMetadata(ALICE, PARENT, LEGACY_REPLY_NEW),
        ),
      );
    },
  );

  await check("writes outside every matched path are rejected", () =>
    assertFails(
      uploadBytes(ref(alice, "random/whatever.jpg"), smallImage, jpeg),
    ),
  );

  console.log(`\n${passed} passed, ${failed} failed`);
  await testEnv.cleanup();
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
