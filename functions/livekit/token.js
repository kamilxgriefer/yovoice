const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret, defineString } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const { AccessToken, TrackSource } = require("livekit-server-sdk");
const { Timestamp } = require("firebase-admin/firestore");

const { requireAuthentication } = require("../utils/auth");

const { db, normalizeText, roomIsActive } = require("../utils/firestore");
const {
  assertLedgerReplay,
  consumeRateLimit,
  ledgerData,
  operationIdentity,
  rateLimitReference,
  requireRequestId,
  transactionGetAll,
} = require("../integrity/guards");
const {
  activeVoiceSessionReference,
  writeActiveVoiceSession,
} = require("./sessions");

const REGION = "europe-west1";

const livekitApiKey = defineSecret("LIVEKIT_API_KEY");

const livekitApiSecret = defineSecret("LIVEKIT_API_SECRET");

// Not a secret — this is the public WebSocket endpoint every client needs
// to connect, the same way a hostname would be. Set via `functions/.env`
// (LIVEKIT_URL=wss://your-project.livekit.cloud) or `firebase functions:config`.
const livekitUrl = defineString("LIVEKIT_URL");

const SPEAKING_ROLES = new Set(["host", "speaker"]);
const SAFE_DOCUMENT_ID = /^[A-Za-z0-9_-]{1,128}$/u;
const VOICE_TOKEN_TTL = "5m";
const VOICE_TOKEN_TTL_SECONDS = 5 * 60;
const VOICE_TOKEN_RATE_WINDOW_MS = 60 * 1000;
const VOICE_TOKEN_RATE_LIMIT = 12;
const VOICE_TOKEN_ATTEMPT_SCOPE = "room.voice.token.attempt";
const VOICE_TOKEN_ATTEMPT_LIMIT = Object.freeze({
  windowMs: VOICE_TOKEN_RATE_WINDOW_MS,
  maxEvents: VOICE_TOKEN_RATE_LIMIT,
});
const DEFERRED_REQUEST_ID_CONFLICT = Symbol("voice-token-request-id-conflict");

function voiceTokenOperationLedgerReference(identity) {
  return db.doc(`integrityOperationLedgers/${identity.id}`);
}

function voiceTokenAttemptRateReference(uid) {
  return rateLimitReference(db, VOICE_TOKEN_ATTEMPT_SCOPE, uid);
}

function completedVoiceTokenReplay(snapshot, {
  uid,
  identity,
  nowMs,
  deferRequestIdConflict = false,
}) {
  if (snapshot?.exists) {
    const data = snapshot.data() ?? {};
    if (
      data.kind !== "room.voice.token" ||
      data.ownerId !== uid ||
      data.inputHash !== identity.inputHash
    ) {
      if (deferRequestIdConflict) {
        return DEFERRED_REQUEST_ID_CONFLICT;
      }
    }
  }
  const result = assertLedgerReplay(snapshot, {
    kind: "room.voice.token",
    uid,
    inputHash: identity.inputHash,
  });
  if (!result) return null;
  if (
    typeof result.participantToken !== "string" ||
    result.participantToken.length === 0 ||
    !SAFE_DOCUMENT_ID.test(normalizeText(result.roomName, 128)) ||
    !Number.isSafeInteger(result.expiresAtMillis)
  ) {
    throw new HttpsError("data-loss", "The private token ledger is invalid.");
  }
  if (result.expiresAtMillis <= nowMs) {
    throw new HttpsError(
      "already-exists",
      "This token request has expired. Start a new connection attempt.",
    );
  }
  return result;
}

async function consumeVoiceTokenAttempt({
  uid,
  identity = null,
  nowMs = Date.now(),
}) {
  const now = Timestamp.fromMillis(nowMs);
  const rateReference = voiceTokenAttemptRateReference(uid);
  const ledgerReference = identity === null
    ? null
    : voiceTokenOperationLedgerReference(identity);
  const outcome = await db.runTransaction(async (transaction) => {
    const snapshots = await transactionGetAll(
      transaction,
      ...(ledgerReference === null ? [] : [ledgerReference]),
      rateReference,
    );
    if (ledgerReference !== null) {
      const replay = completedVoiceTokenReplay(snapshots[0], {
        uid,
        identity,
        nowMs,
        deferRequestIdConflict: true,
      });
      if (replay && replay !== DEFERRED_REQUEST_ID_CONFLICT) return replay;
      if (replay === DEFERRED_REQUEST_ID_CONFLICT) {
        consumeRateLimit(transaction, snapshots.at(-1), {
          reference: rateReference,
          scope: VOICE_TOKEN_ATTEMPT_SCOPE,
          uid,
          nowMs,
          now,
          ...VOICE_TOKEN_ATTEMPT_LIMIT,
        });
        return DEFERRED_REQUEST_ID_CONFLICT;
      }
    }
    consumeRateLimit(transaction, snapshots.at(-1), {
      reference: rateReference,
      scope: VOICE_TOKEN_ATTEMPT_SCOPE,
      uid,
      nowMs,
      now,
      ...VOICE_TOKEN_ATTEMPT_LIMIT,
    });
    return null;
  });
  if (outcome === DEFERRED_REQUEST_ID_CONFLICT) {
    throw new HttpsError(
      "already-exists",
      "requestId was already used for another operation.",
    );
  }
  return outcome;
}

function buildParticipantName(participant, profile, authenticatedUser) {
  const profileName = normalizeText(profile.displayName, 120);
  if (profileName) return profileName;

  const tokenName = normalizeText(authenticatedUser.token.name, 120);
  if (tokenName) return tokenName;

  const participantName = normalizeText(participant.displayName, 120);
  if (participantName) return participantName;

  const tokenEmail = normalizeText(authenticatedUser.token.email, 160);

  if (tokenEmail) {
    return tokenEmail;
  }

  return "YoVoice user";
}

function restrictionIsActive(restriction, now = Date.now()) {
  if (restriction?.type !== "communicationMute") return false;
  if (restriction.expiresAt == null) return true;
  const expiresAt =
    typeof restriction.expiresAt.toMillis === "function"
      ? restriction.expiresAt.toMillis()
      : new Date(restriction.expiresAt).getTime();
  return Number.isFinite(expiresAt) && expiresAt > now;
}

function buildParticipantMetadata(participant, profile, authenticatedUser) {
  return JSON.stringify({
    uid: authenticatedUser.uid,
    role: participant.role ?? "listener",
    username: normalizeText(profile.displayName, 80) || null,
    photoUrl: null,
  });
}

async function readSnapshots(references, transaction = null) {
  if (transaction && typeof transaction.getAll === "function") {
    return transaction.getAll(...references);
  }
  if (transaction) {
    const snapshots = [];
    for (const reference of references) {
      snapshots.push(await transaction.get(reference));
    }
    return snapshots;
  }
  return Promise.all(references.map((reference) => reference.get()));
}

/**
 * Resolves voice authority from canonical server state. Kept separate from
 * JWT signing so emulator tests can prove denial/allowance without loading
 * production LiveKit secrets.
 */
async function authorizeRoomVoiceAccess(
  roomId,
  authenticatedUser,
  transaction = null,
) {
  if (!SAFE_DOCUMENT_ID.test(roomId)) {
    throw new HttpsError("invalid-argument", "A room ID is required.");
  }

  const roomRef = db.collection("rooms").doc(roomId);
  const [roomSnapshot] = await readSnapshots([roomRef], transaction);
  if (!roomSnapshot.exists) {
    throw new HttpsError("not-found", "This room does not exist.");
  }
  const room = roomSnapshot.data() ?? {};
  if (!roomIsActive(room) || room.isLive !== true) {
    throw new HttpsError(
      "failed-precondition",
      "This room is not currently live.",
    );
  }

  const participantRef = roomRef
    .collection("participants")
    .doc(authenticatedUser.uid);
  const [participantSnapshot, profileSnapshot, restrictionSnapshot] =
    await readSnapshots(
      [
        participantRef,
        db.collection("users").doc(authenticatedUser.uid),
        db.collection("restrictions").doc(authenticatedUser.uid),
      ],
      transaction,
    );
  if (!participantSnapshot.exists) {
    throw new HttpsError(
      "permission-denied",
      "You must join this room before requesting voice access.",
    );
  }

  const participant = participantSnapshot.data() ?? {};
  const profile = profileSnapshot.exists ? (profileSnapshot.data() ?? {}) : {};
  const restriction = restrictionSnapshot.exists
    ? (restrictionSnapshot.data() ?? {})
    : {};
  if (
    participant.userId !== authenticatedUser.uid ||
    participant.banned === true ||
    !profileSnapshot.exists ||
    profile.banned === true ||
    profile.disabled === true
  ) {
    throw new HttpsError(
      "permission-denied",
      "This account does not have voice access to the room.",
    );
  }

  const clubId = normalizeText(room.clubId, 128);
  if (clubId) {
    const [clubSnapshot, membershipSnapshot] = await readSnapshots(
      [
        db.collection("clubs").doc(clubId),
        db
          .collection("clubs")
          .doc(clubId)
          .collection("members")
          .doc(authenticatedUser.uid),
      ],
      transaction,
    );
    const club = clubSnapshot.exists ? (clubSnapshot.data() ?? {}) : {};
    const membership = membershipSnapshot.exists
      ? (membershipSnapshot.data() ?? {})
      : {};
    if (
      !clubSnapshot.exists ||
      club.status !== "active" ||
      club.deletionInProgress === true ||
      !membershipSnapshot.exists ||
      membership.userId !== authenticatedUser.uid ||
      membership.banned === true ||
      !["owner", "coOwner", "admin", "moderator", "member"].includes(
        membership.role,
      )
    ) {
      throw new HttpsError(
        "permission-denied",
        "Only active Club members may join this lounge.",
      );
    }
  } else if (
    room.visibility !== "public" &&
    room.hostId !== authenticatedUser.uid &&
    participant.admittedBy !== room.hostId
  ) {
    // Participant existence alone is not authority: before the matching
    // Rules hardening, any signed-in user could create this row. Private
    // non-Club rooms require a durable host-admission marker, so legacy
    // forged rows fail closed.
    throw new HttpsError(
      "permission-denied",
      "The room host has not admitted this participant.",
    );
  }

  return {
    room,
    participant,
    profile,
    communicationMuted: restrictionIsActive(restriction),
  };
}

/**
 * True when every participant of this room may publish, without being promoted.
 *
 * Mirrors `RoomExperience.fromValue` in
 * lib/features/rooms/data/models/room_experience.dart: the enum has two values,
 * the legacy string 'podcast' maps onto `broadcast`, and ANYTHING ELSE —
 * including a room with no `experience` field, which is 27 of the 45 rooms in
 * production — is a community room. The default is therefore "everyone speaks",
 * matching the client's own reading of the same field.
 */
function everyoneMaySpeak(room) {
  const experience = String(room?.experience ?? "community");
  return experience !== "broadcast" && experience !== "podcast";
}

function deriveVoiceGrant(access, authenticatedUser) {
  const { room, participant, profile, communicationMuted } = access;
  const isHost = room.hostId === authenticatedUser.uid;
  // A COMMUNITY ROOM IS A CONVERSATION, NOT A STAGE. New clients join it as
  // speakers; the experience fallback remains important for legacy roster
  // rows that still say `listener`. Only a BROADCAST room has an audience
  // that must be promoted; everywhere else everyone present may talk.
  const isSpeaker =
    SPEAKING_ROLES.has(participant.role) || everyoneMaySpeak(room);
  const canPublish =
    !communicationMuted &&
    (isHost || isSpeaker) &&
    // `participant.isMuted` — the person's OWN mute — is DELIBERATELY not
    // consulted here. It is a track state, not a permission. Folding it in
    // meant muting yourself revoked your right to publish: the client read the
    // missing permission as "you are audience", replaced the mute toggle with
    // a Listening label, and left no control to unmute with. The flag then
    // persisted in Firestore, so the next token arrived without publish rights
    // too and re-entering the room reproduced it. Only a moderator mute
    // (`hostMuted`), a server mute (`serverMuted`) or a sanction
    // (`communicationMuted`) may take publishing away.
    participant.hostMuted !== true &&
    participant.serverMuted !== true;
  const participantName = buildParticipantName(
    participant,
    profile,
    authenticatedUser,
  );
  return {
    participantName,
    participantMetadata: buildParticipantMetadata(
      participant,
      profile,
      authenticatedUser,
    ),
    permissions: {
      canPublish,
      canSubscribe: true,
      canPublishData: !communicationMuted,
      hidden: false,
      recorder: false,
    },
  };
}

function voiceGrantMatches(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

/**
 * Last authority check before a signed JWT is returned. The same transaction
 * reads every durable gate and writes the per-user session mirror. A ban,
 * mute, room close or membership removal racing token issuance changes one of
 * those read documents, forces a retry, and then fails closed.
 */
async function recordAuthorizedVoiceSession({
  roomId,
  authenticatedUser,
  expectedGrant,
  expiresAt,
  nowMs = Date.now(),
  operation = null,
}) {
  return db.runTransaction(async (transaction) => {
    if (operation !== null) {
      const replay = completedVoiceTokenReplay(
        await transaction.get(
          voiceTokenOperationLedgerReference(operation.identity),
        ),
        {
          uid: authenticatedUser.uid,
          identity: operation.identity,
          nowMs,
        },
      );
      if (replay) return { access: null, replay };
    }
    const currentAccess = await authorizeRoomVoiceAccess(
      roomId,
      authenticatedUser,
      transaction,
    );
    const currentGrant = deriveVoiceGrant(currentAccess, authenticatedUser);
    if (!voiceGrantMatches(currentGrant, expectedGrant)) {
      throw new HttpsError(
        "aborted",
        "Voice access changed while the token was being issued. Retry.",
      );
    }
    const sessionReference = activeVoiceSessionReference(
      authenticatedUser.uid,
      roomId,
    );
    const currentSession = await transaction.get(sessionReference);
    const currentExpiry = currentSession.data()?.expiresAt;
    const currentWindowStart = currentSession.data()?.tokenWindowStartedAt;
    const currentWindowCount = currentSession.data()?.tokenIssueCount;
    const withinCurrentWindow =
      currentWindowStart instanceof Timestamp &&
      nowMs - currentWindowStart.toMillis() >= 0 &&
      nowMs - currentWindowStart.toMillis() < VOICE_TOKEN_RATE_WINDOW_MS;
    const tokenIssueCount =
      withinCurrentWindow && Number.isInteger(currentWindowCount)
        ? currentWindowCount + 1
        : 1;
    if (tokenIssueCount > VOICE_TOKEN_RATE_LIMIT) {
      throw new HttpsError(
        "resource-exhausted",
        "Too many voice connection attempts. Wait a moment and retry.",
      );
    }
    const tokenWindowStartedAt = withinCurrentWindow
      ? currentWindowStart
      : Timestamp.fromMillis(nowMs);
    const effectiveExpiry =
      currentExpiry instanceof Timestamp &&
      currentExpiry.toMillis() > expiresAt.toMillis()
        ? currentExpiry
        : expiresAt;
    writeActiveVoiceSession(transaction, {
      userId: authenticatedUser.uid,
      roomId,
      expiresAt: effectiveExpiry,
      roomKind: normalizeText(currentAccess.room.roomKind, 80) || null,
      clubId: normalizeText(currentAccess.room.clubId, 128) || null,
      tokenWindowStartedAt,
      tokenIssueCount,
      tokenLastIssuedAt: Timestamp.fromMillis(nowMs),
    });
    if (operation !== null) {
      transaction.create(
        voiceTokenOperationLedgerReference(operation.identity),
        ledgerData({
          kind: "room.voice.token",
          uid: authenticatedUser.uid,
          requestId: operation.requestId,
          inputHash: operation.identity.inputHash,
          result: operation.result,
          now: Timestamp.fromMillis(nowMs),
        }),
      );
    }
    return { access: currentAccess, replay: null };
  });
}

async function createLiveKitTokenHandler(request, {
  AccessTokenClass = AccessToken,
  apiKey = () => livekitApiKey.value(),
  apiSecret = () => livekitApiSecret.value(),
  serverUrl = () => livekitUrl.value(),
  clock = () => Date.now(),
} = {}) {
    const authenticatedUser = requireAuthentication(request);

    const roomId = normalizeText(request.data?.roomId, 128);
    if (!SAFE_DOCUMENT_ID.test(roomId)) {
      throw new HttpsError("invalid-argument", "A room ID is required.");
    }
    const requestId = request.data?.requestId === undefined ||
        request.data?.requestId === null
      ? null
      : requireRequestId(request.data.requestId);
    const tokenIdentity = requestId === null
      ? null
      : operationIdentity(
        "room.voice.token",
        authenticatedUser.uid,
        requestId,
        { roomId },
      );
    const nowMs = clock();

    const preflightReplay = await consumeVoiceTokenAttempt({
      uid: authenticatedUser.uid,
      identity: tokenIdentity,
      nowMs,
    });
    if (preflightReplay) return preflightReplay;

    const access = await authorizeRoomVoiceAccess(roomId, authenticatedUser);
    const grant = deriveVoiceGrant(access, authenticatedUser);
    const { participantName, participantMetadata, permissions } = grant;
    const { canPublish, canSubscribe, canPublishData, hidden, recorder } =
      permissions;

    try {
      const accessToken = new AccessTokenClass(
        apiKey(),
        apiSecret(),
        {
          identity: authenticatedUser.uid,
          name: participantName,
          metadata: participantMetadata,
          ttl: VOICE_TOKEN_TTL,
        },
      );

      accessToken.addGrant({
        roomJoin: true,
        room: roomId,
        canPublish,
        // Voice rooms never grant camera or screen-share capability. A
        // modified client must not be able to turn a voice-only room into an
        // unannounced video broadcast merely because `canPublish` is true.
        ...(canPublish ? { canPublishSources: [TrackSource.MICROPHONE] } : {}),
        canSubscribe,
        canPublishData,
        hidden,
        recorder,
      });

      const participantToken = await accessToken.toJwt();
      const expiresAt = Timestamp.fromMillis(
        nowMs + VOICE_TOKEN_TTL_SECONDS * 1000,
      );
      const result = {
        serverUrl: serverUrl(),
        participantToken,
        token: participantToken,
        roomName: roomId,
        participantIdentity: authenticatedUser.uid,
        participantName,
        expiresAtMillis: expiresAt.toMillis(),
        permissions,
      };

      // Mint first, then perform the final transactional revalidation and
      // mirror write. If a sanction commits before this transaction it is
      // observed and denied; if it commits afterwards, its retryable outbox
      // discovers this mirror and revokes the already-minted identity.
      const recorded = await recordAuthorizedVoiceSession({
        roomId,
        authenticatedUser,
        expectedGrant: grant,
        expiresAt,
        nowMs,
        operation: tokenIdentity === null ? null : {
          identity: tokenIdentity,
          requestId,
          result,
        },
      });
      if (recorded.replay) return recorded.replay;

      return result;
    } catch (error) {
      logger.error("Failed to create LiveKit token", {
        errorName: error?.name ?? null,
        errorCode: error?.code ?? null,
      });

      if (error instanceof HttpsError) throw error;

      throw new HttpsError(
        "internal",
        "The LiveKit access token could not be created.",
      );
    }
}

const createLiveKitToken = onCall(
  {
    region: REGION,
    enforceAppCheck: false,
    memory: "256MiB",
    timeoutSeconds: 30,
    maxInstances: 50,
    minInstances: 1,
    secrets: [livekitApiKey, livekitApiSecret],
  },
  (request) => createLiveKitTokenHandler(request),
);

module.exports = {
  authorizeRoomVoiceAccess,
  buildParticipantMetadata,
  buildParticipantName,
  consumeVoiceTokenAttempt,
  createLiveKitToken,
  createLiveKitTokenHandler,
  deriveVoiceGrant,
  recordAuthorizedVoiceSession,
  restrictionIsActive,
  VOICE_TOKEN_TTL,
  VOICE_TOKEN_TTL_SECONDS,
  VOICE_TOKEN_RATE_LIMIT,
  VOICE_TOKEN_RATE_WINDOW_MS,
  VOICE_TOKEN_ATTEMPT_LIMIT,
  VOICE_TOKEN_ATTEMPT_SCOPE,
  voiceTokenAttemptRateReference,
};
