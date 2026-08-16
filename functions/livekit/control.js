const { RoomServiceClient } = require("livekit-server-sdk");

const LIVEKIT_SECRETS = Object.freeze([
  "LIVEKIT_API_KEY",
  "LIVEKIT_API_SECRET",
]);

const DEFAULT_ATTEMPTS = 2;
const DEFAULT_BACKOFF_MS = 75;
const DEFAULT_REQUEST_TIMEOUT_SECONDS = 4;
const REVOKE_CLOCK_SKEW_SECONDS = 1;
const PARTICIPANT_BATCH_SIZE = 20;
// Legacy fallback only. At two 4-second attempts per lookup and batches of
// 20 this keeps the worst-case discovery phase bounded below the callable's
// timeout. A per-user activeVoiceSessions mirror is the long-term primary
// index; exceeding this fallback bound fails visibly instead of silently
// claiming that every session was found.
const MAX_LEGACY_ROOM_SCAN = 200;

class LiveKitControlError extends Error {
  constructor(operation, cause) {
    super(`LiveKit control operation failed: ${operation}`);
    this.name = "LiveKitControlError";
    this.operation = operation;
    this.cause = cause;
  }
}

function isNotFound(error) {
  const code = String(error?.code ?? "")
    .trim()
    .toLowerCase()
    .replaceAll("-", "_");
  return error?.status === 404 || code === "not_found";
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function revocationTimestamp(now) {
  // LiveKit invalidates tokens whose nbf is before revokeTokenTs. One
  // second of skew also catches a token minted in the same wall-clock
  // second as this moderation decision.
  return BigInt(Math.floor(now() / 1000) + REVOKE_CLOCK_SKEW_SECONDS);
}

async function inBatches(values, size, action) {
  for (let index = 0; index < values.length; index += size) {
    await Promise.all(values.slice(index, index + size).map(action));
  }
}

/**
 * A small, injectable control-plane around LiveKit's RoomServiceClient.
 *
 * Firestore remains the durable authority. Callers update that state first,
 * so new token requests fail closed, then invoke this helper to revoke the
 * already-issued session. Remote calls retry a bounded number of times and
 * expose a typed failure; callers must surface that partial outcome rather
 * than claiming the moderation action completed everywhere.
 */
function createLiveKitControl({
  client,
  attempts = DEFAULT_ATTEMPTS,
  backoffMs = DEFAULT_BACKOFF_MS,
  sleep = delay,
  now = Date.now,
  maxRoomScan = MAX_LEGACY_ROOM_SCAN,
}) {
  if (!client) throw new Error("A LiveKit RoomServiceClient is required.");

  const boundedAttempts = Math.max(1, Math.min(Number(attempts) || 1, 3));
  const boundedRoomScan = Math.max(
    1,
    Math.min(Number(maxRoomScan) || MAX_LEGACY_ROOM_SCAN, MAX_LEGACY_ROOM_SCAN),
  );

  async function invoke(operation, action, { absentIsSuccess = true } = {}) {
    let lastError;
    for (let attempt = 1; attempt <= boundedAttempts; attempt += 1) {
      try {
        return {
          value: await action(),
          attempts: attempt,
          alreadyAbsent: false,
        };
      } catch (error) {
        if (absentIsSuccess && isNotFound(error)) {
          return { value: null, attempts: attempt, alreadyAbsent: true };
        }
        lastError = error;
        if (attempt < boundedAttempts) {
          await sleep(backoffMs * attempt);
        }
      }
    }
    throw new LiveKitControlError(operation, lastError);
  }

  async function revokeParticipant(roomId, identity) {
    const revokeTokenTs = revocationTimestamp(now);
    return invoke("removeParticipant", () =>
      client.removeParticipant(roomId, identity, { revokeTokenTs }),
    );
  }

  async function setParticipantPermissions(roomId, identity, changes) {
    const allowedChanges = {};
    for (const key of ["canPublish", "canPublishData", "canSubscribe"]) {
      if (typeof changes?.[key] === "boolean") {
        allowedChanges[key] = changes[key];
      }
    }
    if (Object.keys(allowedChanges).length === 0) {
      throw new Error("At least one participant permission is required.");
    }

    return invoke("updateParticipant", async () => {
      const participant = await client.getParticipant(roomId, identity);
      const currentPermission = participant?.permission ?? {};
      return client.updateParticipant(roomId, identity, {
        // Permissions are replaced atomically by LiveKit. Preserve every
        // unrelated bit and override only server-derived booleans.
        permission: {
          ...currentPermission,
          ...allowedChanges,
        },
      });
    });
  }

  async function setPublishingAllowed(roomId, identity, canPublish) {
    return setParticipantPermissions(roomId, identity, {
      canPublish: canPublish === true,
    });
  }

  async function findParticipantRooms(identity) {
    const listed = await invoke("listRooms", () => client.listRooms());
    if (listed.alreadyAbsent) return [];

    const rooms = Array.isArray(listed.value) ? listed.value : [];
    if (rooms.length > boundedRoomScan) {
      const cause = Object.assign(
        new Error("The legacy LiveKit room scan exceeded its safety bound."),
        { code: "resource_exhausted" },
      );
      throw new LiveKitControlError("participantRoomScanBound", cause);
    }
    const found = [];
    const lookupFailures = [];
    await inBatches(rooms, PARTICIPANT_BATCH_SIZE, async (room) => {
      const roomName = String(room?.name ?? "").trim();
      if (!roomName) return;
      try {
        const participant = await invoke(
          "getParticipant",
          () => client.getParticipant(roomName, identity),
        );
        if (!participant.alreadyAbsent) found.push(roomName);
      } catch (error) {
        lookupFailures.push(error);
      }
    });

    if (lookupFailures.length > 0) throw lookupFailures[0];
    return found;
  }

  async function endRoom(roomId) {
    let participants = [];
    let listFailure = null;
    try {
      const listed = await invoke(
        "listParticipants",
        () => client.listParticipants(roomId),
      );
      if (listed.alreadyAbsent) return listed;
      participants = Array.isArray(listed.value) ? listed.value : [];
    } catch (error) {
      // Still attempt deleteRoom: it immediately disconnects the room even
      // when listing/revoking individual token timestamps is unavailable.
      listFailure = error;
    }

    const revocationFailures = [];
    await inBatches(participants, PARTICIPANT_BATCH_SIZE, async (participant) => {
      const identity = String(participant?.identity ?? "").trim();
      if (!identity) return;
      try {
        await revokeParticipant(roomId, identity);
      } catch (error) {
        revocationFailures.push(error);
      }
    });

    let deletion = null;
    let deleteFailure = null;
    try {
      deletion = await invoke("deleteRoom", () => client.deleteRoom(roomId));
    } catch (error) {
      deleteFailure = error;
    }

    const failure = listFailure ?? revocationFailures[0] ?? deleteFailure;
    if (failure) {
      throw failure instanceof LiveKitControlError
        ? failure
        : new LiveKitControlError("endRoom", failure);
    }

    return {
      ...deletion,
      revokedParticipants: participants.length,
    };
  }

  return Object.freeze({
    endRoom,
    findParticipantRooms,
    revokeParticipant,
    setParticipantPermissions,
    setPublishingAllowed,
  });
}

let productionControl = null;

function getProductionLiveKitControl() {
  if (productionControl) return productionControl;

  const url = String(process.env.LIVEKIT_URL ?? "").trim();
  const apiKey = String(process.env.LIVEKIT_API_KEY ?? "").trim();
  const apiSecret = String(process.env.LIVEKIT_API_SECRET ?? "").trim();
  if (!url || !apiKey || !apiSecret) {
    throw new Error("LiveKit control-plane configuration is incomplete.");
  }

  productionControl = createLiveKitControl({
    client: new RoomServiceClient(url, apiKey, apiSecret, {
      requestTimeout: DEFAULT_REQUEST_TIMEOUT_SECONDS,
      // The helper owns an explicit, bounded retry. Disabling the SDK's
      // separate regional retry keeps the callable's upper bound honest.
      failover: false,
    }),
  });
  return productionControl;
}

module.exports = {
  LIVEKIT_SECRETS,
  MAX_LEGACY_ROOM_SCAN,
  LiveKitControlError,
  createLiveKitControl,
  getProductionLiveKitControl,
  isNotFound,
};
