// ADVERSARIAL, READ-ONLY probes for the invite (ADR-178) and participation
// (ADR-181) slices. Written by the Adversarial Security Auditor; changes no
// tracked file and asserts only what the committed firestore.rules do. Novel
// angles the authors' own suites did not try: operator-variant roster
// enumeration (in / != / >=) against the raised-hand list rule, cross-server
// IDOR on the participant reads, and serverInviteRefs isolation.
// Run exactly like the committed Servers suite:
//   ./firestore-tests/node_modules/.bin/firebase emulators:exec --only firestore,storage \
//     --project demo-yovoice-server-acl 'node firestore-tests/server_followups_adversarial.test.js'
const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const { initializeTestEnvironment, assertFails, assertSucceeds } = require("@firebase/rules-unit-testing");
const {
  collection, collectionGroup, deleteDoc, doc, getDoc, getDocs, query,
  serverTimestamp, setDoc, updateDoc, where,
} = require("firebase/firestore");

const PROJECT = "demo-yovoice-server-acl";
const OWNER = "fa-owner";
const ADMIN = "fa-admin";
const MEMBER = "fa-member";       // session host (startedById), server role member
const LISTENER = "fa-listener";   // hand raised
const QUIET = "fa-quiet";         // hand NOT raised — the roster-enumeration bait
const OTHERMEMBER = "fa-other-member"; // member of a different server only
const ACTIVE = "fa-active";
const OTHER = "fa-other";
const SALON = "salon";
const ANCHOR = "fa-anchor";
const GEN = "fa-gen";
let passed = 0;
let failed = 0;
const leaks = [];

function endpoint(value, fallback) {
  const parts = (value || `127.0.0.1:${fallback}`).split(":");
  return { host: parts[0], port: Number(parts[1]) };
}
function server(id, changes = {}) {
  return { serverSchemaVersion: 1, serverType: "company", templateVersion: 1,
    serverActivationState: "active", revision: 1, status: "active", type: "community",
    ownerId: OWNER, privacy: "inviteOnly", name: id, description: "private",
    memberCount: 5, onlineCount: 0, defaultLanguage: "pl", ...changes };
}
function member(uid, role = "member", changes = {}) {
  return { userId: uid, role, displayName: uid, photoUrl: null,
    authorizationRevision: 1, joinedAt: new Date(0), isOnline: false, ...changes };
}
function participant(uid, role, changes = {}) {
  return { serverSchemaVersion: 1, serverId: ACTIVE, channelId: SALON, roomId: ANCHOR, sessionId: GEN,
    userId: uid, role, authorizationRevision: 1, hostMuted: false, serverMuted: false, isMuted: true,
    isHandRaised: false, handRaisedAt: null, displayName: uid, photoUrl: null,
    tokenAuthorityFingerprint: "f".repeat(64), joinedAt: new Date(0), updatedAt: new Date(0), ...changes };
}
const salon = (changes = {}) => ({ serverSchemaVersion: 1, serverId: ACTIVE, kind: "voice", type: "voice",
  name: "Salon", position: 0, isPrivate: false, accessMode: "members",
  accessPolicy: { accessMode: "members", roleIds: [], userIds: [] }, categoryId: null, status: "active",
  roomId: ANCHOR, activeSessionId: GEN, experience: "community", mediaMode: "audio",
  aclRevision: 1, revision: 1, liveness: { schemaVersion: 1, isLive: true, startedAt: new Date(0) }, ...changes });
const anchor = (changes = {}) => ({ serverSchemaVersion: 1, serverId: ACTIVE, clubId: ACTIVE, channelId: SALON,
  serverActivationState: "active", status: "active", visibility: "private", hostId: OWNER, serverOwnerId: OWNER,
  hostName: OWNER, name: "Salon", roomKind: "serverChannel", roomType: "community", experience: "community",
  mediaMode: "audio", isLive: true, voiceSessionId: GEN, livekitRoomName: "srv_live", participantCount: 0, ...changes });
const generation = (changes = {}) => ({ serverSchemaVersion: 1, serverId: ACTIVE, channelId: SALON, roomId: ANCHOR,
  sessionId: GEN, livekitRoomName: "srv_live", experience: "community", mediaMode: "audio", sourcePolicyVersion: 1,
  authorizationRevision: 1, status: "live", startedById: MEMBER, startedAt: new Date(0), endedAt: null,
  maxTokenExpiresAtMillis: 0, ...changes });

async function check(name, action) {
  try { await action(); passed++; console.log(`OK ${name}`); }
  catch (error) { failed++; console.error(`FAIL ${name}: ${error.message}`); }
}

async function main() {
  const env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: { ...endpoint(process.env.FIRESTORE_EMULATOR_HOST, 8085),
      rules: fs.readFileSync(path.join(__dirname, "../firestore.rules"), "utf8") },
  });
  const db = (uid) => env.authenticatedContext(uid, { email_verified: true }).firestore();
  const seed = (entries) => env.withSecurityRulesDisabled(async (ctx) => {
    for (const [loc, value] of Object.entries(entries)) {
      if (value === null) await deleteDoc(doc(ctx.firestore(), loc));
      else await setDoc(doc(ctx.firestore(), loc), value);
    }
  });
  const read = (uid, loc) => getDoc(doc(db(uid), loc));
  const own = (uid) => `rooms/${ANCHOR}/participants/${uid}`;
  const participants = (uid) => collection(db(uid), `rooms/${ANCHOR}/participants`);

  try {
    await env.clearFirestore();
    const fixtures = {};
    for (const uid of [OWNER, ADMIN, MEMBER, LISTENER, QUIET, OTHERMEMBER]) {
      fixtures[`users/${uid}`] = { displayName: uid, banned: false, disabled: false };
    }
    fixtures[`clubs/${ACTIVE}`] = server(ACTIVE);
    for (const [uid, role] of [[OWNER, "owner"], [ADMIN, "admin"], [MEMBER, "member"], [LISTENER, "member"], [QUIET, "member"]]) {
      fixtures[`clubs/${ACTIVE}/members/${uid}`] = member(uid, role);
    }
    fixtures[`clubs/${OTHER}`] = server(OTHER, { ownerId: "someone-else" });
    fixtures[`clubs/${OTHER}/members/${OTHERMEMBER}`] = member(OTHERMEMBER, "admin");
    fixtures[`clubs/${ACTIVE}/channels/${SALON}`] = salon();
    fixtures[`clubs/${ACTIVE}/channels/${SALON}/channelSessions/${GEN}`] = generation();
    fixtures[`rooms/${ANCHOR}`] = anchor();
    fixtures[own(MEMBER)] = participant(MEMBER, "host");
    fixtures[own(ADMIN)] = participant(ADMIN, "guest");
    fixtures[own(LISTENER)] = participant(LISTENER, "listener", { isHandRaised: true, handRaisedAt: new Date(1) });
    fixtures[own(QUIET)] = participant(QUIET, "listener", { isHandRaised: false });
    fixtures[`users/${MEMBER}/serverInviteRefs/${ACTIVE}`] = { serverId: ACTIVE, generation: 1, expiresAt: new Date(Date.now() + 86_400_000) };
    await seed(fixtures);

    // Crown jewel: can a non-`==` operator defeat the bare-equality roster
    // guard and return a participant whose hand is DOWN? A denial is safe; a
    // success is a leak only if it returns a hand-down document (QUIET).
    const enumAttempt = async (label, uid, filters) => {
      let snap;
      try {
        snap = await getDocs(query(participants(uid), ...filters));
      } catch { console.log(`OK ${label} (denied)`); passed++; return; }
      const ids = snap.docs.map((d) => d.id);
      const handDown = snap.docs.filter((d) => d.data().isHandRaised !== true).map((d) => d.id);
      if (handDown.length > 0) {
        failed++; leaks.push(`${label}: enumerated hand-DOWN participants ${JSON.stringify(handDown)}`);
        console.error(`FAIL ${label}: LEAK returned hand-down ${JSON.stringify(handDown)} (all: ${JSON.stringify(ids)})`);
      } else {
        passed++; console.log(`OK ${label} (allowed but only raised hands: ${JSON.stringify(ids)})`);
      }
    };
    const pins = [where("serverId", "==", ACTIVE), where("channelId", "==", SALON), where("sessionId", "==", GEN)];
    await enumAttempt("host cannot enumerate roster via isHandRaised in [true,false]", MEMBER, [...pins, where("isHandRaised", "in", [true, false])]);
    await enumAttempt("host cannot enumerate roster via isHandRaised != false", MEMBER, [...pins, where("isHandRaised", "!=", false)]);
    await enumAttempt("host cannot enumerate roster via isHandRaised >= false", MEMBER, [...pins, where("isHandRaised", ">=", false)]);
    await enumAttempt("host cannot enumerate roster via isHandRaised not-in [false]", MEMBER, [...pins, where("isHandRaised", "not-in", [false])]);
    await enumAttempt("owner cannot enumerate roster via isHandRaised in [true,false]", OWNER, [...pins, where("isHandRaised", "in", [true, false])]);

    await check("the exact four-equality raised-hand query returns only the raised hand for the host and moderate roles", async () => {
      for (const uid of [MEMBER, OWNER, ADMIN]) {
        const snap = await assertSucceeds(getDocs(query(participants(uid), ...pins, where("isHandRaised", "==", true))));
        assert.deepEqual(snap.docs.map((d) => d.id), [LISTENER], `queue for ${uid}`);
      }
    });
    await check("a plain member with a participant doc, not host and not moderate-capable, cannot list the queue", async () => {
      await assertFails(getDocs(query(participants(LISTENER), ...pins, where("isHandRaised", "==", true))));
      await assertFails(getDocs(query(participants(QUIET), ...pins, where("isHandRaised", "==", true))));
    });
    await check("cross-server: an admin of a DIFFERENT server cannot list the queue nor read any participant here", async () => {
      await assertFails(getDocs(query(participants(OTHERMEMBER), ...pins, where("isHandRaised", "==", true))));
      await assertFails(read(OTHERMEMBER, own(LISTENER)));
      await assertFails(read(OTHERMEMBER, own(OTHERMEMBER)));
    });
    await check("own-document IDOR: no participant reads another participant's document, in either direction", async () => {
      await assertFails(read(LISTENER, own(QUIET)));
      await assertFails(read(QUIET, own(LISTENER)));
      await assertFails(read(ADMIN, own(MEMBER)));
      await assertSucceeds(read(LISTENER, own(LISTENER)));
      await assertSucceeds(read(QUIET, own(QUIET)));
    });
    await check("cross-generation: reading your own doc bound to a superseded generation is denied once a new generation is live", async () => {
      await seed({ [`clubs/${ACTIVE}/channels/${SALON}/channelSessions/newgen`]: generation({ sessionId: "newgen", livekitRoomName: "srv_new", startedById: MEMBER }),
        [`clubs/${ACTIVE}/channels/${SALON}`]: salon({ activeSessionId: "newgen" }),
        [`rooms/${ANCHOR}`]: anchor({ voiceSessionId: "newgen", livekitRoomName: "srv_new" }) });
      // LISTENER's own document still names the old GEN; the anchor now names newgen.
      await assertFails(read(LISTENER, own(LISTENER)));
      await seed({ [`clubs/${ACTIVE}/channels/${SALON}`]: salon(), [`rooms/${ANCHOR}`]: anchor() });
      await assertSucceeds(read(LISTENER, own(LISTENER)));
    });
    await check("no client escalates by writing role, mutes or authorizationRevision on their own participant doc", async () => {
      const ref = doc(db(LISTENER), own(LISTENER));
      await assertFails(updateDoc(ref, { role: "guest" }));
      await assertFails(updateDoc(ref, { role: "host" }));
      await assertFails(updateDoc(ref, { hostMuted: false }));
      await assertFails(updateDoc(ref, { serverMuted: false }));
      await assertFails(updateDoc(ref, { authorizationRevision: 99 }));
      await assertFails(updateDoc(ref, { isHandRaised: true, updatedAt: serverTimestamp() }));
      await assertFails(deleteDoc(ref));
      const after = (await assertSucceeds(read(LISTENER, own(LISTENER)))).data();
      assert.equal(after.role, "listener");
      assert.equal(after.authorizationRevision, 1);
    });
    await check("serverInviteRefs is owner-only and never client-writable, across users", async () => {
      await assertSucceeds(read(MEMBER, `users/${MEMBER}/serverInviteRefs/${ACTIVE}`));
      await assertFails(read(OTHERMEMBER, `users/${MEMBER}/serverInviteRefs/${ACTIVE}`));
      await assertFails(read(OWNER, `users/${MEMBER}/serverInviteRefs/${ACTIVE}`));
      // A client cannot forge a pointer to grant itself a discoverable invite.
      await assertFails(setDoc(doc(db(OTHERMEMBER), `users/${OTHERMEMBER}/serverInviteRefs/${ACTIVE}`),
        { serverId: ACTIVE, generation: 1, expiresAt: new Date(Date.now() + 86_400_000) }));
      await assertFails(setDoc(doc(db(MEMBER), `users/${MEMBER}/serverInviteRefs/${OTHER}`),
        { serverId: OTHER, generation: 1, expiresAt: new Date(Date.now() + 86_400_000) }));
      await assertFails(updateDoc(doc(db(MEMBER), `users/${MEMBER}/serverInviteRefs/${ACTIVE}`), { generation: 9 }));
      await assertFails(getDocs(query(collectionGroup(db(MEMBER), "serverInviteRefs"), where("serverId", "==", ACTIVE))));
    });
  } finally { await env.cleanup(); }
  console.log(`\nServer followups adversarial: ${passed} passed, ${failed} failed.`);
  if (leaks.length) { console.error("LEAKS:\n" + leaks.join("\n")); }
  if (failed) process.exitCode = 1;
}
main();
