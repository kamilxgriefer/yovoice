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
const { deleteObject, getBytes, listAll, ref, uploadBytes } = require("firebase/storage");

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

    await check("Server event listing has its committed scheduled-event composites, including the reminder collection group", async () => {
      const indexes = JSON.parse(fs.readFileSync(
        path.join(__dirname, "../firestore.indexes.json"),
        "utf8",
      )).indexes;
      const eventIndexes = indexes.filter((index) => index.collectionGroup === "events");
      assert.deepEqual(eventIndexes, [
        {
          collectionGroup: "events",
          queryScope: "COLLECTION",
          fields: [
            { fieldPath: "status", order: "ASCENDING" },
            { fieldPath: "startsAt", order: "ASCENDING" },
          ],
        },
        {
          collectionGroup: "events",
          queryScope: "COLLECTION",
          fields: [
            { fieldPath: "status", order: "ASCENDING" },
            { fieldPath: "endsAt", order: "ASCENDING" },
          ],
        },
        // ADR-213: sendServerEventRemindersSchedule queries events ACROSS
        // channels, and a collection-group query needs a COLLECTION_GROUP
        // index — automatic single-field indexes are COLLECTION scope only,
        // and the emulator enforces neither. Declared here and in
        // functions/test/server_event_reminders.test.js, which also runs the
        // real cross-parent query (ADR-007).
        {
          collectionGroup: "events",
          queryScope: "COLLECTION_GROUP",
          fields: [
            { fieldPath: "reminderOptInEnabled", order: "ASCENDING" },
            { fieldPath: "status", order: "ASCENDING" },
            { fieldPath: "startsAt", order: "ASCENDING" },
          ],
        },
      ]);
    });
    await check("Podcast question listing has the committed status plus createdAt composite index", async () => {
      const indexes = JSON.parse(fs.readFileSync(
        path.join(__dirname, "../firestore.indexes.json"),
        "utf8",
      )).indexes;
      const questionIndexes = indexes.filter((index) => index.collectionGroup === "questions");
      assert.deepEqual(questionIndexes, [{
        collectionGroup: "questions",
        queryScope: "COLLECTION",
        fields: [
          { fieldPath: "status", order: "ASCENDING" },
          { fieldPath: "createdAt", order: "DESCENDING" },
        ],
      }]);
    });
    await check("Podcast episode archive, cleanup and Egress worker composites are committed", async () => {
      const indexes = JSON.parse(fs.readFileSync(
        path.join(__dirname, "../firestore.indexes.json"),
        "utf8",
      )).indexes;
      assert.deepEqual(indexes.filter((index) => index.collectionGroup === "episodes"), [
        {
          collectionGroup: "episodes",
          queryScope: "COLLECTION",
          fields: [
            { fieldPath: "status", order: "ASCENDING" },
            { fieldPath: "publishedAt", order: "DESCENDING" },
          ],
        },
        {
          collectionGroup: "episodes",
          queryScope: "COLLECTION_GROUP",
          fields: [
            { fieldPath: "serverId", order: "ASCENDING" },
            { fieldPath: "studioChannelId", order: "ASCENDING" },
          ],
        },
      ]);
      assert.deepEqual(indexes.filter(
        (index) => index.collectionGroup === "serverPodcastEgressJobs",
      ), [{
        collectionGroup: "serverPodcastEgressJobs",
        queryScope: "COLLECTION",
        fields: [
          { fieldPath: "status", order: "ASCENDING" },
          { fieldPath: "nextAttemptAt", order: "ASCENDING" },
        ],
      }]);
    });
    await check("Company whiteboard listing has the committed generation plus sequence composite index", async () => {
      const indexes = JSON.parse(fs.readFileSync(
        path.join(__dirname, "../firestore.indexes.json"),
        "utf8",
      )).indexes;
      const whiteboardIndexes = indexes.filter(
        (index) => index.collectionGroup === "whiteboardStrokes",
      );
      assert.deepEqual(whiteboardIndexes, [{
        collectionGroup: "whiteboardStrokes",
        queryScope: "COLLECTION",
        fields: [
          { fieldPath: "generation", order: "ASCENDING" },
          { fieldPath: "sequence", order: "ASCENDING" },
        ],
      }]);
    });
    await check("Family Memory listing has the committed channel, status and createdAt composite index", async () => {
      const indexes = JSON.parse(fs.readFileSync(
        path.join(__dirname, "../firestore.indexes.json"),
        "utf8",
      )).indexes;
      const memoryIndexes = indexes.filter((index) => index.collectionGroup === "moments");
      assert.deepEqual(memoryIndexes, [{
        collectionGroup: "moments",
        queryScope: "COLLECTION",
        fields: [
          { fieldPath: "channelId", order: "ASCENDING" },
          { fieldPath: "status", order: "ASCENDING" },
          { fieldPath: "createdAt", order: "DESCENDING" },
        ],
      }]);
    });

    await check("legacy public GET and broad legacy channel query remain available", async () => {
      await assertSucceeds(read(OUTSIDER, "clubs/legacy-public"));
      await assertSucceeds(getDocs(query(collection(db(OWNER), "clubs/legacy-public/channels"), orderBy("position"))));
    });

    // THE OLD-CLIENT GATE, measured rather than assumed.
    //
    // ClubService.watchChannels() issues a bare orderBy('position') with no
    // equality filters. The migrated fixture below is the EXACT post-image
    // functions/servers/migration_apply.js writes, with the activation pair
    // set to active/active so that what is being measured is the QUERY SHAPE
    // and nothing else. Note what the fixture deliberately does NOT contain:
    // a restricted channel. The folklore says the old query breaks "once a
    // channel collection holds restricted documents"; it breaks the moment the
    // ROOT carries a server marker, because isLegacyClub() reads the root.
    const MIGRATED = "gate-migrated";
    const migratedChannel = (position, name, kind, type, changes = {}) => ({
      serverSchemaVersion: 1, serverId: MIGRATED, kind, name, type, position,
      isPrivate: false, accessMode: "members",
      accessPolicy: { accessMode: "members", roleIds: [], userIds: [] },
      categoryId: null, status: "active", roomId: null, activeSessionId: null,
      liveness: idle(), experience: null, mediaMode: null, aclRevision: 1, revision: 1,
      historySource: { kind: "channelMessages" }, createdBy: OWNER, createdAt: new Date(0), ...changes,
    });
    await seed({
      [`clubs/${MIGRATED}`]: {
        serverSchemaVersion: 1, serverType: "community", templateVersion: 1,
        entitlementPolicyId: "legacyCommunityPremiumV1", serverActivationState: "active",
        status: "active", revision: 1, type: "community", ownerId: OWNER, ownerName: OWNER,
        name: "Migrated", description: "", privacy: "public", avatarUrl: null, bannerUrl: null,
        defaultLanguage: "English", memberCount: 2, onlineCount: 0,
        migration: { version: 1, sourceKind: "club", sourceId: MIGRATED, state: "complete" },
      },
      [`clubs/${MIGRATED}/members/${OWNER}`]: member(OWNER, "owner"),
      [`clubs/${MIGRATED}/members/${MEMBER}`]: member(MEMBER, "member"),
      [`clubs/${MIGRATED}/channels/general`]: migratedChannel(0, "general", "text", "chat"),
      [`clubs/${MIGRATED}/channels/announcements`]: migratedChannel(1, "announcements", "announcements", "announcement"),
      // The legacy twin: identical channels, root NOT versioned.
      [`clubs/gate-legacy`]: { type: "community", privacy: "public", status: "active",
        ownerId: OWNER, name: "Legacy twin", memberCount: 2, onlineCount: 0 },
      [`clubs/gate-legacy/members/${OWNER}`]: member(OWNER, "owner"),
      [`clubs/gate-legacy/members/${MEMBER}`]: member(MEMBER, "member"),
      [`clubs/gate-legacy/channels/general`]: { name: "general", type: "chat", position: 0, isPrivate: false },
      [`clubs/gate-legacy/channels/announcements`]: { name: "announcements", type: "announcement", position: 1, isPrivate: false },
    });
    const bareChannelQuery = (uid, sid) =>
      getDocs(query(collection(db(uid), `clubs/${sid}/channels`), orderBy("position")));

    await check("old-client gate: the installed bare orderBy(position) query dies on a migrated root with NO restricted channel", async () => {
      // The legacy twin still answers, for owner and ordinary member alike.
      await assertSucceeds(bareChannelQuery(OWNER, "gate-legacy"));
      await assertSucceeds(bareChannelQuery(MEMBER, "gate-legacy"));
      // The migrated root denies the same query WHOLESALE — not a shorter list.
      await assertFails(bareChannelQuery(OWNER, MIGRATED));
      await assertFails(bareChannelQuery(MEMBER, MIGRATED));
      // Rules are not filters: pinning only ONE of the two equalities is still
      // the whole query denied.
      await assertFails(getDocs(query(collection(db(MEMBER), `clubs/${MIGRATED}/channels`),
        where("accessMode", "==", "members"), orderBy("position"))));
      await assertFails(getDocs(query(collection(db(MEMBER), `clubs/${MIGRATED}/channels`),
        where("status", "==", "active"), orderBy("position"))));
      // The compatible client's pinned query is the one that works, and it
      // needs BOTH equalities plus membership.
      const pinned = await assertSucceeds(directory(MEMBER, MIGRATED));
      assert.deepEqual(pinned.docs.map((item) => item.id).sort(), ["announcements", "general"]);
      await assertFails(directory(OUTSIDER, MIGRATED));
    });

    await check("old-client gate: adding a restricted channel changes nothing about the denial and nothing about the pinned query", async () => {
      await seed({ [`clubs/${MIGRATED}/channels/hr`]: migratedChannel(2, "HR", "text", "chat", {
        isPrivate: true, accessMode: "restricted",
        accessPolicy: { accessMode: "restricted", roleIds: ["owner"], userIds: [] },
      }) });
      await assertFails(bareChannelQuery(OWNER, MIGRATED));
      await assertFails(bareChannelQuery(MEMBER, MIGRATED));
      const pinned = await assertSucceeds(directory(MEMBER, MIGRATED));
      assert.equal(pinned.docs.some((item) => item.id === "hr"), false);
      await seed({ [`clubs/${MIGRATED}/channels/hr`]: null });
    });

    await check("old-client gate: a migrated root that is still HELD is owner-only, which is why activation is its own step", async () => {
      await seed({ [`clubs/${MIGRATED}`]: {
        serverSchemaVersion: 1, serverType: "community", templateVersion: 1,
        entitlementPolicyId: "legacyCommunityPremiumV1", serverActivationState: "held",
        status: "preparing", revision: 1, type: "community", ownerId: OWNER, ownerName: OWNER,
        name: "Migrated", description: "", privacy: "public", avatarUrl: null, bannerUrl: null,
        defaultLanguage: "English", memberCount: 2, onlineCount: 0,
        migration: { version: 1, sourceKind: "club", sourceId: MIGRATED, state: "complete" },
      } });
      await assertSucceeds(read(OWNER, `clubs/${MIGRATED}`));
      await assertSucceeds(directory(OWNER, MIGRATED));
      for (const uid of [MEMBER, OUTSIDER]) {
        await assertFails(read(uid, `clubs/${MIGRATED}`));
        await assertFails(directory(uid, MIGRATED));
        await assertFails(bareChannelQuery(uid, MIGRATED));
      }
    });

    await check("the published client gate is world-readable to a signed-in caller and writable by nobody", async () => {
      const gatePath = "serverMigrationGates/clientCompatibilityV1";
      await seed({ [gatePath]: { schemaVersion: 1, gateId: "clientCompatibilityV1",
        minimumClientVersion: "1.9.0", minimumClientBuild: 42,
        platformMinimumBuild: { android: 42, ios: 42, web: 42, macos: 42, windows: 42, linux: 42 },
        status: "open", attestedBy: null, attestedAt: null, revision: 1, updatedAt: new Date(0) } });
      for (const uid of [OWNER, MEMBER, OUTSIDER, BANNED]) {
        const gate = await assertSucceeds(read(uid, gatePath));
        assert.equal(gate.data().minimumClientBuild, 42);
      }
      for (const uid of [OWNER, MEMBER, OUTSIDER]) {
        await assertFails(updateDoc(doc(db(uid), gatePath), { status: "satisfied" }));
        await assertFails(updateDoc(doc(db(uid), gatePath), { minimumClientBuild: 1 }));
        await assertFails(setDoc(doc(db(uid), gatePath), { schemaVersion: 1 }));
        await assertFails(deleteDoc(doc(db(uid), gatePath)));
        await assertFails(setDoc(doc(db(uid), "serverMigrationGates/forged"), { schemaVersion: 1 }));
      }
      // The gate is still exactly what the server published.
      const after = await assertSucceeds(read(OUTSIDER, gatePath));
      assert.equal(after.data().status, "open");
      assert.equal(after.data().revision, 1);
    });

    await check("the migration run ledger is invisible and unwritable from every client", async () => {
      await seed({ "serverMigrationRuns/run-1": { schemaVersion: 1, runId: "run-1", status: "completed" },
        "serverMigrationRuns/run-1/rootSteps/club_gate-migrated": { schemaVersion: 1, stage: "complete" } });
      for (const uid of [OWNER, MEMBER, OUTSIDER]) {
        await assertFails(read(uid, "serverMigrationRuns/run-1"));
        await assertFails(read(uid, "serverMigrationRuns/run-1/rootSteps/club_gate-migrated"));
        await assertFails(getDocs(collection(db(uid), "serverMigrationRuns")));
        await assertFails(setDoc(doc(db(uid), "serverMigrationRuns/forged"), { schemaVersion: 1 }));
        await assertFails(updateDoc(doc(db(uid), "serverMigrationRuns/run-1"), { status: "open" }));
        await assertFails(deleteDoc(doc(db(uid), "serverMigrationRuns/run-1")));
      }
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
    await check("Servers V1 admission closes the legacy Family quota bypass at Free 5 and Premium 30", async () => {
      const freeUid = "legacy-family-free-at-five";
      const premiumUid = "legacy-family-premium-at-thirty";
      const legacyUid = "legacy-family-not-admitted";
      const entries = {
        [`users/${freeUid}`]: { displayName: freeUid, banned: false, disabled: false },
        [`users/${premiumUid}`]: { displayName: premiumUid, banned: false, disabled: false },
        [`users/${legacyUid}`]: { displayName: legacyUid, banned: false, disabled: false },
        "appConfig/serversV1": {
          schemaVersion: 1, callableAccess: "testers",
          testerUids: [freeUid, premiumUid], workersEnabled: true, revision: 1,
        },
        [`entitlements/${premiumUid}`]: {
          schemaVersion: 1, userId: premiumUid, plan: "premium",
          status: "active", isPremium: true,
          currentPeriodEnd: new Date("2099-01-01T00:00:00Z"),
        },
      };
      for (let index = 0; index < 5; index += 1) {
        entries[`clubs/free-owned-${index}`] = server(`free-owned-${index}`, {
          ownerId: freeUid, entitlementPolicyId: "freeServersV1",
        });
      }
      for (let index = 0; index < 30; index += 1) {
        entries[`clubs/premium-owned-${index}`] = server(`premium-owned-${index}`, {
          ownerId: premiumUid, entitlementPolicyId: "freeServersV1",
        });
      }
      await seed(entries);

      await assertFails(legacyFamilyGraph(db(freeUid), freeUid).batch.commit());
      await assertFails(legacyFamilyGraph(db(premiumUid), premiumUid).batch.commit());
      await assertSucceeds(legacyFamilyGraph(db(legacyUid), legacyUid).batch.commit());

      await assertFails(read(freeUid, "appConfig/serversV1"));
      await assertFails(setDoc(doc(db(freeUid), "appConfig/serversV1"), {
        ...entries["appConfig/serversV1"], callableAccess: "disabled",
      }));
    });
    await check("a malformed Servers V1 activation document fails legacy Family creation closed", async () => {
      const uid = "legacy-family-malformed-activation";
      await seed({ [`users/${uid}`]: { displayName: uid, banned: false, disabled: false } });
      for (const malformed of [
        { schemaVersion: 2, callableAccess: "testers", testerUids: [], workersEnabled: false, revision: 1 },
        { schemaVersion: 1, callableAccess: "testers", testerUids: ["duplicate", "duplicate"], workersEnabled: false, revision: 1 },
      ]) {
        await seed({ "appConfig/serversV1": malformed });
        await assertFails(legacyFamilyGraph(db(uid), uid).batch.commit());
      }
      await seed({ "appConfig/serversV1": {
        schemaVersion: 1, callableAccess: "testers",
        testerUids: [], workersEnabled: true, revision: 2,
      } });
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
    await check("all Server event profiles inherit exact channel ACLs and remain server-written", async () => {
      const profiles = [
        ["rules-event-friends", "friends", "events", "friendsEvent", false],
        ["rules-event-community", "community", "events", "communityEvent", false],
        ["rules-event-family", "family", "calendar", "familyCalendarEvent", true],
        ["rules-event-podcast", "podcast", "events", "podcastProgramEvent", true],
      ];
      const event = (serverId, channelId, eventId, eventKind, reminderEnabled) => ({
        schemaVersion: 1, serverId, channelId, eventId, eventKind,
        serverType: profiles.find(([id]) => id === serverId)[1], channelKind: channelId,
        rsvpEnabled: true, reminderOptInEnabled: reminderEnabled, reminderCount: 1,
        title: "Dinner", description: "At seven",
        startsAt: new Date(Date.now() + 60_000), endsAt: new Date(Date.now() + 120_000),
        timeZone: "Europe/Amsterdam", status: "scheduled",
        responseCounts: { going: 1, maybe: 0, declined: 0 },
        authorId: OWNER, revision: 1, createdAt: new Date(0), updatedAt: new Date(0),
      });
      const response = (serverId, channelId, eventId, reminderEnabled) => ({
        schemaVersion: 1, serverId, channelId, eventId,
        userId: MEMBER, response: "going", reminderRequested: reminderEnabled,
        eventRevision: 1, operationId: "a".repeat(64),
        createdAt: new Date(0), updatedAt: new Date(0),
      });
      const entries = {};
      const cleanup = {};
      for (const [serverId, serverType, channelKind, eventKind, reminderEnabled] of profiles) {
        const eventId = `event-${serverType}`;
        const eventPath = `clubs/${serverId}/channels/${channelKind}/events/${eventId}`;
        const responsePath = `${eventPath}/responses/${MEMBER}`;
        entries[`clubs/${serverId}`] = server(serverId, {
          serverType,
          type: serverType === "family" ? "family" : "community",
          privacy: serverType === "community" ? "public" : "inviteOnly",
        });
        entries[`clubs/${serverId}/members/${OWNER}`] = member(OWNER, "owner");
        entries[`clubs/${serverId}/members/${MEMBER}`] = member(MEMBER);
        entries[`clubs/${serverId}/members/${ADMIN}`] = member(ADMIN, "admin");
        entries[`clubs/${serverId}/channels/${channelKind}`] = channel(serverId, false, {
          kind: channelKind, name: `${serverType} module`,
        });
        entries[eventPath] = event(serverId, channelKind, eventId, eventKind, reminderEnabled);
        entries[responsePath] = response(serverId, channelKind, eventId, reminderEnabled);
        for (const location of Object.keys(entries)) cleanup[location] = null;
      }
      const restrictedServer = "rules-event-restricted";
      const restrictedEvent = `clubs/${restrictedServer}/channels/events/events/event-private`;
      const restrictedResponse = `${restrictedEvent}/responses/${MEMBER}`;
      entries[`clubs/${restrictedServer}`] = server(restrictedServer, { serverType: "friends" });
      entries[`clubs/${restrictedServer}/members/${OWNER}`] = member(OWNER, "owner");
      entries[`clubs/${restrictedServer}/members/${MEMBER}`] = member(MEMBER);
      entries[`clubs/${restrictedServer}/members/${ADMIN}`] = member(ADMIN, "admin");
      entries[`clubs/${restrictedServer}/channels/events`] = channel(restrictedServer, true, {
        kind: "events", name: "Restricted events",
      });
      entries[`clubs/${restrictedServer}/channels/events/accessGrants/${OWNER}`] =
        grant(restrictedServer, "events", OWNER);
      entries[`clubs/${restrictedServer}/channels/events/accessGrants/${MEMBER}`] =
        grant(restrictedServer, "events", MEMBER);
      entries[restrictedEvent] = {
        ...event(profiles[0][0], "events", "event-private", "friendsEvent", false),
        serverId: restrictedServer,
      };
      entries[restrictedResponse] = response(restrictedServer, "events", "event-private", false);

      const heldServer = "rules-event-held";
      const heldEvent = `clubs/${heldServer}/channels/events/events/event-held`;
      entries[`clubs/${heldServer}`] = server(heldServer, {
        held: true, serverType: "friends",
      });
      entries[`clubs/${heldServer}/members/${OWNER}`] = member(OWNER, "owner");
      entries[`clubs/${heldServer}/channels/events`] = channel(heldServer, false, { kind: "events" });
      entries[heldEvent] = {
        ...event(profiles[0][0], "events", "event-held", "friendsEvent", false),
        serverId: heldServer,
      };
      for (const location of Object.keys(entries)) cleanup[location] = null;
      await seed(entries);

      for (const [serverId, serverType, channelKind] of profiles) {
        const eventId = `event-${serverType}`;
        const eventPath = `clubs/${serverId}/channels/${channelKind}/events/${eventId}`;
        const responsePath = `${eventPath}/responses/${MEMBER}`;
        await assertSucceeds(read(MEMBER, eventPath));
        await assertSucceeds(read(MEMBER, responsePath));
        const scheduled = await assertSucceeds(getDocs(query(
          collection(db(MEMBER), `clubs/${serverId}/channels/${channelKind}/events`),
          where("status", "==", "scheduled"), orderBy("startsAt"),
        )));
        assert.deepEqual(scheduled.docs.map((item) => item.id), [eventId]);
        await assertFails(read(OUTSIDER, eventPath));
        await assertFails(read(OUTSIDER, responsePath));
        for (const uid of [OWNER, MEMBER, ADMIN, OUTSIDER]) {
          await assertFails(setDoc(doc(db(uid), eventPath), entries[eventPath]));
          await assertFails(updateDoc(doc(db(uid), eventPath), { title: "Forged" }));
          await assertFails(deleteDoc(doc(db(uid), eventPath)));
          await assertFails(setDoc(doc(db(uid), responsePath), entries[responsePath]));
          await assertFails(updateDoc(doc(db(uid), responsePath), { response: "declined" }));
          await assertFails(deleteDoc(doc(db(uid), responsePath)));
        }
      }

      // Restricted content needs the same current grant as the channel.
      await assertSucceeds(read(MEMBER, restrictedEvent));
      await assertSucceeds(read(MEMBER, restrictedResponse));
      await assertFails(read(ADMIN, restrictedEvent));
      await assertFails(read(ADMIN, restrictedResponse));
      // Preparation metadata never opens module content, even to its owner.
      await assertFails(read(OWNER, heldEvent));

      await seed(cleanup);
    });
    await check("Podcast questions inherit channel ACLs while each member sees only their own vote", async () => {
      const podcastId = "rules-podcast-questions";
      const restrictedId = "rules-podcast-questions-restricted";
      const heldId = "rules-podcast-questions-held";
      const question = (serverId, questionId, status = "queued") => ({
        schemaVersion: 1,
        serverId,
        channelId: "questions",
        questionId,
        questionKind: "podcastQuestion",
        authorId: MEMBER,
        authorName: MEMBER,
        body: "How did you choose the guest?",
        status,
        voteCount: 1,
        revision: 1,
        onAirAt: status === "onAir" ? new Date(0) : null,
        onAirById: status === "onAir" ? OWNER : null,
        createdAt: new Date(0),
        updatedAt: new Date(0),
      });
      const vote = (serverId, questionId, uid) => ({
        schemaVersion: 1,
        serverId,
        channelId: "questions",
        questionId,
        userId: uid,
        active: true,
        questionRevision: 1,
        operationId: "b".repeat(64),
        createdAt: new Date(0),
        updatedAt: new Date(0),
      });
      const ordinaryQuestion = `clubs/${podcastId}/channels/questions/questions/question-one`;
      const restrictedQuestion = `clubs/${restrictedId}/channels/questions/questions/question-private`;
      const heldQuestion = `clubs/${heldId}/channels/questions/questions/question-held`;
      const entries = {
        [`clubs/${podcastId}`]: server(podcastId, {
          serverType: "podcast", privacy: "inviteOnly",
        }),
        [`clubs/${podcastId}/members/${OWNER}`]: member(OWNER, "owner"),
        [`clubs/${podcastId}/members/${MEMBER}`]: member(MEMBER),
        [`clubs/${podcastId}/members/${ADMIN}`]: member(ADMIN, "admin"),
        [`clubs/${podcastId}/channels/questions`]: channel(podcastId, false, {
          kind: "questions", name: "Listener questions",
        }),
        [ordinaryQuestion]: question(podcastId, "question-one", "onAir"),
        [`${ordinaryQuestion}/votes/${OWNER}`]: vote(podcastId, "question-one", OWNER),
        [`${ordinaryQuestion}/votes/${MEMBER}`]: vote(podcastId, "question-one", MEMBER),
        [`${ordinaryQuestion}/votes/${ADMIN}`]: vote(podcastId, "question-one", ADMIN),
        [`${ordinaryQuestion}/votes/${OUTSIDER}`]: vote(podcastId, "question-one", OUTSIDER),

        [`clubs/${restrictedId}`]: server(restrictedId, {
          serverType: "podcast", privacy: "inviteOnly",
        }),
        [`clubs/${restrictedId}/members/${OWNER}`]: member(OWNER, "owner"),
        [`clubs/${restrictedId}/members/${MEMBER}`]: member(MEMBER),
        [`clubs/${restrictedId}/members/${ADMIN}`]: member(ADMIN, "admin"),
        [`clubs/${restrictedId}/channels/questions`]: channel(restrictedId, true, {
          kind: "questions", name: "Private questions",
        }),
        [`clubs/${restrictedId}/channels/questions/accessGrants/${OWNER}`]:
          grant(restrictedId, "questions", OWNER),
        [`clubs/${restrictedId}/channels/questions/accessGrants/${MEMBER}`]:
          grant(restrictedId, "questions", MEMBER),
        [restrictedQuestion]: question(restrictedId, "question-private"),
        [`${restrictedQuestion}/votes/${MEMBER}`]: vote(restrictedId, "question-private", MEMBER),

        [`clubs/${heldId}`]: server(heldId, {
          held: true, serverType: "podcast", privacy: "inviteOnly",
        }),
        [`clubs/${heldId}/members/${OWNER}`]: member(OWNER, "owner"),
        [`clubs/${heldId}/channels/questions`]: channel(heldId, false, {
          kind: "questions", name: "Held questions",
        }),
        [heldQuestion]: question(heldId, "question-held"),
      };
      await seed(entries);

      await assertSucceeds(read(MEMBER, ordinaryQuestion));
      const visible = await assertSucceeds(getDocs(query(
        collection(db(MEMBER), `clubs/${podcastId}/channels/questions/questions`),
        where("status", "in", ["queued", "onAir"]), orderBy("createdAt", "desc"),
      )));
      assert.deepEqual(visible.docs.map((row) => row.id), ["question-one"]);
      await assertFails(read(OUTSIDER, ordinaryQuestion));
      await assertSucceeds(read(MEMBER, `${ordinaryQuestion}/votes/${MEMBER}`));
      await assertFails(read(MEMBER, `${ordinaryQuestion}/votes/${ADMIN}`));
      await assertSucceeds(read(ADMIN, `${ordinaryQuestion}/votes/${ADMIN}`));
      await assertFails(getDocs(collection(db(MEMBER), `${ordinaryQuestion}/votes`)));

      // Restricted questions need the same current grant as the channel.
      await assertSucceeds(read(MEMBER, restrictedQuestion));
      await assertSucceeds(read(MEMBER, `${restrictedQuestion}/votes/${MEMBER}`));
      await assertFails(read(ADMIN, restrictedQuestion));
      await assertFails(read(ADMIN, `${restrictedQuestion}/votes/${MEMBER}`));
      // A held root exposes neither questions nor votes, including to owner.
      await assertFails(read(OWNER, heldQuestion));

      for (const uid of [OWNER, MEMBER, ADMIN, OUTSIDER]) {
        await assertFails(setDoc(doc(db(uid), ordinaryQuestion), question(podcastId, "question-one")));
        await assertFails(updateDoc(doc(db(uid), ordinaryQuestion), { status: "queued" }));
        await assertFails(deleteDoc(doc(db(uid), ordinaryQuestion)));
        const ownVote = `${ordinaryQuestion}/votes/${uid}`;
        await assertFails(setDoc(doc(db(uid), ownVote), vote(podcastId, "question-one", uid)));
        await assertFails(updateDoc(doc(db(uid), ownVote), { active: false }));
        await assertFails(deleteDoc(doc(db(uid), ownVote)));
      }

      await seed(Object.fromEntries(Object.keys(entries).map((location) => [location, null])));
    });
    await check("Podcast recording state is moderator-only while members list only published canonical episodes", async () => {
      const podcastId = "rules-podcast-episodes";
      const heldId = "rules-podcast-episodes-held";
      const publishedId = "episode-published";
      const readyId = "episode-ready";
      const episode = (serverId, episodeId, status) => ({
        schemaVersion: 1,
        episodeKind: "podcastEpisode",
        serverId,
        clubId: serverId,
        channelId: "episodes",
        studioChannelId: "studio",
        episodeId,
        sessionId: `session-${episodeId}`,
        livekitRoomName: `srv_${episodeId}`,
        title: status === "published" ? "Published show" : "Moderator preview",
        status,
        revision: status === "published" ? 4 : 3,
        createdById: OWNER,
        createdByName: OWNER,
        egressId: `egress-${episodeId}`,
        outputPath: `server_podcast_episodes/${serverId}/episodes/${episodeId}.mp3`,
        providerStatus: "complete",
        media: {
          storagePath: `server_podcast_episodes/${serverId}/episodes/${episodeId}.mp3`,
          generation: "501",
          contentType: "audio/mpeg",
          size: 4096,
          durationMillis: 60_000,
        },
        failureCode: null,
        createdAt: new Date(0),
        updatedAt: new Date(0),
        stoppedAt: new Date(0),
        readyAt: new Date(0),
        publishedAt: status === "published" ? new Date(0) : null,
        publishedById: status === "published" ? OWNER : null,
      });
      const state = (serverId) => ({
        schemaVersion: 1,
        kind: "podcastRecordingState",
        serverId,
        studioChannelId: "studio",
        channelId: "episodes",
        episodeId: readyId,
        sessionId: `session-${readyId}`,
        title: "Moderator preview",
        status: "ready",
        providerStatus: "complete",
        episodeRevision: 3,
        updatedAt: new Date(0),
      });
      const publishedPath =
        `clubs/${podcastId}/channels/episodes/episodes/${publishedId}`;
      const readyPath = `clubs/${podcastId}/channels/episodes/episodes/${readyId}`;
      const statePath =
        `clubs/${podcastId}/channels/studio/podcastRecordingState/main`;
      const heldPublishedPath =
        `clubs/${heldId}/channels/episodes/episodes/${publishedId}`;
      const entries = {
        [`clubs/${podcastId}`]: server(podcastId, {
          serverType: "podcast", privacy: "inviteOnly",
        }),
        [`clubs/${podcastId}/members/${OWNER}`]: member(OWNER, "owner"),
        [`clubs/${podcastId}/members/${MEMBER}`]: member(MEMBER),
        [`clubs/${podcastId}/members/${ADMIN}`]: member(ADMIN, "admin"),
        [`clubs/${podcastId}/channels/studio`]: channel(podcastId, false, {
          kind: "stage", name: "Studio", experience: "broadcast", mediaMode: "audio",
        }),
        [`clubs/${podcastId}/channels/episodes`]: channel(podcastId, false, {
          kind: "episodes", name: "Episodes",
        }),
        [publishedPath]: episode(podcastId, publishedId, "published"),
        [readyPath]: episode(podcastId, readyId, "ready"),
        [statePath]: state(podcastId),
        [`serverPodcastEgressJobs/${readyId}`]: {
          schemaVersion: 1, kind: "podcastEgressJob", serverId: podcastId,
        },
        [`clubs/${heldId}`]: server(heldId, {
          held: true, serverType: "podcast", privacy: "inviteOnly",
        }),
        [`clubs/${heldId}/members/${OWNER}`]: member(OWNER, "owner"),
        [`clubs/${heldId}/channels/episodes`]: channel(heldId, false, {
          kind: "episodes", name: "Episodes",
        }),
        [heldPublishedPath]: episode(heldId, publishedId, "published"),
      };
      await seed(entries);

      await assertSucceeds(read(MEMBER, publishedPath));
      await assertFails(read(MEMBER, readyPath));
      await assertFails(read(MEMBER, statePath));
      const memberArchive = await assertSucceeds(getDocs(query(
        collection(db(MEMBER), `clubs/${podcastId}/channels/episodes/episodes`),
        where("status", "==", "published"),
        orderBy("publishedAt", "desc"),
      )));
      assert.deepEqual(memberArchive.docs.map((row) => row.id), [publishedId]);
      await assertFails(getDocs(query(
        collection(db(MEMBER), `clubs/${podcastId}/channels/episodes/episodes`),
        orderBy("createdAt", "desc"),
      )));

      await assertSucceeds(read(ADMIN, publishedPath));
      await assertSucceeds(read(ADMIN, readyPath));
      await assertSucceeds(read(ADMIN, statePath));
      const moderatorArchive = await assertSucceeds(getDocs(query(
        collection(db(ADMIN), `clubs/${podcastId}/channels/episodes/episodes`),
        orderBy("createdAt", "desc"),
      )));
      assert.deepEqual(new Set(moderatorArchive.docs.map((row) => row.id)),
        new Set([publishedId, readyId]));
      for (const pathValue of [publishedPath, readyPath, statePath,
        `serverPodcastEgressJobs/${readyId}`]) {
        await assertFails(read(OUTSIDER, pathValue));
        await assertFails(read(MEMBER, pathValue === publishedPath ?
          `serverPodcastEgressJobs/${readyId}` : pathValue));
      }
      await assertFails(read(OWNER, heldPublishedPath));

      for (const uid of [OWNER, MEMBER, ADMIN, OUTSIDER]) {
        await assertFails(setDoc(doc(db(uid), publishedPath),
          episode(podcastId, publishedId, "published")));
        await assertFails(updateDoc(doc(db(uid), publishedPath), { title: "Forged" }));
        await assertFails(deleteDoc(doc(db(uid), publishedPath)));
        await assertFails(setDoc(doc(db(uid), statePath), state(podcastId)));
        await assertFails(deleteDoc(doc(db(uid), statePath)));
        await assertFails(setDoc(doc(db(uid), `serverPodcastEgressJobs/forged-${uid}`), {
          schemaVersion: 1, kind: "podcastEgressJob", serverId: podcastId,
        }));
      }

      const corruptPath = `clubs/${podcastId}/channels/episodes/episodes/corrupt`;
      await seed({ [corruptPath]: {
        ...episode(podcastId, "corrupt", "published"),
        outputPath: "server_podcast_episodes/another/path.mp3",
      } });
      await assertFails(read(MEMBER, corruptPath));
      await assertFails(read(ADMIN, corruptPath));

      await seed(Object.fromEntries(Object.keys(entries)
        .concat(corruptPath).map((location) => [location, null])));
    });
    await check("Family shared-list rows inherit the channel ACL and remain server-written", async () => {
      const familyId = "rules-family-list";
      const heldFamilyId = "rules-family-list-held";
      const itemPath = `clubs/${familyId}/channels/list/listItems/item-one`;
      const heldItemPath = `clubs/${heldFamilyId}/channels/list/listItems/item-held`;
      const item = (serverId, itemId) => ({
        schemaVersion: 1,
        serverId,
        channelId: "list",
        itemId,
        text: "Milk",
        checked: false,
        checkedById: null,
        createdById: MEMBER,
        revision: 1,
        createdAt: new Date(0),
        updatedAt: new Date(0),
      });
      const entries = {
        [`clubs/${familyId}`]: server(familyId, {
          serverType: "family", type: "family", privacy: "inviteOnly",
        }),
        [`clubs/${familyId}/members/${OWNER}`]: member(OWNER, "owner"),
        [`clubs/${familyId}/members/${MEMBER}`]: member(MEMBER),
        [`clubs/${familyId}/members/${ADMIN}`]: member(ADMIN, "admin"),
        [`clubs/${familyId}/channels/list`]: channel(familyId, false, {
          kind: "list", name: "Shopping list",
        }),
        [itemPath]: item(familyId, "item-one"),
        [`clubs/${heldFamilyId}`]: server(heldFamilyId, {
          held: true, serverType: "family", type: "family", privacy: "inviteOnly",
        }),
        [`clubs/${heldFamilyId}/members/${OWNER}`]: member(OWNER, "owner"),
        [`clubs/${heldFamilyId}/channels/list`]: channel(heldFamilyId, false, {
          kind: "list", name: "Shopping list",
        }),
        [heldItemPath]: item(heldFamilyId, "item-held"),
      };
      await seed(entries);

      await assertSucceeds(read(MEMBER, itemPath));
      const visible = await assertSucceeds(getDocs(
        collection(db(MEMBER), `clubs/${familyId}/channels/list/listItems`),
      ));
      assert.deepEqual(visible.docs.map((row) => row.id), ["item-one"]);
      await assertFails(read(OUTSIDER, itemPath));
      await assertFails(read(OWNER, heldItemPath));
      for (const uid of [OWNER, MEMBER, ADMIN, OUTSIDER]) {
        await assertFails(setDoc(doc(db(uid), itemPath), item(familyId, "item-one")));
        await assertFails(updateDoc(doc(db(uid), itemPath), { checked: true }));
        await assertFails(deleteDoc(doc(db(uid), itemPath)));
      }

      await seed(Object.fromEntries(Object.keys(entries).map((location) => [location, null])));
    });
    await check("Company whiteboards inherit their channel ACL and every mutation stays callable-owned", async () => {
      const companyId = "rules-company-whiteboard";
      const restrictedId = "rules-company-whiteboard-private";
      const heldId = "rules-company-whiteboard-held";
      const state = (serverId) => ({
        schemaVersion: 1,
        serverId,
        channelId: "whiteboard",
        stateId: "main",
        generation: 1,
        revision: 1,
        strokeCount: 1,
        nextSequence: 2,
        clearedAt: null,
        clearedById: null,
        updatedAt: new Date(0),
      });
      const stroke = (serverId, strokeId) => ({
        schemaVersion: 1,
        serverId,
        channelId: "whiteboard",
        strokeId,
        strokeKind: "polyline",
        authorId: MEMBER,
        generation: 1,
        sequence: 1,
        revision: 1,
        color: "blue",
        lineWidth: 5,
        points: [{ x: .1, y: .2 }, { x: .8, y: .7 }],
        createdAt: new Date(0),
      });
      const ordinaryState =
        `clubs/${companyId}/channels/whiteboard/whiteboardState/main`;
      const ordinaryStroke =
        `clubs/${companyId}/channels/whiteboard/whiteboardStrokes/stroke-one`;
      const restrictedState =
        `clubs/${restrictedId}/channels/whiteboard/whiteboardState/main`;
      const restrictedStroke =
        `clubs/${restrictedId}/channels/whiteboard/whiteboardStrokes/stroke-private`;
      const heldState =
        `clubs/${heldId}/channels/whiteboard/whiteboardState/main`;
      const entries = {
        [`clubs/${companyId}`]: server(companyId),
        [`clubs/${companyId}/members/${OWNER}`]: member(OWNER, "owner"),
        [`clubs/${companyId}/members/${MEMBER}`]: member(MEMBER),
        [`clubs/${companyId}/channels/whiteboard`]: channel(companyId, false, {
          kind: "whiteboard", name: "Whiteboard",
        }),
        [ordinaryState]: state(companyId),
        [ordinaryStroke]: stroke(companyId, "stroke-one"),

        [`clubs/${restrictedId}`]: server(restrictedId),
        [`clubs/${restrictedId}/members/${OWNER}`]: member(OWNER, "owner"),
        [`clubs/${restrictedId}/members/${MEMBER}`]: member(MEMBER),
        [`clubs/${restrictedId}/members/${ADMIN}`]: member(ADMIN, "admin"),
        [`clubs/${restrictedId}/channels/whiteboard`]: channel(restrictedId, true, {
          kind: "whiteboard", name: "Private whiteboard",
        }),
        [`clubs/${restrictedId}/channels/whiteboard/accessGrants/${MEMBER}`]:
          grant(restrictedId, "whiteboard", MEMBER),
        [restrictedState]: state(restrictedId),
        [restrictedStroke]: stroke(restrictedId, "stroke-private"),

        [`clubs/${heldId}`]: server(heldId, { held: true }),
        [`clubs/${heldId}/members/${OWNER}`]: member(OWNER, "owner"),
        [`clubs/${heldId}/channels/whiteboard`]: channel(heldId, false, {
          kind: "whiteboard", name: "Held whiteboard",
        }),
        [heldState]: state(heldId),
      };
      await seed(entries);

      await assertSucceeds(read(MEMBER, ordinaryState));
      await assertSucceeds(read(MEMBER, ordinaryStroke));
      const visible = await assertSucceeds(getDocs(query(
        collection(db(MEMBER), `clubs/${companyId}/channels/whiteboard/whiteboardStrokes`),
        where("generation", "==", 1),
        orderBy("sequence"),
      )));
      assert.deepEqual(visible.docs.map((row) => row.id), ["stroke-one"]);
      await assertFails(read(OUTSIDER, ordinaryState));
      await assertFails(read(OUTSIDER, ordinaryStroke));

      await assertSucceeds(read(MEMBER, restrictedState));
      await assertSucceeds(read(MEMBER, restrictedStroke));
      await assertFails(read(ADMIN, restrictedState));
      await assertFails(read(ADMIN, restrictedStroke));
      await assertFails(read(OWNER, heldState));

      // Ephemeral motion moved to the active LiveKit data plane. The retired
      // Firestore path has no client read or write rule at all.
      const retiredDraft =
        `clubs/${companyId}/channels/whiteboard/whiteboardDrafts/${MEMBER}`;
      await assertFails(setDoc(doc(db(MEMBER), retiredDraft), { draftId: "old" }));
      await assertFails(read(MEMBER, retiredDraft));

      for (const uid of [OWNER, MEMBER, ADMIN, OUTSIDER]) {
        await assertFails(setDoc(doc(db(uid), ordinaryState), state(companyId)));
        await assertFails(updateDoc(doc(db(uid), ordinaryState), { revision: 2 }));
        await assertFails(deleteDoc(doc(db(uid), ordinaryState)));
        await assertFails(setDoc(
          doc(db(uid), ordinaryStroke),
          stroke(companyId, "stroke-one"),
        ));
        await assertFails(updateDoc(doc(db(uid), ordinaryStroke), { color: "red" }));
        await assertFails(deleteDoc(doc(db(uid), ordinaryStroke)));
      }

      await seed(Object.fromEntries(Object.keys(entries).map((location) => [location, null])));
    });
    await check("V1 Family check-ins stay member-private, location-free and callable-written", async () => {
      const familyId = "rules-family-checkins";
      const heldFamilyId = "rules-family-checkins-held";
      const checkInPath = `clubs/${familyId}/checkIns/check-one`;
      const heldCheckInPath = `clubs/${heldFamilyId}/checkIns/check-held`;
      const checkIn = (serverId, checkInId) => ({
        schemaVersion: 1,
        serverId,
        clubId: serverId,
        checkInId,
        userId: MEMBER,
        displayName: MEMBER,
        photoUrl: null,
        status: "allGood",
        createdAt: new Date(0),
      });
      const entries = {
        [`clubs/${familyId}`]: server(familyId, {
          serverType: "family", type: "family", privacy: "inviteOnly",
        }),
        [`clubs/${familyId}/members/${OWNER}`]: member(OWNER, "owner"),
        [`clubs/${familyId}/members/${MEMBER}`]: member(MEMBER),
        [`clubs/${familyId}/members/${ADMIN}`]: member(ADMIN, "admin"),
        [checkInPath]: checkIn(familyId, "check-one"),
        [`clubs/${heldFamilyId}`]: server(heldFamilyId, {
          held: true, serverType: "family", type: "family", privacy: "inviteOnly",
        }),
        [`clubs/${heldFamilyId}/members/${OWNER}`]: member(OWNER, "owner"),
        [heldCheckInPath]: checkIn(heldFamilyId, "check-held"),
      };
      await seed(entries);

      await assertSucceeds(read(MEMBER, checkInPath));
      const visible = await assertSucceeds(getDocs(
        collection(db(MEMBER), `clubs/${familyId}/checkIns`),
      ));
      assert.deepEqual(visible.docs.map((row) => row.id), ["check-one"]);
      await assertFails(read(OUTSIDER, checkInPath));
      await assertFails(read(OWNER, heldCheckInPath));
      // The existing active Company fixture cannot expose a row through the
      // V1 Family-only branch, even to one of its own members.
      await assertFails(read(MEMBER, `clubs/${ACTIVE}/checkIns/one`));
      for (const uid of [OWNER, MEMBER, ADMIN, OUTSIDER]) {
        await assertFails(setDoc(doc(db(uid), checkInPath), checkIn(familyId, "check-one")));
        await assertFails(updateDoc(doc(db(uid), checkInPath), { status: "callMe" }));
        await assertFails(deleteDoc(doc(db(uid), checkInPath)));
      }

      await seed(Object.fromEntries(Object.keys(entries).map((location) => [location, null])));
    });
    await check("V1 Family Memories inherit the Memories-channel ACL and stay callable-written", async () => {
      const familyId = "rules-family-memories";
      const heldFamilyId = "rules-family-memories-held";
      const memoryId = "fm_0123456789abcdef0123456789abcdef01234567";
      const memoryPath = `clubs/${familyId}/moments/${memoryId}`;
      const heldPath = `clubs/${heldFamilyId}/moments/${memoryId}`;
      const memory = (serverId, changes = {}) => ({
        schemaVersion: 1,
        memoryKind: "familyMemory",
        serverId,
        clubId: serverId,
        channelId: "memories",
        memoryId,
        authorId: MEMBER,
        authorDisplayName: MEMBER,
        authorPhotoUrl: null,
        caption: "A private family memory",
        status: "published",
        photo: {
          storagePath: `family_moments/${serverId}/${MEMBER}/${memoryId}_photo.jpg`,
          generation: "1",
          contentType: "image/jpeg",
          size: 128,
        },
        voice: {
          storagePath: `family_moments/${serverId}/${MEMBER}/${memoryId}_voice.m4a`,
          generation: "2",
          contentType: "audio/mp4",
          size: 1024,
          durationMs: 1000,
        },
        revision: 1,
        createdAt: new Date(0),
        updatedAt: new Date(0),
        ...changes,
      });
      const entries = {
        [`clubs/${familyId}`]: server(familyId, {
          serverType: "family", type: "family", privacy: "inviteOnly",
        }),
        [`clubs/${familyId}/members/${OWNER}`]: member(OWNER, "owner"),
        [`clubs/${familyId}/members/${MEMBER}`]: member(MEMBER),
        [`clubs/${familyId}/members/${ADMIN}`]: member(ADMIN, "admin"),
        [`clubs/${familyId}/channels/memories`]: channel(familyId, false, {
          kind: "memories", name: "Memories",
        }),
        [memoryPath]: memory(familyId),
        [`clubs/${heldFamilyId}`]: server(heldFamilyId, {
          held: true, serverType: "family", type: "family", privacy: "inviteOnly",
        }),
        [`clubs/${heldFamilyId}/members/${OWNER}`]: member(OWNER, "owner"),
        [`clubs/${heldFamilyId}/channels/memories`]: channel(heldFamilyId, false, {
          kind: "memories", name: "Memories",
        }),
        [heldPath]: memory(heldFamilyId),
      };
      await seed(entries);

      await assertSucceeds(read(MEMBER, memoryPath));
      const visible = await assertSucceeds(getDocs(query(
        collection(db(MEMBER), `clubs/${familyId}/moments`),
        where("channelId", "==", "memories"),
        where("status", "==", "published"),
        orderBy("createdAt", "desc"),
      )));
      assert.deepEqual(visible.docs.map((row) => row.id), [memoryId]);
      await assertFails(read(OUTSIDER, memoryPath));
      await assertFails(read(BANNED, memoryPath));
      await assertFails(read(OWNER, heldPath));
      await seed({ [memoryPath]: memory(familyId, { status: "deleting" }) });
      await assertFails(read(MEMBER, memoryPath));
      await seed({ [memoryPath]: memory(familyId) });
      for (const uid of [OWNER, MEMBER, ADMIN, OUTSIDER]) {
        await assertFails(setDoc(doc(db(uid), memoryPath), memory(familyId)));
        await assertFails(updateDoc(doc(db(uid), memoryPath), { caption: "forged" }));
        await assertFails(deleteDoc(doc(db(uid), memoryPath)));
      }

      await seed(Object.fromEntries(Object.keys(entries).map((location) => [location, null])));
    });
    await check("Community follow projections are private, owner-readable only and server-written", async () => {
      const communityId = "rules-community-follow";
      const follow = (uid) => ({
        schemaVersion: 1,
        serverId: communityId,
        userId: uid,
        following: true,
        createdAt: new Date(0),
        updatedAt: new Date(0),
      });
      const primary = `clubs/${communityId}/followers/${MEMBER}`;
      const mirror = `users/${MEMBER}/serverFollows/${communityId}`;
      const entries = {
        [`clubs/${communityId}`]: server(communityId, {
          serverType: "community", type: "community", privacy: "public",
        }),
        [`clubs/${communityId}/members/${OWNER}`]: member(OWNER, "owner"),
        [`clubs/${communityId}/members/${MEMBER}`]: member(MEMBER),
        [primary]: follow(MEMBER),
        [mirror]: follow(MEMBER),
        [`serverFamilyMemoryUploadReservations/fm_private`]: { serverId: communityId },
        [`serverFamilyMemoryUploadLeases/${MEMBER}`]: { serverId: communityId },
        [`serverFamilyMemoryUploadBudgets/private`]: { ownerId: MEMBER },
        [`serverFamilyMemoryDeletionJobs/private`]: { serverId: communityId },
      };
      await seed(entries);

      await assertSucceeds(read(MEMBER, mirror));
      const own = await assertSucceeds(getDocs(
        collection(db(MEMBER), `users/${MEMBER}/serverFollows`),
      ));
      assert.deepEqual(own.docs.map((row) => row.id), [communityId]);
      for (const uid of [OWNER, OUTSIDER, BANNED]) {
        await assertFails(read(uid, mirror));
        await assertFails(getDocs(collection(db(uid), `users/${MEMBER}/serverFollows`)));
      }
      for (const uid of [OWNER, MEMBER, OUTSIDER]) {
        await assertFails(read(uid, primary));
        await assertFails(getDocs(collection(db(uid), `clubs/${communityId}/followers`)));
        await assertFails(setDoc(doc(db(uid), primary), follow(MEMBER)));
        await assertFails(setDoc(doc(db(uid), mirror), follow(MEMBER)));
        await assertFails(updateDoc(doc(db(uid), mirror), { following: false }));
        await assertFails(deleteDoc(doc(db(uid), mirror)));
      }
      for (const location of [
        "serverFamilyMemoryUploadReservations/fm_private",
        `serverFamilyMemoryUploadLeases/${MEMBER}`,
        "serverFamilyMemoryUploadBudgets/private",
        "serverFamilyMemoryDeletionJobs/private",
      ]) {
        await assertFails(read(MEMBER, location));
        await assertFails(setDoc(doc(db(MEMBER), location), { forged: true }));
        await assertFails(updateDoc(doc(db(MEMBER), location), { forged: true }));
        await assertFails(deleteDoc(doc(db(MEMBER), location)));
      }

      await seed(Object.fromEntries(Object.keys(entries).map((location) => [location, null])));
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
    await check("a migration-STAGED legacy channel is still fully manageable, which is why liveness is written with the root", async () => {
      // This is the property functions/servers/migration_apply.js depends on.
      // Its channels stage writes every V1 field onto a channel whose ROOT is
      // still unversioned, and that window has to be invisible to the Club
      // sitting in it. The field that would have broken it is `liveness` —
      // see the check above — so the engine writes that one with the root
      // instead. Everything else the stage writes is inert here, proven by
      // exercising the real manager write against a really staged document.
      await seed({ "clubs/legacy-public/channels/staged": {
        name: "Staged", type: "chat", position: 10, isPrivate: false, createdBy: OWNER,
        serverSchemaVersion: 1, serverId: "legacy-public", kind: "text",
        accessMode: "members", accessPolicy: { accessMode: "members", roleIds: [], userIds: [] },
        categoryId: null, status: "active", roomId: null, activeSessionId: null,
        experience: null, mediaMode: null, aclRevision: 1, revision: 1,
        historySource: { kind: "channelMessages" },
      } });
      await assertSucceeds(updateDoc(doc(db(OWNER), "clubs/legacy-public/channels/staged"), { name: "Renamed while staged" }));
      await assertSucceeds(updateDoc(doc(db(OWNER), "clubs/legacy-public/channels/staged"), { position: 11 }));
      // The broad legacy channel query still answers for a member of that
      // Club: the ROOT is what decides, and it is not versioned yet. (Only
      // OWNER is a member of the legacy-public fixture.)
      await assertSucceeds(read(OWNER, "clubs/legacy-public/channels/staged"));
      await assertSucceeds(getDocs(query(collection(db(OWNER), "clubs/legacy-public/channels"), orderBy("position"))));
      await assertFails(getDocs(query(collection(db(OUTSIDER), "clubs/legacy-public/channels"), orderBy("position"))));
      // The forgery guard is unchanged on a staged channel.
      await assertFails(updateDoc(doc(db(OWNER), "clubs/legacy-public/channels/staged"), { liveness: live() }));
      await assertSucceeds(deleteDoc(doc(db(OWNER), "clubs/legacy-public/channels/staged")));
    });
    await check("unfinished channel modules remain denied, not generic client writable", async () => {
      for (const moduleName of ["questions", "episodes", "boards", "files", "listItems"]) {
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
    // ADR-207 widened WHO may call createServerInviteV1 on a publicly joinable
    // server to every ordinary member. That is a callable-side predicate and
    // deliberately buys no Rules access at all: this check is what turns "no
    // firestore.rules change is needed" from an assertion into evidence.
    const PUBLIC_V1 = "server-public-v1";
    await check("a member of a PUBLIC V1 server gains no client write and no foreign read on invites: the widened inviter predicate is callable-side only", async () => {
      await seed({
        [`clubs/${PUBLIC_V1}`]: server(PUBLIC_V1, { serverType: "community", privacy: "public", name: "Public community" }),
        [`clubs/${PUBLIC_V1}/members/${OWNER}`]: member(OWNER, "owner"),
        [`clubs/${PUBLIC_V1}/members/${ADMIN}`]: member(ADMIN, "admin"),
        [`clubs/${PUBLIC_V1}/members/${MEMBER}`]: member(MEMBER, "member"),
        [`clubs/${PUBLIC_V1}/invites/${OUTSIDER}`]: v1Invite(OUTSIDER, { serverId: PUBLIC_V1, inviterId: MEMBER, serverName: "Public community" }),
        [`clubs/${PUBLIC_V1}/invites/${STRANGER}`]: v1Invite(STRANGER, { serverId: PUBLIC_V1, inviterId: MEMBER, serverName: "Public community" }),
      });
      const publicInvite = `clubs/${PUBLIC_V1}/invites/${OUTSIDER}`;
      // The member who may now ISSUE an invitation still writes nothing.
      for (const uid of [OWNER, ADMIN, MEMBER, OUTSIDER]) {
        await assertFails(setDoc(doc(db(uid), `clubs/${PUBLIC_V1}/invites/forged-${uid}`),
          v1Invite(`forged-${uid}`, { serverId: PUBLIC_V1, inviterId: uid })));
        await assertFails(setDoc(doc(db(uid), publicInvite), v1Invite(OUTSIDER, { serverId: PUBLIC_V1, status: "accepted" })));
        await assertFails(updateDoc(doc(db(uid), publicInvite), { status: "accepted" }));
        await assertFails(updateDoc(doc(db(uid), publicInvite), { generation: 99 }));
        await assertFails(deleteDoc(doc(db(uid), publicInvite)));
      }
      // Reading is unchanged too: the invitee and the managers, never the
      // plain member who issued it, and never a second invitee's document.
      await assertSucceeds(read(OUTSIDER, publicInvite));
      await assertSucceeds(read(OWNER, publicInvite));
      await assertSucceeds(read(ADMIN, publicInvite));
      await assertFails(read(MEMBER, publicInvite));
      await assertFails(read(STRANGER, publicInvite));
      await assertFails(read(OUTSIDER, `clubs/${PUBLIC_V1}/invites/${STRANGER}`));
      // The self-scoped collection group is still the only discovery, and a
      // public root does not widen it.
      const own = await assertSucceeds(getDocs(query(collectionGroup(db(OUTSIDER), "invites"), where("inviteeId", "==", OUTSIDER))));
      assert.ok(own.docs.some((item) => item.ref.path === publicInvite));
      await assertFails(getDocs(query(collectionGroup(db(MEMBER), "invites"), where("serverId", "==", PUBLIC_V1))));
      await assertFails(getDocs(collection(db(MEMBER), `clubs/${PUBLIC_V1}/invites`)));
      // The private pointer stays server-written on a public root as well.
      await assertFails(setDoc(doc(db(MEMBER), `users/${OUTSIDER}/serverInviteRefs/${PUBLIC_V1}`),
        { serverId: PUBLIC_V1, generation: 1, expiresAt: new Date(Date.now() + 86_400_000) }));
      await assertFails(setDoc(doc(db(OUTSIDER), `users/${OUTSIDER}/serverInviteRefs/${PUBLIC_V1}`),
        { serverId: PUBLIC_V1, generation: 1, expiresAt: new Date(Date.now() + 86_400_000) }));
      await env.withSecurityRulesDisabled(async (ctx) => {
        const stored = (await getDoc(doc(ctx.firestore(), publicInvite))).data();
        assert.equal(stored.status, "pending");
        assert.equal(stored.generation, 1);
        assert.equal(stored.inviterId, MEMBER);
      });
      await seed({ [`clubs/${PUBLIC_V1}/invites/${OUTSIDER}`]: null,
        [`clubs/${PUBLIC_V1}/invites/${STRANGER}`]: null });
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
    await check("a hand decision (request to speak) is readable only by its subject, never widens the queue and is never client-written", async () => {
      const DECLINED = "server-declined";
      const APPROVED = "server-approved";
      await seed({
        [`users/${DECLINED}`]: { displayName: DECLINED, banned: false, disabled: false },
        [`users/${APPROVED}`]: { displayName: APPROVED, banned: false, disabled: false },
        [`clubs/${ACTIVE}/members/${DECLINED}`]: member(DECLINED, "member"),
        [`clubs/${ACTIVE}/members/${APPROVED}`]: member(APPROVED, "member"),
        [own(DECLINED)]: participant(DECLINED, "listener", { isHandRaised: false, handRaisedAt: null,
          handDecision: "declined", handDecidedAt: new Date(3), handDecidedById: ADMIN }),
        [own(APPROVED)]: participant(APPROVED, "guest", { authorizationRevision: 2, isHandRaised: false,
          handRaisedAt: null, handDecision: "approved", handDecidedAt: new Date(4), handDecidedById: MEMBER }),
      });
      // The subject reads the answer on their own live-generation document.
      const declined = await assertSucceeds(read(DECLINED, own(DECLINED)));
      assert.equal(declined.data().handDecision, "declined");
      assert.equal(declined.data().isHandRaised, false);
      const approved = await assertSucceeds(read(APPROVED, own(APPROVED)));
      assert.equal(approved.data().handDecision, "approved");
      assert.equal(approved.data().role, "guest");
      // Nobody else point-reads an answered document, and the host's queue
      // still names only the hand that is up.
      for (const uid of [OWNER, MEMBER, ADMIN, LISTENER]) {
        await assertFails(read(uid, own(DECLINED)));
        await assertFails(read(uid, own(APPROVED)));
      }
      for (const uid of [MEMBER, OWNER, ADMIN]) {
        assert.deepEqual((await assertSucceeds(hands(uid))).docs.map((item) => item.id), [LISTENER]);
      }
      // An answer is callable-only: the subject cannot clear, forge or
      // re-raise it, and nobody else can write one.
      await assertFails(updateDoc(doc(db(DECLINED), own(DECLINED)), { handDecision: null }));
      await assertFails(updateDoc(doc(db(DECLINED), own(DECLINED)), { isHandRaised: true, handDecision: null,
        updatedAt: serverTimestamp() }));
      await assertFails(updateDoc(doc(db(MEMBER), own(LISTENER)), { isHandRaised: false, handDecision: "declined",
        handDecidedAt: serverTimestamp(), handDecidedById: MEMBER }));
      await assertFails(updateDoc(doc(db(ADMIN), own(LISTENER)), { handDecision: "approved" }));
      // An ended generation closes the answer too.
      await seed({ [`clubs/${ACTIVE}/channels/${SALON}`]: salon({ activeSessionId: null, liveness: idle() }),
        [`rooms/${ANCHOR}`]: anchor({ isLive: false, voiceSessionId: null, livekitRoomName: null, serverSessionCleanupId: GENERATION }) });
      await assertFails(read(DECLINED, own(DECLINED)));
      await seed({ [`clubs/${ACTIVE}/channels/${SALON}`]: salon(), [`rooms/${ANCHOR}`]: anchor(),
        [own(DECLINED)]: null, [own(APPROVED)]: null });
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

    // ---------------------------------------------------------------------
    // Management parity (ADR-F). Every write removeServerMemberV1,
    // setServerMemberBanV1, deleteServerV1 and the four staff adapters make
    // is an Admin SDK write onto a path no client may touch — and each of
    // those writes is then HONOURED by these same rules. Both halves are
    // proven here: the deny, and the enforcement it produces.
    // ---------------------------------------------------------------------
    const PARITY = "server-parity";
    const PARITY_BANNED = "server-parity-banned";
    await seed({
      [`users/${PARITY_BANNED}`]: { displayName: PARITY_BANNED, banned: false, disabled: false },
      [`clubs/${PARITY}`]: server(PARITY),
      [`clubs/${PARITY}/members/${OWNER}`]: member(OWNER, "owner"),
      [`clubs/${PARITY}/members/${MEMBER}`]: member(MEMBER, "member"),
      [`clubs/${PARITY}/members/${ADMIN}`]: member(ADMIN, "admin"),
      [`clubs/${PARITY}/members/${PARITY_BANNED}`]: member(PARITY_BANNED, "member"),
      [`clubs/${PARITY}/channels/general`]: channel(PARITY),
      [`clubs/${PARITY}/memberAuthorizations/${MEMBER}`]: {
        schemaVersion: 1, userId: MEMBER, revision: 1, status: "member", updatedAt: new Date(0),
      },
      [`serverControlOutbox/parity-job`]: {
        schemaVersion: 1, kind: "memberRemoved", serverId: PARITY, userId: MEMBER,
        membershipRevision: 2, operationId: "parity-job", status: "pending",
      },
    });

    await check("the authorization ledger a removal/ban advances is unreadable and unwritable by every client", async () => {
      const location = `clubs/${PARITY}/memberAuthorizations/${MEMBER}`;
      for (const uid of [OWNER, ADMIN, MEMBER, OUTSIDER]) {
        await assertFails(read(uid, location));
        await assertFails(setDoc(doc(db(uid), location), { schemaVersion: 1, userId: uid, revision: 99, status: "member" }));
        await assertFails(updateDoc(doc(db(uid), location), { revision: 99 }));
        await assertFails(deleteDoc(doc(db(uid), location)));
      }
      // Not even the subject may mint their own revision — that is the fence
      // every grant and every issued media token is checked against.
      await assertFails(setDoc(doc(db(MEMBER), `clubs/${PARITY}/memberAuthorizations/${MEMBER}`),
        { schemaVersion: 1, userId: MEMBER, revision: 2, status: "member" }));
    });

    await check("the control outbox that revokes a removed or banned member is closed to every client", async () => {
      for (const uid of [OWNER, ADMIN, MEMBER, OUTSIDER]) {
        await assertFails(read(uid, "serverControlOutbox/parity-job"));
        await assertFails(setDoc(doc(db(uid), "serverControlOutbox/forged"), {
          schemaVersion: 1, kind: "serverDelete", serverId: PARITY, operationId: "forged", status: "pending",
        }));
        await assertFails(updateDoc(doc(db(uid), "serverControlOutbox/parity-job"), { status: "completed" }));
        await assertFails(deleteDoc(doc(db(uid), "serverControlOutbox/parity-job")));
      }
      await assertFails(getDocs(query(collection(db(OWNER), "serverControlOutbox"), limit(1))));
    });

    await check("OBS broadcast usage slots and the runtime capacity switch are closed to every client", async () => {
      const usage = `serverBroadcastUsage/${OWNER}`;
      const capacity = "serverRuntimeCapacity/communityBroadcastV1";
      const slot = (uid) => ({
        schemaVersion: 1, source: "yovoice.obs.rtmp", uid, serverId: PARITY, channelId: "stage",
        roomId: "stage-room", sessionId: "session-one", livekitRoomName: "srv_parity_stage_session-one",
        participantIdentity: "obs_parity", state: "active", operationId: "a".repeat(64),
        leaseId: null, leaseExpiresAtMillis: 0, ingressId: "ingress_one", updatedAt: new Date(0),
      });
      await seed({
        [usage]: slot(OWNER),
        [capacity]: { schemaVersion: 1, enabled: true, activeCount: 1, limit: 25, updatedAt: new Date(0) },
      });
      for (const uid of [OWNER, ADMIN, MEMBER, OUTSIDER]) {
        await assertFails(read(uid, usage));
        await assertFails(setDoc(doc(db(uid), `serverBroadcastUsage/${uid}`), slot(uid)));
        await assertFails(updateDoc(doc(db(uid), usage), { state: "provisioning" }));
        await assertFails(deleteDoc(doc(db(uid), usage)));
        await assertFails(getDocs(query(collection(db(uid), "serverBroadcastUsage"), limit(1))));
        await assertFails(read(uid, capacity));
        await assertFails(setDoc(doc(db(uid), capacity),
          { schemaVersion: 1, enabled: true, activeCount: 0, limit: 25, updatedAt: new Date(0) }));
        await assertFails(updateDoc(doc(db(uid), capacity), { enabled: false }));
        await assertFails(deleteDoc(doc(db(uid), capacity)));
        await assertFails(getDocs(query(collection(db(uid), "serverRuntimeCapacity"), limit(1))));
      }
      const anonymous = env.unauthenticatedContext().firestore();
      await assertFails(getDoc(doc(anonymous, capacity)));
      await assertFails(getDocs(query(collection(anonymous, "serverBroadcastUsage"), limit(1))));
    });

    await check("no client can remove a member, ban one, lift a ban, suspend a root or mark it deleted", async () => {
      const target = `clubs/${PARITY}/members/${MEMBER}`;
      // Removal: member delete is closed for EVERY role, on a versioned root
      // and on a legacy one — removeServerMemberV1 is the only writer.
      for (const uid of [OWNER, ADMIN, MEMBER, OUTSIDER]) {
        await assertFails(deleteDoc(doc(db(uid), target)));
        await assertFails(deleteDoc(doc(db(uid), `clubs/${PARITY}/members/${uid}`)));
      }
      // Ban and lift: `banned` is not in any client field allowlist.
      for (const uid of [OWNER, ADMIN, MEMBER]) {
        await assertFails(updateDoc(doc(db(uid), target), { banned: true }));
        await assertFails(updateDoc(doc(db(uid), target), { banned: false }));
        await assertFails(updateDoc(doc(db(uid), target), { banned: true, banReason: "x", bannedBy: uid }));
        await assertFails(updateDoc(doc(db(uid), target), { authorizationRevision: 99 }));
      }
      // Moderation status and the deletion mark are root fields no client
      // may write on a versioned root, and the root itself is undeletable.
      for (const uid of [OWNER, ADMIN, MEMBER, OUTSIDER]) {
        await assertFails(updateDoc(doc(db(uid), `clubs/${PARITY}`), { status: "suspended" }));
        await assertFails(updateDoc(doc(db(uid), `clubs/${PARITY}`), { status: "active", moderationReason: null }));
        await assertFails(updateDoc(doc(db(uid), `clubs/${PARITY}`), { deletionInProgress: true }));
        await assertFails(updateDoc(doc(db(uid), `clubs/${PARITY}`), { memberCount: 1 }));
        await assertFails(deleteDoc(doc(db(uid), `clubs/${PARITY}`)));
      }
      // Nothing above moved anything.
      const after = (await assertSucceeds(read(OWNER, target))).data();
      assert.equal(after.banned, undefined);
      assert.equal(after.authorizationRevision, 1);
    });

    await check("a server ban, a suspension and a deletion mark are each HONOURED by these rules", async () => {
      // Baseline: the member can read the root and list channels.
      await assertSucceeds(read(PARITY_BANNED, `clubs/${PARITY}`));
      await assertSucceeds(directory(PARITY_BANNED, PARITY));

      await seed({ [`clubs/${PARITY}/members/${PARITY_BANNED}`]: member(PARITY_BANNED, "member", { banned: true }) });
      await assertFails(directory(PARITY_BANNED, PARITY));
      await assertFails(read(PARITY_BANNED, `clubs/${PARITY}/channels/general`));
      await assertFails(read(PARITY_BANNED, `clubs/${PARITY}/channels/general/messages/one`));
      // Lifting the ban restores exactly what it removed.
      await seed({ [`clubs/${PARITY}/members/${PARITY_BANNED}`]: member(PARITY_BANNED, "member", { banned: false }) });
      await assertSucceeds(directory(PARITY_BANNED, PARITY));

      // A staff suspension freezes the root for everyone, owner included.
      await seed({ [`clubs/${PARITY}`]: server(PARITY, { status: "suspended" }) });
      for (const uid of [OWNER, ADMIN, MEMBER]) await assertFails(directory(uid, PARITY));
      await seed({ [`clubs/${PARITY}`]: server(PARITY) });
      await assertSucceeds(directory(MEMBER, PARITY));

      // The deletion mark does the same, and it is what deleteServerV1 and
      // the staff adapter write.
      await seed({ [`clubs/${PARITY}`]: server(PARITY, { deletionInProgress: true }) });
      for (const uid of [OWNER, ADMIN, MEMBER]) await assertFails(directory(uid, PARITY));
      await seed({ [`clubs/${PARITY}`]: server(PARITY) });
    });

    const MEMORY_UPLOAD_SERVER = "rules-family-upload";
    const MEMORY_UPLOAD_ID = "fm_89abcdef0123456789abcdef0123456789abcdef";
    const MEMORY_PHOTO = `family_moments/${MEMORY_UPLOAD_SERVER}/${OWNER}/${MEMORY_UPLOAD_ID}_photo.jpg`;
    const MEMORY_VOICE = `family_moments/${MEMORY_UPLOAD_SERVER}/${OWNER}/${MEMORY_UPLOAD_ID}_voice.m4a`;
    const memoryMetadata = (assetKind) => ({
      yovoiceServerId: MEMORY_UPLOAD_SERVER,
      yovoiceChannelId: "memories",
      yovoiceOwnerUid: OWNER,
      yovoiceMemoryId: MEMORY_UPLOAD_ID,
      yovoiceAssetKind: assetKind,
    });
    await seed({
      [`clubs/${MEMORY_UPLOAD_SERVER}`]: server(MEMORY_UPLOAD_SERVER, {
        serverType: "family", type: "family", privacy: "inviteOnly",
      }),
      [`clubs/${MEMORY_UPLOAD_SERVER}/members/${OWNER}`]: member(OWNER, "owner"),
      [`clubs/${MEMORY_UPLOAD_SERVER}/members/${MEMBER}`]: member(MEMBER),
      [`clubs/${MEMORY_UPLOAD_SERVER}/channels/memories`]: channel(MEMORY_UPLOAD_SERVER, false, {
        kind: "memories", name: "Memories",
      }),
      [`serverFamilyMemoryUploadReservations/${MEMORY_UPLOAD_ID}`]: {
        schemaVersion: 1,
        kind: "serverFamilyMemory",
        serverId: MEMORY_UPLOAD_SERVER,
        channelId: "memories",
        memoryId: MEMORY_UPLOAD_ID,
        ownerId: OWNER,
        requestId: "memory-upload-request",
        caption: "",
        photoStoragePath: MEMORY_PHOTO,
        photoContentType: "image/jpeg",
        photoSize: 128,
        voiceStoragePath: MEMORY_VOICE,
        voiceContentType: "audio/mp4",
        voiceSize: 1024,
        voiceDurationMs: 1000,
        status: "uploading",
        createdAt: new Date(),
        expiresAt: new Date(Date.now() + 60 * 60_000),
      },
    });
    await check("a live Family Memory reservation accepts only its two exact immutable objects", async () => {
      await assertSucceeds(uploadBytes(
        ref(storage(OWNER), MEMORY_PHOTO),
        new Uint8Array(128),
        { contentType: "image/jpeg", customMetadata: memoryMetadata("photo") },
      ));
      await assertFails(uploadBytes(
        ref(storage(OWNER), MEMORY_VOICE),
        new Uint8Array(1024),
        { contentType: "audio/mp4", customMetadata: {
          ...memoryMetadata("voice"), forged: "true",
        } },
      ));
      await assertSucceeds(uploadBytes(
        ref(storage(OWNER), MEMORY_VOICE),
        new Uint8Array(1024),
        { contentType: "audio/mp4", customMetadata: memoryMetadata("voice") },
      ));
      await assertFails(uploadBytes(
        ref(storage(OWNER), MEMORY_PHOTO),
        new Uint8Array(128),
        { contentType: "image/jpeg", customMetadata: memoryMetadata("photo") },
      ));
      await assertFails(deleteObject(ref(storage(OWNER), MEMORY_PHOTO)));
      await assertFails(uploadBytes(
        ref(storage(MEMBER),
          `family_moments/${MEMORY_UPLOAD_SERVER}/${MEMBER}/${MEMORY_UPLOAD_ID}_photo.jpg`),
        new Uint8Array(128),
        { contentType: "image/jpeg", customMetadata: memoryMetadata("photo") },
      ));
      await assertFails(uploadBytes(
        ref(storage(OWNER),
          `family_moments/${MEMORY_UPLOAD_SERVER}/${OWNER}/${MEMORY_UPLOAD_ID}_photo.png`),
        new Uint8Array(128),
        { contentType: "image/png", customMetadata: memoryMetadata("photo") },
      ));
    });
    await check("Family Memory direct reads exist only for the owner while the upload reservation is live", async () => {
      await assertSucceeds(getBytes(ref(storage(OWNER), MEMORY_PHOTO)));
      await assertFails(getBytes(ref(storage(MEMBER), MEMORY_PHOTO)));
      await assertFails(getBytes(ref(storage(OUTSIDER), MEMORY_PHOTO)));
      await assertFails(listAll(ref(storage(OWNER),
        `family_moments/${MEMORY_UPLOAD_SERVER}/${OWNER}`)));
      await seed({ [`serverFamilyMemoryUploadReservations/${MEMORY_UPLOAD_ID}`]: null });
      await assertFails(getBytes(ref(storage(OWNER), MEMORY_PHOTO)));
      await assertFails(getBytes(ref(storage(MEMBER), MEMORY_VOICE)));
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
    await check("Podcast episode MP3s have no Firebase client read, list, upload or delete path", async () => {
      const pathValue = `server_podcast_episodes/${ACTIVE}/episodes/episode-one.mp3`;
      await env.withSecurityRulesDisabled(async (ctx) => {
        await uploadBytes(ref(ctx.storage(PROJECT), pathValue), new Uint8Array(1024), {
          contentType: "audio/mpeg",
        });
      });
      for (const uid of [OWNER, MEMBER, ADMIN, OUTSIDER]) {
        await assertFails(getBytes(ref(storage(uid), pathValue)));
        await assertFails(listAll(ref(storage(uid), `server_podcast_episodes/${ACTIVE}`)));
        await assertFails(uploadBytes(ref(storage(uid), pathValue), new Uint8Array(1024), {
          contentType: "audio/mpeg",
        }));
        await assertFails(deleteObject(ref(storage(uid), pathValue)));
      }
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
