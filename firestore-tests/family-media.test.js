// Combined Firestore + Storage regressions for private Family Moment media.
//
// Run (repo root):
//   firebase emulators:exec --only firestore,storage --project demo-yovoice \
//     'npm --prefix firestore-tests run test:family-media'
//
// Family upload is not present in the shipping clients. Phase B therefore
// keeps member-only reads and fails closed on every client write until a
// server-issued upload-session document can bind the future object to a row.
const fs = require("fs");
const path = require("path");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
const { doc, setDoc, deleteDoc } = require("firebase/firestore");
const { ref, uploadBytes, getBytes, deleteObject } = require("firebase/storage");

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

const audio = { contentType: "audio/mp4" };
const smallAudio = new Uint8Array(128 * 1024);

const OWNER = "parent-uid";
const MEMBER = "sibling-uid";
const BANNED_MEMBER = "banned-member-uid";
const OUTSIDER = "outsider-uid";
const MISMATCH = "mismatch-uid";
const FAMILY = `family_${OWNER}`;
const OTHER_FAMILY = `family_${OUTSIDER}`;
const SUSPENDED_FAMILY = "family_suspended";
const DELETING_FAMILY = "family_deleting";
const NON_FAMILY = "community-with-member";
const OBJECT = `family_moments/${FAMILY}/${MEMBER}/moment.m4a`;

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
  await testEnv.clearStorage();

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, `clubs/${FAMILY}`), {
      name: "The Family",
      ownerId: OWNER,
      type: "family",
      status: "active",
      deletionInProgress: false,
    });
    await setDoc(doc(db, `clubs/${FAMILY}/members/${OWNER}`), {
      userId: OWNER,
      role: "owner",
      banned: false,
    });
    await setDoc(doc(db, `clubs/${FAMILY}/members/${MEMBER}`), {
      userId: MEMBER,
      role: "member",
      banned: false,
    });
    await setDoc(doc(db, `clubs/${FAMILY}/members/${BANNED_MEMBER}`), {
      userId: BANNED_MEMBER,
      role: "member",
      banned: true,
    });
    await setDoc(doc(db, `clubs/${FAMILY}/members/${MISMATCH}`), {
      userId: OUTSIDER,
      role: "member",
      banned: false,
    });

    await setDoc(doc(db, `clubs/${OTHER_FAMILY}`), {
      ownerId: OUTSIDER,
      type: "family",
      status: "active",
    });
    await setDoc(doc(db, `clubs/${OTHER_FAMILY}/members/${OUTSIDER}`), {
      userId: OUTSIDER,
      role: "owner",
      banned: false,
    });

    for (const [clubId, data] of [
      [SUSPENDED_FAMILY, { type: "family", status: "suspended" }],
      [DELETING_FAMILY, {
        type: "family",
        status: "active",
        deletionInProgress: true,
      }],
      [NON_FAMILY, { type: "community", status: "active" }],
    ]) {
      await setDoc(doc(db, `clubs/${clubId}`), {
        ownerId: OWNER,
        deletionInProgress: false,
        ...data,
      });
      await setDoc(doc(db, `clubs/${clubId}/members/${MEMBER}`), {
        userId: MEMBER,
        role: "member",
        banned: false,
      });
    }

    // Admin-only seed stands in for the future upload-session backend. Client
    // writes are intentionally closed in this phase.
    await uploadBytes(ref(ctx.storage(), OBJECT), smallAudio, audio);
    await uploadBytes(
      ref(ctx.storage(), `family_moments/${SUSPENDED_FAMILY}/${MEMBER}/moment.m4a`),
      smallAudio,
      audio,
    );
    await uploadBytes(
      ref(ctx.storage(), `family_moments/${DELETING_FAMILY}/${MEMBER}/moment.m4a`),
      smallAudio,
      audio,
    );
    await uploadBytes(
      ref(ctx.storage(), `family_moments/${NON_FAMILY}/${MEMBER}/moment.m4a`),
      smallAudio,
      audio,
    );
  });

  const storageFor = (uid, verified = true) =>
    testEnv.authenticatedContext(uid, { email_verified: verified }).storage();
  const owner = storageFor(OWNER);
  const member = storageFor(MEMBER);
  const bannedMember = storageFor(BANNED_MEMBER);
  const outsider = storageFor(OUTSIDER);
  const mismatch = storageFor(MISMATCH);
  const unverified = storageFor(MEMBER, false);
  const anon = testEnv.unauthenticatedContext().storage();

  const at = (storage, clubId, uid, file = "moment.m4a") =>
    ref(storage, `family_moments/${clubId}/${uid}/${file}`);

  await check("active family owner and member can read family media", async () => {
    await assertSucceeds(getBytes(ref(owner, OBJECT)));
    await assertSucceeds(getBytes(ref(member, OBJECT)));
  });

  await check("anonymous and non-member accounts cannot read family media", async () => {
    await assertFails(getBytes(ref(anon, OBJECT)));
    await assertFails(getBytes(ref(outsider, OBJECT)));
  });

  await check("banned membership closes family media immediately", () =>
    assertFails(getBytes(ref(bannedMember, OBJECT))),
  );

  await check("membership document id cannot impersonate another userId", () =>
    assertFails(getBytes(ref(mismatch, OBJECT))),
  );

  await check("suspended or deleting family is not readable", async () => {
    await assertFails(getBytes(at(member, SUSPENDED_FAMILY, MEMBER)));
    await assertFails(getBytes(at(member, DELETING_FAMILY, MEMBER)));
  });

  await check("a community membership cannot unlock the family media namespace", () =>
    assertFails(getBytes(at(member, NON_FAMILY, MEMBER))),
  );

  await check("all member/owner client creates fail closed", async () => {
    await assertFails(uploadBytes(
      at(member, FAMILY, MEMBER, "new.m4a"), smallAudio, audio,
    ));
    await assertFails(uploadBytes(
      at(owner, FAMILY, OWNER, "new.m4a"), smallAudio, audio,
    ));
    await assertFails(uploadBytes(
      at(unverified, FAMILY, MEMBER, "new.m4a"), smallAudio, audio,
    ));
  });

  await check("existing family objects cannot be overwritten by a client", () =>
    assertFails(uploadBytes(ref(member, OBJECT), smallAudio, audio)),
  );

  await check("existing family objects cannot be client-deleted", async () => {
    await assertFails(deleteObject(ref(member, OBJECT)));
    await assertFails(deleteObject(ref(owner, OBJECT)));
  });

  await check("membership in another family grants no cross-family write", () =>
    assertFails(uploadBytes(
      at(outsider, FAMILY, OUTSIDER, "cross.m4a"), smallAudio, audio,
    )),
  );

  await check("removing membership immediately closes existing media reads", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await deleteDoc(doc(ctx.firestore(), `clubs/${FAMILY}/members/${MEMBER}`));
    });
    await assertFails(getBytes(ref(member, OBJECT)));
  });

  console.log(`\n${passed} passed, ${failed} failed`);
  await testEnv.cleanup();
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
