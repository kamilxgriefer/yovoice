// The one liker predicate of "See who liked" (ADR-230), for all five targets
// (voiceMoment, voiceMomentComment, reel, reelComment, serverMessage).
//
// A liker L is shown to viewer V iff L === V (you always see yourself), or
// ALL of:
//   1. users/{L} is an active profile (exists; not banned, disabled or
//      deleted; no authDeletedAt)                                   phase 1
//   2. likesHiddenOf(users/{L}) === false ("Hide my likes")          phase 1
//   3. profileVisibilityOf(users/{L}) is "public", or "friends" with both
//      canonical friendshipGuards edges; "private" is hidden   phase 1 + 3
//   4. restrictions/{L} holds no live communicationMute (every target,
//      Servers included: restricted accounts are never listed)       phase 2
//   5. no block either way (users/{V}/blocked/{L}, users/{L}/blocked/{V})
//                                                                     phase 2
//   6. publicProfiles/{L} is canonical (it supplies displayName)     phase 2
//   7. Server messages only: clubs/{s}/members/{L} is a canonical member
//      (departed, banned and deleted reactors keep their uid in the map)
//                                                                     phase 2
//
// This is the Voice audience predicate (moments/integrity.js
// assertVoiceMomentAudienceFromContext) applied to the liker as principal.
// A liker list exposes a person, so profile visibility applies to Yeels too,
// although the Yeel CONTENT rule has no visibility check.
//
// The loader is phased cheapest-first so a hidden candidate costs less:
// phase 2 is read only for phase-1 survivors, phase 3 only for friends-only
// phase-2 survivors. Every read is a plain getAll (no transaction).

const {
  activeProfile,
  canonicalPublicProfile,
  isValidOpaqueUid,
  restrictionIsActive,
} = require("../integrity/guards");
const {
  exactFriendshipGuard,
  profileVisibilityOf,
} = require("../profile/media_contract");
const { canonicalMember } = require("../servers/authority");
const { HttpsError } = require("firebase-functions/v2/https");

// Maximum reads the loader spends on ONE candidate, per surface:
// content: users 1 + (restrictions, publicProfiles, 2 blocks) 4 + 2 guards;
// serverMessage adds the member row.
const LIKER_CONTEXT_MAX_READS = Object.freeze({
  content: 7,
  serverMessage: 8,
});

// Missing or false = visible; true = hidden; ANY other stored value = hidden
// (fail closed, as profileVisibilityOf treats malformed as private). Accepts
// the users/{uid} data or its snapshot; no profile at all is hidden.
function likesHiddenOf(userDataOrSnapshot) {
  const userData = typeof userDataOrSnapshot?.data === "function" &&
      typeof userDataOrSnapshot?.exists === "boolean"
    ? (userDataOrSnapshot.exists ? userDataOrSnapshot.data() : null)
    : userDataOrSnapshot;
  if (!userData || typeof userData !== "object") return true;
  const value = userData.likesHidden;
  if (value === undefined || value === false) return false;
  return true;
}

// Reuses the throwing guards as boolean predicates, so this predicate cannot
// drift from the checks the rest of the backend applies. Only an HttpsError
// (a refusal) means "hidden"; anything else is a bug and propagates.
function passes(check) {
  try {
    check();
    return true;
  } catch (error) {
    if (error instanceof HttpsError) return false;
    throw error;
  }
}

function snapshotExists(snapshot) {
  return snapshot?.exists === true;
}

function phaseOneAllows(context) {
  if (!passes(() => activeProfile(context.likerProfile, "The liker"))) {
    return false;
  }
  const data = context.likerProfile.data() ?? {};
  if (likesHiddenOf(data)) return false;
  const visibility = profileVisibilityOf(data);
  return visibility === "public" || visibility === "friends";
}

function publicIdentity(context) {
  let identity = null;
  const ok = passes(() => {
    identity = canonicalPublicProfile(context.publicProfile, context.likerId);
  });
  return ok ? identity : null;
}

function phaseTwoAllows(context, { nowMs, surface }) {
  if (!context.phaseTwoLoaded) return false;
  if (
    snapshotExists(context.likerRestriction) &&
    restrictionIsActive(context.likerRestriction.data(), nowMs)
  ) {
    return false;
  }
  if (snapshotExists(context.viewerBlock) || snapshotExists(context.likerBlock)) {
    return false;
  }
  if (publicIdentity(context) === null) return false;
  if (surface === "serverMessage") {
    if (!passes(() =>
      canonicalMember(context.member, context.likerId, context.server))) {
      return false;
    }
  }
  return true;
}

function phaseThreeAllows(context, viewerId) {
  if (!context.phaseThreeLoaded) return false;
  return exactFriendshipGuard(
    context.forwardFriendship,
    viewerId,
    context.likerId,
  ) &&
    exactFriendshipGuard(context.reverseFriendship, context.likerId, viewerId);
}

function requireSurface(surface, server, serverId) {
  if (surface === "content") return;
  if (surface !== "serverMessage") {
    throw new TypeError(`Unknown liker surface: ${surface}`);
  }
  if (typeof serverId !== "string" || serverId.length === 0 ||
      !server || typeof server !== "object") {
    throw new TypeError("serverMessage contexts need serverId and server.");
  }
}

async function readAll(getAll, references) {
  if (references.length === 0) return [];
  const snapshots = await getAll(...references);
  if (!Array.isArray(snapshots) || snapshots.length !== references.length) {
    throw new TypeError("getAll must return one snapshot per reference.");
  }
  return snapshots;
}

// Returns Map<likerId, context>. `likerIds` may contain duplicates and
// invalid values; an invalid id gets a context that is never visible and
// costs no read.
async function loadLikerContexts({
  getAll,
  db,
  viewerId,
  likerIds,
  nowMs,
  surface = "content",
  serverId = null,
  server = null,
}) {
  if (typeof getAll !== "function" || !db?.doc) {
    throw new TypeError("getAll and db are required.");
  }
  if (!isValidOpaqueUid(viewerId)) throw new TypeError("viewerId is invalid.");
  if (!Number.isSafeInteger(nowMs)) throw new TypeError("nowMs is required.");
  requireSurface(surface, server, serverId);

  const contexts = new Map();
  for (const likerId of likerIds) {
    if (contexts.has(likerId)) continue;
    contexts.set(likerId, {
      likerId,
      valid: isValidOpaqueUid(likerId),
      self: likerId === viewerId,
      surface,
      server,
      likerProfile: null,
      likerRestriction: null,
      publicProfile: null,
      viewerBlock: null,
      likerBlock: null,
      member: null,
      forwardFriendship: null,
      reverseFriendship: null,
      phaseOneLoaded: false,
      phaseTwoLoaded: false,
      phaseThreeLoaded: false,
    });
  }
  const all = [...contexts.values()].filter((context) => context.valid);

  // Phase 1: users/{L} for everyone but the viewer.
  const phaseOne = all.filter((context) => !context.self);
  const profiles = await readAll(
    getAll,
    phaseOne.map((context) => db.doc(`users/${context.likerId}`)),
  );
  phaseOne.forEach((context, index) => {
    context.likerProfile = profiles[index];
    context.phaseOneLoaded = true;
  });

  // Phase 2: survivors of phase 1; the viewer needs only a public identity.
  const phaseTwo = all.filter((context) =>
    context.self || phaseOneAllows(context));
  const references = [];
  const slots = [];
  for (const context of phaseTwo) {
    const start = references.length;
    references.push(db.doc(`publicProfiles/${context.likerId}`));
    if (!context.self) {
      references.push(
        db.doc(`restrictions/${context.likerId}`),
        db.doc(`users/${viewerId}/blocked/${context.likerId}`),
        db.doc(`users/${context.likerId}/blocked/${viewerId}`),
      );
      if (surface === "serverMessage") {
        references.push(db.doc(`clubs/${serverId}/members/${context.likerId}`));
      }
    }
    slots.push([context, start]);
  }
  const phaseTwoSnapshots = await readAll(getAll, references);
  for (const [context, start] of slots) {
    context.publicProfile = phaseTwoSnapshots[start];
    if (!context.self) {
      context.likerRestriction = phaseTwoSnapshots[start + 1];
      context.viewerBlock = phaseTwoSnapshots[start + 2];
      context.likerBlock = phaseTwoSnapshots[start + 3];
      if (surface === "serverMessage") {
        context.member = phaseTwoSnapshots[start + 4];
      }
    }
    context.phaseTwoLoaded = true;
  }

  // Phase 3: friends-only phase-2 survivors need both friendship guards.
  const phaseThree = phaseTwo.filter((context) =>
    !context.self &&
    profileVisibilityOf(context.likerProfile.data()) === "friends" &&
    phaseTwoAllows(context, { nowMs, surface }));
  const guards = await readAll(
    getAll,
    phaseThree.flatMap((context) => [
      db.doc(`friendshipGuards/${viewerId}/friends/${context.likerId}`),
      db.doc(`friendshipGuards/${context.likerId}/friends/${viewerId}`),
    ]),
  );
  phaseThree.forEach((context, index) => {
    context.forwardFriendship = guards[index * 2];
    context.reverseFriendship = guards[index * 2 + 1];
    context.phaseThreeLoaded = true;
  });
  return contexts;
}

function likerIsVisible(context, { viewerId, nowMs }) {
  if (!context || context.valid !== true) return false;
  if (!Number.isSafeInteger(nowMs)) throw new TypeError("nowMs is required.");
  // Yourself: always, as long as there is a canonical name to show.
  if (context.likerId === viewerId) {
    return context.phaseTwoLoaded && publicIdentity(context) !== null;
  }
  if (!context.phaseOneLoaded || !phaseOneAllows(context)) return false;
  if (!phaseTwoAllows(context, { nowMs, surface: context.surface })) return false;
  const visibility = profileVisibilityOf(context.likerProfile.data());
  if (visibility === "public") return true;
  return visibility === "friends" && phaseThreeAllows(context, viewerId);
}

// The wire row of one visible liker. photoUrl is ALWAYS null: avatars
// resolve through the viewer-authorised media grant, never a stored URL.
function projectLiker(context, { reaction = null } = {}) {
  const identity = publicIdentity(context);
  if (identity === null) {
    throw new TypeError("projectLiker needs a visible liker context.");
  }
  return {
    userId: context.likerId,
    displayName: identity.displayName,
    photoUrl: null,
    reaction,
  };
}

// The scan loop's `resolveVisible` for this predicate: loads the contexts of
// one chunk and returns, IN ORDER, the projected row or null per candidate.
function likerResolver({
  getAll,
  db,
  viewerId,
  nowMs,
  surface = "content",
  serverId = null,
  server = null,
}) {
  return async (candidates) => {
    const contexts = await loadLikerContexts({
      getAll,
      db,
      viewerId,
      likerIds: candidates
        .map((candidate) => candidate.likerId)
        .filter((likerId) => likerId !== null),
      nowMs,
      surface,
      serverId,
      server,
    });
    return candidates.map((candidate) => {
      if (candidate.likerId === null) return null;
      const context = contexts.get(candidate.likerId);
      return likerIsVisible(context, { viewerId, nowMs })
        ? projectLiker(context, { reaction: candidate.reaction ?? null })
        : null;
    });
  };
}

module.exports = {
  LIKER_CONTEXT_MAX_READS,
  likerIsVisible,
  likerResolver,
  likesHiddenOf,
  loadLikerContexts,
  projectLiker,
};
