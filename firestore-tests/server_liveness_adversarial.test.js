// ADVERSARIAL, READ-ONLY PROBES against the committed firestore.rules for the
// ADR-A channel liveness projection. Written by the Adversarial Security
// Auditor; it changes no repository file and asserts only what the rules do.
// Run exactly like the committed Servers suite:
//   firebase emulators:exec --only firestore,storage \
//     --project demo-yovoice-server-acl 'node firestore-tests/server_liveness_adversarial.test.js'
const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const { initializeTestEnvironment, assertFails, assertSucceeds } = require("@firebase/rules-unit-testing");
const {
  FieldPath, arrayUnion, collection, collectionGroup, deleteDoc, deleteField, doc,
  getDoc, getDocs, increment, orderBy, query, serverTimestamp, setDoc, updateDoc,
  where, writeBatch,
} = require("firebase/firestore");

const PROJECT = "demo-yovoice-server-acl";
const OWNER = "server-owner";
const MEMBER = "server-member";
const ADMIN = "server-admin";
const OUTSIDER = "server-outsider";
const BANNED = "server-banned";
const HELD = "server-held";
const ACTIVE = "server-active";
let passed = 0;
let failed = 0;

function endpoint(value, fallback) {
  const parts = (value || `127.0.0.1:${fallback}`).split(":");
  return { host: parts[0], port: Number(parts[1]) };
}

function server(id, { held = false, ...changes } = {}) {
  return {
    serverSchemaVersion: 1, serverType: "company", templateVersion: 1,
    serverActivationState: held ? "held" : "active", revision: 1,
    status: held ? "preparing" : "active", type: "community", ownerId: OWNER,
    privacy: "inviteOnly", name: id, description: "private", memberCount: 3,
    onlineCount: 0, defaultLanguage: "pl", ...changes,
  };
}

function member(uid, role = "member", changes = {}) {
  return { userId: uid, role, displayName: uid, photoUrl: null,
    authorizationRevision: 1, joinedAt: new Date(0), isOnline: false, ...changes };
}

const idle = () => ({ schemaVersion: 1, isLive: false, startedAt: null });
const live = (startedAt = new Date(0)) => ({ schemaVersion: 1, isLive: true, startedAt });

function channel(serverId, restricted = false, changes = {}) {
  return {
    serverSchemaVersion: 1, serverId, kind: "text", type: "chat", revision: 1,
    aclRevision: 1, status: "active", name: restricted ? "HR private" : "General",
    position: restricted ? 1 : 0, roomId: null, activeSessionId: null,
    experience: null, mediaMode: null, isPrivate: restricted,
    accessMode: restricted ? "restricted" : "members",
    accessPolicy: { accessMode: restricted ? "restricted" : "members",
      roleIds: restricted ? ["owner"] : [], userIds: restricted ? [MEMBER] : [] },
    liveness: idle(), ...changes,
  };
}

function grant(serverId, channelId, uid = MEMBER, changes = {}) {
  return { schemaVersion: 1, serverId, channelId, userId: uid,
    aclRevision: 1, membershipRevision: 1,
    capabilities: { read: true, write: true, manage: uid === OWNER,
      moderate: uid === OWNER, joinVoice: false, startSession: false }, ...changes };
}

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
  const context = (uid) => env.authenticatedContext(uid, { email_verified: true });
  const db = (uid) => context(uid).firestore();
  const seed = (entries) => env.withSecurityRulesDisabled(async (ctx) => {
    for (const [location, value] of Object.entries(entries)) {
      if (value === null) await deleteDoc(doc(ctx.firestore(), location));
      else await setDoc(doc(ctx.firestore(), location), value);
    }
  });
  const read = (uid, location) => getDoc(doc(db(uid), location));
  const raw = async (location) => {
    let value;
    await env.withSecurityRulesDisabled(async (ctx) => {
      value = (await getDoc(doc(ctx.firestore(), location))).data() ?? null;
    });
    return value;
  };
  // The exact V1 member directory query the new composite index serves.
  const directory = (uid, sid) => getDocs(query(collection(db(uid), `clubs/${sid}/channels`),
    where("accessMode", "==", "members"), where("status", "==", "active"), orderBy("position")));

  try {
    await env.clearFirestore();
    const fixtures = {};
    for (const uid of [OWNER, MEMBER, ADMIN, OUTSIDER, BANNED]) {
      fixtures[`users/${uid}`] = { displayName: uid, banned: uid === BANNED, disabled: false };
    }
    for (const sid of [HELD, ACTIVE]) {
      fixtures[`clubs/${sid}`] = server(sid, { held: sid === HELD });
      for (const [uid, role] of [[OWNER, "owner"], [MEMBER, "member"], [ADMIN, "admin"], [BANNED, "member"]]) {
        fixtures[`clubs/${sid}/members/${uid}`] = member(uid, role);
      }
      fixtures[`clubs/${sid}/channels/general`] = channel(sid, false, { liveness: live() });
      fixtures[`clubs/${sid}/channels/hr`] = channel(sid, true, { liveness: live() });
      for (const uid of [OWNER, MEMBER]) {
        fixtures[`clubs/${sid}/channels/hr/accessGrants/${uid}`] = grant(sid, "hr", uid);
      }
    }
    fixtures["clubs/legacy-public"] = { type: "community", privacy: "public", status: "active",
      ownerId: OWNER, name: "Legacy", memberCount: 1, onlineCount: 0 };
    fixtures[`clubs/legacy-public/members/${OWNER}`] = member(OWNER, "owner");
    fixtures["clubs/legacy-public/channels/chat"] = { name: "Legacy chat", type: "chat", position: 0 };
    fixtures["clubs/legacy-public/channels/second"] = { name: "Second", type: "chat", position: 1 };
    await seed(fixtures);

    // 1. The committed suite proves the whole-map and one dotted write on a V1
    // channel (which has no client write path at all) and the whole-map write
    // on a legacy one. The untested case is the legacy channel that carries NO
    // map: a dotted or escaped path CREATES the key, and the guard reads the
    // POST-write document, so it must still refuse.
    await check("P0 probe: dotted, multi-segment and FieldPath liveness writes on a legacy channel with no map", async () => {
      const ref = doc(db(OWNER), "clubs/legacy-public/channels/chat");
      await assertSucceeds(updateDoc(ref, { name: "Control rename" })); // differential control
      await assertFails(updateDoc(ref, { "liveness.isLive": true }));
      await assertFails(updateDoc(ref, { "liveness.startedAt": new Date(0) }));
      await assertFails(updateDoc(ref, { "liveness.schemaVersion": 1, "liveness.isLive": true }));
      await assertFails(updateDoc(ref, new FieldPath("liveness", "isLive"), true));
      await assertFails(updateDoc(ref, new FieldPath("liveness"), live()));
      await assertFails(setDoc(ref, { liveness: live() }, { merge: true }));
      const after = await raw("clubs/legacy-public/channels/chat");
      assert.equal(Object.hasOwn(after, "liveness"), false, "no refused write created the key");
      assert.equal(after.name, "Control rename", "the control write did land");
    });

    // 2. Rules authorize each write in a batch independently; a legitimate
    // write must not carry a forged one in with it.
    await check("P1 probe: a batch cannot smuggle a liveness write beside a legitimate legacy one", async () => {
      const client = db(OWNER);
      const batch = writeBatch(client);
      batch.update(doc(client, "clubs/legacy-public/channels/chat"), { name: "Batched rename" });
      batch.update(doc(client, "clubs/legacy-public/channels/second"), { liveness: live() });
      await assertFails(batch.commit());
      const chat = await raw("clubs/legacy-public/channels/chat");
      const second = await raw("clubs/legacy-public/channels/second");
      assert.equal(chat.name, "Control rename", "the batch was refused whole");
      assert.equal(Object.hasOwn(second, "liveness"), false);
    });

    // 3. THE INDEX SURFACE. firestore.indexes.json gained channels(accessMode,
    // status, position) at COLLECTION scope. If any collectionGroup read over
    // `channels` were authorized, one query would harvest every server's
    // liveness at once. There is no /{path=**}/channels rule, so it must fail
    // even when carrying the exact filters the new index serves.
    await check("P0 probe: no collectionGroup path exists over channels, with or without the indexed filters", async () => {
      for (const uid of [OWNER, MEMBER, ADMIN, OUTSIDER]) {
        await assertFails(getDocs(collectionGroup(db(uid), "channels")));
        await assertFails(getDocs(query(collectionGroup(db(uid), "channels"),
          where("accessMode", "==", "members"), where("status", "==", "active"), orderBy("position"))));
        await assertFails(getDocs(query(collectionGroup(db(uid), "channels"),
          where("liveness.isLive", "==", true))));
      }
    });

    // 4. The indexed directory cannot be repointed at anything else. A list
    // rule is evaluated against the query's constraints (SECURITY.md 10), so
    // these are authorization tests, not filter tests.
    await check("P1 probe: the indexed directory query cannot be repointed at restricted or non-active channels", async () => {
      const channels = collection(db(MEMBER), `clubs/${ACTIVE}/channels`);
      await assertFails(getDocs(query(channels, where("accessMode", "==", "restricted"),
        where("status", "==", "active"), orderBy("position"))));
      await assertFails(getDocs(query(channels, where("accessMode", "==", "members"),
        where("status", "==", "archived"), orderBy("position"))));
      await assertFails(getDocs(query(channels, where("status", "==", "active"), orderBy("position"))));
      await assertFails(getDocs(query(channels, where("liveness.isLive", "==", true))));
      // Adding a liveness filter ON TOP of both required equalities is allowed
      // and grants nothing new: it is the same ACL, the same documents.
      const onlyLive = await assertSucceeds(getDocs(query(channels, where("accessMode", "==", "members"),
        where("status", "==", "active"), where("liveness.isLive", "==", true), orderBy("position"))));
      assert.deepEqual(onlyLive.docs.map((item) => item.id), ["general"]);
    });

    // 5. Liveness follows the channel ACL for every non-member shape.
    await check("P1 probe: outsider, banned member and removed member read no liveness", async () => {
      for (const uid of [OUTSIDER, BANNED]) {
        await assertFails(read(uid, `clubs/${ACTIVE}/channels/general`));
        await assertFails(directory(uid, ACTIVE));
      }
      await seed({ [`clubs/${ACTIVE}/members/${MEMBER}`]: null });
      await assertFails(read(MEMBER, `clubs/${ACTIVE}/channels/general`));
      await assertFails(directory(MEMBER, ACTIVE));
      await seed({ [`clubs/${ACTIVE}/members/${MEMBER}`]: member(MEMBER) });
      assert.equal((await assertSucceeds(read(MEMBER, `clubs/${ACTIVE}/channels/general`))).data().liveness.isLive, true);
    });

    // 6. A held server is owner-configuration only; its liveness must not be
    // the field that leaks its existence to a member who cannot read the root.
    await check("P1 probe: held-server liveness is invisible to its own members and admins", async () => {
      for (const uid of [MEMBER, ADMIN, OUTSIDER]) {
        await assertFails(read(uid, `clubs/${HELD}/channels/general`));
        await assertFails(directory(uid, HELD));
      }
      assert.equal((await assertSucceeds(read(OWNER, `clubs/${HELD}/channels/general`))).data().liveness.isLive, true);
    });

    // 7. A restricted channel's liveness needs the CURRENT grant, not any grant.
    await check("P1 probe: a stale or forged grant reveals no restricted liveness", async () => {
      for (const changes of [{ aclRevision: 2 }, { membershipRevision: 2 },
        { capabilities: { read: false } }, { userId: OWNER }]) {
        await seed({ [`clubs/${ACTIVE}/channels/hr/accessGrants/${MEMBER}`]: grant(ACTIVE, "hr", MEMBER, changes) });
        await assertFails(read(MEMBER, `clubs/${ACTIVE}/channels/hr`));
      }
      await seed({ [`clubs/${ACTIVE}/channels/hr/accessGrants/${MEMBER}`]: grant(ACTIVE, "hr") });
      await assertSucceeds(read(MEMBER, `clubs/${ACTIVE}/channels/hr`));
    });

    // 8. ASYMMETRY, reported rather than assumed: `list` is proven by the
    // query's two equalities alone, while `get` runs canReadServerChannel()
    // and validates serverSchemaVersion, serverId, the revisions and the
    // accessMode/accessPolicy agreement. A document that disagrees with itself
    // is therefore returned by the directory and refused by a point read. No
    // client can create one today (V1 channels have no client write path), so
    // this is a fail-open-if-the-writer-ever-slips surface, not a live hole.
    await check("P2 probe: the indexed directory returns channels whose own get() is denied", async () => {
      await seed({
        [`clubs/${ACTIVE}/channels/leaky`]: channel(ACTIVE, false, {
          name: "Zarzad private", position: 5, liveness: live(),
          accessPolicy: { accessMode: "restricted", roleIds: ["owner"], userIds: [] },
        }),
        [`clubs/${ACTIVE}/channels/unversioned`]: (() => {
          const value = channel(ACTIVE, false, { name: "No version", position: 6, liveness: live() });
          delete value.serverSchemaVersion;
          return value;
        })(),
      });
      const listed = await assertSucceeds(directory(MEMBER, ACTIVE));
      const ids = listed.docs.map((item) => item.id);
      assert.ok(ids.includes("leaky"), "a self-inconsistent channel IS listed");
      assert.ok(ids.includes("unversioned"), "an unversioned channel IS listed");
      assert.equal(listed.docs.find((item) => item.id === "leaky").data().liveness.isLive, true);
      await assertFails(read(MEMBER, `clubs/${ACTIVE}/channels/leaky`));
      await assertFails(read(MEMBER, `clubs/${ACTIVE}/channels/unversioned`));
      await seed({ [`clubs/${ACTIVE}/channels/leaky`]: null, [`clubs/${ACTIVE}/channels/unversioned`]: null });
    });

    // 9. Residual surface, proven so the report can state it precisely: the
    // legacy channel create/update rules carry no field allowlist, so a legacy
    // club manager can still pre-stage every OTHER V1 marker on a channel.
    // Only `liveness` is refused. The root — which no client can version — is
    // what still decides which adapter reads the document.
    await check("P2 probe: a legacy manager can stage every V1 marker except liveness", async () => {
      const forged = { name: "Staged", type: "voice", position: 4,
        serverSchemaVersion: 1, serverId: "legacy-public", kind: "voice",
        accessMode: "members", accessPolicy: { accessMode: "members", roleIds: [], userIds: [] },
        status: "active", revision: 1, aclRevision: 1, isPrivate: false,
        activeSessionId: "srv_forged_session", roomId: "forged-room",
        experience: "community", mediaMode: "audio" };
      await assertSucceeds(setDoc(doc(db(OWNER), "clubs/legacy-public/channels/staged"), forged));
      await assertFails(setDoc(doc(db(OWNER), "clubs/legacy-public/channels/staged2"), { ...forged, liveness: live() }));
      const stored = await raw("clubs/legacy-public/channels/staged");
      assert.equal(stored.serverSchemaVersion, 1);
      assert.equal(stored.activeSessionId, "srv_forged_session");
      assert.equal(Object.hasOwn(stored, "liveness"), false);
      // The forged document does not become a V1 channel: the root is legacy,
      // so the V1 point-read path is not even selected, and the V1 anchor and
      // session it names stay unreadable.
      await assertFails(read(OUTSIDER, "clubs/legacy-public/channels/staged"));
      await assertSucceeds(read(OWNER, "clubs/legacy-public/channels/staged"));
      await assertFails(read(OWNER, "clubs/legacy-public/channels/staged/channelSessions/srv_forged_session"));
    });

    // 10. Nothing may create a channel (with or without liveness) under a club
    // root that does not exist — isLegacyClub() is TRUE for a missing root.
    await check("P1 probe: the missing-root branch of isLegacyClub creates no orphan liveness", async () => {
      for (const payload of [channel("ghost-server", false, { liveness: live() }),
        { name: "Orphan", type: "chat", position: 0 }]) {
        await assertFails(setDoc(doc(db(OWNER), "clubs/ghost-server/channels/orphan"), payload));
        await assertFails(setDoc(doc(db(OUTSIDER), "clubs/ghost-server/channels/orphan"), payload));
      }
    });

    // 11. The projection must not become a second door to the things it
    // projects, for the actor that owns them.
    await check("P1 probe: liveness opens no session, anchor, roster or grant for its own owner", async () => {
      await seed({
        [`clubs/${ACTIVE}/channels/general/channelSessions/s1`]: { serverSchemaVersion: 1,
          serverId: ACTIVE, channelId: "general", sessionId: "s1", roomId: "anchor-1",
          livekitRoomName: "srv_1", status: "live", startedById: OWNER, startedAt: new Date(0) },
        [`clubs/${ACTIVE}/channels/general/channelSessions/s1/tokenRecipients/${OWNER}`]: { userId: OWNER },
        "rooms/anchor-1": { serverSchemaVersion: 1, serverId: ACTIVE, clubId: ACTIVE,
          channelId: "general", status: "active", visibility: "public", hostId: OWNER, isLive: true,
          participantCount: 4 },
        [`rooms/anchor-1/participants/${OWNER}`]: { userId: OWNER, role: "host" },
        [`activeVoiceSessions/${OWNER}/rooms/anchor-1`]: { serverSchemaVersion: 1, serverId: ACTIVE },
      });
      for (const uid of [OWNER, MEMBER, ADMIN, OUTSIDER]) {
        await assertFails(read(uid, `clubs/${ACTIVE}/channels/general/channelSessions/s1`));
        await assertFails(read(uid, `clubs/${ACTIVE}/channels/general/channelSessions/s1/tokenRecipients/${OWNER}`));
        await assertFails(read(uid, "rooms/anchor-1"));
        await assertFails(read(uid, `rooms/anchor-1/participants/${OWNER}`));
        await assertFails(read(uid, `clubs/${ACTIVE}/channels/hr/accessGrants/${uid}`));
        await assertFails(read(uid, `activeVoiceSessions/${OWNER}/rooms/anchor-1`));
      }
      await assertFails(getDocs(query(collectionGroup(db(OWNER), "channelSessions"), where("status", "==", "live"))));
      await assertFails(getDocs(query(collectionGroup(db(OWNER), "participants"), where("userId", "==", OWNER))));
      // ...and the channel still reports the generation to a member, which is
      // the whole point of the projection.
      assert.equal((await assertSucceeds(read(MEMBER, `clubs/${ACTIVE}/channels/general`))).data().liveness.isLive, true);
    });

    // 12. REGRESSION SURFACE of the new guard. noClientChannelLiveness() is the
    // first thing that ever made the legacy channel update rule read
    // request.resource, and the emulator reports an EVALUATION ERROR (not a
    // plain false) for the refused liveness shapes. An evaluation error denies
    // inside this conjunction, but if it fired for ordinary write shapes the
    // guard would have taken legitimate legacy channel writes down with it.
    await check("P2 probe: every ordinary legacy channel write shape still succeeds under the new guard", async () => {
      const ref = doc(db(OWNER), "clubs/legacy-public/channels/second");
      await assertSucceeds(updateDoc(ref, { name: "Plain rename" }));
      await assertSucceeds(updateDoc(ref, { "meta.pinned": true }));
      await assertSucceeds(updateDoc(ref, new FieldPath("meta", "pinned"), false));
      await assertSucceeds(updateDoc(ref, { updatedAt: serverTimestamp() }));
      await assertSucceeds(updateDoc(ref, { tags: arrayUnion("a") }));
      await assertSucceeds(updateDoc(ref, { position: increment(1) }));
      await assertSucceeds(updateDoc(ref, { name: "Kept", meta: deleteField() }));
      const stored = await raw("clubs/legacy-public/channels/second");
      assert.equal(stored.name, "Kept");
      assert.equal(Object.hasOwn(stored, "meta"), false);
    });

    // 13. FIRST-WRITE LOOPHOLE on the one batch a client may still use to
    // create channel documents: the legacy Family bootstrap. The whole
    // seven-document batch must be refused if any channel carries the map, and
    // nothing may survive partially.
    await check("P0 probe: the legacy Family bootstrap cannot seed liveness on its own channels", async () => {
      const uid = "adversarial-family-owner";
      await seed({ [`users/${uid}`]: { displayName: uid, banned: false, disabled: false } });
      const clubId = `family_${uid}`;
      const roomId = `club_lounge_${clubId}`;
      const build = (extra) => {
        const client = db(uid);
        const batch = writeBatch(client);
        const entries = {
          [`clubs/${clubId}`]: { name: "Batch Family", description: "Our private home",
            ownerId: uid, ownerName: uid, avatarUrl: null, bannerUrl: null, privacy: "inviteOnly",
            type: "family", status: "active", defaultLanguage: "English", memberCount: 1,
            onlineCount: 1, defaultChatChannelId: "general", defaultVoiceChannelId: "lounge",
            loungeRoomId: roomId, announcementChannelId: "announcements",
            createdAt: serverTimestamp(), updatedAt: serverTimestamp() },
          [`clubs/${clubId}/members/${uid}`]: { userId: uid, displayName: uid, photoUrl: null,
            role: "owner", isOnline: true, joinedAt: serverTimestamp(), invitedBy: null },
          [`users/${uid}/clubs/${clubId}`]: { clubId, name: "Batch Family", avatarUrl: null,
            role: "owner", joinedAt: serverTimestamp() },
          [`clubs/${clubId}/channels/general`]: { name: "general", type: "chat", position: 0,
            isPrivate: false, createdBy: uid, createdAt: serverTimestamp() },
          [`clubs/${clubId}/channels/announcements`]: { name: "announcements", type: "announcement",
            position: 1, isPrivate: false, createdBy: uid, createdAt: serverTimestamp() },
          [`clubs/${clubId}/channels/lounge`]: { name: "Family Lounge", type: "voice", position: 2,
            isPrivate: false, createdBy: uid, roomId, createdAt: serverTimestamp(), ...extra },
          [`rooms/${roomId}`]: { hostId: uid, hostName: uid, hostPhotoUrl: null,
            name: "Batch Family Lounge", description: "Our private home", category: "club",
            visibility: "private", language: "English", maxParticipants: null, participantCount: 0,
            memberCount: 1, isLive: false, roomType: "community", status: "active", imageUrl: null,
            approvalRequired: false, slowModeSeconds: 0, autoMuteNewUsers: false,
            membersCanStartVoice: true, experience: "community", clubId, roomKind: "clubLounge",
            createdAt: serverTimestamp(), updatedAt: serverTimestamp() },
        };
        for (const [location, value] of Object.entries(entries)) batch.set(doc(client, location), value);
        return { batch, paths: Object.keys(entries) };
      };
      const forged = build({ liveness: live() });
      await assertFails(forged.batch.commit());
      for (const location of forged.paths) assert.equal(await raw(location), null, `${location} must not exist`);
      const honest = build({});
      await assertSucceeds(honest.batch.commit());
      assert.equal(Object.hasOwn(await raw(`clubs/${clubId}/channels/lounge`), "liveness"), false);
    });

    // 14. PRECISION of ADR-177's "frozen to client writes" claim. The guard
    // reads the POST-write document, so a write that REMOVES the map passes.
    // A legacy manager can strip a map they could never write. Reported as a
    // documentation-precision item: the legacy adapter renders no liveness.
    await check("P3 probe: a legacy manager can strip (not set) an existing liveness map", async () => {
      await seed({ "clubs/legacy-public/channels/carried": { name: "Carried", type: "chat", position: 3, liveness: live() } });
      const ref = doc(db(OWNER), "clubs/legacy-public/channels/carried");
      await assertFails(updateDoc(ref, { name: "Still frozen" }));
      await assertSucceeds(updateDoc(ref, { name: "Stripped", liveness: deleteField() }));
      assert.equal(Object.hasOwn(await raw("clubs/legacy-public/channels/carried"), "liveness"), false);
      await seed({ "clubs/legacy-public/channels/carried2": { name: "Carried", type: "chat", position: 3, liveness: live() } });
      await assertSucceeds(setDoc(doc(db(OWNER), "clubs/legacy-public/channels/carried2"), { name: "Overwritten", type: "chat", position: 3 }));
      assert.equal(Object.hasOwn(await raw("clubs/legacy-public/channels/carried2"), "liveness"), false);
    });

    // 15. HELD BOUNDARY (dd8609f7) re-attacked through the branches a client
    // can still write: no client may version a root or an anchor, so no
    // legacy branch can be steered onto a V1 document.
    await check("P0 probe: no client can version a legacy root, a family bootstrap root, or a legacy room", async () => {
      const root = doc(db(OWNER), "clubs/legacy-public");
      for (const patch of [{ serverSchemaVersion: 1 }, { serverActivationState: "active" }, { serverType: "community" },
        { serverSchemaVersion: 1, templateVersion: 1, serverType: "community", serverActivationState: "active", revision: 1, updatedAt: serverTimestamp() }]) {
        await assertFails(updateDoc(root, patch));
      }
      const stored = await raw("clubs/legacy-public");
      assert.equal(Object.hasOwn(stored, "serverSchemaVersion"), false);
      // Family bootstrap carrying V1 markers on its root is refused whole.
      const uid = "adversarial-family-versioner";
      await seed({ [`users/${uid}`]: { displayName: uid, banned: false, disabled: false } });
      const clubId = `family_${uid}`; const roomId = `club_lounge_${clubId}`;
      const client = db(uid); const batch = writeBatch(client);
      batch.set(doc(client, `clubs/${clubId}`), { name: "Versioned Family", description: "x", ownerId: uid, ownerName: uid,
        avatarUrl: null, bannerUrl: null, privacy: "inviteOnly", type: "family", status: "active", defaultLanguage: "pl",
        memberCount: 1, onlineCount: 1, defaultChatChannelId: "general", defaultVoiceChannelId: "lounge", loungeRoomId: roomId,
        announcementChannelId: "announcements", createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
        serverSchemaVersion: 1, templateVersion: 1, serverType: "family", serverActivationState: "active", revision: 1 });
      batch.set(doc(client, `clubs/${clubId}/members/${uid}`), { userId: uid, displayName: uid, photoUrl: null, role: "owner", isOnline: true, joinedAt: serverTimestamp(), invitedBy: null });
      batch.set(doc(client, `users/${uid}/clubs/${clubId}`), { clubId, name: "Versioned Family", avatarUrl: null, role: "owner", joinedAt: serverTimestamp() });
      batch.set(doc(client, `clubs/${clubId}/channels/general`), { name: "general", type: "chat", position: 0, isPrivate: false, createdBy: uid, createdAt: serverTimestamp() });
      batch.set(doc(client, `clubs/${clubId}/channels/announcements`), { name: "announcements", type: "announcement", position: 1, isPrivate: false, createdBy: uid, createdAt: serverTimestamp() });
      batch.set(doc(client, `clubs/${clubId}/channels/lounge`), { name: "Lounge", type: "voice", position: 2, isPrivate: false, createdBy: uid, roomId, createdAt: serverTimestamp() });
      batch.set(doc(client, `rooms/${roomId}`), { hostId: uid, hostName: uid, hostPhotoUrl: null, name: "Lounge room", description: "x", category: "club",
        visibility: "private", language: "pl", maxParticipants: null, participantCount: 0, memberCount: 1, isLive: false, roomType: "community",
        status: "active", imageUrl: null, approvalRequired: false, slowModeSeconds: 0, autoMuteNewUsers: false, membersCanStartVoice: true,
        experience: "community", clubId, roomKind: "clubLounge", createdAt: serverTimestamp(), updatedAt: serverTimestamp() });
      await assertFails(batch.commit());
      assert.equal(await raw(`clubs/${clubId}`), null);
      // A legacy room host cannot add the V1 markers that would make rules
      // (and assertLegacyRoomAccess) treat the room as a versioned anchor.
      await seed({ "rooms/legacy-room": { hostId: OWNER, hostName: OWNER, hostPhotoUrl: null, name: "Legacy room", description: "",
        category: "club", visibility: "public", language: "pl", maxParticipants: null, participantCount: 0, memberCount: 1,
        isLive: false, roomType: "community", status: "active", imageUrl: null, approvalRequired: false, slowModeSeconds: 0,
        autoMuteNewUsers: false, membersCanStartVoice: true, experience: "community", createdAt: new Date(0), updatedAt: new Date(0) } });
      const room = doc(db(OWNER), "rooms/legacy-room");
      let control = "refused";
      try { await updateDoc(room, { name: "Renamed legacy room", updatedAt: serverTimestamp() }); control = "ok"; } catch { /* recorded below */ }
      console.log(`   (control: legacy host metadata rename ${control})`);
      await assertFails(updateDoc(room, { serverSchemaVersion: 1, updatedAt: serverTimestamp() }));
      await assertFails(updateDoc(room, { serverId: "server-active", updatedAt: serverTimestamp() }));
      await assertFails(updateDoc(room, { clubId: ACTIVE, updatedAt: serverTimestamp() }));
      const after = await raw("rooms/legacy-room");
      assert.equal(Object.hasOwn(after, "serverSchemaVersion") || Object.hasOwn(after, "serverId"), false);
    });

    // 16. Default-deny on every private V1 collection a client might try to
    // reach through the channel it can now read.
    await check("P1 probe: channelSessions, tokenRecipients, serverControlOutbox and accessGrants accept no client write", async () => {
      for (const uid of [OWNER, ADMIN, MEMBER]) {
        await assertFails(setDoc(doc(db(uid), `clubs/${ACTIVE}/channels/general/channelSessions/forged`), { status: "live", serverSchemaVersion: 1 }));
        await assertFails(updateDoc(doc(db(uid), `clubs/${ACTIVE}/channels/general/channelSessions/s1`), { status: "ended" }));
        await assertFails(deleteDoc(doc(db(uid), `clubs/${ACTIVE}/channels/general/channelSessions/s1`)));
        await assertFails(setDoc(doc(db(uid), `clubs/${ACTIVE}/channels/general/channelSessions/s1/tokenRecipients/x`), { userId: uid }));
        await assertFails(setDoc(doc(db(uid), "serverControlOutbox/forged"), { kind: "sessionEnd", status: "pending" }));
        await assertFails(setDoc(doc(db(uid), `clubs/${ACTIVE}/channels/hr/accessGrants/${uid}`), grant(ACTIVE, "hr", uid)));
        await assertFails(setDoc(doc(db(uid), `users/${uid}/serverChannelRefs/forged`), { serverId: ACTIVE, channelId: "hr" }));
      }
    });

    // 17. Read shapes that ARE allowed, recorded so the report can name the
    // residual surface rather than imply it is closed: a guest-role member, a
    // communication-muted member (reads are not communication), and an
    // outsider who can read a PUBLIC active root but none of its channels.
    await check("P2 probe: guest and communication-muted members read liveness; a public root's outsider does not", async () => {
      const GUEST = "server-guest";
      await seed({ [`users/${GUEST}`]: { displayName: GUEST, banned: false, disabled: false },
        [`clubs/${ACTIVE}/members/${GUEST}`]: member(GUEST, "guest") });
      assert.equal((await assertSucceeds(read(GUEST, `clubs/${ACTIVE}/channels/general`))).data().liveness.isLive, true);
      await assertSucceeds(directory(GUEST, ACTIVE));
      await seed({ [`restrictions/${MEMBER}`]: { type: "communicationMute", expiresAt: null } });
      assert.equal((await assertSucceeds(read(MEMBER, `clubs/${ACTIVE}/channels/general`))).data().liveness.isLive, true);
      await seed({ [`restrictions/${MEMBER}`]: null, [`clubs/${ACTIVE}/members/${GUEST}`]: null });
      const PUBLIC = "server-public";
      await seed({ [`clubs/${PUBLIC}`]: server(PUBLIC, { privacy: "public" }),
        [`clubs/${PUBLIC}/members/${OWNER}`]: member(OWNER, "owner"),
        [`clubs/${PUBLIC}/channels/general`]: channel(PUBLIC, false, { liveness: live() }) });
      await assertSucceeds(read(OUTSIDER, `clubs/${PUBLIC}`));
      await assertFails(read(OUTSIDER, `clubs/${PUBLIC}/channels/general`));
      await assertFails(directory(OUTSIDER, PUBLIC));
    });

    // 18. A stranded live map on a terminated channel cannot surface: the
    // directory pins status == active and the point read requires it.
    await check("P2 probe: a stranded live projection on an archived channel is unreachable", async () => {
      await seed({ [`clubs/${ACTIVE}/channels/archived-live`]: channel(ACTIVE, false, { status: "archived", position: 9, liveness: live() }) });
      const listed = await assertSucceeds(directory(MEMBER, ACTIVE));
      assert.equal(listed.docs.some((item) => item.id === "archived-live"), false);
      await assertFails(read(MEMBER, `clubs/${ACTIVE}/channels/archived-live`));
      await assertFails(read(OWNER, `clubs/${ACTIVE}/channels/archived-live`));
      await seed({ [`clubs/${ACTIVE}/channels/archived-live`]: null });
    });
  } finally { await env.cleanup(); }
  console.log(`Liveness adversarial: ${passed} passed, ${failed} failed.`);
  if (failed) process.exitCode = 1;
}

main().catch((error) => { console.error(error); process.exitCode = 1; });
