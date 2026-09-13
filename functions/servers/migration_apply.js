"use strict";

/**
 * The legacy Club/room migration APPLY ENGINE.
 *
 * `migration_plan.js` decides what a root would map to, `migration_collector.js`
 * gathers the evidence, `migration_inventory.js` checks that the evidence is
 * internally consistent. None of the three can mutate anything. This module is
 * the one that can — and it is written so that the overwhelming majority of
 * its behaviour is REFUSAL.
 *
 * Properties this file is responsible for, each enforced in code rather than
 * described in a comment:
 *
 *  - **Idempotent per root.** Every write is computed as a patch against the
 *    observed document and dropped when it would change nothing, so a second
 *    run over an already-migrated root produces zero writes — whether it
 *    resumes the same run record or starts a fresh one.
 *  - **Resumable.** A run persists a record per root carrying its stage and
 *    member cursor, written in the SAME transaction as the stage it describes.
 *    An interrupted run restarts at the next unfinished stage.
 *  - **Bounded.** Roots per run, members per root, members per transaction,
 *    channels per root, bound rooms per root and invitations probed per root
 *    are hard caps. Exceeding one is a refusal, never a larger read.
 *  - **Never migrates a live root.** Liveness and transient participation are
 *    probed for every anchor the root owns, in every stage transaction, so a
 *    session that starts mid-run defers the root instead of racing the write.
 *  - **Never promotes a transient participant.** `rooms/{id}/participants` is
 *    read ONLY through `probeTransientParticipants`, which returns a count and
 *    lets the snapshot go out of scope; the durable member sources are named
 *    in one frozen list that a participation roster is not in.
 *  - **Never touches media.** `avatarUrl`, `bannerUrl` and `imageUrl` are on
 *    the immutable-field list, no Storage client is constructed, and no object
 *    name or generation is read or rewritten. Media survives by being left
 *    alone; where migrating would leave it unreadable, the root is refused
 *    instead (`STRANDED_IF_NON_EMPTY`).
 *  - **`onlineCount` is reset, not carried.** Presence has no V1 writer
 *    (`docs/Servers.md` gap G6), so a carried count would be fabricated.
 *    Member `isOnline` is reset for the same reason.
 *  - **Entitlements are preserved exactly.** A paid Club keeps
 *    `legacyCommunityPremiumV1`; the post-image is run through the SAME
 *    `classifyServerAllocation` the capacity accounting uses, so a mistake
 *    fails here instead of silently charging someone's five free servers.
 *  - **Families are excluded (ADR-E).** Not by convention: by
 *    `familyMigrationAllowed()`, which reads the three rules-branch flags that
 *    `clubs/{id}/checkIns`, `clubs/{id}/moments` and `family_moments` Storage
 *    still lack. When those branches land the flags flip and the refusal stops
 *    firing, with no other edit.
 *  - **The old-client gate is a precondition, not a note.** See
 *    `migration_gate.js`. The gate document is read inside the transaction
 *    that versions the root, its revision is pinned to the one the operator
 *    reviewed, and the observed installed-base census must contain zero
 *    incompatible sessions.
 *
 * Production apply is NOT implemented here and cannot be reached from here:
 * `separate-production-migration-approval` is the eighth required gate and has
 * no in-code evidence source, so `applyReady` is permanently `false` and write
 * mode refuses to run anywhere but a local emulator.
 */

const crypto = require("node:crypto");
const { FieldPath } = require("firebase-admin/firestore");
const { fail } = require("../integrity/guards");
const { isValidOpaqueUid } = require("../achievements/identity");
const { isVersionedServer } = require("../utils/server_access");
const {
  MAX_SERVER_CHANNELS, ROLES, accessPolicy, channelLiveness, legacyChannelType, mediaConfiguration,
} = require("./contract");
const { FREE_ALLOCATION_POLICIES, classifyServerAllocation } = require("./capacity");
const { REQUIRED_NEXT_GATES, standaloneServerId } = require("./migration_plan");
const { CLIENT_GATE_PATH, assessClientGate } = require("./migration_gate");

const APPLY_VERSION = 1;
const MIGRATION_RECORD_VERSION = 1;
const RUN_COLLECTION = "serverMigrationRuns";
const RUN_STEP_COLLECTION = "rootSteps";
const MODES = Object.freeze(["dryRun", "apply"]);
// A run's stages, in the ONLY order that is safe. Members and channels are
// additive and inert while the root is unversioned — legacy Rules still govern
// the space — so they can be staged ahead and re-run. Writing the root is the
// irreversible flip: it goes last, it is the step the client gate guards, and
// it is the step whose transaction re-reads liveness.
const STAGES = Object.freeze(["members", "channels", "root", "complete"]);
const MIGRATION_STATES = Object.freeze(["pending", "membersAuthorized", "channelsVersioned", "complete"]);
const STAGE_STATE = Object.freeze({
  members: "pending", channels: "membersAuthorized", root: "channelsVersioned", complete: "complete",
});

const MAX_ROOTS_PER_RUN = 200;
const MAX_MEMBERS_PER_ROOT = 5000;
const MEMBER_PAGE_SIZE = 100;
const MAX_CHANNELS_PER_ROOT = MAX_SERVER_CHANNELS;
const MAX_BOUND_ROOMS_PER_ROOT = MAX_SERVER_CHANNELS;
const MAX_INVITE_PROBE = 100;
const EXISTENCE_PROBE = 1;
// The only refusals that clear by themselves when a session ends. Everything
// else is a hard refusal and is never reported as `deferred`.
const LIVENESS_REASONS = Object.freeze(["active-session-must-not-be-migrated", "transient-participants-present"]);
const SAFE_ID = /^[A-Za-z0-9_-]{1,128}$/u;
const PROJECT_ID = /^[a-z][a-z0-9-]{0,62}$/u;
// Identical to the CLI's (scripts/servers_migration_apply_dry_run.js): a
// LOCAL emulator endpoint, never a hostname that merely looks local.
const LOCAL_EMULATOR_HOST = /^(127\.0\.0\.1|localhost|\[::1\]):[0-9]{1,5}$/u;
const DIGEST = /^[0-9a-f]{64}$/u;

/**
 * What a client can still READ once a root carries the server markers, read
 * off the committed Rules rather than off intent. This is the registry the
 * engine refuses against; every `false` below is a live defect with a named
 * owner in `club-retirement-inventory.md`, and flipping one to `true` is a
 * deliberate edit made in the same release as the Rules branch it claims.
 */
const V1_CLIENT_READ_PATHS = Object.freeze({
  // firestore.rules: clubs/{id} get, activeServerRoot branch.
  serverRoot: true,
  // firestore.rules: channels list, with accessMode and status pinned.
  channelList: true,
  // firestore.rules: canReadClubChannel -> canReadServerChannel.
  channelMessages: true,
  // users/{uid}/serverChannelRefs plus a point get of the channel.
  restrictedChannelDiscovery: true,
  // The server-owned liveness projection on the channel document (ADR-A).
  channelLiveness: true,
  // canAccessRoom() requires isLegacyRoomData(), so a versioned anchor is
  // denied. That is BY DESIGN for a V1 channel anchor — the client reaches a
  // session through callables — so it is not a stranding on its own. The
  // legacy content underneath it is, and has its own entries below.
  roomAnchor: false,
  // rooms/{id}/messages inherits canAccessRoom(): a bound room's own history
  // stops being readable the moment its parent Club carries a server marker.
  roomMessages: false,
  // A standalone room becomes a NEW root whose only channel's history lives at
  // rooms/{id}/messages, and whose anchor is the room itself. Both are covered
  // by the two entries above, so adoption stays closed until they open.
  standaloneRoomAdoption: false,
  // storage.rules isOrdinaryClubMedia() requires the root to carry NONE of the
  // three server markers, for `read` as well as for write.
  clubArtworkStorage: false,
  // firestore.rules clubs/{id}/checkIns — isLegacyClub-gated.
  familyCheckIns: false,
  // firestore.rules clubs/{id}/moments — isLegacyClub-gated.
  familyMoments: false,
  // storage.rules /family_moments/{clubId}/... — isActiveFamilyMember()
  // explicitly excludes the three server markers.
  familyMomentsStorage: false,
  // A legacy invitation document carries none of the V1 fields
  // respondToServerInviteV1 requires, and member `create` is isLegacyClub
  // gated, so a legacy pending invite can never be accepted after migration.
  legacyPendingInvitation: false,
});

// ADR-E, enforced rather than described. Families migrate last, and "last"
// means: after these three Rules branches exist.
const FAMILY_RULES_BRANCHES = Object.freeze(["familyCheckIns", "familyMoments", "familyMomentsStorage"]);

/**
 * ADR-F, enforced rather than described — the same shape ADR-E gets, and for
 * the same reason: a load-bearing blocker that lives only in a comment drifts.
 *
 * "A migrated server with no removal, no ban and no deletion is a Trust &
 * Safety regression that cannot be hotfixed from the client" was ranked the
 * HIGHEST risk of the retirement inventory and was the one blocker with no
 * flag. Each entry names the V1 surface that closes it. `functions/test/
 * servers_management_independent_qa.test.js` pins these keys against the real
 * registration table and the real staff adapters, so a flag cannot stay true
 * after its callable is removed or renamed.
 */
const V1_MANAGEMENT_CAPABILITIES = Object.freeze({
  // servers/management.js removeServerMemberV1 (R1).
  removeMember: true,
  // servers/management.js setServerMemberBanV1, set AND lift (R2).
  banMember: true,
  // servers/management.js deleteServerV1 (R3).
  deleteServer: true,
  // admin/clubs.js delegates setClubModerationStatus, removeClubMember,
  // setClubMemberBan and adminDeleteClub to the V1 staff adapters (R4).
  // NOT included: staff ownership transfer (transferClubOwnership) still
  // refuses a versioned root, and owner-initiated transferServerOwnershipV1
  // is the only V1 transfer. That is an open gap, tracked separately; it is
  // not part of ADR-F's four names and does not gate this flag.
  adminSurface: true,
});

/**
 * Legacy content that must keep a client read path. Each entry names the
 * capability flag deciding whether migrating would strand it. An EMPTY
 * resource strands nothing, so each probe is a bounded existence check and the
 * refusal fires only on real data.
 */
const STRANDED_IF_NON_EMPTY = Object.freeze([
  { resource: "clubMoments", capability: "familyMoments", reason: "club-moments-would-lose-their-read-path" },
  { resource: "clubCheckIns", capability: "familyCheckIns", reason: "club-check-ins-would-lose-their-read-path" },
  { resource: "boundRoomMessages", capability: "roomMessages", reason: "bound-room-history-would-lose-its-read-path" },
  // A bound room's COVER is stranded exactly as the club's own artwork is:
  // `room_images/{roomId}/{file}` is `allow read: if false` in Storage and
  // its only access path is getRoomCoverMediaAccess -> authorizeMediaAccess
  // -> assertLegacyRoomAccess, which denies as soon as the parent club is a
  // versioned server. Messages are what the history refusal fires on; a cover
  // is not, so a room carrying a cover and no messages used to migrate its
  // artwork into the dark with no refusal, no log and no inventory row.
  // `roomAnchor` was already declared `false` in the registry and was the one
  // flag no refusal consulted, so this costs no new capability.
  { resource: "boundRoomArtwork", capability: "roomAnchor", reason: "bound-room-artwork-would-lose-its-read-path" },
  { resource: "clubArtwork", capability: "clubArtworkStorage", reason: "club-artwork-would-lose-its-read-path" },
  { resource: "pendingInvitations", capability: "legacyPendingInvitation", reason: "legacy-pending-invitation-has-no-v1-acceptance-path" },
]);

// Fields the apply engine may never write. Media identity is here because
// preserving an object name and its generation means not rewriting the field
// that points at it; identity is here because a migration that renames or
// re-owns a space is not a migration.
const IMMUTABLE_ROOT_FIELDS = Object.freeze([
  "avatarUrl", "bannerUrl", "imageUrl", "name", "description", "ownerId", "ownerName", "privacy",
  "createdAt", "defaultChatChannelId", "defaultVoiceChannelId", "announcementChannelId",
  "loungeRoomId", "defaultLanguage", "hostId", "clubId",
]);
const IMMUTABLE_CHANNEL_FIELDS = Object.freeze(["name", "position", "createdBy", "createdAt"]);
const IMMUTABLE_MEMBER_FIELDS = Object.freeze([
  "userId", "role", "joinedAt", "displayName", "photoUrl", "invitedBy", "banned",
]);

// `legacy type` -> V1 `kind`. Anything else is refused; a channel whose kind
// cannot be derived is never guessed into `text`.
const LEGACY_CHANNEL_KIND = Object.freeze({ chat: "text", announcement: "announcements", voice: "voice" });

// The ONLY places a durable server member may come from. A transient RTC
// roster is not in this list, and `assertDurableMemberSource` is the single
// door every membership read goes through, so no later edit can add one.
const DURABLE_MEMBER_SOURCES = Object.freeze(["members", "roomMembers", "owner"]);

const compare = (a, b) => (a < b ? -1 : a > b ? 1 : 0);
const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");
const sortedUnique = (values) => [...new Set(values)].sort(compare);

function fingerprint(path, updateTime) {
  return sha256(JSON.stringify([path, updateTime.seconds, updateTime.nanoseconds]));
}

function plainTimestamp(value) {
  const seconds = value?.seconds;
  const nanoseconds = value?.nanoseconds;
  if (!Number.isSafeInteger(seconds) || seconds < 0 || !Number.isInteger(nanoseconds) ||
      nanoseconds < 0 || nanoseconds >= 1e9) {
    fail("internal", "A Firestore snapshot did not carry a usable timestamp.");
  }
  return { seconds, nanoseconds };
}

function familyMigrationAllowed(paths = V1_CLIENT_READ_PATHS) {
  return FAMILY_RULES_BRANCHES.every((key) => paths[key] === true);
}

function managementParityExists(capabilities = V1_MANAGEMENT_CAPABILITIES) {
  return Object.values(capabilities).every((value) => value === true);
}

function assertDurableMemberSource(scope) {
  if (!DURABLE_MEMBER_SOURCES.includes(scope)) {
    fail("internal", "A transient participation roster is not a membership source.");
  }
  return scope;
}

function assertPatchPreserves(patch, immutable, label) {
  for (const field of immutable) {
    if (Object.hasOwn(patch, field)) {
      fail("internal", `A migration patch attempted to rewrite an immutable ${label} field.`);
    }
  }
  return patch;
}

function deepEqual(a, b) {
  if (a === b) return true;
  if (a === null || b === null || typeof a !== "object" || typeof b !== "object") return false;
  if (Array.isArray(a) !== Array.isArray(b)) return false;
  if (Array.isArray(a)) return a.length === b.length && a.every((item, index) => deepEqual(item, b[index]));
  const keys = Object.keys(a);
  if (keys.length !== Object.keys(b).length) return false;
  return keys.every((key) => Object.hasOwn(b, key) && deepEqual(a[key], b[key]));
}

/**
 * Drops every field the document already carries with that exact value, so a
 * patch that would change nothing becomes an empty patch and therefore no
 * write. This is where per-root idempotence actually comes from.
 */
function reduceToChanges(current, desired) {
  const patch = {};
  for (const [key, value] of Object.entries(desired)) {
    if (!deepEqual(current?.[key], value)) patch[key] = value;
  }
  return patch;
}

/**
 * The single write surface. In `dryRun` the transaction object is never
 * reached, so a dry run cannot construct a write even by mistake; it records
 * the intent — path plus field NAMES, never values, which would put display
 * names and media URLs into a manifest — and counts it.
 */
function createWriter(mode, transaction) {
  if (!MODES.includes(mode)) fail("invalid-argument", "The migration mode is unsupported.");
  const intents = [];
  let applied = 0;
  return {
    mode,
    intents,
    write(item) {
      if (item.op === "update" && Object.keys(item.data).length === 0) return;
      intents.push({ op: item.op, path: item.reference.path, fields: Object.keys(item.data).sort(compare) });
      if (mode !== "apply") return;
      if (item.op === "update") transaction.update(item.reference, item.data);
      else transaction.set(item.reference, item.data);
      applied += 1;
    },
    // Planned writes are what a dry run reports; applied writes are what
    // actually reached Firestore. They are counted separately so a dry run
    // can prove the second number is zero instead of asserting it.
    planned() { return intents.length; },
    applied() { return applied; },
  };
}

async function probeCount(transaction, query) {
  const snapshot = await transaction.get(query);
  return snapshot.size;
}

/**
 * The transient-participation probe. It returns a COUNT and nothing else: the
 * snapshot never leaves this function, so no uid, display name or session role
 * from a live RTC roster can reach a membership decision or the manifest.
 */
async function probeTransientParticipants(transaction, roomReference) {
  const snapshot = await transaction.get(roomReference.collection("participants").limit(EXISTENCE_PROBE));
  return snapshot.size;
}

function liveRoom(room) {
  return room.isLive === true ||
    (Number.isSafeInteger(room.participantCount) && room.participantCount > 0) ||
    (typeof room.voiceSessionId === "string" && room.voiceSessionId.length > 0);
}

/**
 * The V1 post-image of one legacy channel. Everything is deterministic:
 * `kind` from the legacy `type`, media configuration from `kind` through the
 * SAME `mediaConfiguration()` the creation path uses, `historySource` from
 * where the history physically already is.
 */
function channelPostImage({ serverId, channel, historySource }) {
  const reasons = [];
  const kind = LEGACY_CHANNEL_KIND[channel.type];
  if (!kind) return { reasons: ["unsupported-legacy-channel-type"], desired: null };
  if (channel.type !== legacyChannelType(kind)) reasons.push("unsupported-legacy-channel-type");
  if (!Number.isSafeInteger(channel.position) || channel.position < 0) {
    reasons.push("channel-position-missing-or-malformed");
  }
  // This legacy flag is security authority. Only the exact public value may
  // enter the all-members V1 post-image; missing, null, strings and numbers
  // are unknown privacy and fail closed instead of becoming public.
  if (channel.isPrivate !== false) {
    reasons.push(channel.isPrivate === true
      ? "restricted-legacy-channel-requires-access-mapping"
      : "channel-privacy-flag-missing-or-malformed");
  }
  // A channel this run already staged is NOT an error — re-running the stage
  // has to reduce to zero writes. Only a version this engine does not
  // understand refuses, and it refuses rather than being overwritten.
  if (channel.serverSchemaVersion !== undefined && channel.serverSchemaVersion !== 1) {
    reasons.push("unsupported-channel-schema-version");
  }
  const media = kind === "voice";
  const roomId = channel.roomId ?? null;
  if (media && (typeof roomId !== "string" || !SAFE_ID.test(roomId))) {
    reasons.push("media-channel-without-a-room-anchor");
  }
  if (!media && roomId !== null) reasons.push("non-media-channel-carries-a-room-anchor");
  if (reasons.length > 0) return { reasons: sortedUnique(reasons), desired: null };
  const { experience, mediaMode } = mediaConfiguration(kind, media ? "community" : null, media ? "audio" : null);
  const desired = {
    serverSchemaVersion: 1, serverId, kind,
    accessMode: "members", isPrivate: false,
    accessPolicy: { ...accessPolicy({ accessMode: "members", roleIds: [], userIds: [] }) },
    categoryId: null, status: "active", roomId,
    activeSessionId: null,
    experience, mediaMode, aclRevision: 1, revision: 1,
    historySource,
  };
  // TWO fields are deliberately NOT part of this post-image.
  //
  // `liveness` belongs to the ROOT stage. `firestore.rules` refuses a legacy
  // manager's channel update whose POST-write document carries a `liveness`
  // map (`noClientChannelLiveness()`, which guards the forged-LIVE-badge
  // case). Staging it onto a root that is still unversioned would therefore
  // break channel rename, reorder and delete for that Club's managers for as
  // long as the staging window lasts — the staged half is supposed to be
  // inert, and with `liveness` in it, it is not. It is written in the same
  // transaction that versions the root, where the legacy rule no longer
  // applies to anyone.
  //
  // `updatedAt` differs on every run by construction, so including it here
  // would make a re-run of an unfinished stage rewrite every document it
  // already wrote. The caller stamps it only when the patch is otherwise
  // non-empty.
  return { reasons: [], desired: assertPatchPreserves(desired, IMMUTABLE_CHANNEL_FIELDS, "channel") };
}

/**
 * The V1 post-image of one legacy root. `migration` is exactly the four fields
 * the contract defines, and `entitlementPolicyId` is asserted against the
 * shared capacity classifier rather than merely assigned.
 */
function rootPostImage({ sourceKind, sourceId, serverType, entitlementPolicyId, memberCount, state }) {
  if (!MIGRATION_STATES.includes(state)) fail("internal", "An unsupported migration state was requested.");
  const desired = {
    serverSchemaVersion: 1, serverType, templateVersion: 1, entitlementPolicyId,
    serverActivationState: "held", status: "preparing", revision: 1,
    type: serverType === "family" ? "family" : "community",
    memberCount, onlineCount: 0,
    migration: { version: MIGRATION_RECORD_VERSION, sourceKind, sourceId, state },
  };
  assertPatchPreserves(desired, IMMUTABLE_ROOT_FIELDS, "root");
  // The post-image goes through the SAME classifier the free/paid allowance
  // reads. A paid Club must classify as legacyCommunityPremiumV1, which is not
  // a free-allocation policy and therefore can never consume one of the 20
  // free servers; an adopted room keeps its own room-scoped allocation
  // identity and is therefore never charged twice.
  const classified = classifyServerAllocation(desired);
  if (classified.policy !== entitlementPolicyId || classified.versioned !== true) {
    fail("internal", "The migrated allocation policy does not classify as intended.");
  }
  if (sourceKind === "club" && FREE_ALLOCATION_POLICIES.includes(entitlementPolicyId)) {
    fail("internal", "A migrated Club must never be charged to the free server allowance.");
  }
  if (entitlementPolicyId === "legacyRoomV1" &&
      (desired.migration.sourceKind !== "room" || !SAFE_ID.test(desired.migration.sourceId))) {
    // readOwnerAllocations() de-duplicates an adopted room by exactly this
    // provenance and fails closed without it.
    fail("internal", "A migrated room allocation needs its source provenance.");
  }
  return desired;
}

/**
 * Reduce, then stamp. A document that already carries every desired value is
 * left completely alone — including its `updatedAt` — so re-running an
 * unfinished stage writes nothing rather than writing a fresh timestamp over
 * identical content.
 */
function stampedPatch(current, desired, stamp) {
  const patch = reduceToChanges(current, desired);
  if (Object.keys(patch).length > 0) patch.updatedAt = stamp;
  return patch;
}

function stepKey(mapping) {
  return `${mapping.provenance.sourceKind}_${mapping.provenance.sourceId}`;
}

/**
 * A write intent's SHAPE, with every document id replaced by `*`. It is what a
 * reviewer needs from a dry run — how many members, how many channels, how
 * many roots — without the manifest carrying one more identifier than the
 * source ids it already lists.
 */
function intentShape(path) {
  const parts = path.split("/");
  return parts.map((part, index) => (index % 2 === 1 ? "*" : part)).join("/");
}

/**
 * Which of the eight `REQUIRED_NEXT_GATES` this run can evidence. A gate is
 * closed only by something this run actually observed; nothing here can close
 * `separate-production-migration-approval`, which is why `applyReady` never
 * becomes true.
 */
function gateStatus({ inventoryComplete, clientGateSatisfied, refusalsEnforced }) {
  const closed = {
    // The Firestore-side related-record inventory is complete and enforced, but
    // no Storage object or generation enumeration exists: the engine preserves
    // media by never writing it, which is not the same as having inventoried
    // it. Reported open until a Storage listing pass exists.
    "complete-related-record-and-media-generation-inventory": inventoryComplete,
    "canonical-owner-membership-ban-and-invitation-validation": refusalsEnforced,
    // Satisfied conservatively: every restricted legacy channel REFUSES, so no
    // access mapping is ever converted without an explicit later review.
    "reviewed-private-admission-and-channel-access-mapping": refusalsEnforced,
    "shared-free-paid-and-family-allocation-reconciliation": refusalsEnforced,
    "compatible-client-and-idle-session-cutover-gate": clientGateSatisfied,
    // HALF closed, therefore reported OPEN. The SOURCE half is real: every
    // stage transaction recomputes the root's version fingerprint and refuses a
    // stale plan. The PROVIDER half is not: this engine never contacts LiveKit,
    // it refuses on any liveness signal in Firestore instead. That is
    // conservative, but it is not the provider-generation revalidation the gate
    // names, and `docs/Servers.md` already carries an undischarged activation
    // precondition for exactly the provider's empty-room semantics.
    "transaction-time-source-and-provider-generation-revalidation": false,
    // The RESUME half is proven (the manifest reports `resumeProven`), but the
    // gate names resume AND a reviewed non-destructive rollback, and the
    // second half does not exist: removing `serverSchemaVersion` reopens a
    // legacy read branch over data that may since have become private, so
    // there is no safe generic inverse for the root write. Reported open.
    "reviewed-resumable-apply-and-non-destructive-rollback": false,
    // No code path can attest to a human approval, and inventing one would be
    // the exact failure this whole staged design exists to prevent.
    "separate-production-migration-approval": false,
  };
  return REQUIRED_NEXT_GATES.map((gate) => ({ gate, closed: closed[gate] === true }));
}

function createLegacyMigrationApplyEngine(dependencies) {
  if (dependencies === null || typeof dependencies !== "object" || Array.isArray(dependencies)) {
    fail("invalid-argument", "Apply engine dependencies are invalid.");
  }
  const allowed = ["firestore", "Timestamp", "projectId", "emulator", "mode", "clock"];
  if (Object.keys(dependencies).some((key) => !allowed.includes(key))) {
    fail("invalid-argument", "Apply engine dependencies contain an unsupported key.");
  }
  const { firestore, Timestamp, projectId, emulator, mode = "dryRun", clock = Date.now } = dependencies;
  if (firestore === null || typeof firestore !== "object" ||
      ["collection", "doc", "runTransaction"].some((method) => typeof firestore[method] !== "function")) {
    fail("invalid-argument", "A Firestore instance is required.");
  }
  if (!Timestamp || typeof Timestamp.fromMillis !== "function") {
    fail("invalid-argument", "A Timestamp factory is required.");
  }
  if (typeof projectId !== "string" || !PROJECT_ID.test(projectId)) fail("invalid-argument", "projectId is invalid.");
  if (typeof emulator !== "boolean") fail("invalid-argument", "emulator must be a boolean.");
  if (!MODES.includes(mode)) fail("invalid-argument", "mode is invalid.");
  if (typeof clock !== "function") fail("invalid-argument", "clock must be a function.");
  // Write mode exists to PROVE the engine against a local emulator. A
  // production apply is the eighth required gate: a separately approved,
  // human-run step this module deliberately cannot perform.
  //
  // `emulator: true` is a caller ASSERTION; the three facts below are
  // OBSERVATIONS, and the single guarantee this whole design rests on may not
  // be the one guarantee taken on trust. A future caller — a script, a
  // repaired harness, a copy of the runbook — constructing the engine with
  // `emulator: true` while the admin app resolves a production project would
  // otherwise write to production. The CLI already checks all three; the CLI
  // cannot reach apply mode, so the check lived only where it was not needed.
  if (mode === "apply") {
    if (emulator !== true || !LOCAL_EMULATOR_HOST.test(process.env.FIRESTORE_EMULATOR_HOST ?? "") ||
        !projectId.startsWith("demo-")) {
      fail("failed-precondition", "Write mode is available only against a local emulator.");
    }
  }

  function now() {
    const millis = clock();
    if (!Number.isSafeInteger(millis) || millis < 0) fail("internal", "The clock did not return a usable time.");
    return Timestamp.fromMillis(millis);
  }

  function sourceUnchanged(mapping, snapshot) {
    const expected = mapping.sourceVersion?.versionFingerprint;
    if (typeof expected !== "string" || expected.length === 0) return false;
    return fingerprint(mapping.sourcePath, plainTimestamp(snapshot.updateTime)) === expected;
  }

  /**
   * Every room this Club owns — by the BACK-POINTER, not only by the forward
   * pointers.
   *
   * The boundary the migration is about to cross is keyed on `room.clubId`:
   * `firestore.rules` isLegacyRoomData() reads it, `clubs/deletion.js` and
   * `clubs/voice.js` both enumerate with `.where("clubId","==",clubId)`. A
   * room bound to the Club by that field but named by no channel and not by
   * `loungeRoomId` used to be invisible to ALL THREE protective probes at
   * once — measured: a root planned `applied` while that room was live with
   * seven participants and five messages, every count reading zero. Both
   * `active-session-must-not-be-migrated` and
   * `bound-room-history-would-lose-its-read-path` failed silently, through
   * the same hole, and the operator's runbook says to read the refusals.
   *
   * So the set is the UNION of three sources, and the query is bounded with
   * an explicit overflow refusal rather than paging further:
   *   1. `channel.roomId` for every channel (forward);
   *   2. `root.loungeRoomId`, plus the `club_lounge_{clubId}` fallback that
   *      `clubs/deletion.js:205-212` asserts is a real state, because lounges
   *      are created lazily and a club can have one with no pointer to it;
   *   3. `rooms.where("clubId","==",sourceId)` (back-pointer), the same
   *      authority the deletion sweep and the Rules use.
   */
  async function readBoundRooms({ transaction, mapping, root, channels }) {
    const data = root.snapshot.data();
    const ids = new Set();
    if (mapping.provenance.sourceKind === "club") {
      for (const channel of channels) {
        const roomId = channel.data.roomId;
        if (typeof roomId === "string" && SAFE_ID.test(roomId)) ids.add(roomId);
      }
      if (typeof data.loungeRoomId === "string" && SAFE_ID.test(data.loungeRoomId)) ids.add(data.loungeRoomId);
      const lazyLounge = `club_lounge_${mapping.provenance.sourceId}`;
      if (SAFE_ID.test(lazyLounge)) ids.add(lazyLounge);
      const bound = await transaction.get(
        firestore.collection("rooms")
          .where("clubId", "==", mapping.provenance.sourceId)
          .limit(MAX_BOUND_ROOMS_PER_ROOT + 1),
      );
      if (bound.size > MAX_BOUND_ROOMS_PER_ROOT) return { rooms: [], overflowed: true };
      for (const document of bound.docs) if (SAFE_ID.test(document.id)) ids.add(document.id);
    }
    const sorted = [...ids].sort(compare);
    if (sorted.length > MAX_BOUND_ROOMS_PER_ROOT) return { rooms: [], overflowed: true };
    const rooms = [];
    for (const id of sorted) {
      const reference = firestore.doc(`rooms/${id}`);
      const snapshot = await transaction.get(reference);
      rooms.push({ id, reference, data: snapshot.exists ? snapshot.data() : null });
    }
    return { rooms, overflowed: false };
  }

  /**
   * Liveness and transient participation for every anchor this root owns,
   * plus the root itself when the root IS a room. Run in EVERY stage
   * transaction, so a session that starts mid-run defers the root rather than
   * racing it.
   */
  async function probeLiveness({ transaction, mapping, root, boundRooms }) {
    const anchors = [...boundRooms];
    if (mapping.provenance.sourceKind === "room") {
      anchors.push({ id: mapping.provenance.sourceId, reference: root.reference,
        data: root.snapshot.exists ? root.snapshot.data() : null });
    }
    let live = 0;
    let participants = 0;
    for (const anchor of anchors) {
      if (!anchor.data) continue;
      if (liveRoom(anchor.data)) live += 1;
      participants += await probeTransientParticipants(transaction, anchor.reference);
    }
    const reasons = [];
    if (live > 0) reasons.push("active-session-must-not-be-migrated");
    if (participants > 0) reasons.push("transient-participants-present");
    return { live, participants, reasons };
  }

  async function probeStrandedResources({ transaction, mapping, root, boundRooms }) {
    const reference = root.reference;
    const data = root.snapshot.data();
    const observed = {
      clubMoments: 0, clubCheckIns: 0, boundRoomMessages: 0, boundRoomArtwork: 0,
      clubArtwork: 0, pendingInvitations: 0,
    };
    if (mapping.provenance.sourceKind === "club") {
      observed.clubMoments = await probeCount(transaction, reference.collection("moments").limit(EXISTENCE_PROBE));
      observed.clubCheckIns = await probeCount(transaction, reference.collection("checkIns").limit(EXISTENCE_PROBE));
      const invites = await transaction.get(reference.collection("invites").limit(MAX_INVITE_PROBE + 1));
      observed.pendingInvitations = invites.size > MAX_INVITE_PROBE
        ? invites.size
        : invites.docs.filter((doc) => doc.data()?.status === "pending").length;
      observed.clubArtwork = [data.avatarUrl, data.bannerUrl]
        .filter((value) => typeof value === "string" && value.length > 0).length;
    } else {
      observed.clubArtwork = typeof data.imageUrl === "string" && data.imageUrl.length > 0 ? 1 : 0;
    }
    for (const room of boundRooms) {
      observed.boundRoomMessages += await probeCount(transaction, room.reference.collection("messages").limit(EXISTENCE_PROBE));
      if (typeof room.data?.imageUrl === "string" && room.data.imageUrl.length > 0) observed.boundRoomArtwork += 1;
    }
    const reasons = [];
    for (const entry of STRANDED_IF_NON_EMPTY) {
      if (observed[entry.resource] > 0 && V1_CLIENT_READ_PATHS[entry.capability] !== true) {
        reasons.push(entry.reason);
      }
    }
    return { observed, reasons };
  }

  function memberPostImage(uid, member) {
    const reasons = [];
    if (!isValidOpaqueUid(uid) || member.userId !== uid || !ROLES.includes(member.role)) {
      reasons.push("member-record-needs-reconciliation");
    }
    const current = member.authorizationRevision;
    const revision = Number.isSafeInteger(current) && current > 0 && current < Number.MAX_SAFE_INTEGER
      ? current : 1;
    // Presence is reset, never carried: `isOnline` has no V1 writer, so the
    // only honest value after migration is false. `banned` is on the immutable
    // list, so a ban survives the migration untouched.
    const desired = { authorizationRevision: revision, isOnline: false };
    assertPatchPreserves(desired, IMMUTABLE_MEMBER_FIELDS, "member");
    return { reasons: sortedUnique(reasons), desired, revision };
  }

  /**
   * One root, one stage, one transaction. Nothing is written until every
   * validation for that stage has passed: writes are buffered as intents and
   * flushed only at the end, so a refusal can never leave a half-applied
   * stage behind. The run's step record is written in the SAME transaction as
   * the stage it describes, which is what makes resume exact.
   */
  async function runStage({ runId, mapping, stage, step, expectedGateRevision, clientCensus }) {
    return firestore.runTransaction(async (transaction) => {
      const stamp = now();
      const result = { stage, reasons: [], writes: 0, planned: 0, intents: [], counts: {}, alreadyApplied: false };
      const collection = mapping.provenance.sourceKind === "club" ? "clubs" : "rooms";
      const rootReference = firestore.doc(`${collection}/${mapping.provenance.sourceId}`);
      const rootSnapshot = await transaction.get(rootReference);
      const root = { reference: rootReference, snapshot: rootSnapshot };
      const refuse = (...reasons) => { result.reasons = sortedUnique([...result.reasons, ...reasons]); return result; };

      if (!rootSnapshot.exists) return refuse("source-root-missing");
      const data = rootSnapshot.data();
      // Idempotence is checked BEFORE staleness, and the order matters. Any
      // write changes a document's update time, so a plan replayed after its
      // own run finished is stale BY CONSTRUCTION; checking staleness first
      // would report every replay as "your plan moved" and hide the fact that
      // the work is simply already done. Both answers refuse and neither
      // writes, so the only thing at stake is which one an operator reads —
      // and "already migrated" is the true one.
      if (isVersionedServer(data)) {
        const migration = data.migration;
        const matches = Boolean(migration) && migration.version === MIGRATION_RECORD_VERSION &&
          migration.sourceKind === mapping.provenance.sourceKind &&
          migration.sourceId === mapping.provenance.sourceId;
        result.alreadyApplied = matches;
        return refuse(matches ? "already-migrated" : "target-already-versioned-by-another-provenance");
      }
      // Transaction-time source revalidation: for a root that is NOT already
      // migrated, a plan computed from an older snapshot is a stale decision,
      // not a target.
      if (!sourceUnchanged(mapping, rootSnapshot)) return refuse("source-version-changed-since-plan");
      if (data.status !== "active" || data.deletionInProgress === true) {
        return refuse("root-not-active-or-being-deleted");
      }
      // ADR-F, beside ADR-E and for the same reason: a root migrated while
      // the management parity slice is missing is un-moderatable, and that
      // cannot be hotfixed from the client.
      if (!managementParityExists()) {
        return refuse("management-parity-slice-does-not-exist-yet");
      }
      // ADR-E, before any work that could be mistaken for progress.
      const family = data.type === "family" || mapping.serverType === "family" ||
        mapping.provenance.sourceId.startsWith("family_");
      if (family && !familyMigrationAllowed()) {
        return refuse("family-migration-deferred-until-v1-rules-branches-exist");
      }
      if (mapping.provenance.sourceKind === "room" && V1_CLIENT_READ_PATHS.standaloneRoomAdoption !== true) {
        return refuse("standalone-room-adoption-has-no-v1-client-read-path");
      }

      const channelSnapshot = await transaction.get(
        rootReference.collection("channels").orderBy(FieldPath.documentId()).limit(MAX_CHANNELS_PER_ROOT + 1),
      );
      if (channelSnapshot.size > MAX_CHANNELS_PER_ROOT) return refuse("channel-set-exceeds-bounded-page-budget");
      const channels = channelSnapshot.docs.map((doc) => ({ id: doc.id, reference: doc.ref, data: doc.data() }));
      const bound = await readBoundRooms({ transaction, mapping, root, channels });
      if (bound.overflowed) return refuse("bound-room-set-exceeds-bounded-page-budget");
      const liveness = await probeLiveness({ transaction, mapping, root, boundRooms: bound.rooms });
      const stranded = await probeStrandedResources({ transaction, mapping, root, boundRooms: bound.rooms });
      // `boundRooms` counts the rooms that EXIST, not the ids that were
      // probed. The discovery set deliberately carries ids that may not
      // resolve — the lazy `club_lounge_{id}` fallback, and a channel pointer
      // left behind by a room that is gone — and counting those would report
      // phantom bound rooms in the very manifest an operator reads before
      // deciding anything. Over-reporting is a smaller failure than the
      // under-reporting this probe was widened to fix, but it is still a
      // count that does not mean what it says.
      const existingBoundRooms = bound.rooms.filter((room) => room.data !== null).length;
      result.counts = { channels: channels.length, boundRooms: existingBoundRooms,
        liveRooms: liveness.live, transientParticipants: liveness.participants, ...stranded.observed };
      if (liveness.reasons.length > 0 || stranded.reasons.length > 0) {
        return refuse(...liveness.reasons, ...stranded.reasons);
      }

      const pending = [];
      let nextStage = stage;
      const progress = { memberCursor: step.memberCursor, memberCount: step.memberCount,
        ownerSeen: step.ownerSeen, channelCount: step.channelCount };

      if (stage === "members") {
        assertDurableMemberSource("members");
        let query = rootReference.collection("members").orderBy(FieldPath.documentId()).limit(MEMBER_PAGE_SIZE + 1);
        if (step.memberCursor !== null) query = query.startAfter(step.memberCursor);
        const page = await transaction.get(query);
        const docs = page.docs.slice(0, MEMBER_PAGE_SIZE);
        const more = page.size > MEMBER_PAGE_SIZE;
        const total = step.memberCount + docs.length;
        if (total > MAX_MEMBERS_PER_ROOT) return refuse("member-graph-exceeds-bounded-page-budget");
        const authorizations = docs.length === 0 ? [] : await transaction.getAll(
          ...docs.map((doc) => rootReference.collection("memberAuthorizations").doc(doc.id)),
        );
        const reasons = [];
        let ownerSeen = step.ownerSeen;
        docs.forEach((doc, index) => {
          const member = doc.data();
          const view = memberPostImage(doc.id, member);
          if (view.reasons.length > 0) { reasons.push(...view.reasons); return; }
          if (member.role === "owner") {
            if (data.ownerId !== doc.id) reasons.push("owner-membership-missing-or-not-canonical");
            ownerSeen = true;
          } else if (data.ownerId === doc.id) {
            reasons.push("owner-membership-missing-or-not-canonical");
          }
          pending.push({ op: "update", reference: doc.ref, data: reduceToChanges(member, view.desired) });
          const authorization = authorizations[index];
          const current = authorization.exists ? authorization.data() : null;
          const unchanged = Boolean(current) && current.schemaVersion === 1 && current.userId === doc.id &&
            current.revision === view.revision && current.status === "member";
          if (!unchanged) {
            pending.push({ op: "set", reference: authorization.ref, data: {
              schemaVersion: 1, userId: doc.id, revision: view.revision, status: "member", updatedAt: stamp,
            } });
          }
        });
        if (reasons.length > 0) return refuse(...reasons);
        if (!more && !ownerSeen) return refuse("owner-membership-missing-or-not-canonical");
        progress.memberCursor = more ? docs.at(-1).id : null;
        progress.memberCount = total;
        progress.ownerSeen = ownerSeen;
        if (!more) nextStage = "channels";
      } else if (stage === "channels") {
        const historySource = mapping.provenance.sourceKind === "room"
          ? { kind: "legacyRoomMessages", roomId: mapping.provenance.sourceId }
          : { kind: "channelMessages" };
        const reasons = [];
        for (const channel of channels) {
          const view = channelPostImage({
            serverId: mapping.provenance.sourceId, channel: channel.data, historySource,
          });
          if (view.reasons.length > 0) { reasons.push(...view.reasons); continue; }
          pending.push({ op: "update", reference: channel.reference, data: stampedPatch(channel.data, view.desired, stamp) });
        }
        if (reasons.length > 0) return refuse(...reasons);
        progress.channelCount = channels.length;
        nextStage = "root";
      } else if (stage === "root") {
        const gateSnapshot = await transaction.get(firestore.doc(CLIENT_GATE_PATH));
        let assessment = null;
        try {
          assessment = assessClientGate({ snapshot: gateSnapshot, expectedRevision: expectedGateRevision, census: clientCensus });
        } catch {
          return refuse("client-compatibility-gate-not-satisfied");
        }
        result.gate = {
          // `satisfied` is the assessment's own verdict, not a value re-derived
          // from the fields below: a pinned-revision mismatch refuses while
          // status is "satisfied" and the census is clean, so recomputing it
          // here would report a closed gate for a run the gate just stopped.
          satisfied: assessment.satisfied, reasons: assessment.reasons,
          revision: assessment.gate.revision, status: assessment.gate.status,
          minimumClientVersion: assessment.gate.minimumClientVersion,
          minimumClientBuild: assessment.gate.minimumClientBuild,
          incompatibleSessions: assessment.observed.incompatibleSessions,
          compatibleSessions: assessment.observed.compatibleSessions,
          incompatiblePlatforms: assessment.observed.platforms,
        };
        if (!assessment.satisfied) return refuse(...assessment.reasons);
        if (!Number.isSafeInteger(step.memberCount) || step.memberCount < 1 || step.ownerSeen !== true) {
          return refuse("member-stage-did-not-complete");
        }
        // The root is only versioned when every one of its channels really is.
        // In `apply` that is read off the documents. In `dryRun` nothing was
        // written, so the honest equivalent is that the channels stage this
        // run just planned covered exactly these channels — checking the
        // documents there would refuse every root for not having the writes a
        // dry run is defined not to make.
        const staged = channels.every((channel) => channel.data.serverSchemaVersion === 1);
        const plannedAll = mode === "dryRun" && step.channelCount === channels.length;
        if (channels.length === 0 || !(staged || plannedAll)) {
          return refuse("channel-stage-did-not-complete");
        }
        if (data.type !== undefined && data.type !== "community") return refuse("unknown-legacy-server-type");
        const desired = rootPostImage({
          // The plan's own provenance, not a hardcoded "club". A room-sourced
          // root is refused earlier today, so this never fired — but the day
          // `standaloneRoomAdoption` flips, the first adopted room would
          // reach here as `legacyRoomV1` + `sourceKind: "club"` and throw
          // `internal` with the WRONG diagnosis, aborting the entire run
          // (there is no per-root try/catch) rather than that one root.
          sourceKind: mapping.provenance.sourceKind, sourceId: mapping.provenance.sourceId,
          serverType: mapping.serverType, entitlementPolicyId: mapping.entitlementPolicyId,
          memberCount: step.memberCount, state: "complete",
        });
        // The liveness projection lands here, with the root, for the reason
        // given in channelPostImage: it is the field a legacy channel update
        // is refused for carrying.
        for (const channel of channels) {
          pending.push({ op: "update", reference: channel.reference,
            data: stampedPatch(channel.data, { liveness: channelLiveness() }, stamp) });
        }
        pending.push({ op: "update", reference: rootReference, data: stampedPatch(data, desired, stamp) });
        nextStage = "complete";
      } else {
        return refuse("unsupported-stage");
      }

      const writer = createWriter(mode, transaction);
      for (const item of pending) writer.write(item);
      if (mode === "apply") {
        writer.write({ op: "set", reference: firestore.doc(`${RUN_COLLECTION}/${runId}`)
          .collection(RUN_STEP_COLLECTION).doc(stepKey(mapping)), data: {
          schemaVersion: APPLY_VERSION, runId,
          sourceKind: mapping.provenance.sourceKind, sourceId: mapping.provenance.sourceId,
          targetServerId: mapping.serverId ?? null, stage: nextStage, state: STAGE_STATE[nextStage],
          memberCursor: progress.memberCursor, memberCount: progress.memberCount,
          ownerSeen: progress.ownerSeen === true, channelCount: progress.channelCount,
          sourceFingerprint: mapping.sourceVersion?.versionFingerprint ?? null,
          disposition: nextStage === "complete" ? "applied" : "inProgress", updatedAt: stamp,
        } });
      }
      result.writes = writer.applied();
      result.planned = writer.planned();
      result.intents = writer.intents;
      result.nextStage = nextStage;
      result.progress = progress;
      return result;
    });
  }

  /**
   * The run ledger. The plan digest is recorded for provenance and reported
   * when it drifts, but it deliberately does NOT gate a resume: the engine's
   * own staged writes change channel documents, so a re-collected plan has a
   * different digest by construction and a digest gate would make every
   * interrupted run unresumable. Per-root safety is the ROOT document's own
   * version fingerprint, which the staged members and channels writes never
   * touch, checked twice — against the run record here, and against the live
   * document inside every stage transaction.
   */
  async function readRunRecord(runId, planDigest) {
    const reference = firestore.doc(`${RUN_COLLECTION}/${runId}`);
    const snapshot = await reference.get();
    const steps = new Map();
    let planDigestAtRunStart = planDigest;
    if (snapshot.exists) {
      const run = snapshot.data();
      if (run.schemaVersion !== APPLY_VERSION || run.runId !== runId) {
        fail("failed-precondition", "The migration run record needs reconciliation.");
      }
      if (run.projectId !== projectId) fail("failed-precondition", "This run record belongs to a different project.");
      if (typeof run.planDigest === "string") planDigestAtRunStart = run.planDigest;
    }
    const stepSnapshot = await reference.collection(RUN_STEP_COLLECTION)
      .orderBy(FieldPath.documentId()).limit(MAX_ROOTS_PER_RUN + 1).get();
    if (stepSnapshot.size > MAX_ROOTS_PER_RUN) fail("failed-precondition", "The run record exceeds its bound.");
    for (const doc of stepSnapshot.docs) steps.set(doc.id, doc.data());
    return { reference, exists: snapshot.exists, steps, planDigestAtRunStart,
      planDigestChanged: planDigestAtRunStart !== planDigest };
  }

  /**
   * Execute (or plan) one run over a reviewed mapping report.
   *
   * `mappings` are `planLegacyServerMappings(...).mappings` entries; only
   * `planned` ones are eligible. `expectedGateRevision` is the client-gate
   * revision the operator reviewed and `clientCensus` is their observed
   * installed base. Neither can be derived from the database, which is the
   * point: they are the human half of the old-client gate.
   */
  async function run({ runId, mappings, planDigest, expectedGateRevision, clientCensus = null }) {
    if (typeof runId !== "string" || !SAFE_ID.test(runId)) fail("invalid-argument", "runId is invalid.");
    if (!Array.isArray(mappings)) fail("invalid-argument", "mappings must be an array.");
    if (mappings.length > MAX_ROOTS_PER_RUN) fail("invalid-argument", "The run exceeds its root bound.");
    if (typeof planDigest !== "string" || !DIGEST.test(planDigest)) fail("invalid-argument", "planDigest is invalid.");
    if (!Number.isSafeInteger(expectedGateRevision) || expectedGateRevision < 1 ||
        expectedGateRevision >= Number.MAX_SAFE_INTEGER) {
      fail("invalid-argument", "expectedGateRevision must pin the reviewed client gate revision.");
    }
    const record = mode === "apply"
      ? await readRunRecord(runId, planDigest)
      : { reference: null, exists: false, steps: new Map(), planDigestAtRunStart: planDigest, planDigestChanged: false };
    const generatedAt = new Date(now().toMillis()).toISOString();
    const roots = [];
    let writeCount = 0;
    let plannedWrites = 0;
    let resumedRoots = 0;
    let clientGate = null;
    const plannedByShape = {};

    for (const mapping of mappings) {
      if (!mapping || typeof mapping !== "object" || typeof mapping.sourcePath !== "string") {
        fail("invalid-argument", "A mapping entry is invalid.");
      }
      if (mapping.disposition !== "planned") {
        // `already-versioned` is not a refusal: the planner is reporting a root
        // that a previous run finished. It is recorded as such so a re-run's
        // summary reads as "nothing left to do" rather than as a wall of
        // refusals.
        const done = mapping.disposition === "already-versioned";
        roots.push({ sourcePath: mapping.sourcePath, sourceKind: null, sourceId: null,
          targetServerId: mapping.serverId ?? null,
          disposition: done ? "already-applied" : "refused", stage: done ? "complete" : null, stagesRun: [],
          reasons: [done ? "plan-already-versioned" : `plan-disposition-${mapping.disposition}`],
          writes: 0, plannedWrites: 0, counts: {},
          alreadyApplied: done, resumed: false, memberCount: 0, channelCount: 0 });
        continue;
      }
      // A room bound to a Club carries no provenance of its own: the planner
      // maps it THROUGH its parent, and migrating the parent is what moves it.
      // Treating it as a second root would produce a second target for one
      // space, so it is recorded as covered and never applied separately.
      if (!mapping.provenance && mapping.sourcePath.startsWith("rooms/") &&
          typeof mapping.serverId === "string") {
        roots.push({ sourcePath: mapping.sourcePath, sourceKind: "room", sourceId: null,
          targetServerId: mapping.serverId, disposition: "covered", stage: null, stagesRun: [],
          reasons: ["bound-room-is-migrated-with-its-parent-server"], writes: 0, plannedWrites: 0, counts: {},
          alreadyApplied: false, resumed: false, memberCount: 0, channelCount: 0 });
        continue;
      }
      if (!mapping.provenance || !["club", "room"].includes(mapping.provenance.sourceKind) ||
          typeof mapping.provenance.sourceId !== "string" || !SAFE_ID.test(mapping.provenance.sourceId)) {
        fail("invalid-argument", "A mapping entry is invalid.");
      }
      const entry = {
        sourcePath: mapping.sourcePath, sourceKind: mapping.provenance.sourceKind,
        sourceId: mapping.provenance.sourceId, targetServerId: mapping.serverId ?? null,
        serverType: mapping.serverType ?? null, entitlementPolicyId: mapping.entitlementPolicyId ?? null,
        disposition: "refused", stage: null, stagesRun: [], reasons: [], writes: 0, plannedWrites: 0,
        counts: {}, alreadyApplied: false, resumed: false, memberCount: 0, channelCount: 0,
        // Migration writes `held` + `preparing`, so the space is owner-only
        // until a separately authorized activation. That is not a defect of
        // this engine; it is why activation is its own gate.
        memberAccessSuspendedUntilActivation: true,
      };
      const key = stepKey(mapping);
      const step = record.steps.get(key) ?? null;
      if (step) { entry.resumed = true; resumedRoots += 1; }
      // A run record written for a DIFFERENT version of this root is not a
      // resume point. The root's own fingerprint is the identity here, not the
      // whole-plan digest.
      if (step && step.sourceFingerprint !== (mapping.sourceVersion?.versionFingerprint ?? null)) {
        entry.reasons = ["resume-record-does-not-match-this-source-version"];
        entry.stage = step.stage ?? null;
        roots.push(entry);
        continue;
      }
      let stage = step?.stage ?? "members";
      if (!STAGES.includes(stage)) fail("failed-precondition", "The migration run record needs reconciliation.");
      const progress = {
        memberCursor: step?.memberCursor ?? null, memberCount: step?.memberCount ?? 0,
        ownerSeen: step?.ownerSeen === true, channelCount: step?.channelCount ?? 0,
      };
      if (stage === "complete") {
        entry.disposition = "applied";
        entry.stage = "complete";
        entry.memberCount = progress.memberCount;
        entry.channelCount = progress.channelCount;
        roots.push(entry);
        continue;
      }
      let guard = 0;
      let stopped = false;
      const maxIterations = Math.ceil(MAX_MEMBERS_PER_ROOT / MEMBER_PAGE_SIZE) + STAGES.length;
      while (stage !== "complete" && !stopped) {
        guard += 1;
        if (guard > maxIterations) fail("internal", "A migration root exceeded its stage budget.");
        const outcome = await runStage({ runId, mapping, stage, step: progress, expectedGateRevision, clientCensus });
        entry.stagesRun.push(stage);
        entry.writes += outcome.writes;
        entry.plannedWrites += outcome.planned;
        writeCount += outcome.writes;
        plannedWrites += outcome.planned;
        if (Object.keys(outcome.counts).length > 0) entry.counts = outcome.counts;
        for (const intent of outcome.intents) {
          const shape = `${intent.op} ${intentShape(intent.path)}`;
          plannedByShape[shape] = (plannedByShape[shape] ?? 0) + 1;
        }
        if (outcome.gate) { entry.gate = outcome.gate; clientGate = outcome.gate; }
        if (outcome.reasons.length > 0) {
          entry.reasons = outcome.reasons;
          entry.stage = stage;
          entry.alreadyApplied = outcome.alreadyApplied;
          // `deferred` means "retry when the room is idle", so it is only
          // true when idleness is the ONLY thing standing in the way. A root
          // that is live AND holds stranded history, a stranded cover or any
          // other hard refusal will never pass by waiting; reporting it as
          // deferred told the operator the opposite (principal F9). That
          // mattered most for exactly the roots P1-1 exposed: a room found by
          // the back-pointer is typically live and history-bearing at once.
          entry.disposition = outcome.alreadyApplied ? "already-applied"
            : outcome.reasons.every((reason) => LIVENESS_REASONS.includes(reason))
              ? "deferred" : "refused";
          stopped = true;
          break;
        }
        Object.assign(progress, outcome.progress);
        stage = outcome.nextStage;
      }
      if (!stopped) {
        entry.disposition = "applied";
        entry.stage = "complete";
      }
      entry.memberCount = progress.memberCount;
      entry.channelCount = progress.channelCount;
      roots.push(entry);
    }

    if (mode === "apply") {
      await record.reference.set({
        schemaVersion: APPLY_VERSION, runId, mode, projectId, emulator, planDigest,
        expectedGateRevision, status: "completed",
        counts: { roots: roots.length, applied: roots.filter((item) => item.disposition === "applied").length },
        updatedAt: now(),
      }, { merge: true });
      writeCount += 1;
      plannedWrites += 1;
    }

    const dispositions = {};
    const refusalReasons = {};
    for (const root of roots) {
      dispositions[root.disposition] = (dispositions[root.disposition] ?? 0) + 1;
      for (const reason of root.reasons) refusalReasons[reason] = (refusalReasons[reason] ?? 0) + 1;
    }
    const gates = gateStatus({
      // A Storage-object and generation enumeration is not part of this run;
      // the engine preserves media by never writing it, which is not the same
      // as having inventoried it.
      inventoryComplete: false,
      clientGateSatisfied: clientGate !== null && clientGate.satisfied === true,
      refusalsEnforced: true,
    });
    const body = {
      manifestVersion: APPLY_VERSION,
      scope: mode === "dryRun" ? "apply-engine-dry-run-no-writes" : "apply-engine-emulator-write-run",
      mode, dryRun: mode === "dryRun", generatedAt, projectId, emulator, runId, planDigest,
      planDigestAtRunStart: record.planDigestAtRunStart, planDigestChanged: record.planDigestChanged,
      clientGate: {
        path: CLIENT_GATE_PATH, expectedRevision: expectedGateRevision,
        censusSupplied: clientCensus !== null && clientCensus !== undefined, observed: clientGate,
      },
      capabilities: { ...V1_CLIENT_READ_PATHS },
      familyMigrationAllowed: familyMigrationAllowed(),
      bounds: {
        maxRootsPerRun: MAX_ROOTS_PER_RUN, maxMembersPerRoot: MAX_MEMBERS_PER_ROOT,
        memberPageSize: MEMBER_PAGE_SIZE, maxChannelsPerRoot: MAX_CHANNELS_PER_ROOT,
        maxBoundRoomsPerRoot: MAX_BOUND_ROOMS_PER_ROOT, maxInviteProbe: MAX_INVITE_PROBE,
      },
      roots,
      summary: {
        roots: roots.length, dispositions, refusalReasons, resumedRoots,
        plannedWrites, writeCount,
        plannedWritesByShape: Object.fromEntries(Object.entries(plannedByShape).sort(([a], [b]) => compare(a, b))),
      },
      requiredGates: gates,
      openGates: gates.filter((gate) => !gate.closed).map((gate) => gate.gate),
      // Reported separately from the gate it belongs to, because the gate also
      // names a reviewed non-destructive rollback that does not exist.
      resumeProven: mode === "apply",
      // Never true. `separate-production-migration-approval` has no in-code
      // evidence source, and write mode is emulator-only by construction.
      applyReady: false,
      plannedWrites,
      writeCount,
    };
    if (mode === "dryRun" && writeCount !== 0) fail("internal", "A dry run must not write.");
    return { ...body, reportDigest: sha256(JSON.stringify(body)) };
  }

  return Object.freeze({ run, mode });
}

module.exports = {
  APPLY_VERSION, DURABLE_MEMBER_SOURCES, FAMILY_RULES_BRANCHES, IMMUTABLE_CHANNEL_FIELDS,
  IMMUTABLE_MEMBER_FIELDS, IMMUTABLE_ROOT_FIELDS, LEGACY_CHANNEL_KIND, LIVENESS_REASONS, MAX_BOUND_ROOMS_PER_ROOT,
  MAX_CHANNELS_PER_ROOT, MAX_INVITE_PROBE, MAX_MEMBERS_PER_ROOT, MAX_ROOTS_PER_RUN,
  MEMBER_PAGE_SIZE, MIGRATION_RECORD_VERSION, MIGRATION_STATES, MODES, RUN_COLLECTION,
  RUN_STEP_COLLECTION, STAGES, STRANDED_IF_NON_EMPTY, V1_CLIENT_READ_PATHS,
  V1_MANAGEMENT_CAPABILITIES,
  assertDurableMemberSource, assertPatchPreserves, channelPostImage,
  createLegacyMigrationApplyEngine, familyMigrationAllowed, managementParityExists,
  reduceToChanges, rootPostImage, stampedPatch, standaloneServerId,
};
