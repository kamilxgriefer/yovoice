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
const { doc, setDoc } = require("firebase/firestore");
const {
  ref, uploadBytes, getBytes, deleteObject, listAll,
} = require("firebase/storage");

const FIRESTORE_RULES = path.resolve(__dirname, "../firestore.rules");
const STORAGE_RULES = path.resolve(__dirname, "../storage.rules");

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
const tooSmallAudio = new Uint8Array(1000);
const oversizeAudio = new Uint8Array(12 * 1024 * 1024 + 1);

const ALICE = "alice-uid";
const BOB = "bob-uid";
const MALLORY = "mallory-uid";
const NEWBIE = "newbie-uid";
const BANNED = "banned-uid";
const DISABLED = "disabled-uid";
const MOMENT = "AbCdEfGhIjKlMnOpQrSt";
const PARENT = "ZyXwVuTsRqPoNmLkJiHg";
const COMMENT = "0123456789AbCdEfGhIj";
const DIRECT_CONVERSATION = "dm_storage_test";
const DIRECT_IMAGE_MESSAGE = `m_${"a".repeat(40)}`;
const DIRECT_CONTRACT_IMAGE = `m_${"d".repeat(40)}`;
const DIRECT_VOICE_MESSAGE = `m_${"e".repeat(40)}`;
const DIRECT_UNVERIFIED_MESSAGE = `m_${"f".repeat(40)}`;
const DIRECT_EXPIRED_MESSAGE = `m_${"0".repeat(40)}`;

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

function directMetadata(ownerId, conversationId, messageId, type, extra = {}) {
  return {
    contentType: type === "image" ? "image/jpeg" : "audio/mp4",
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
    await Promise.all((await objectsUnder(root)).map((item) => deleteObject(item)));

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

async function seed(testEnv) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const uid of [ALICE, BOB, MALLORY, NEWBIE]) {
      await setDoc(doc(db, `users/${uid}`), { uid, banned: false, disabled: false });
    }
    await setDoc(doc(db, `users/${BANNED}`), { uid: BANNED, banned: true });
    await setDoc(doc(db, `users/${DISABLED}`), { uid: DISABLED, disabled: true });

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
      authorId: ALICE,
      audioUrl: null,
      storagePath: `voice_moments/${ALICE}/${MOMENT}.m4a`,
      durationSeconds: 30,
      isPublished: false,
    });
    await setDoc(doc(db, `voiceMoments/${PARENT}`), {
      authorId: BOB,
      isPublished: true,
    });
    await setDoc(doc(db, "voiceMoments/UnpublishedParent01"), {
      authorId: BOB,
      isPublished: false,
    });
    await setDoc(doc(db, `conversations/${DIRECT_CONVERSATION}`), {
      schemaVersion: 2,
      participantIds: [ALICE, BOB],
    });
    await setDoc(doc(db, `directMessageUploadReservations/${DIRECT_IMAGE_MESSAGE}`), {
      schemaVersion: 1,
      ownerId: ALICE,
      conversationId: DIRECT_CONVERSATION,
      messageId: DIRECT_IMAGE_MESSAGE,
      recipientId: BOB,
      type: "image",
      contentType: "image/jpeg",
      durationSeconds: null,
      storagePath:
        `message_attachments/${ALICE}/${DIRECT_CONVERSATION}/${DIRECT_IMAGE_MESSAGE}.jpg`,
      status: "uploading",
      createdAt: new Date(),
      expiresAt: new Date(Date.now() + 10 * 60 * 1000),
    });
    await setDoc(doc(db, `directMessageUploadReservations/${DIRECT_CONTRACT_IMAGE}`), {
      schemaVersion: 1,
      ownerId: ALICE,
      conversationId: DIRECT_CONVERSATION,
      messageId: DIRECT_CONTRACT_IMAGE,
      recipientId: BOB,
      type: "image",
      contentType: "image/jpeg",
      durationSeconds: null,
      storagePath:
        `message_attachments/${ALICE}/${DIRECT_CONVERSATION}/${DIRECT_CONTRACT_IMAGE}.jpg`,
      status: "uploading",
      createdAt: new Date(),
      expiresAt: new Date(Date.now() + 10 * 60 * 1000),
    });
    await setDoc(doc(db, `directMessageUploadReservations/${DIRECT_VOICE_MESSAGE}`), {
      schemaVersion: 1,
      ownerId: ALICE,
      conversationId: DIRECT_CONVERSATION,
      messageId: DIRECT_VOICE_MESSAGE,
      recipientId: BOB,
      type: "voice",
      contentType: "audio/mp4",
      durationSeconds: 7,
      storagePath:
        `message_attachments/${ALICE}/${DIRECT_CONVERSATION}/${DIRECT_VOICE_MESSAGE}.m4a`,
      status: "uploading",
      createdAt: new Date(),
      expiresAt: new Date(Date.now() + 10 * 60 * 1000),
    });
    await setDoc(doc(db, `directMessageUploadReservations/${DIRECT_UNVERIFIED_MESSAGE}`), {
      schemaVersion: 1,
      ownerId: NEWBIE,
      conversationId: DIRECT_CONVERSATION,
      messageId: DIRECT_UNVERIFIED_MESSAGE,
      recipientId: BOB,
      type: "voice",
      contentType: "audio/mp4",
      durationSeconds: 7,
      storagePath:
        `message_attachments/${NEWBIE}/${DIRECT_CONVERSATION}/${DIRECT_UNVERIFIED_MESSAGE}.m4a`,
      status: "uploading",
      createdAt: new Date(),
      expiresAt: new Date(Date.now() + 10 * 60 * 1000),
    });
    await setDoc(doc(db, `directMessageUploadReservations/${DIRECT_EXPIRED_MESSAGE}`), {
      schemaVersion: 1,
      ownerId: ALICE,
      conversationId: DIRECT_CONVERSATION,
      messageId: DIRECT_EXPIRED_MESSAGE,
      recipientId: BOB,
      type: "voice",
      contentType: "audio/mp4",
      durationSeconds: 7,
      storagePath:
        `message_attachments/${ALICE}/${DIRECT_CONVERSATION}/${DIRECT_EXPIRED_MESSAGE}.m4a`,
      status: "uploading",
      createdAt: new Date(Date.now() - 20 * 60 * 1000),
      expiresAt: new Date(Date.now() - 10 * 60 * 1000),
    });
  });
}

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: "demo-yovoice",
    firestore: {
      rules: fs.readFileSync(FIRESTORE_RULES, "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
    storage: {
      rules: fs.readFileSync(STORAGE_RULES, "utf8"),
      host: "127.0.0.1",
      port: 9199,
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
  const directImagePath =
    `message_attachments/${ALICE}/${DIRECT_CONVERSATION}/${DIRECT_IMAGE_MESSAGE}.jpg`;
  await check("reserved direct image uploads with exact identity", () =>
    assertSucceeds(uploadBytes(
      ref(alice, directImagePath),
      smallImage,
      directMetadata(ALICE, DIRECT_CONVERSATION, DIRECT_IMAGE_MESSAGE, "image"),
    )),
  );
  await check("only conversation participants can read private attachments", async () => {
    await assertSucceeds(getBytes(ref(alice, directImagePath)));
    await assertSucceeds(getBytes(ref(bob, directImagePath)));
    await assertFails(getBytes(ref(mallory, directImagePath)));
    await assertFails(getBytes(ref(anon, directImagePath)));
  });
  await check("direct attachment objects are immutable to clients", async () => {
    await assertFails(uploadBytes(
      ref(alice, directImagePath),
      smallImage,
      directMetadata(ALICE, DIRECT_CONVERSATION, DIRECT_IMAGE_MESSAGE, "image"),
    ));
    await assertFails(deleteObject(ref(alice, directImagePath)));
  });
  await check("forged or missing direct reservations fail closed", async () => {
    const forgedMessage = `m_${"b".repeat(40)}`;
    await assertFails(uploadBytes(
      ref(alice,
        `message_attachments/${ALICE}/${DIRECT_CONVERSATION}/${forgedMessage}.jpg`),
      smallImage,
      directMetadata(ALICE, DIRECT_CONVERSATION, forgedMessage, "image"),
    ));
    const wrongPathMessage = `m_${"c".repeat(40)}`;
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(),
        `directMessageUploadReservations/${wrongPathMessage}`), {
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
      });
    });
    await assertFails(uploadBytes(
      ref(alice,
        `message_attachments/${ALICE}/${DIRECT_CONVERSATION}/${wrongPathMessage}.jpg`),
      smallImage,
      directMetadata(ALICE, DIRECT_CONVERSATION, wrongPathMessage, "image"),
    ));
  });
  await check("direct image MIME, extension and byte bounds cannot be spoofed", async () => {
    const path =
      `message_attachments/${ALICE}/${DIRECT_CONVERSATION}/${DIRECT_CONTRACT_IMAGE}.jpg`;
    await assertFails(uploadBytes(
      ref(alice, path),
      smallImage,
      {
        ...directMetadata(
          ALICE,
          DIRECT_CONVERSATION,
          DIRECT_CONTRACT_IMAGE,
          "image",
        ),
        contentType: "image/png",
      },
    ));
    await assertFails(uploadBytes(
      ref(alice, path),
      oversizeAudio,
      directMetadata(
        ALICE,
        DIRECT_CONVERSATION,
        DIRECT_CONTRACT_IMAGE,
        "image",
      ),
    ));
    await assertFails(uploadBytes(
      ref(alice, path),
      tooSmallImage,
      directMetadata(
        ALICE,
        DIRECT_CONVERSATION,
        DIRECT_CONTRACT_IMAGE,
        "image",
      ),
    ));
  });
  await check("reserved direct voice media is private and enforces the 12 MB cap", async () => {
    const path =
      `message_attachments/${ALICE}/${DIRECT_CONVERSATION}/${DIRECT_VOICE_MESSAGE}.m4a`;
    await assertFails(uploadBytes(
      ref(alice, path),
      oversizeAudio,
      directMetadata(
        ALICE,
        DIRECT_CONVERSATION,
        DIRECT_VOICE_MESSAGE,
        "voice",
      ),
    ));
    await assertSucceeds(uploadBytes(
      ref(alice, path),
      smallAudio,
      directMetadata(
        ALICE,
        DIRECT_CONVERSATION,
        DIRECT_VOICE_MESSAGE,
        "voice",
      ),
    ));
    await assertSucceeds(getBytes(ref(alice, path)));
    await assertSucceeds(getBytes(ref(bob, path)));
    await assertFails(getBytes(ref(mallory, path)));
  });
  await check("unverified and expired direct upload sessions fail closed", async () => {
    const unverifiedPath =
      `message_attachments/${NEWBIE}/${DIRECT_CONVERSATION}/${DIRECT_UNVERIFIED_MESSAGE}.m4a`;
    await assertFails(uploadBytes(
      ref(newbie, unverifiedPath),
      smallAudio,
      directMetadata(
        NEWBIE,
        DIRECT_CONVERSATION,
        DIRECT_UNVERIFIED_MESSAGE,
        "voice",
      ),
    ));
    const expiredPath =
      `message_attachments/${ALICE}/${DIRECT_CONVERSATION}/${DIRECT_EXPIRED_MESSAGE}.m4a`;
    await assertFails(uploadBytes(
      ref(alice, expiredPath),
      smallAudio,
      directMetadata(
        ALICE,
        DIRECT_CONVERSATION,
        DIRECT_EXPIRED_MESSAGE,
        "voice",
      ),
    ));
  });

  // --- Profile: active owner, exact name/MIME, append-only. ---
  await check("active owner can create a JPEG profile image", () =>
    assertSucceeds(uploadBytes(
      ref(alice, `users/${ALICE}/profile/avatar_1.jpg`), smallImage, jpeg,
    )),
  );
  await check("unverified active owner can upload during onboarding", () =>
    assertSucceeds(uploadBytes(
      ref(newbie, `users/${NEWBIE}/profile/banner_2.png`), smallImage, png,
    )),
  );
  await check("legacy WebP profile image remains compatible", () =>
    assertSucceeds(uploadBytes(
      ref(alice, `users/${ALICE}/profile/avatar_3.webp`), smallImage, webp,
    )),
  );
  await check("profile overwrite is rejected", () =>
    assertFails(uploadBytes(
      ref(alice, `users/${ALICE}/profile/avatar_1.jpg`), smallImage, jpeg,
    )),
  );
  await check("profile MIME/extension mismatch is rejected", () =>
    assertFails(uploadBytes(
      ref(alice, `users/${ALICE}/profile/avatar_4.png`), smallImage, jpeg,
    )),
  );
  await check("unknown profile filename is rejected", () =>
    assertFails(uploadBytes(
      ref(alice, `users/${ALICE}/profile/takeover.jpg`), smallImage, jpeg,
    )),
  );
  await check("too-small and oversized profile images are rejected", async () => {
    await assertFails(uploadBytes(
      ref(alice, `users/${ALICE}/profile/avatar_5.jpg`), tooSmallImage, jpeg,
    ));
    await assertFails(uploadBytes(
      ref(alice, `users/${ALICE}/profile/avatar_6.jpg`), overProfileCap, jpeg,
    ));
  });
  await check("non-image profile payload is rejected", () =>
    assertFails(uploadBytes(
      ref(alice, `users/${ALICE}/profile/avatar_7.jpg`), smallImage, pdf,
    )),
  );
  await check("other, banned, disabled and anonymous users cannot upload profile media", async () => {
    await assertFails(uploadBytes(
      ref(mallory, `users/${ALICE}/profile/avatar_8.jpg`), smallImage, jpeg,
    ));
    await assertFails(uploadBytes(
      ref(banned, `users/${BANNED}/profile/avatar_8.jpg`), smallImage, jpeg,
    ));
    await assertFails(uploadBytes(
      ref(disabled, `users/${DISABLED}/profile/avatar_8.jpg`), smallImage, jpeg,
    ));
    await assertFails(uploadBytes(
      ref(anon, `users/${ALICE}/profile/avatar_8.jpg`), smallImage, jpeg,
    ));
  });
  await check("profile images remain publicly readable", () =>
    assertSucceeds(getBytes(ref(alice, `users/${ALICE}/profile/avatar_1.jpg`))),
  );
  await check("active owner can delete their old profile object", () =>
    assertSucceeds(deleteObject(ref(alice, `users/${ALICE}/profile/avatar_3.webp`))),
  );

  // --- Room: existing active Room, canonical host and no overwrite. ---
  const roomImage = `room_images/active-room/${ALICE}_1.jpg`;
  await check("verified active host can create a Room cover", () =>
    assertSucceeds(uploadBytes(ref(alice, roomImage), smallImage, jpeg)),
  );
  await check("Room cover overwrite is rejected", () =>
    assertFails(uploadBytes(ref(alice, roomImage), smallImage, jpeg)),
  );
  await check("non-host cannot create or delete a Room cover", async () => {
    await assertFails(uploadBytes(
      ref(bob, `room_images/active-room/${BOB}_1.jpg`), smallImage, jpeg,
    ));
    await assertFails(deleteObject(ref(bob, roomImage)));
  });
  await check("missing, suspended and deleting Rooms reject covers", async () => {
    await assertFails(uploadBytes(
      ref(alice, `room_images/missing-room/${ALICE}_1.jpg`), smallImage, jpeg,
    ));
    await assertFails(uploadBytes(
      ref(alice, `room_images/suspended-room/${ALICE}_1.jpg`), smallImage, jpeg,
    ));
    await assertFails(uploadBytes(
      ref(alice, `room_images/deleting-room/${ALICE}_1.jpg`), smallImage, jpeg,
    ));
  });
  await check("Room filename and MIME must match the current client format", async () => {
    await assertFails(uploadBytes(
      ref(alice, `room_images/active-room/${ALICE}_x.jpg`), smallImage, jpeg,
    ));
    await assertFails(uploadBytes(
      ref(alice, `room_images/active-room/${ALICE}_2.png`), smallImage, jpeg,
    ));
  });
  await check("unverified Room host is rejected", () =>
    assertFails(uploadBytes(
      ref(testEnv.authenticatedContext(ALICE, { email_verified: false }).storage(),
        `room_images/active-room/${ALICE}_3.jpg`),
      smallImage,
      jpeg,
    )),
  );
  await check("active verified Room host can delete the cover", () =>
    assertSucceeds(deleteObject(ref(alice, roomImage))),
  );

  // --- Club: root-first bounded upload, live canonical authority. ---
  const preRootAvatar = `clubs/${ALICE}/new-club/avatar`;
  await check("pre-root Club media cannot create orphan objects", async () => {
    for (let attempt = 0; attempt < 12; attempt += 1) {
      await assertFails(uploadBytes(
        ref(alice, `clubs/${ALICE}/unreserved-${attempt}/avatar`),
        smallImage,
        jpeg,
      ));
    }
    await assertFails(uploadBytes(ref(alice, preRootAvatar), smallImage, jpeg));
    await assertFails(deleteObject(ref(alice, preRootAvatar)));
  });
  await check("pre-root upload is limited to own path and avatar/banner names", async () => {
    await assertFails(uploadBytes(
      ref(mallory, `clubs/${ALICE}/other-new-club/avatar`), smallImage, jpeg,
    ));
    await assertFails(uploadBytes(
      ref(alice, `clubs/${ALICE}/other-new-club/random`), smallImage, jpeg,
    ));
  });

  const ownedAvatar = `clubs/${ALICE}/club-owned/avatar`;
  const transferredAvatar = `clubs/${ALICE}/transferred-club/avatar`;
  await check("current owner can create and update canonical Club media", async () => {
    await assertSucceeds(uploadBytes(ref(alice, ownedAvatar), smallImage, jpeg));
    await assertSucceeds(getBytes(ref(anon, ownedAvatar)));
    await assertSucceeds(uploadBytes(ref(alice, ownedAvatar), smallImage, png));
  });
  await check("current admin can update and delete existing Club media", async () => {
    await assertSucceeds(uploadBytes(ref(bob, ownedAvatar), smallImage, webp));
    await assertSucceeds(deleteObject(ref(bob, ownedAvatar)));
  });
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await uploadBytes(ref(ctx.storage(), transferredAvatar), smallImage, jpeg);
  });
  await check("former owner cannot take over media through their historical path", async () => {
    await assertFails(uploadBytes(ref(alice, transferredAvatar), smallImage, jpeg));
    await assertFails(deleteObject(ref(alice, transferredAvatar)));
  });
  await check("canonical new owner can update/delete the historical object", async () => {
    await assertSucceeds(uploadBytes(ref(bob, transferredAvatar), smallImage, jpeg));
    await assertSucceeds(deleteObject(ref(bob, transferredAvatar)));
  });
  await check("ordinary or banned Club members cannot manage media", async () => {
    await assertFails(uploadBytes(
      ref(mallory, `clubs/${ALICE}/club-owned/banner`), smallImage, jpeg,
    ));
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `clubs/club-owned/members/${BOB}`), {
        userId: BOB,
        role: "admin",
        banned: true,
      });
    });
    await assertFails(uploadBytes(
      ref(bob, `clubs/${ALICE}/club-owned/banner`), smallImage, jpeg,
    ));
  });
  await check("inactive Club rejects owner media", () =>
    assertFails(uploadBytes(
      ref(alice, `clubs/${ALICE}/suspended-club/avatar`), smallImage, jpeg,
    )),
  );
  await check("Club media accepts only exact names, exact MIME and bounded image bytes", async () => {
    await assertFails(uploadBytes(
      ref(alice, `clubs/${ALICE}/club-owned/avatar.jpg`), smallImage, jpeg,
    ));
    await assertFails(uploadBytes(
      ref(alice, `clubs/${ALICE}/club-owned/avatar`), smallImage, pdf,
    ));
    await assertFails(uploadBytes(
      ref(alice, `clubs/${ALICE}/club-owned/avatar`), tooSmallImage, jpeg,
    ));
  });

  // The client build live in production uploads Club media as
  // `{kind}_{millisecondsSinceEpoch}.{ext}`; the build in this tree uploads
  // the deterministic `{kind}`. The deploy sequence has a window where both
  // are talking to the same ruleset, so both names have to be accepted —
  // with the same name/MIME pairing the profile path already enforces.
  await check("new timestamped Club objects are rejected to bound object count", async () => {
    await assertFails(uploadBytes(
      ref(alice, `clubs/${ALICE}/club-owned/avatar_1755300000000.jpg`),
      smallImage, jpeg,
    ));
    await assertFails(uploadBytes(
      ref(alice, `clubs/${ALICE}/club-owned/banner_1755300000001.png`),
      smallImage, png,
    ));
    await assertFails(uploadBytes(
      ref(alice, `clubs/${ALICE}/club-owned/avatar_1755300000002.webp`),
      smallImage, webp,
    ));
    await assertFails(uploadBytes(
      ref(alice, `clubs/${ALICE}/club-owned/banner_1755300000003.jpeg`),
      smallImage, jpeg,
    ));
  });
  await check("timestamped pre-root Club media is rejected", async () => {
    const preRootTimestamped = `clubs/${ALICE}/new-club-2/banner_1755300000004.jpg`;
    await assertFails(uploadBytes(ref(alice, preRootTimestamped), smallImage, jpeg));
  });
  const familyAvatar = `clubs/${ALICE}/family_${ALICE}/avatar`;
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await uploadBytes(ref(ctx.storage(), familyAvatar), smallImage, jpeg);
  });
  await check("Family media is private-by-absence for every client", async () => {
    for (const client of [anon, alice, bob, mallory]) {
      await assertFails(getBytes(ref(client, familyAvatar)));
    }
    await assertFails(uploadBytes(ref(alice, familyAvatar), smallImage, jpeg));
    await assertFails(uploadBytes(ref(bob, familyAvatar), smallImage, jpeg));
    await assertFails(deleteObject(ref(alice, familyAvatar)));
  });
  await check("timestamped Club media keeps every other Club guarantee", async () => {
    // Not a Club manager.
    await assertFails(uploadBytes(
      ref(mallory, `clubs/${ALICE}/club-owned/avatar_1755300000005.jpg`),
      smallImage, jpeg,
    ));
    // Extension must agree with the declared MIME, as on the profile path.
    await assertFails(uploadBytes(
      ref(alice, `clubs/${ALICE}/club-owned/avatar_1755300000006.jpg`),
      smallImage, png,
    ));
    // Only avatar/banner, only image extensions, only a numeric suffix.
    await assertFails(uploadBytes(
      ref(alice, `clubs/${ALICE}/club-owned/logo_1755300000007.jpg`),
      smallImage, jpeg,
    ));
    await assertFails(uploadBytes(
      ref(alice, `clubs/${ALICE}/club-owned/avatar_1755300000008.svg`),
      smallImage, jpeg,
    ));
    await assertFails(uploadBytes(
      ref(alice, `clubs/${ALICE}/club-owned/avatar_notatimestamp.jpg`),
      smallImage, jpeg,
    ));
    // The pattern must match the WHOLE name, not appear inside it —
    // otherwise any prefix or suffix rides in on a legitimate-looking core.
    await assertFails(uploadBytes(
      ref(alice, `clubs/${ALICE}/club-owned/not-an-avatar_1755300000011.jpg`),
      smallImage, jpeg,
    ));
    await assertFails(uploadBytes(
      ref(alice, `clubs/${ALICE}/club-owned/avatar_1755300000012.jpg.html`),
      smallImage, jpeg,
    ));
    // Size bounds are unchanged.
    await assertFails(uploadBytes(
      ref(alice, `clubs/${ALICE}/club-owned/avatar_1755300000009.jpg`),
      tooSmallImage, jpeg,
    ));
    // A suspended Club still refuses media under either name.
    await assertFails(uploadBytes(
      ref(alice, `clubs/${ALICE}/suspended-club/avatar_1755300000010.jpg`),
      smallImage, jpeg,
    ));
  });

  // --- Main Voice Moment: existing unpublished exact draft, create-only. ---
  const momentPath = `voice_moments/${ALICE}/${MOMENT}.m4a`;
  await check("verified active author can upload their exact unpublished draft", () =>
    assertSucceeds(uploadBytes(
      ref(alice, momentPath), smallAudio, momentMetadata(ALICE, MOMENT),
    )),
  );
  await check("Voice Moment overwrite is rejected", () =>
    assertFails(uploadBytes(
      ref(alice, momentPath), smallAudio, momentMetadata(ALICE, MOMENT),
    )),
  );
  await check("missing draft cannot allocate an orphan Voice Moment", () =>
    assertFails(uploadBytes(
      ref(alice, `voice_moments/${ALICE}/${COMMENT}.m4a`),
      smallAudio,
      momentMetadata(ALICE, COMMENT),
    )),
  );
  await check("draft path, author and custom metadata must match exactly", async () => {
    await assertFails(uploadBytes(
      ref(bob, `voice_moments/${BOB}/${MOMENT}.m4a`),
      smallAudio,
      momentMetadata(BOB, MOMENT),
    ));
    await assertFails(uploadBytes(
      ref(alice, `voice_moments/${ALICE}/${MOMENT}.m4a`),
      smallAudio,
      momentMetadata(ALICE, MOMENT, { extra: "x" }),
    ));
  });
  await check("Voice Moment requires exact filename, audio MIME and size bounds", async () => {
    await assertFails(uploadBytes(
      ref(alice, `voice_moments/${ALICE}/${MOMENT}.wav`),
      smallAudio,
      momentMetadata(ALICE, MOMENT),
    ));
    await assertFails(uploadBytes(
      ref(alice, `voice_moments/${ALICE}/${MOMENT}.m4a`),
      smallImage,
      { ...jpeg, customMetadata: { authorId: ALICE, momentId: MOMENT } },
    ));
    await assertFails(uploadBytes(
      ref(alice, `voice_moments/${ALICE}/${MOMENT}.m4a`),
      tooSmallAudio,
      momentMetadata(ALICE, MOMENT),
    ));
    await assertFails(uploadBytes(
      ref(alice, `voice_moments/${ALICE}/${MOMENT}.m4a`),
      oversizeAudio,
      momentMetadata(ALICE, MOMENT),
    ));
  });
  await check("signed-in users can read, anonymous users cannot read Voice Moments", async () => {
    await assertSucceeds(getBytes(ref(mallory, momentPath)));
    await assertFails(getBytes(ref(anon, momentPath)));
  });
  await check("only active author can delete a Voice Moment object", async () => {
    await assertFails(deleteObject(ref(mallory, momentPath)));
    await assertSucceeds(deleteObject(ref(alice, momentPath)));
  });

  // --- Voice replies: published parent + exact author/path/metadata. ---
  const replyPath = `voice_replies/${ALICE}/${PARENT}/${COMMENT}.m4a`;
  await check("verified active author can create a reply for a published parent", () =>
    assertSucceeds(uploadBytes(
      ref(alice, replyPath),
      smallAudio,
      replyMetadata(ALICE, PARENT, COMMENT),
    )),
  );
  await check("legacy exact M4A MIME remains compatible for replies", async () => {
    const second = "aBcDeFgHiJkLmNoPqRsT";
    await assertSucceeds(uploadBytes(
      ref(bob, `voice_replies/${BOB}/${PARENT}/${second}.m4a`),
      smallAudio,
      {
        ...legacyAudio,
        customMetadata: { authorId: BOB, momentId: PARENT, commentId: second },
      },
    ));
  });
  await check("reply overwrite is rejected", () =>
    assertFails(uploadBytes(
      ref(alice, replyPath),
      smallAudio,
      replyMetadata(ALICE, PARENT, COMMENT),
    )),
  );
  await check("unpublished or missing parent rejects reply allocation", async () => {
    const unpublished = "UnpublishedParent01";
    await assertFails(uploadBytes(
      ref(alice, `voice_replies/${ALICE}/${unpublished}/${COMMENT}.m4a`),
      smallAudio,
      replyMetadata(ALICE, unpublished, COMMENT),
    ));
    await assertFails(uploadBytes(
      ref(alice, `voice_replies/${ALICE}/MissingParentId00001/${COMMENT}.m4a`),
      smallAudio,
      replyMetadata(ALICE, "MissingParentId00001", COMMENT),
    ));
  });
  await check("reply filename and all metadata dimensions must match", async () => {
    await assertFails(uploadBytes(
      ref(alice, `voice_replies/${ALICE}/${PARENT}/short.m4a`),
      smallAudio,
      replyMetadata(ALICE, PARENT, "short"),
    ));
    await assertFails(uploadBytes(
      ref(alice, `voice_replies/${ALICE}/${PARENT}/${COMMENT}.m4a`),
      smallAudio,
      replyMetadata(BOB, PARENT, COMMENT),
    ));
    await assertFails(uploadBytes(
      ref(alice, `voice_replies/${ALICE}/${PARENT}/${COMMENT}.m4a`),
      smallAudio,
      replyMetadata(ALICE, PARENT, COMMENT, { extra: "x" }),
    ));
  });
  await check("only reply author can delete their reply object", async () => {
    await assertFails(deleteObject(ref(bob, replyPath)));
    await assertSucceeds(deleteObject(ref(alice, replyPath)));
  });

  await check("writes outside every matched path are rejected", () =>
    assertFails(uploadBytes(ref(alice, "random/whatever.jpg"), smallImage, jpeg)),
  );

  console.log(`\n${passed} passed, ${failed} failed`);
  await testEnv.cleanup();
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
