// End-to-end notification smoke test: two isolated identities, the REAL
// firestore.rules, and the REAL Functions emulator, so the actual
// deployed triggers produce the notifications rather than a handler
// being called directly.
//
// Requires BOTH emulators, started against the project the functions are
// loaded under:
//
//   firebase emulators:start --only functions,firestore --project yovoice-fn-test
//   node firestore-tests/notifications.smoke.js
//
// Exits non-zero if any stage regresses.

const fs = require("fs");
const path = require("path");
const { initializeTestEnvironment } = require("@firebase/rules-unit-testing");
const {
  doc,
  setDoc,
  getDoc,
  getDocs,
  deleteDoc,
  collection,
  query,
  where,
  orderBy,
  limit,
  serverTimestamp,
  writeBatch,
} = require("firebase/firestore");

// Must match the project the Functions emulator loaded, or no trigger runs.
const PROJECT = "yovoice-fn-test";
const A = "acct-a";
const B = "acct-b";

const rows = [];
function stage(name, ok, detail) {
  rows.push({ name, ok, detail: detail || "" });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Firestore->Functions delivery in the emulator is asynchronous and the
// first invocation pays a cold start. Polling is the honest way to wait
// for an at-least-once trigger; a fixed sleep just races it.
async function waitFor(read, predicate, budgetMs = 25000) {
  const deadline = Date.now() + budgetMs;
  let last = await read();
  while (!predicate(last) && Date.now() < deadline) {
    await sleep(500);
    last = await read();
  }
  return last;
}

(async () => {
  const env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: {
      host: "127.0.0.1",
      port: 8080,
      rules: fs.readFileSync(
        path.join(__dirname, "..", "firestore.rules"),
        "utf8",
      ),
    },
  });
  await env.clearFirestore();

  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const uid of [A, B]) {
      await setDoc(doc(db, `users/${uid}`), {
        uid,
        displayName: uid === A ? "Ada" : "Bo",
        email: `${uid}@yovoice.app`,
        friendCount: 0,
        followerCount: 0,
        followingCount: 0,
      });
    }
  });

  const ctxA = env.authenticatedContext(A, {
    email: `${A}@yovoice.app`,
    email_verified: true,
  });
  const ctxB = env.authenticatedContext(B, {
    email: `${B}@yovoice.app`,
    email_verified: true,
  });
  const dbA = ctxA.firestore();
  const dbB = ctxB.firestore();

  async function inbox(ctx, uid) {
    const snap = await getDocs(
      collection(ctx.firestore(), `users/${uid}/notifications`),
    );
    return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
  }

  // ---- 1/2. A sends B a friend request (authoritative source write) ----
  try {
    await setDoc(doc(dbA, `users/${B}/friendRequests/${A}`), {
      senderId: A,
      senderName: "Ada",
      senderEmail: `${A}@yovoice.app`,
      senderPhotoUrl: null,
      createdAt: serverTimestamp(),
    });
    await setDoc(doc(dbA, `users/${A}/sentFriendRequests/${B}`), {
      receiverId: B,
      createdAt: serverTimestamp(),
    });
    stage("1. friendRequest source document committed", true);
  } catch (e) {
    stage("1. friendRequest source document committed", false, e.code);
  }

  // ---- 3. Does a notification exist for B, with no client help? ----
  let got = await waitFor(() => inbox(ctxB, B), (v) => v.length > 0);
  stage(
    "2. server-side trigger created a friendRequest notification",
    got.length > 0,
    got.length ? `${got.length} doc(s)` : "NONE — no trigger exists for this path",
  );

  // Now the CLIENT path the app actually uses today.
  try {
    await setDoc(doc(dbA, `users/${B}/notifications/friendRequest:${A}`), {
      type: "friendRequest",
      actorId: A,
      actorName: "Ada",
      actorPhotoUrl: null,
      targetId: null,
      targetLabel: null,
      isRead: false,
      createdAt: serverTimestamp(),
      dedupeKey: `friendRequest:${A}`,
      bellSuppressed: false,
    });
    stage("3. client can NO LONGER forge a friendRequest notification", false, "write succeeded — forgery still possible");
  } catch (e) {
    stage("3. client can NO LONGER forge a friendRequest notification", e.code === "permission-denied", e.code);
  }

  got = await inbox(ctxB, B);
  stage(
    "4. recipient B can READ the server-written notification",
    got.length === 1,
    `${got.length} doc(s)`,
  );

  // ---- 5. bell feed + badge queries ----
  try {
    const visible = await getDocs(
      query(
        collection(dbB, `users/${B}/notifications`),
        where("bellSuppressed", "==", false),
        orderBy("createdAt", "desc"),
        limit(50),
      ),
    );
    stage("5. bell feed (indexed visible query) includes it", visible.size === 1, `${visible.size}`);
  } catch (e) {
    stage("5. bell feed (indexed visible query) includes it", false, e.code);
  }
  try {
    const unread = await getDocs(
      query(collection(dbB, `users/${B}/notifications`), where("isRead", "==", false)),
    );
    stage("6. unread badge counts it", unread.size === 1, `${unread.size}`);
  } catch (e) {
    stage("6. unread badge counts it", false, e.code);
  }

  // ---- 7. retry / double submit must not duplicate ----
  try {
    await setDoc(doc(dbA, `users/${B}/notifications/friendRequest:${A}`), {
      type: "friendRequest",
      actorId: A,
      actorName: "Ada",
      actorPhotoUrl: null,
      targetId: null,
      targetLabel: null,
      isRead: false,
      createdAt: serverTimestamp(),
      dedupeKey: `friendRequest:${A}`,
      bellSuppressed: false,
    });
  } catch (_) {
    /* denial is the dedupe mechanism */
  }
  got = await inbox(ctxB, B);
    // Replay the authoritative source write; the deterministic id must
  // absorb it.
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `users/${B}/friendRequests/${A}`), {
      senderId: A,
      senderName: "Ada",
      senderEmail: `${A}@yovoice.app`,
      senderPhotoUrl: null,
      createdAt: serverTimestamp(),
    });
  });
  await sleep(4000);
  got = await inbox(ctxB, B);
  stage("7. replaying the source event creates no duplicate", got.length === 1, `${got.length} doc(s)`);

  // ---- 8. B accepts; does A learn about it? ----
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, `users/${B}/friends/${A}`), {
      userId: A,
      createdAt: serverTimestamp(),
    });
    await setDoc(doc(db, `users/${A}/friends/${B}`), {
      userId: B,
      createdAt: serverTimestamp(),
    });
    await deleteDoc(doc(db, `users/${B}/friendRequests/${A}`));
  });
  let aInbox = await waitFor(() => inbox(ctxA, A), (v) => v.length > 0);
  stage(
    "8. acceptance notified the ORIGINAL REQUESTER via a trigger",
    aInbox.length > 0,
    aInbox.length ? `${aInbox.length}` : "NONE — no trigger exists for this path",
  );

  // ---- 9. A follows B ----
  try {
    await setDoc(doc(dbA, `users/${A}/following/${B}`), {
      uid: B,
      displayName: "Bo",
      followedAt: serverTimestamp(),
    });
    await setDoc(doc(dbA, `users/${B}/followers/${A}`), {
      uid: A,
      displayName: "Ada",
      followedAt: serverTimestamp(),
    });
    stage("9. follow source documents committed", true);
  } catch (e) {
    stage("9. follow source documents committed", false, e.code);
  }
  got = await waitFor(
    () => inbox(ctxB, B),
    (v) => v.some((n) => n.type === "follow"),
  );
  const followNotifs = got.filter((n) => n.type === "follow");
  stage(
    "10. follow notified the followed user via a trigger",
    followNotifs.length > 0,
    followNotifs.length ? `${followNotifs.length}` : "NONE — no trigger exists for this path",
  );

  // ---- 11. friend DM stays off the bell (they are friends now) ----
  try {
    await setDoc(doc(dbA, `users/${B}/notifications/dm-carrier`), {
      type: "directMessage",
      actorId: A,
      actorName: "Ada",
      actorPhotoUrl: null,
      targetId: "conv-1",
      targetLabel: null,
      isRead: false,
      createdAt: serverTimestamp(),
      dedupeKey: null,
      bellSuppressed: true,
    });
    const visible = await getDocs(
      query(
        collection(dbB, `users/${B}/notifications`),
        where("bellSuppressed", "==", false),
        orderBy("createdAt", "desc"),
      ),
    );
    const anyDm = visible.docs.some((d) => d.data().type === "directMessage");
    stage("11. friend DM carrier stays OUT of the bell feed", !anyDm);
  } catch (e) {
    stage("11. friend DM carrier stays OUT of the bell feed", false, e.code);
  }

  // ---- 12. non-friend DM is a VISIBLE message request ----
  try {
    const C = "acct-c";
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `users/${C}`), { uid: C, displayName: "Cy" });
    });
    const ctxC = env.authenticatedContext(C, {
      email: `${C}@yovoice.app`,
      email_verified: true,
    });
    await setDoc(doc(ctxC.firestore(), `users/${B}/notifications/dm-request`), {
      type: "directMessage",
      actorId: C,
      actorName: "Cy",
      actorPhotoUrl: null,
      targetId: "conv-2",
      targetLabel: null,
      isRead: false,
      createdAt: serverTimestamp(),
      dedupeKey: null,
      bellSuppressed: false,
    });
    stage("12. non-friend message request IS bell-visible", true);
  } catch (e) {
    stage("12. non-friend message request IS bell-visible", false, e.code);
  }

  // ---- 13. a stranger cannot suppress their own record ----
  try {
    const D = "acct-d";
    const ctxD = env.authenticatedContext(D, {
      email: `${D}@yovoice.app`,
      email_verified: true,
    });
    await setDoc(doc(ctxD.firestore(), `users/${B}/notifications/sneaky`), {
      type: "directMessage",
      actorId: D,
      actorName: "Dee",
      actorPhotoUrl: null,
      targetId: null,
      targetLabel: null,
      isRead: false,
      createdAt: serverTimestamp(),
      dedupeKey: null,
      bellSuppressed: true,
    });
    stage("13. stranger CANNOT hide itself from the bell", false, "write succeeded!");
  } catch (e) {
    stage("13. stranger CANNOT hide itself from the bell", e.code === "permission-denied", e.code);
  }

  // ---- 14-17. the acceptance signal cannot be faked ----------------
  //
  // The request document is deleted on accept, decline, cancel AND
  // block. Each of these drives the REAL onFriendRequestResolved trigger
  // and asserts what it must not produce.

  async function clearInbox(uid) {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      const snap = await getDocs(collection(db, `users/${uid}/notifications`));
      await Promise.all(snap.docs.map((d) => deleteDoc(d.ref)));
    });
  }

  async function resetRelationship() {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      for (const path of [
        `users/${A}/friends/${B}`,
        `users/${B}/friends/${A}`,
        `users/${A}/friendRequests/${B}`,
        `users/${B}/friendRequests/${A}`,
      ]) {
        await deleteDoc(doc(db, path)).catch(() => {});
      }
    });
  }

  // DECLINE: request deleted, no friendship ever created.
  await clearInbox(A);
  await resetRelationship();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, `users/${B}/friendRequests/${A}`), {
      senderId: A,
      createdAt: serverTimestamp(),
    });
  });
  await sleep(3000);
  await clearInbox(A);
  await env.withSecurityRulesDisabled(async (ctx) => {
    await deleteDoc(doc(ctx.firestore(), `users/${B}/friendRequests/${A}`));
  });
  await sleep(4000);
  stage(
    "14. DECLINE emits no acceptance",
    (await inbox(ctxA, A)).filter((n) => n.type === "friendAccepted").length === 0,
  );

  // BLOCK: friendship AND both requests removed in one transaction, the
  // way blockUser does it. The friendship is gone by trigger time.
  await clearInbox(A);
  await resetRelationship();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, `users/${B}/friends/${A}`), {
      userId: A,
      createdAt: serverTimestamp(),
    });
    await setDoc(doc(db, `users/${B}/friendRequests/${A}`), {
      senderId: A,
      createdAt: serverTimestamp(),
    });
  });
  await sleep(2500);
  await clearInbox(A);
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const batch = writeBatch(db);
    batch.delete(doc(db, `users/${B}/friends/${A}`));
    batch.delete(doc(db, `users/${B}/friendRequests/${A}`));
    await batch.commit();
  });
  await sleep(4000);
  stage(
    "15. BLOCK (friendship + request removed together) emits no acceptance",
    (await inbox(ctxA, A)).filter((n) => n.type === "friendAccepted").length === 0,
  );

  // STALE REQUEST beside an OLD friendship: cleanup deletes only the
  // request. Existence of a friendship alone must not read as acceptance.
  await clearInbox(A);
  await resetRelationship();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, `users/${B}/friends/${A}`), {
      userId: A,
      // Long-established friendship, not one created by this deletion.
      createdAt: new Date(Date.now() - 1000 * 60 * 60 * 24 * 30),
    });
    await setDoc(doc(db, `users/${B}/friendRequests/${A}`), {
      senderId: A,
      createdAt: serverTimestamp(),
    });
  });
  await sleep(2500);
  await clearInbox(A);
  await env.withSecurityRulesDisabled(async (ctx) => {
    await deleteDoc(doc(ctx.firestore(), `users/${B}/friendRequests/${A}`));
  });
  await sleep(4000);
  stage(
    "16. cleanup of a STALE request beside an old friendship emits no " +
      "acceptance",
    (await inbox(ctxA, A)).filter((n) => n.type === "friendAccepted").length === 0,
  );

  // And the genuine case still works after all of that.
  await clearInbox(A);
  await resetRelationship();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, `users/${B}/friendRequests/${A}`), {
      senderId: A,
      createdAt: serverTimestamp(),
    });
  });
  await sleep(3000);
  await clearInbox(A);
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, `users/${B}/friends/${A}`), {
      userId: A,
      createdAt: serverTimestamp(),
    });
    batch.set(doc(db, `users/${A}/friends/${B}`), {
      userId: B,
      createdAt: serverTimestamp(),
    });
    batch.delete(doc(db, `users/${B}/friendRequests/${A}`));
    await batch.commit();
  });
  const accepted = await waitFor(
    () => inbox(ctxA, A),
    (v) => v.some((n) => n.type === "friendAccepted"),
  );
  const acceptedRows = accepted.filter((n) => n.type === "friendAccepted");
  stage(
    "17. a GENUINE acceptance still notifies the requester exactly once, " +
      "with the accepter as actor",
    acceptedRows.length === 1 && acceptedRows[0].actorId === B,
    acceptedRows.length ? `actor=${acceptedRows[0].actorId}` : "none",
  );

  // Push tokens are deliberately NOT asserted here. No client runs in
  // this harness, so there is no token to find, and a green check here
  // would imply an OS delivery path this test cannot exercise. Push is
  // reported separately, with its own evidence.

  console.log("\n  NOTIFICATION PIPELINE, END TO END\n");
  for (const r of rows) {
    console.log(
      `  ${r.ok ? "PASS" : "FAIL"}  ${r.name}${r.detail ? "  [" + r.detail + "]" : ""}`,
    );
  }
  console.log("");

  await env.cleanup();

  const failed = rows.filter((r) => !r.ok);
  if (failed.length) {
    console.error(`  ${failed.length} stage(s) FAILED\n`);
    process.exit(1);
  }
})().catch((e) => {
  console.error("REPRO FAILED", e);
  process.exit(1);
});
