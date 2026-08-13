// Combined Firestore + Storage rules suite for Family Moment audio.
//
// This is the ONLY suite that proves the cross-service gate: the
// `family_moments/{clubId}/{uid}/…` Storage path is authorised by a
// `firestore.exists()` lookup against the family room's member document.
// Storage rules alone cannot be trusted to enforce that — the lookup has
// to actually resolve — so both emulators must be running in the SAME
// hub for this to mean anything.
//
// Run (repo root), with both emulators up:
//   firebase emulators:start --only firestore,storage --project yovoice-ec54a
//   npm --prefix firestore-tests run test:family-media
//
// A green run here is the precondition for deploying storage.rules. If
// this cannot be made to pass reliably, the family_moments rule must NOT
// be deployed and Family Moments must stay disabled in the client.
const fs = require("fs");
const path = require("path");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
const { doc, setDoc, deleteDoc } = require("firebase/firestore");
const { ref, uploadBytes, getBytes } = require("firebase/storage");

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

const audio = { contentType: "audio/m4a" };
const image = { contentType: "image/jpeg" };
const smallAudio = new Uint8Array(128 * 1024);
const oversizeAudio = new Uint8Array(12 * 1024 * 1024 + 1);

const OWNER = "parent-uid";
const MEMBER = "sibling-uid";
const OUTSIDER = "outsider-uid";
const FAMILY = `family_${OWNER}`;
const OTHER_FAMILY = `family_${OUTSIDER}`;

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: "rules-test-yovoice",
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
  await testEnv.clearStorage();

  // Seed the family room and its roster with rules disabled — this suite
  // is about the Storage gate, not about how membership got written.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, `clubs/${FAMILY}`), {
      name: "The Family",
      ownerId: OWNER,
      type: "family",
      privacy: "inviteOnly",
    });
    await setDoc(doc(db, `clubs/${FAMILY}/members/${OWNER}`), {
      userId: OWNER,
      role: "owner",
    });
    await setDoc(doc(db, `clubs/${FAMILY}/members/${MEMBER}`), {
      userId: MEMBER,
      role: "member",
    });
    // A second family room the outsider owns, for the wrong-path case.
    await setDoc(doc(db, `clubs/${OTHER_FAMILY}`), {
      name: "Other Family",
      ownerId: OUTSIDER,
      type: "family",
    });
    await setDoc(doc(db, `clubs/${OTHER_FAMILY}/members/${OUTSIDER}`), {
      userId: OUTSIDER,
      role: "owner",
    });
  });

  const owner = testEnv
    .authenticatedContext(OWNER, { email_verified: true })
    .storage();
  const member = testEnv
    .authenticatedContext(MEMBER, { email_verified: true })
    .storage();
  const outsider = testEnv
    .authenticatedContext(OUTSIDER, { email_verified: true })
    .storage();
  const unverified = testEnv
    .authenticatedContext("newbie-uid", { email_verified: false })
    .storage();

  const at = (storage, clubId, uid, file = "moment.m4a") =>
    ref(storage, `family_moments/${clubId}/${uid}/${file}`);

  // 1. The gate resolves at all: an active member may upload.
  await check("an active family member can upload family moment audio", () =>
    assertSucceeds(uploadBytes(at(member, FAMILY, MEMBER), smallAudio, audio)),
  );

  await check("the owner can upload family moment audio", () =>
    assertSucceeds(uploadBytes(at(owner, FAMILY, OWNER), smallAudio, audio)),
  );

  // 2. Non-member.
  await check("a signed-in NON-member cannot upload into the family", () =>
    assertFails(
      uploadBytes(at(outsider, FAMILY, OUTSIDER), smallAudio, audio),
    ),
  );

  // 3. Read access is member-only — and this is the case that proves the
  // firestore lookup is really being consulted, not silently passing.
  await check("family media is readable by members", () =>
    assertSucceeds(getBytes(at(member, FAMILY, MEMBER))),
  );

  await check("family media is NOT readable by a non-member", () =>
    assertFails(getBytes(at(outsider, FAMILY, MEMBER))),
  );

  // 4. Wrong family room path.
  await check(
    "a member of one family cannot upload into a DIFFERENT family room",
    () =>
      assertFails(
        uploadBytes(at(member, OTHER_FAMILY, MEMBER), smallAudio, audio),
      ),
  );

  // 5. Ownership of the media segment.
  await check(
    "a member cannot write media under another member's uid segment",
    () =>
      assertFails(uploadBytes(at(member, FAMILY, OWNER), smallAudio, audio)),
  );

  // 6. Content type and size.
  await check("a non-audio content type is rejected", () =>
    assertFails(uploadBytes(at(member, FAMILY, MEMBER, "x.jpg"), smallAudio, image)),
  );

  await check("audio over the 12 MB cap is rejected", () =>
    assertFails(
      uploadBytes(at(member, FAMILY, MEMBER, "big.m4a"), oversizeAudio, audio),
    ),
  );

  await check("an unverified account cannot upload family media", () =>
    assertFails(
      uploadBytes(at(unverified, FAMILY, "newbie-uid"), smallAudio, audio),
    ),
  );

  // 7. Removal closes the door — the whole point of gating on the live
  // membership document rather than on a claim baked into the path.
  await check(
    "a REMOVED member can no longer upload or read family media",
    async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await deleteDoc(
          doc(ctx.firestore(), `clubs/${FAMILY}/members/${MEMBER}`),
        );
      });
      await assertFails(
        uploadBytes(at(member, FAMILY, MEMBER, "after.m4a"), smallAudio, audio),
      );
      await assertFails(getBytes(at(member, FAMILY, MEMBER)));
    },
  );

  // 8. Family media cannot be laundered into a public Moment path.
  await check(
    "family media cannot be written into the public voice_moments path "
      + "under another account, and public moment paths stay per-uid",
    async () => {
      await assertFails(
        uploadBytes(
          ref(owner, `voice_moments/${MEMBER}/laundered.m4a`),
          smallAudio,
          audio,
        ),
      );
      // A family room id is not a user id: it cannot stand in as one.
      await assertFails(
        uploadBytes(
          ref(owner, `voice_moments/${FAMILY}/laundered.m4a`),
          smallAudio,
          audio,
        ),
      );
    },
  );

  console.log(`\n${passed} passed, ${failed} failed`);
  await testEnv.cleanup();
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
