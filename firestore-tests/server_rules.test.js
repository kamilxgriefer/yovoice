// V1 boundary regression: real member directory queries, opaque private refs,
// revocation, held roots and Storage. Uses an isolated demo project only.
// FIRESTORE_EMULATOR_HOST=127.0.0.1:8085 FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9198 \
//   node firestore-tests/server_rules.test.js
const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const { initializeTestEnvironment, assertFails, assertSucceeds } = require("@firebase/rules-unit-testing");
const {
  collection, collectionGroup, deleteDoc, doc, getDoc, getDocs, limit,
  orderBy, query, serverTimestamp, setDoc, updateDoc, where, writeBatch,
} = require("firebase/firestore");
const { getBytes, listAll, ref, uploadBytes } = require("firebase/storage");

const PROJECT = "demo-yovoice-server-acl";
const OWNER = "server-owner";
const MEMBER = "server-member";
const OUTSIDER = "server-outsider";
const ADMIN = "server-admin";
const BANNED = "server-banned";
const HELD = "server-held";
const ACTIVE = "server-active";
const OTHER = "server-other";
// A signed-in, active account with no relation to any fixture server.
const STRANGER = "server-stranger";
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

function channel(serverId, restricted = false, changes = {}) {
  return {
    serverSchemaVersion: 1, serverId, kind: "text", type: "chat", revision: 1,
    aclRevision: 1, status: "active", name: restricted ? "HR private" : "General",
    position: restricted ? 1 : 0, roomId: null, activeSessionId: null,
    experience: null, mediaMode: null, isPrivate: restricted,
    accessMode: restricted ? "restricted" : "members",
    accessPolicy: { accessMode: restricted ? "restricted" : "members",
      roleIds: restricted ? ["owner"] : [], userIds: restricted ? [MEMBER] : [] },
    liveness: idle(),
    ...changes,
  };
}

// The server-owned liveness projection (ADR-A). No participantCount exists in
// either state: token admission is not presence, so no honest writer for a
// count exists yet and a client must render "live, count unknown".
function idle() {
  return { schemaVersion: 1, isLive: false, startedAt: null };
}

function live(startedAt = new Date(0)) {
  return { schemaVersion: 1, isLive: true, startedAt };
}

function grant(serverId, channelId, uid = MEMBER, changes = {}) {
  return { schemaVersion: 1, serverId, channelId, userId: uid,
    aclRevision: 1, membershipRevision: 1,
    capabilities: { read: true, write: true, manage: uid === OWNER,
      moderate: uid === OWNER, joinVoice: false, startSession: false }, ...changes };
}

// The existing ClubService Family bootstrap is one seven-document batch.
// Keep the production shape (including server timestamps and canonical
// identity), not an Admin-root write that would bypass the reservation gate.
function legacyFamilyGraph(db, uid) {
  const clubId = `family_${uid}`;
  const roomId = `club_lounge_${clubId}`;
  const batch = writeBatch(db);
  const entries = {
    [`clubs/${clubId}`]: {
      name: "Batch Family", description: "Our private home", ownerId: uid,
      ownerName: uid, avatarUrl: null, bannerUrl: null, privacy: "inviteOnly",
      type: "family", status: "active", defaultLanguage: "English",
      memberCount: 1, onlineCount: 1, defaultChatChannelId: "general",
      defaultVoiceChannelId: "lounge", loungeRoomId: roomId,
      announcementChannelId: "announcements", createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    },
    [`clubs/${clubId}/members/${uid}`]: {
      userId: uid, displayName: uid, photoUrl: null, role: "owner",
      isOnline: true, joinedAt: serverTimestamp(), invitedBy: null,
    },
    [`users/${uid}/clubs/${clubId}`]: {
      clubId, name: "Batch Family", avatarUrl: null, role: "owner", joinedAt: serverTimestamp(),
    },
    [`clubs/${clubId}/channels/general`]: {
      name: "general", type: "chat", position: 0, isPrivate: false,
      createdBy: uid, createdAt: serverTimestamp(),
    },
    [`clubs/${clubId}/channels/announcements`]: {
      name: "announcements", type: "announcement", position: 1, isPrivate: false,
      createdBy: uid, createdAt: serverTimestamp(),
    },
    [`clubs/${clubId}/channels/lounge`]: {
      name: "Family Lounge", type: "voice", position: 2, isPrivate: false,
      createdBy: uid, roomId, createdAt: serverTimestamp(),
    },
    [`rooms/${roomId}`]: {
      hostId: uid, hostName: uid, hostPhotoUrl: null, name: "Batch Family Lounge",
      description: "Our private home", category: "club", visibility: "private",
      language: "English", maxParticipants: null, participantCount: 0, memberCount: 1,
      isLive: false, roomType: "community", status: "active", imageUrl: null,
      approvalRequired: false, slowModeSeconds: 0, autoMuteNewUsers: false,
      membersCanStartVoice: true, experience: "community", clubId, roomKind: "clubLounge",
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    },
  };
  for (const [location, value] of Object.entries(entries)) batch.set(doc(db, location), value);
  return { batch, clubId, roomId, paths: Object.keys(entries) };
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
    storage: { ...endpoint(process.env.FIREBASE_STORAGE_EMULATOR_HOST, 9198),
      rules: fs.readFileSync(path.join(__dirname, "../storage.rules"), "utf8") },
  });
  const context = (uid) => env.authenticatedContext(uid, { email_verified: true });
  const db = (uid) => context(uid).firestore();
  const storage = (uid) => uid ? context(uid).storage(PROJECT) : env.unauthenticatedContext().storage(PROJECT);
  const seed = (entries) => env.withSecurityRulesDisabled(async (ctx) => {
    for (const [location, value] of Object.entries(entries)) {
      if (value === null) await deleteDoc(doc(ctx.firestore(), location));
      else await setDoc(doc(ctx.firestore(), location), value);
    }
  });
  const read = (uid, location) => getDoc(doc(db(uid), location));
  const directory = (uid, sid) => getDocs(query(collection(db(uid), `clubs/${sid}/channels`),
    where("accessMode", "==", "members"), where("status", "==", "active"), orderBy("position")));
  try {
    await env.clearFirestore();
    const fixtures = {};
    for (const uid of [OWNER, MEMBER, ADMIN, OUTSIDER, BANNED]) {
      fixtures[`users/${uid}`] = { displayName: uid, banned: uid === BANNED, disabled: false };
    }
    for (const sid of [HELD, ACTIVE, OTHER]) {
      fixtures[`clubs/${sid}`] = server(sid, { held: sid === HELD });
      for (const [uid, role] of [[OWNER, "owner"], [MEMBER, "member"], [ADMIN, "admin"], [BANNED, "member"]]) {
        fixtures[`clubs/${sid}/members/${uid}`] = member(uid, role);
      }
      for (const [cid, restricted] of [["general", false], ["hr", true]]) {
        fixtures[`clubs/${sid}/channels/${cid}`] = channel(sid, restricted);
        fixtures[`clubs/${sid}/channels/${cid}/messages/one`] = {
          clubId: sid, channelId: cid, senderId: MEMBER, content: "private message",
          createdAt: new Date(0), isDeleted: false,
        };
        if (restricted) for (const uid of [OWNER, MEMBER]) {
          fixtures[`clubs/${sid}/channels/${cid}/accessGrants/${uid}`] = grant(sid, cid, uid);
        }
      }
      fixtures[`clubs/${sid}/moments/one`] = { authorId: MEMBER, clubId: sid };
      fixtures[`clubs/${sid}/checkIns/one`] = { userId: MEMBER, clubId: sid };
    }
    fixtures[`users/${MEMBER}/serverChannelRefs/one`] = { serverId: ACTIVE, channelId: "hr" };
    fixtures[`rooms/held-anchor`] = {
      serverSchemaVersion: 1, serverId: HELD, serverOwnerId: OWNER, clubId: HELD,
      channelId: "hr", status: "preparing", visibility: "private", hostId: null,
      isLive: false, name: "held private channel", roomType: "community",
    };
    fixtures[`rooms/forged-public-v1`] = {
      serverSchemaVersion: 1, serverId: ACTIVE, clubId: ACTIVE, channelId: "hr",
      status: "active", visibility: "public", hostId: OWNER, isLive: true,
    };
    fixtures[`rooms/legacy-bound-to-v1`] = {
      clubId: HELD, status: "active", visibility: "public", hostId: OWNER, isLive: true,
    };
    for (const rid of ["held-anchor", "forged-public-v1", "legacy-bound-to-v1"]) {
      fixtures[`rooms/${rid}/participants/${MEMBER}`] = { userId: MEMBER, role: "speaker" };
      fixtures[`rooms/${rid}/roomMembers/${OUTSIDER}`] = { userId: OUTSIDER, role: "member" };
      fixtures[`rooms/${rid}/messages/one`] = { senderId: MEMBER, text: "private" };
    }
    fixtures[`clubs/legacy-public`] = {
      type: "community", privacy: "public", status: "active", ownerId: OWNER,
      name: "Legacy", memberCount: 1, onlineCount: 0,
    };
    fixtures[`clubs/legacy-public/members/${OWNER}`] = member(OWNER, "owner");
    fixtures[`clubs/legacy-public/channels/chat`] = { name: "Legacy chat", type: "chat", position: 0 };
    fixtures[`clubs/legacy-family`] = { type: "family", privacy: "inviteOnly", status: "active", ownerId: OWNER };
    fixtures[`clubs/legacy-family/members/${OWNER}`] = member(OWNER, "owner");
    fixtures[`rooms/legacy-public`] = { hostId: OWNER, visibility: "public", status: "active", name: "Legacy" };
    await seed(fixtures);

    await check("legacy public GET and broad legacy channel query remain available", async () => {
      await assertSucceeds(read(OUTSIDER, "clubs/legacy-public"));
      await assertSucceeds(getDocs(query(collection(db(OWNER), "clubs/legacy-public/channels"), orderBy("position"))));
    });
    await check("legacy Family remains private", async () => {
      await assertSucceeds(read(OWNER, "clubs/legacy-family"));
      await assertFails(read(OUTSIDER, "clubs/legacy-family"));
    });
    await check("legacy Family without an ownership reservation still creates the exact complete graph", async () => {
      const uid = "legacy-family-new-owner";
      await seed({ [`users/${uid}`]: { displayName: uid, banned: false, disabled: false } });
      const graph = legacyFamilyGraph(db(uid), uid);
      assert.equal((await assertSucceeds(read(uid, `clubs/${graph.clubId}`))).exists(), false);
      await assertSucceeds(graph.batch.commit());
      for (const location of graph.paths) assert.equal((await assertSucceeds(read(uid, location))).exists(), true);
      await assertFails(read(OUTSIDER, `clubs/${graph.clubId}`));
      await env.withSecurityRulesDisabled(async (ctx) => {
        assert.equal((await getDoc(doc(ctx.firestore(), `serverFamilyOwnerReservations/${uid}`))).exists(), false);
      });
    });
    await check("transferred V1 Family reservation prevents a second legacy family_B atomically", async () => {
      const uid = "transferred-family-owner-b";
      const transferredId = "family_original-owner-a";
      await seed({
        [`users/${uid}`]: { displayName: uid, banned: false, disabled: false },
        [`clubs/${transferredId}`]: server(transferredId, { held: true, ownerId: uid, type: "family", serverType: "family" }),
        [`clubs/${transferredId}/members/${uid}`]: member(uid, "owner"),
        [`serverFamilyOwnerReservations/${uid}`]: { schemaVersion: 1, ownerId: uid,
          serverId: transferredId, status: "active", updatedAt: new Date(0) },
      });
      const graph = legacyFamilyGraph(db(uid), uid);
      await assertSucceeds(read(uid, `clubs/${transferredId}`));
      await assertFails(graph.batch.commit());
      await env.withSecurityRulesDisabled(async (ctx) => {
        for (const location of graph.paths) assert.equal((await getDoc(doc(ctx.firestore(), location))).exists(), false);
        assert.equal((await getDoc(doc(ctx.firestore(), `clubs/${transferredId}`))).data().ownerId, uid);
      });
    });
    await check("any existing Family reservation fails closed, including malformed and orphan states", async () => {
      const variants = [
        {}, { schemaVersion: null }, { schemaVersion: 2, status: "active" },
        { schemaVersion: 1, ownerId: OWNER, status: "active", serverId: "wrong-owner" },
        { schemaVersion: 1, status: "released", serverId: "released-family" },
        { schemaVersion: 1, status: "active", serverId: "../invalid" },
        { schemaVersion: 1, status: "active", serverId: null },
        { schemaVersion: 1, status: "active", serverId: "missing-family" },
      ];
      for (const [index, value] of variants.entries()) {
        const uid = `malformed-family-reservation-${index}`;
        await seed({ [`users/${uid}`]: { displayName: uid, banned: false, disabled: false },
          [`serverFamilyOwnerReservations/${uid}`]: { ownerId: uid, ...value } });
        const graph = legacyFamilyGraph(db(uid), uid);
        await assertFails(graph.batch.commit());
        await env.withSecurityRulesDisabled(async (ctx) => {
          for (const location of graph.paths) assert.equal((await getDoc(doc(ctx.firestore(), location))).exists(), false);
        });
      }
    });
    await check("a valid own-id reservation cannot be erased or bypassed by the legacy bootstrap", async () => {
      const uid = "reserved-family-new-owner";
      const reservationPath = `serverFamilyOwnerReservations/${uid}`;
      await seed({ [`users/${uid}`]: { displayName: uid, banned: false, disabled: false },
        [reservationPath]: { schemaVersion: 1, ownerId: uid, serverId: `family_${uid}`,
          status: "active", updatedAt: new Date(0) } });
      await assertFails(read(uid, reservationPath));
      await assertFails(deleteDoc(doc(db(uid), reservationPath)));
      await assertFails(updateDoc(doc(db(uid), reservationPath), { status: "released" }));
      await assertFails(legacyFamilyGraph(db(uid), uid).batch.commit());
      const bypassDb = db(uid);
      const bypass = legacyFamilyGraph(bypassDb, uid);
      bypass.batch.delete(doc(bypassDb, reservationPath));
      await assertFails(bypass.batch.commit());
    });
    await check("held root is owner configuration only", async () => {
      await assertSucceeds(read(OWNER, `clubs/${HELD}`));
      for (const uid of [MEMBER, ADMIN, OUTSIDER]) await assertFails(read(uid, `clubs/${HELD}`));
      await assertSucceeds(directory(OWNER, HELD));
      await assertFails(directory(MEMBER, HELD));
      await assertSucceeds(read(OWNER, `clubs/${HELD}/channels/hr`));
    });
    await check("proper public discovery query excludes preparing roots", async () => {
      await seed({ [`clubs/${HELD}`]: server(HELD, { held: true, privacy: "public", serverType: "community" }) });
      const result = await assertSucceeds(getDocs(query(collection(db(OUTSIDER), "clubs"),
        where("privacy", "==", "public"), where("type", "==", "community"), where("status", "==", "active"), limit(8))));
      assert.equal(result.docs.some((item) => item.id === HELD), false);
      assert.equal(result.docs.some((item) => item.id === "legacy-public"), true);
    });
    await check("legacy host/public room list excludes held anchor by canonical shape", async () => {
      for (const filter of [where("hostId", "==", OWNER), where("visibility", "==", "public")]) {
        const result = await assertSucceeds(getDocs(query(collection(db(OWNER), "rooms"), filter)));
        assert.equal(result.docs.some((item) => item.id === "held-anchor"), false);
      }
    });
    await check("active private root is not readable by outsider", async () => {
      await assertSucceeds(read(MEMBER, `clubs/${ACTIVE}`));
      await assertFails(read(OUTSIDER, `clubs/${ACTIVE}`));
    });
    await check("V1 private root cannot inherit a stale or forged legacy invitation preview", async () => {
      for (const status of ["pending", "declined", "accepted", "expired"]) {
        await seed({ [`clubs/${ACTIVE}/invites/${OUTSIDER}`]: {
          inviteeId: OUTSIDER, inviterId: OWNER, status,
          expiresAt: new Date(0), generation: "stale", inviterAuthorizationRevision: 0,
        } });
        await assertFails(read(OUTSIDER, `clubs/${ACTIVE}`));
        await assertFails(directory(OUTSIDER, ACTIVE));
      }
      await seed({ [`clubs/legacy-family/invites/${OUTSIDER}`]: {
        inviteeId: OUTSIDER, inviterId: OWNER, status: "pending",
      } });
      await assertSucceeds(read(OUTSIDER, "clubs/legacy-family"));
    });
    await check("member directory uses both filters and excludes restricted metadata", async () => {
      const result = await assertSucceeds(directory(MEMBER, ACTIVE));
      assert.deepEqual(result.docs.map((item) => item.id), ["general"]);
      await assertFails(getDocs(query(collection(db(MEMBER), `clubs/${ACTIVE}/channels`), orderBy("position"))));
      await assertFails(getDocs(query(collection(db(MEMBER), `clubs/${ACTIVE}/channels`), where("accessMode", "==", "members"))));
      await assertFails(directory(OUTSIDER, ACTIVE));
      await assertFails(directory(BANNED, ACTIVE));
    });
    await check("restricted current grant permits point reads and message query only", async () => {
      await assertSucceeds(read(MEMBER, `clubs/${ACTIVE}/channels/hr`));
      await assertSucceeds(getDocs(collection(db(MEMBER), `clubs/${ACTIVE}/channels/hr/messages`)));
      await assertFails(read(ADMIN, `clubs/${ACTIVE}/channels/hr`));
      await assertFails(read(OUTSIDER, `clubs/${ACTIVE}/channels/hr/messages/one`));
      await assertFails(getDocs(query(collection(db(MEMBER), `clubs/${ACTIVE}/channels`), where("accessMode", "==", "restricted"))));
    });
    await check("self opaque reference query is discovery, never shared authority", async () => {
      await assertSucceeds(getDocs(query(collection(db(MEMBER), `users/${MEMBER}/serverChannelRefs`), where("serverId", "==", ACTIVE))));
      await assertFails(read(OUTSIDER, `users/${MEMBER}/serverChannelRefs/one`));
      await assertFails(setDoc(doc(db(MEMBER), `users/${MEMBER}/serverChannelRefs/forged`), { serverId: OTHER, channelId: "hr" }));
      await assertFails(getDocs(query(collectionGroup(db(MEMBER), "accessGrants"), where("userId", "==", MEMBER))));
    });
    const grantPath = `clubs/${ACTIVE}/channels/hr/accessGrants/${MEMBER}`;
    for (const [label, changes] of Object.entries({
      "stale ACL": { aclRevision: 2 }, "stale membership": { membershipRevision: 2 },
      "cross server": { serverId: OTHER }, "cross channel": { channelId: "general" },
      "cross user": { userId: OWNER }, "unknown grant version": { schemaVersion: 2 },
      "read denied": { capabilities: { read: false } },
    })) await check(`${label} grant is denied`, async () => {
      await seed({ [grantPath]: grant(ACTIVE, "hr", MEMBER, changes) });
      await assertFails(read(MEMBER, `clubs/${ACTIVE}/channels/hr`));
      await assertFails(read(MEMBER, `clubs/${ACTIVE}/channels/hr/messages/one`));
    });
    await seed({ [grantPath]: grant(ACTIVE, "hr") });
    await check("membership removal immediately invalidates a still-current grant", async () => {
      await seed({ [`clubs/${ACTIVE}/members/${MEMBER}`]: null });
      await assertFails(read(MEMBER, `clubs/${ACTIVE}/channels/hr`));
      await assertFails(directory(MEMBER, ACTIVE));
      await seed({ [`clubs/${ACTIVE}/members/${MEMBER}`]: member(MEMBER) });
    });
    await check("current grant without current policy is denied", async () => {
      await seed({ [`clubs/${ACTIVE}/channels/hr`]: channel(ACTIVE, true, {
        accessPolicy: { accessMode: "restricted", roleIds: ["owner"], userIds: [] },
      }) });
      await assertFails(read(MEMBER, `clubs/${ACTIVE}/channels/hr`));
      await seed({ [`clubs/${ACTIVE}/channels/hr`]: channel(ACTIVE, true) });
    });
    await check("owner has no restricted wildcard when its grant is missing", async () => {
      await seed({ [`clubs/${ACTIVE}/channels/hr/accessGrants/${OWNER}`]: null });
      await assertFails(read(OWNER, `clubs/${ACTIVE}/channels/hr`));
    });
    await check("held content and roster deny even owner", async () => {
      for (const location of ["channels/general/messages/one", "channels/hr/messages/one", "moments/one", "checkIns/one"]) {
        await assertFails(read(OWNER, `clubs/${HELD}/${location}`));
      }
      await assertFails(getDocs(collection(db(OWNER), `clubs/${HELD}/members`)));
    });
    await check("legacy room visibility, host, participant and member OR branches cannot open V1", async () => {
      for (const rid of ["held-anchor", "forged-public-v1", "legacy-bound-to-v1"]) {
        for (const uid of [OWNER, MEMBER, OUTSIDER]) {
          await assertFails(read(uid, `rooms/${rid}`));
          await assertFails(read(uid, `rooms/${rid}/messages/one`));
        }
        await assertFails(read(MEMBER, `rooms/${rid}/participants/${MEMBER}`));
      }
    });
    await check("unknown/null root version and mismatched activation fail closed", async () => {
      for (const changes of [{ serverSchemaVersion: 2 }, { serverSchemaVersion: null },
        { serverActivationState: "held" }, { serverType: "unknown" }]) {
        await seed({ [`clubs/${ACTIVE}`]: server(ACTIVE, changes) });
        await assertFails(read(MEMBER, `clubs/${ACTIVE}`));
        await assertFails(read(MEMBER, `clubs/${ACTIVE}/channels/general/messages/one`));
      }
      await seed({ [`clubs/${ACTIVE}`]: server(ACTIVE) });
    });
    await check("legacy direct writes cannot forge V1 metadata, roles, grants or channel ACL", async () => {
      await assertFails(updateDoc(doc(db(OWNER), `clubs/${ACTIVE}`), { name: "forged", updatedAt: serverTimestamp() }));
      await assertFails(updateDoc(doc(db(OWNER), `clubs/${ACTIVE}/members/${MEMBER}`), { role: "admin" }));
      await assertFails(updateDoc(doc(db(OWNER), `clubs/${ACTIVE}/channels/general`), { accessMode: "restricted" }));
      await assertFails(setDoc(doc(db(OWNER), `clubs/${ACTIVE}/channels/forged`), channel(ACTIVE)));
      await assertFails(setDoc(doc(db(MEMBER), grantPath), grant(ACTIVE, "hr")));
      await assertFails(deleteDoc(doc(db(OWNER), `clubs/${ACTIVE}/channels/general`)));
    });
    await check("server-owned liveness is readable exactly where its channel is, and carries no count", async () => {
      await seed({ [`clubs/${ACTIVE}/channels/general`]: channel(ACTIVE, false, { liveness: live() }) });
      const listed = await assertSucceeds(directory(MEMBER, ACTIVE));
      assert.deepEqual(listed.docs.map((item) => item.id), ["general"]);
      assert.equal(listed.docs[0].data().liveness.isLive, true);
      // Nothing may render a participant count, because nothing writes one.
      assert.equal(Object.hasOwn(listed.docs[0].data().liveness, "participantCount"), false);
      assert.equal((await assertSucceeds(read(MEMBER, `clubs/${ACTIVE}/channels/general`))).data().liveness.isLive, true);
      // The ACL that governs the channel governs its liveness: no membership,
      // no projection. A restricted channel still needs its current grant.
      await assertFails(directory(OUTSIDER, ACTIVE));
      await assertFails(read(OUTSIDER, `clubs/${ACTIVE}/channels/general`));
      await seed({ [`clubs/${ACTIVE}/channels/hr`]: channel(ACTIVE, true, { liveness: live() }) });
      await assertSucceeds(read(MEMBER, `clubs/${ACTIVE}/channels/hr`));
      await assertFails(read(ADMIN, `clubs/${ACTIVE}/channels/hr`));
    });
    await check("a live projection opens neither the session it projects nor the anchor or roster", async () => {
      await seed({ [`clubs/${ACTIVE}/channels/general/channelSessions/live-one`]: {
        serverSchemaVersion: 1, serverId: ACTIVE, channelId: "general", sessionId: "live-one",
        roomId: "forged-public-v1", livekitRoomName: "srv_live", status: "live",
        startedById: OWNER, startedAt: new Date(0), endedAt: null,
      } });
      for (const uid of [OWNER, MEMBER, ADMIN, OUTSIDER]) {
        await assertFails(read(uid, `clubs/${ACTIVE}/channels/general/channelSessions/live-one`));
        await assertFails(getDocs(collection(db(uid), `clubs/${ACTIVE}/channels/general/channelSessions`)));
        await assertFails(read(uid, "rooms/forged-public-v1"));
      }
      await assertFails(getDocs(query(collectionGroup(db(MEMBER), "channelSessions"), where("status", "==", "live"))));
      await assertFails(read(MEMBER, `rooms/forged-public-v1/participants/${MEMBER}`));
    });
    await check("no client writes liveness, including a member holding manage rights on that channel", async () => {
      for (const uid of [OWNER, ADMIN, MEMBER, OUTSIDER]) {
        for (const cid of ["general", "hr"]) {
          await assertFails(updateDoc(doc(db(uid), `clubs/${ACTIVE}/channels/${cid}`), { liveness: live() }));
          await assertFails(updateDoc(doc(db(uid), `clubs/${ACTIVE}/channels/${cid}`), { "liveness.isLive": true }));
          await assertFails(setDoc(doc(db(uid), `clubs/${ACTIVE}/channels/${cid}`), channel(ACTIVE, cid === "hr", { liveness: live() })));
        }
        await assertFails(setDoc(doc(db(uid), `clubs/${ACTIVE}/channels/forged-live`), channel(ACTIVE, false, { liveness: live() })));
        await assertFails(updateDoc(doc(db(uid), `clubs/${ACTIVE}/channels/general`), { liveness: idle() }));
      }
      // The seeded server value is untouched by every refused write above.
      assert.equal((await assertSucceeds(read(MEMBER, `clubs/${ACTIVE}/channels/general`))).data().liveness.isLive, true);
    });
    await check("a legacy manager keeps ordinary channel writes but cannot forge liveness on one", async () => {
      await assertSucceeds(updateDoc(doc(db(OWNER), "clubs/legacy-public/channels/chat"), { name: "Renamed chat" }));
      await assertSucceeds(setDoc(doc(db(OWNER), "clubs/legacy-public/channels/plain"), { name: "Plain", type: "chat", position: 8 }));
      await assertFails(updateDoc(doc(db(OWNER), "clubs/legacy-public/channels/chat"), { liveness: live() }));
      await assertFails(updateDoc(doc(db(OWNER), "clubs/legacy-public/channels/chat"), { liveness: idle() }));
      await assertFails(setDoc(doc(db(OWNER), "clubs/legacy-public/channels/forged"), {
        name: "Forged", type: "chat", position: 9, liveness: live(),
      }));
      // Deletion is unaffected: request.resource is null there, so the guard
      // is on create/update only and a manager can still remove a channel.
      await assertSucceeds(deleteDoc(doc(db(OWNER), "clubs/legacy-public/channels/plain")));
      // Consequence, stated rather than hidden: a legacy channel that already
      // carries the server-owned map is frozen to client writes, because the
      // post-write document still contains it. Fail-closed is the right side.
      await seed({ "clubs/legacy-public/channels/tainted": { name: "Tainted", type: "chat", position: 7, liveness: live() } });
      await assertFails(updateDoc(doc(db(OWNER), "clubs/legacy-public/channels/tainted"), { name: "Renamed" }));
    });
    await check("unsupported channel modules remain denied, not generic client writable", async () => {
      for (const moduleName of ["events", "questions", "episodes", "boards", "files", "listItems"]) {
        await assertFails(setDoc(doc(db(OWNER), `clubs/${ACTIVE}/channels/general/${moduleName}/one`), { title: "forged" }));
      }
    });

    // V1 invitations (ADR-178). The document respondToServerInviteV1 consumes
    // is written only by createServerInviteV1 / revokeServerInviteV1; every
    // client write is denied, and the invitee discovers it through a private
    // pointer in the serverChannelRefs posture, never through a query the
    // boundary forbids.
    const v1Invite = (inviteeId, changes = {}) => ({
      serverSchemaVersion: 1, serverId: ACTIVE, inviteeId, inviterId: OWNER, inviterAuthorizationRevision: 1,
      status: "pending", generation: 1, expiresAt: new Date(Date.now() + 86_400_000),
      serverName: "Private", inviterName: OWNER, createdAt: new Date(0), updatedAt: new Date(0), ...changes,
    });
    await check("a V1 invitation is server-owned: no client create, update or delete for manager, invitee or outsider, while a legacy manager still deletes a legacy invite", async () => {
      await seed({ [`clubs/${ACTIVE}/invites/${OUTSIDER}`]: v1Invite(OUTSIDER),
        [`users/${STRANGER}`]: { displayName: STRANGER, banned: false, disabled: false },
        [`clubs/legacy-public/invites/${OUTSIDER}`]: { clubId: "legacy-public", inviteeId: OUTSIDER, inviterId: OWNER, status: "pending" } });
      const invitePath = `clubs/${ACTIVE}/invites/${OUTSIDER}`;
      for (const uid of [OWNER, ADMIN, MEMBER, OUTSIDER]) {
        await assertFails(setDoc(doc(db(uid), `clubs/${ACTIVE}/invites/${STRANGER}`), v1Invite(STRANGER)));
        await assertFails(setDoc(doc(db(uid), `clubs/${ACTIVE}/invites/forged-${uid}`), v1Invite(`forged-${uid}`)));
        await assertFails(updateDoc(doc(db(uid), invitePath), { status: "accepted" }));
        await assertFails(updateDoc(doc(db(uid), invitePath), { generation: 99 }));
        await assertFails(updateDoc(doc(db(uid), invitePath), { expiresAt: new Date(Date.now() + 10 * 86_400_000) }));
        await assertFails(updateDoc(doc(db(uid), invitePath), { inviterAuthorizationRevision: 2 }));
        await assertFails(setDoc(doc(db(uid), invitePath), v1Invite(OUTSIDER, { status: "accepted" })));
        await assertFails(deleteDoc(doc(db(uid), invitePath)));
      }
      // The invitee cannot accept by writing the roster row the callable owns.
      await assertFails(setDoc(doc(db(OUTSIDER), `clubs/${ACTIVE}/members/${OUTSIDER}`), member(OUTSIDER)));
      // Differential: isLegacyClub is the discriminator, so the same manager
      // keeps the legacy delete on a legacy invite.
      await assertSucceeds(deleteDoc(doc(db(OWNER), `clubs/legacy-public/invites/${OUTSIDER}`)));
      await env.withSecurityRulesDisabled(async (ctx) => {
        const stored = (await getDoc(doc(ctx.firestore(), invitePath))).data();
        assert.equal(stored.status, "pending");
        assert.equal(stored.generation, 1);
        assert.equal(stored.inviterAuthorizationRevision, 1);
      });
    });
    await check("the invitee and the server's managers read a V1 invitation; a plain member, another account and a banned invitee do not; it still opens no root or channel", async () => {
      const invitePath = `clubs/${ACTIVE}/invites/${OUTSIDER}`;
      assert.equal((await assertSucceeds(read(OUTSIDER, invitePath))).data().generation, 1);
      await assertSucceeds(read(OWNER, invitePath));
      await assertSucceeds(read(ADMIN, invitePath));
      await assertFails(read(MEMBER, invitePath));
      await assertFails(read(STRANGER, invitePath));
      await seed({ [`clubs/${ACTIVE}/invites/${BANNED}`]: v1Invite(BANNED) });
      await assertFails(read(BANNED, `clubs/${ACTIVE}/invites/${BANNED}`));
      // The existing self-scoped collectionGroup discovery still works for
      // the invitee alone; it cannot be repointed at anyone else's invites.
      const own = await assertSucceeds(getDocs(query(collectionGroup(db(OUTSIDER), "invites"), where("inviteeId", "==", OUTSIDER))));
      assert.ok(own.docs.some((item) => item.ref.path === invitePath));
      await assertFails(getDocs(query(collectionGroup(db(OUTSIDER), "invites"), where("inviteeId", "==", BANNED))));
      await assertFails(getDocs(query(collectionGroup(db(OUTSIDER), "invites"), where("serverId", "==", ACTIVE))));
      // A pending invitation is not membership: no root, no directory, no
      // channel, no message.
      await assertFails(read(OUTSIDER, `clubs/${ACTIVE}`));
      await assertFails(directory(OUTSIDER, ACTIVE));
      await assertFails(read(OUTSIDER, `clubs/${ACTIVE}/channels/general`));
      await assertFails(read(OUTSIDER, `clubs/${ACTIVE}/channels/general/messages/one`));
      await seed({ [`clubs/${ACTIVE}/invites/${OUTSIDER}`]: null, [`clubs/${ACTIVE}/invites/${BANNED}`]: null });
    });
    await check("serverInviteRefs is owner-only discovery in the serverChannelRefs posture: opaque ids, never client-writable, never a collection group", async () => {
      const pointer = { serverId: ACTIVE, generation: 1, expiresAt: new Date(Date.now() + 86_400_000) };
      await seed({ [`users/${OUTSIDER}/serverInviteRefs/${ACTIVE}`]: pointer, [`users/${BANNED}/serverInviteRefs/${ACTIVE}`]: pointer });
      const own = await assertSucceeds(read(OUTSIDER, `users/${OUTSIDER}/serverInviteRefs/${ACTIVE}`));
      assert.deepEqual(Object.keys(own.data()).sort(), ["expiresAt", "generation", "serverId"]);
      const listed = await assertSucceeds(getDocs(query(collection(db(OUTSIDER), `users/${OUTSIDER}/serverInviteRefs`), where("serverId", "==", ACTIVE))));
      assert.deepEqual(listed.docs.map((item) => item.id), [ACTIVE]);
      await assertSucceeds(getDocs(collection(db(OUTSIDER), `users/${OUTSIDER}/serverInviteRefs`)));
      for (const uid of [OWNER, ADMIN, MEMBER, STRANGER]) {
        await assertFails(read(uid, `users/${OUTSIDER}/serverInviteRefs/${ACTIVE}`));
        await assertFails(getDocs(collection(db(uid), `users/${OUTSIDER}/serverInviteRefs`)));
      }
      await assertFails(read(BANNED, `users/${BANNED}/serverInviteRefs/${ACTIVE}`));
      await assertFails(setDoc(doc(db(OUTSIDER), `users/${OUTSIDER}/serverInviteRefs/${OTHER}`), { serverId: OTHER, generation: 1, expiresAt: new Date(Date.now() + 86_400_000) }));
      await assertFails(updateDoc(doc(db(OUTSIDER), `users/${OUTSIDER}/serverInviteRefs/${ACTIVE}`), { generation: 2 }));
      await assertFails(deleteDoc(doc(db(OUTSIDER), `users/${OUTSIDER}/serverInviteRefs/${ACTIVE}`)));
      await assertFails(getDocs(query(collectionGroup(db(OUTSIDER), "serverInviteRefs"), where("serverId", "==", ACTIVE))));
      // A pointer is discovery, never authority: with no invitation behind it
      // the root and channels stay closed exactly as before.
      await assertFails(read(OUTSIDER, `clubs/${ACTIVE}`));
      await assertFails(directory(OUTSIDER, ACTIVE));
      await seed({ [`users/${OUTSIDER}/serverInviteRefs/${ACTIVE}`]: null, [`users/${BANNED}/serverInviteRefs/${ACTIVE}`]: null });
    });

    // V1 session participation (ADR-181). `rooms/{anchor}/participants/{uid}`
    // is written by token issuance and the participation callables only; it is
    // authorization state (session role, raised hand, host/moderator mutes),
    // never presence. Two reads exist under the channel's own ACL: a person's
    // own document of the live generation, and the raised-hand queue for the
    // session host and moderate-capable roles. The anchor, the generation and
    // the roster stay closed, and no client writes any of it.
    const LISTENER = "server-listener";
    const STALE = "server-stale";
    const SALON = "salon";
    const ANCHOR = "v1-live-anchor";
    const GENERATION = "live-gen";
    const participant = (uid, role, changes = {}) => ({
      serverSchemaVersion: 1, serverId: ACTIVE, channelId: SALON, roomId: ANCHOR, sessionId: GENERATION,
      userId: uid, role, authorizationRevision: 1, hostMuted: false, serverMuted: false, isMuted: true,
      isHandRaised: false, handRaisedAt: null, displayName: uid, photoUrl: null,
      tokenAuthorityFingerprint: "f".repeat(64), joinedAt: new Date(0), updatedAt: new Date(0), ...changes,
    });
    const salon = (changes = {}) => channel(ACTIVE, false, { kind: "voice", type: "voice", name: "Salon", position: 2,
      roomId: ANCHOR, activeSessionId: GENERATION, experience: "community", mediaMode: "audio", liveness: live(), ...changes });
    const anchor = (changes = {}) => ({
      serverSchemaVersion: 1, serverId: ACTIVE, clubId: ACTIVE, channelId: SALON, serverActivationState: "active",
      status: "active", visibility: "private", hostId: OWNER, serverOwnerId: OWNER, hostName: OWNER, name: "Salon",
      roomKind: "serverChannel", roomType: "community", experience: "community", mediaMode: "audio",
      isLive: true, voiceSessionId: GENERATION, livekitRoomName: "srv_live", participantCount: 0, ...changes,
    });
    const generation = (changes = {}) => ({
      serverSchemaVersion: 1, serverId: ACTIVE, channelId: SALON, roomId: ANCHOR, sessionId: GENERATION,
      livekitRoomName: "srv_live", experience: "community", mediaMode: "audio", sourcePolicyVersion: 1,
      authorizationRevision: 1, status: "live", startedById: MEMBER, startedAt: new Date(0), endedAt: null,
      maxTokenExpiresAtMillis: 0, ...changes,
    });
    // The exact client query: four bare equalities, no orderBy (an orderBy
    // would need a composite index that is not committed).
    const hands = (uid, changes = {}) => getDocs(query(collection(db(uid), `rooms/${ANCHOR}/participants`),
      where("serverId", "==", changes.serverId ?? ACTIVE), where("channelId", "==", changes.channelId ?? SALON),
      where("sessionId", "==", changes.sessionId ?? GENERATION), where("isHandRaised", "==", changes.raised ?? true)));
    const own = (uid) => `rooms/${ANCHOR}/participants/${uid}`;
    await seed({
      [`users/${LISTENER}`]: { displayName: LISTENER, banned: false, disabled: false },
      [`users/${STALE}`]: { displayName: STALE, banned: false, disabled: false },
      [`users/${STRANGER}`]: { displayName: STRANGER, banned: false, disabled: false },
      [`clubs/${ACTIVE}/members/${LISTENER}`]: member(LISTENER, "member"),
      [`clubs/${ACTIVE}/members/${STALE}`]: member(STALE, "member"),
      [`clubs/${ACTIVE}/channels/${SALON}`]: salon(),
      [`clubs/${ACTIVE}/channels/${SALON}/channelSessions/${GENERATION}`]: generation(),
      [`rooms/${ANCHOR}`]: anchor(),
      [own(MEMBER)]: participant(MEMBER, "host"),
      [own(ADMIN)]: participant(ADMIN, "guest"),
      [own(LISTENER)]: participant(LISTENER, "listener", { isHandRaised: true, handRaisedAt: new Date(1) }),
      [own(STALE)]: participant(STALE, "listener", { sessionId: "old-gen", isHandRaised: true, handRaisedAt: new Date(2) }),
      [`rooms/legacy-public/participants/${OUTSIDER}`]: { userId: OUTSIDER, displayName: OUTSIDER, role: "listener",
        isMuted: true, isSpeaker: false, isHandRaised: true, joinedAt: new Date(0), updatedAt: new Date(0) },
    });
    await check("a V1 participant reads only their own live-generation document; anchor, generation and roster stay closed", async () => {
      const mine = await assertSucceeds(read(LISTENER, own(LISTENER)));
      assert.equal(mine.data().role, "listener");
      assert.equal(mine.data().isHandRaised, true);
      await assertSucceeds(read(MEMBER, own(MEMBER)));
      await assertSucceeds(read(ADMIN, own(ADMIN)));
      // Nobody reads another person's document: not the host, not the owner,
      // not an admin. The queue below is the only cross-identity read.
      await assertFails(read(MEMBER, own(LISTENER)));
      await assertFails(read(OWNER, own(LISTENER)));
      await assertFails(read(ADMIN, own(MEMBER)));
      // No document, a banned account, an outsider and a stale generation.
      await assertFails(read(OWNER, own(OWNER)));
      await assertFails(read(BANNED, own(BANNED)));
      await assertFails(read(OUTSIDER, own(OUTSIDER)));
      await assertFails(read(STRANGER, own(STRANGER)));
      await assertFails(read(STALE, own(STALE)));
      for (const uid of [OWNER, MEMBER, ADMIN, LISTENER]) {
        await assertFails(read(uid, `rooms/${ANCHOR}`));
        await assertFails(read(uid, `clubs/${ACTIVE}/channels/${SALON}/channelSessions/${GENERATION}`));
        await assertFails(getDocs(collection(db(uid), `rooms/${ANCHOR}/participants`)));
        await assertFails(getDocs(query(collection(db(uid), `rooms/${ANCHOR}/participants`), where("userId", "==", uid))));
        await assertFails(getDocs(query(collection(db(uid), `rooms/${ANCHOR}/participants`), where("sessionId", "==", GENERATION))));
      }
      // The forged and held anchors from the earlier cases still open nothing.
      await assertFails(read(MEMBER, `rooms/forged-public-v1/participants/${MEMBER}`));
      await assertFails(read(MEMBER, `rooms/held-anchor/participants/${MEMBER}`));
      // An ended generation closes the document even to its own subject: the
      // read is bound to the anchor's live pointer, not to the document's own
      // claim about its session.
      await seed({ [`clubs/${ACTIVE}/channels/${SALON}`]: salon({ activeSessionId: null, liveness: idle() }),
        [`rooms/${ANCHOR}`]: anchor({ isLive: false, voiceSessionId: null, livekitRoomName: null, serverSessionCleanupId: GENERATION }) });
      await assertFails(read(LISTENER, own(LISTENER)));
      await assertFails(read(MEMBER, own(MEMBER)));
      await seed({ [`clubs/${ACTIVE}/channels/${SALON}`]: salon(), [`rooms/${ANCHOR}`]: anchor() });
      // A held root closes it too, owner included.
      await seed({ [`clubs/${ACTIVE}`]: server(ACTIVE, { held: true }) });
      await assertFails(read(LISTENER, own(LISTENER)));
      await assertFails(read(MEMBER, own(MEMBER)));
      await seed({ [`clubs/${ACTIVE}`]: server(ACTIVE) });
      // The legacy arm of the split rule is unchanged: a public legacy room's
      // participants stay readable, point read and listing alike.
      await assertSucceeds(read(OUTSIDER, `rooms/legacy-public/participants/${OUTSIDER}`));
      await assertSucceeds(getDocs(collection(db(OUTSIDER), "rooms/legacy-public/participants")));
      await assertSucceeds(getDocs(collection(db(STRANGER), "rooms/legacy-public/participants")));
    });
    await check("the host and moderate-capable roles list exactly the raised hands of the live generation, every equality pinned", async () => {
      // The host is a plain member: the standing comes from startedById.
      assert.deepEqual((await assertSucceeds(hands(MEMBER))).docs.map((item) => item.id), [LISTENER]);
      // Moderate-capable roles list it whether or not they are in the session
      // (the owner has no participant document): the authority is the server
      // role, never a platform claim.
      for (const uid of [OWNER, ADMIN]) {
        assert.deepEqual((await assertSucceeds(hands(uid))).docs.map((item) => item.id), [LISTENER]);
      }
      // A participant, an outsider, a banned account, a stranger and a member
      // whose document belongs to an older generation do not.
      for (const uid of [LISTENER, OUTSIDER, BANNED, STRANGER, STALE]) await assertFails(hands(uid));
      // Every equality is load-bearing: rules are not filters.
      await assertFails(hands(MEMBER, { raised: false }));
      await assertFails(getDocs(query(collection(db(MEMBER), `rooms/${ANCHOR}/participants`),
        where("serverId", "==", ACTIVE), where("channelId", "==", SALON), where("sessionId", "==", GENERATION))));
      await assertFails(getDocs(query(collection(db(OWNER), `rooms/${ANCHOR}/participants`), where("isHandRaised", "==", true))));
      await assertFails(hands(MEMBER, { sessionId: "old-gen" }));
      await assertFails(hands(OWNER, { sessionId: "old-gen" }));
      await assertFails(hands(MEMBER, { channelId: "general" }));
      await assertFails(hands(MEMBER, { serverId: OTHER }));
      // No top-level wildcard exists for participants, so a collection-group
      // query is denied regardless of its filters.
      await assertFails(getDocs(query(collectionGroup(db(MEMBER), "participants"), where("serverId", "==", ACTIVE),
        where("channelId", "==", SALON), where("sessionId", "==", GENERATION), where("isHandRaised", "==", true))));
      await assertFails(getDocs(query(collectionGroup(db(OWNER), "participants"), where("isHandRaised", "==", true))));
      // The host standing follows the generation's starter, not the document.
      await seed({ [`clubs/${ACTIVE}/channels/${SALON}/channelSessions/${GENERATION}`]: generation({ startedById: OWNER }) });
      await assertFails(hands(MEMBER));
      await assertSucceeds(hands(OWNER));
      await seed({ [`clubs/${ACTIVE}/channels/${SALON}/channelSessions/${GENERATION}`]: generation() });
      // An ended generation has no queue.
      await seed({ [`clubs/${ACTIVE}/channels/${SALON}`]: salon({ activeSessionId: null, liveness: idle() }),
        [`rooms/${ANCHOR}`]: anchor({ isLive: false, voiceSessionId: null, livekitRoomName: null, serverSessionCleanupId: GENERATION }) });
      for (const uid of [MEMBER, OWNER, ADMIN]) await assertFails(hands(uid));
      await seed({ [`clubs/${ACTIVE}/channels/${SALON}`]: salon(), [`rooms/${ANCHOR}`]: anchor() });
      // A restricted channel needs the current grant for both reads: an admin
      // without one loses the queue and their own document.
      await seed({
        [`clubs/${ACTIVE}/channels/${SALON}`]: salon({ isPrivate: true, accessMode: "restricted",
          accessPolicy: { accessMode: "restricted", roleIds: ["owner"], userIds: [MEMBER, LISTENER] } }),
        [`clubs/${ACTIVE}/channels/${SALON}/accessGrants/${OWNER}`]: grant(ACTIVE, SALON, OWNER),
        [`clubs/${ACTIVE}/channels/${SALON}/accessGrants/${MEMBER}`]: grant(ACTIVE, SALON, MEMBER),
        [`clubs/${ACTIVE}/channels/${SALON}/accessGrants/${LISTENER}`]: grant(ACTIVE, SALON, LISTENER),
      });
      await assertFails(hands(ADMIN));
      await assertFails(read(ADMIN, own(ADMIN)));
      await assertSucceeds(hands(OWNER));
      await assertSucceeds(hands(MEMBER));
      await assertSucceeds(read(LISTENER, own(LISTENER)));
      await seed({ [`clubs/${ACTIVE}/channels/${SALON}`]: salon(),
        [`clubs/${ACTIVE}/channels/${SALON}/accessGrants/${OWNER}`]: null,
        [`clubs/${ACTIVE}/channels/${SALON}/accessGrants/${MEMBER}`]: null,
        [`clubs/${ACTIVE}/channels/${SALON}/accessGrants/${LISTENER}`]: null });
    });
    await check("no client writes a V1 participation document: hand, role, mutes and revision are callable-only", async () => {
      for (const [uid, role] of [[LISTENER, "listener"], [MEMBER, "host"], [ADMIN, "guest"], [OWNER, "listener"]]) {
        const reference = doc(db(uid), own(uid));
        // The legacy self-service shape (mute/hand plus updatedAt) is what
        // roomParticipantSelfUpdateAllowed admits on a legacy room; a V1
        // anchor never reaches it because canAccessRoom() is legacy-gated.
        await assertFails(updateDoc(reference, { isHandRaised: uid !== LISTENER, updatedAt: serverTimestamp() }));
        await assertFails(updateDoc(reference, { isMuted: false, updatedAt: serverTimestamp() }));
        await assertFails(updateDoc(reference, { role: "guest" }));
        await assertFails(updateDoc(reference, { hostMuted: false, serverMuted: false }));
        await assertFails(updateDoc(reference, { authorizationRevision: 99 }));
        await assertFails(setDoc(reference, participant(uid, role)));
        await assertFails(deleteDoc(reference));
      }
      // Neither the legacy self-join create shape nor a V1-shaped create
      // lands under a V1 anchor, for a member or an outsider.
      for (const uid of [OUTSIDER, OWNER]) {
        await assertFails(setDoc(doc(db(uid), own(uid)), { userId: uid, displayName: uid, role: "listener",
          isMuted: true, isSpeaker: false, isHandRaised: false, joinedAt: serverTimestamp(), updatedAt: serverTimestamp() }));
      }
      // A host cannot touch another person's document either.
      await assertFails(updateDoc(doc(db(MEMBER), own(LISTENER)), { role: "guest" }));
      await assertFails(updateDoc(doc(db(MEMBER), own(LISTENER)), { hostMuted: true }));
      // Nothing above changed anything.
      const after = (await assertSucceeds(read(LISTENER, own(LISTENER)))).data();
      assert.equal(after.isHandRaised, true);
      assert.equal(after.role, "listener");
      assert.equal(after.authorizationRevision, 1);
      assert.equal((await assertSucceeds(read(OWNER, own(OWNER)).catch(() => ({ exists: () => false })))).exists(), false);
    });

    await env.withSecurityRulesDisabled(async (ctx) => {
      for (const location of [`clubs/${OWNER}/${HELD}/avatar`, `clubs/${OWNER}/${ACTIVE}/avatar`,
        `clubs/${OWNER}/legacy-public/avatar`, `family_moments/legacy-family/${OWNER}/one.m4a`]) {
        await uploadBytes(ref(ctx.storage(PROJECT), location), new Uint8Array(256), { contentType: "image/jpeg" });
      }
    });
    await check("legacy ordinary artwork remains public and legacy Family media private", async () => {
      await assertSucceeds(getBytes(ref(storage(null), `clubs/${OWNER}/legacy-public/avatar`)));
      await assertSucceeds(getBytes(ref(storage(OWNER), `family_moments/legacy-family/${OWNER}/one.m4a`)));
      await assertFails(getBytes(ref(storage(OUTSIDER), `family_moments/legacy-family/${OWNER}/one.m4a`)));
    });
    await check("held and active V1 artwork cannot use legacy public Storage path", async () => {
      for (const sid of [HELD, ACTIVE]) for (const uid of [null, OWNER, MEMBER, OUTSIDER]) {
        await assertFails(getBytes(ref(storage(uid), `clubs/${OWNER}/${sid}/avatar`)));
      }
      await assertFails(listAll(ref(storage(null), `clubs/${OWNER}/${HELD}`)));
      await assertFails(uploadBytes(ref(storage(OWNER), `clubs/${OWNER}/${HELD}/banner`), new Uint8Array(256), { contentType: "image/jpeg" }));
      await assertFails(uploadBytes(ref(storage(OWNER), `server_media/${HELD}/avatar`), new Uint8Array(256), { contentType: "image/jpeg" }));
    });
  } finally { await env.cleanup(); }
  console.log(`Server rules: ${passed} passed, ${failed} failed.`);
  if (failed) process.exitCode = 1;
}

main().catch((error) => { console.error(error); process.exitCode = 1; });
