// Storage security rules suite — the storage-side counterpart of
// rules.test.js. Runs against the Storage emulator; every check either
// proves an allowed operation succeeds or a forbidden one fails.
//
// Run (repo root):
//   firebase emulators:exec --only storage --project demo-yovoice \
//     'npm --prefix firestore-tests run test:storage'
const fs = require("fs");
const path = require("path");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
const { ref, uploadBytes, getBytes, deleteObject } = require("firebase/storage");

const RULES_PATH = path.resolve(__dirname, "../storage.rules");

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
const pdf = { contentType: "application/pdf" };
const audio = { contentType: "audio/m4a" };

const smallImage = new Uint8Array(64 * 1024); // 64 KB
const overProfileCap = new Uint8Array(2 * 1024 * 1024 + 1); // 2 MB + 1
const smallAudio = new Uint8Array(128 * 1024);

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: "rules-test-yovoice",
    storage: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      host: "127.0.0.1",
      port: 9199,
    },
  });

  await testEnv.clearStorage();

  // Mirrors rules.test.js: verified contexts stand in for normal users.
  const alice = testEnv
    .authenticatedContext("alice-uid", { email_verified: true })
    .storage();
  const mallory = testEnv
    .authenticatedContext("mallory-uid", { email_verified: true })
    .storage();
  const unverified = testEnv
    .authenticatedContext("newbie-uid", { email_verified: false })
    .storage();
  const anon = testEnv.unauthenticatedContext().storage();

  // --- users/{uid}/profile — avatar/banner uploads ---

  await check("owner can upload a small JPEG profile image", () =>
    assertSucceeds(
      uploadBytes(ref(alice, "users/alice-uid/profile/avatar_1.jpg"), smallImage, jpeg),
    ),
  );

  await check("unverified owner can still upload a profile image (onboarding)", () =>
    assertSucceeds(
      uploadBytes(ref(unverified, "users/newbie-uid/profile/avatar_1.jpg"), smallImage, jpeg),
    ),
  );

  await check("PNG profile image stays allowed (pre-crop clients)", () =>
    assertSucceeds(
      uploadBytes(ref(alice, "users/alice-uid/profile/avatar_2.png"), smallImage, png),
    ),
  );

  await check("profile image over the 2 MB cap is rejected", () =>
    assertFails(
      uploadBytes(ref(alice, "users/alice-uid/profile/huge.jpg"), overProfileCap, jpeg),
    ),
  );

  await check("non-image content type in profile is rejected", () =>
    assertFails(
      uploadBytes(ref(alice, "users/alice-uid/profile/doc.pdf"), smallImage, pdf),
    ),
  );

  await check("cannot upload into someone else's profile folder", () =>
    assertFails(
      uploadBytes(ref(mallory, "users/alice-uid/profile/takeover.jpg"), smallImage, jpeg),
    ),
  );

  await check("anonymous cannot upload a profile image", () =>
    assertFails(
      uploadBytes(ref(anon, "users/alice-uid/profile/anon.jpg"), smallImage, jpeg),
    ),
  );

  await check("profile images are publicly readable", () =>
    assertSucceeds(getBytes(ref(anon, "users/alice-uid/profile/avatar_1.jpg"))),
  );

  // --- room_images/{roomId} — uploader proven by filename prefix ---

  await check("verified user can upload a room image named with their uid", () =>
    assertSucceeds(
      uploadBytes(ref(alice, "room_images/room-1/alice-uid_1.jpg"), smallImage, jpeg),
    ),
  );

  await check("room image with someone else's uid prefix is rejected", () =>
    assertFails(
      uploadBytes(ref(mallory, "room_images/room-1/alice-uid_2.jpg"), smallImage, jpeg),
    ),
  );

  await check("unverified user cannot upload a room image", () =>
    assertFails(
      uploadBytes(ref(unverified, "room_images/room-1/newbie-uid_1.jpg"), smallImage, jpeg),
    ),
  );

  // --- clubs/{uid}/{clubId} — owner-keyed path ---

  await check("verified user can upload a club image under their own uid", () =>
    assertSucceeds(
      uploadBytes(ref(alice, "clubs/alice-uid/club-1/cover_1.jpg"), smallImage, jpeg),
    ),
  );

  await check("cannot upload a club image under another user's uid", () =>
    assertFails(
      uploadBytes(ref(mallory, "clubs/alice-uid/club-1/cover_2.jpg"), smallImage, jpeg),
    ),
  );

  // --- voice_moments / voice_replies — audio only, reads gated ---

  await check("verified owner can upload an audio voice moment", () =>
    assertSucceeds(
      uploadBytes(ref(alice, "voice_moments/alice-uid/m1.m4a"), smallAudio, audio),
    ),
  );

  await check("image content type in voice_moments is rejected", () =>
    assertFails(
      uploadBytes(ref(alice, "voice_moments/alice-uid/fake.jpg"), smallImage, jpeg),
    ),
  );

  await check("unverified user cannot upload a voice moment", () =>
    assertFails(
      uploadBytes(ref(unverified, "voice_moments/newbie-uid/m1.m4a"), smallAudio, audio),
    ),
  );

  await check("voice moments are NOT readable anonymously", () =>
    assertFails(getBytes(ref(anon, "voice_moments/alice-uid/m1.m4a"))),
  );

  await check("voice moments are readable by any signed-in user", () =>
    assertSucceeds(getBytes(ref(mallory, "voice_moments/alice-uid/m1.m4a"))),
  );

  await check("another user cannot delete someone's voice moment", () =>
    assertFails(deleteObject(ref(mallory, "voice_moments/alice-uid/m1.m4a"))),
  );

  await check("owner can delete their own voice moment", () =>
    assertSucceeds(deleteObject(ref(alice, "voice_moments/alice-uid/m1.m4a"))),
  );

  await check("verified owner can upload an audio voice reply", () =>
    assertSucceeds(
      uploadBytes(ref(alice, "voice_replies/alice-uid/moment-1/r1.m4a"), smallAudio, audio),
    ),
  );

  // --- default deny: no rule for arbitrary top-level paths ---

  await check("writes outside every matched path are rejected", () =>
    assertFails(uploadBytes(ref(alice, "random/whatever.jpg"), smallImage, jpeg)),
  );

  await testEnv.cleanup();

  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
