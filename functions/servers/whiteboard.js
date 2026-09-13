// Company whiteboard V1. Strokes are immutable, normalized polylines. Every
// mutation is callable-owned, replay-safe and reauthorizes the actor
// against the canonical Company/Whiteboard channel before touching content.

const {
  digest,
  fail,
  requireExactInput,
  requireId,
  requireRequestId,
  requireSafeInteger,
  requireUid,
  timestampMillis,
} = require("../integrity/guards");
const { denied, readChannelAccess, validRevision } = require("./authority");
const { requireEnum, revision } = require("./contract");
const { createServerOperations } = require("./operations");

const WHITEBOARD_STATE_ID = "main";
const WHITEBOARD_COLORS = Object.freeze([
  "ink", "red", "orange", "green", "blue", "purple", "white",
]);
const MAX_WHITEBOARD_STROKES = 180;
const MAX_STROKE_POINTS = 64;
const MAX_LINE_WIDTH = 16;

function canonicalStrokeId(uid, requestId) {
  requireUid(uid);
  requireRequestId(requestId);
  return `ws_${digest("server.whiteboard.stroke.create.v1", uid, requestId).slice(0, 40)}`;
}

function baseInput(data, extras = []) {
  const fields = ["serverId", "channelId", "requestId", ...extras];
  requireExactInput(data, fields, fields);
  return {
    serverId: requireId(data.serverId, "serverId"),
    channelId: requireId(data.channelId, "channelId"),
    requestId: requireRequestId(data.requestId),
  };
}

function requireCompanyWhiteboard(access) {
  if (access.server.serverType !== "company" || access.channel.kind !== "whiteboard") {
    denied();
  }
  return access;
}

function normalizedCoordinate(value, label) {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0 || value > 1) {
    fail("invalid-argument", `${label} is invalid.`);
  }
  return value;
}

function strokePoints(value) {
  if (!Array.isArray(value) || value.length < 2 || value.length > MAX_STROKE_POINTS) {
    fail("invalid-argument", `points must contain 2-${MAX_STROKE_POINTS} coordinates.`);
  }
  return value.map((point, index) => {
    requireExactInput(point, ["x", "y"], ["x", "y"]);
    return {
      x: normalizedCoordinate(point.x, `points[${index}].x`),
      y: normalizedCoordinate(point.y, `points[${index}].y`),
    };
  });
}

function defaultBoardState() {
  return {
    exists: false,
    generation: 1,
    revision: 0,
    strokeCount: 0,
    nextSequence: 1,
  };
}

function canonicalBoardState(snapshot, { serverId, channelId }) {
  if (!snapshot.exists) return defaultBoardState();
  const state = snapshot.data() ?? {};
  const clearedAtMillis = state.clearedAt === null
    ? null
    : timestampMillis(state.clearedAt);
  if (snapshot.id !== WHITEBOARD_STATE_ID || state.schemaVersion !== 1 ||
      state.serverId !== serverId || state.channelId !== channelId ||
      state.stateId !== WHITEBOARD_STATE_ID || !validRevision(state.generation) ||
      !validRevision(state.revision) ||
      !Number.isSafeInteger(state.strokeCount) || state.strokeCount < 0 ||
      state.strokeCount > MAX_WHITEBOARD_STROKES ||
      !validRevision(state.nextSequence) || timestampMillis(state.updatedAt) === null ||
      (state.clearedAt === null) !== (state.clearedById === null) ||
      (state.clearedAt !== null && (clearedAtMillis === null ||
        typeof state.clearedById !== "string"))) {
    fail("data-loss", "The company whiteboard state needs reconciliation.");
  }
  return { ...state, exists: true };
}

function canonicalStroke(snapshot, { serverId, channelId, strokeId }) {
  if (!snapshot.exists) fail("not-found", "The selected whiteboard stroke is unavailable.");
  const stroke = snapshot.data() ?? {};
  if (snapshot.id !== strokeId || stroke.schemaVersion !== 1 ||
      stroke.serverId !== serverId || stroke.channelId !== channelId ||
      stroke.strokeId !== strokeId || stroke.strokeKind !== "polyline" ||
      typeof stroke.authorId !== "string" || !validRevision(stroke.generation) ||
      !validRevision(stroke.sequence) || stroke.revision !== 1 ||
      !WHITEBOARD_COLORS.includes(stroke.color) ||
      !Number.isSafeInteger(stroke.lineWidth) || stroke.lineWidth < 1 ||
      stroke.lineWidth > MAX_LINE_WIDTH || timestampMillis(stroke.createdAt) === null) {
    fail("data-loss", "The company whiteboard stroke needs reconciliation.");
  }
  if (!Array.isArray(stroke.points) || stroke.points.length < 2 ||
      stroke.points.length > MAX_STROKE_POINTS) {
    fail("data-loss", "The company whiteboard stroke needs reconciliation.");
  }
  for (const point of stroke.points) {
    if (!point || typeof point !== "object" || Array.isArray(point) ||
        Object.keys(point).sort().join(",") !== "x,y" ||
        typeof point.x !== "number" || !Number.isFinite(point.x) ||
        typeof point.y !== "number" || !Number.isFinite(point.y) ||
        point.x < 0 || point.x > 1 || point.y < 0 || point.y > 1) {
      fail("data-loss", "The company whiteboard stroke needs reconciliation.");
    }
  }
  return stroke;
}

function nextRevision(value, label) {
  const next = value + 1;
  if (!validRevision(next)) fail("data-loss", `${label} revision is exhausted.`);
  return next;
}

function expectedRevision(actual, expected, label) {
  if (actual !== expected) {
    fail("aborted", `${label} changed. Refresh before retrying.`);
  }
}

function createServerWhiteboardService(dependencies) {
  const { db, Timestamp } = dependencies;
  if (!db?.runTransaction || !Timestamp?.fromMillis) {
    throw new TypeError("db and Timestamp are required.");
  }
  const operations = createServerOperations(dependencies);

  async function createServerWhiteboardStrokeV1(request) {
    const input = baseInput(request.data, ["points", "color", "lineWidth"]);
    input.points = strokePoints(request.data.points);
    input.color = requireEnum(request.data.color, WHITEBOARD_COLORS, "color");
    input.lineWidth = requireSafeInteger(request.data.lineWidth, "lineWidth", {
      min: 1,
      max: MAX_LINE_WIDTH,
    });
    return operations.execute(
      request,
      "server.whiteboard.stroke.create.v1",
      input,
      async ({ transaction, auth, prior, now }) => {
        const access = requireCompanyWhiteboard(await readChannelAccess({
          db,
          transaction,
          uid: auth.uid,
          serverId: input.serverId,
          channelId: input.channelId,
          capability: "write",
        }));
        const stateReference = access.channelReference
          .collection("whiteboardState").doc(WHITEBOARD_STATE_ID);
        const strokeId = canonicalStrokeId(auth.uid, input.requestId);
        const strokeReference = access.channelReference
          .collection("whiteboardStrokes").doc(strokeId);
        const [stateSnapshot, existing] = await Promise.all([
          transaction.get(stateReference),
          transaction.get(strokeReference),
        ]);
        const state = canonicalBoardState(stateSnapshot, input);
        if (prior) {
          if (existing.exists) {
            const stroke = canonicalStroke(existing, { ...input, strokeId });
            if (stroke.authorId === auth.uid && stroke.generation === prior.generation &&
                stroke.sequence === prior.sequence && stroke.revision === prior.revision) {
              return prior;
            }
          } else if (state.generation > prior.generation) {
            return prior;
          }
          fail("aborted", "The whiteboard changed after the original stroke.");
        }
        if (existing.exists) {
          fail("data-loss", "A whiteboard stroke exists without its creation receipt.");
        }
        if (state.strokeCount >= MAX_WHITEBOARD_STROKES) {
          fail("resource-exhausted", "The whiteboard is full. A manager can clear it.");
        }
        const boardRevision = state.revision + 1;
        if (!validRevision(boardRevision)) {
          fail("data-loss", "The company whiteboard revision is exhausted.");
        }
        const sequence = state.nextSequence;
        const nextSequence = nextRevision(sequence, "Whiteboard sequence");
        const nextState = {
          schemaVersion: 1,
          serverId: input.serverId,
          channelId: input.channelId,
          stateId: WHITEBOARD_STATE_ID,
          generation: state.generation,
          revision: boardRevision,
          strokeCount: state.strokeCount + 1,
          nextSequence,
          clearedAt: state.exists ? state.clearedAt : null,
          clearedById: state.exists ? state.clearedById : null,
          updatedAt: now,
        };
        if (state.exists) transaction.update(stateReference, nextState);
        else transaction.create(stateReference, nextState);
        transaction.create(strokeReference, {
          schemaVersion: 1,
          serverId: input.serverId,
          channelId: input.channelId,
          strokeId,
          strokeKind: "polyline",
          authorId: auth.uid,
          generation: state.generation,
          sequence,
          revision: 1,
          color: input.color,
          lineWidth: input.lineWidth,
          points: input.points,
          createdAt: now,
        });
        return {
          serverId: input.serverId,
          channelId: input.channelId,
          strokeId,
          generation: state.generation,
          sequence,
          revision: 1,
          boardRevision,
        };
      },
    );
  }

  async function undoServerWhiteboardStrokeV1(request) {
    const input = baseInput(request.data, ["strokeId", "expectedRevision"]);
    input.strokeId = requireId(request.data.strokeId, "strokeId");
    input.expectedRevision = revision(request.data.expectedRevision, "expectedRevision");
    return operations.execute(
      request,
      "server.whiteboard.stroke.undo.v1",
      input,
      async ({ transaction, auth, prior, now }) => {
        const access = requireCompanyWhiteboard(await readChannelAccess({
          db,
          transaction,
          uid: auth.uid,
          serverId: input.serverId,
          channelId: input.channelId,
          capability: "write",
        }));
        const stateReference = access.channelReference
          .collection("whiteboardState").doc(WHITEBOARD_STATE_ID);
        const strokeReference = access.channelReference
          .collection("whiteboardStrokes").doc(input.strokeId);
        const [stateSnapshot, strokeSnapshot] = await Promise.all([
          transaction.get(stateReference),
          transaction.get(strokeReference),
        ]);
        const state = canonicalBoardState(stateSnapshot, input);
        if (prior) {
          if (!strokeSnapshot.exists) return prior;
          fail("aborted", "The whiteboard stroke still exists after the original undo.");
        }
        if (!state.exists) {
          fail("data-loss", "The company whiteboard state needs reconciliation.");
        }
        const stroke = canonicalStroke(strokeSnapshot, input);
        expectedRevision(stroke.revision, input.expectedRevision, "The whiteboard stroke");
        if (stroke.authorId !== auth.uid) denied();
        if (stroke.generation !== state.generation || state.strokeCount < 1) {
          fail("data-loss", "The company whiteboard count needs reconciliation.");
        }
        const boardRevision = nextRevision(state.revision, "Whiteboard");
        transaction.delete(strokeReference);
        transaction.update(stateReference, {
          revision: boardRevision,
          strokeCount: state.strokeCount - 1,
          updatedAt: now,
        });
        return {
          serverId: input.serverId,
          channelId: input.channelId,
          strokeId: input.strokeId,
          undone: true,
          boardRevision,
        };
      },
      { allowRestricted: true },
    );
  }

  async function clearServerWhiteboardV1(request) {
    const input = baseInput(request.data, ["expectedRevision"]);
    input.expectedRevision = requireSafeInteger(
      request.data.expectedRevision,
      "expectedRevision",
      { min: 0 },
    );
    return operations.execute(
      request,
      "server.whiteboard.clear.v1",
      input,
      async ({ transaction, auth, prior, now }) => {
        const access = requireCompanyWhiteboard(await readChannelAccess({
          db,
          transaction,
          uid: auth.uid,
          serverId: input.serverId,
          channelId: input.channelId,
          capability: "manage",
        }));
        const stateReference = access.channelReference
          .collection("whiteboardState").doc(WHITEBOARD_STATE_ID);
        const state = canonicalBoardState(await transaction.get(stateReference), input);
        if (prior) {
          if (state.generation >= prior.generation) return prior;
          fail("aborted", "The whiteboard changed after the original clear.");
        }
        expectedRevision(state.revision, input.expectedRevision, "The whiteboard");
        if (!state.exists || state.strokeCount === 0) {
          return {
            serverId: input.serverId,
            channelId: input.channelId,
            cleared: false,
            deletedCount: 0,
            generation: state.generation,
            revision: state.revision,
          };
        }
        const strokes = await transaction.get(
          access.channelReference.collection("whiteboardStrokes")
            .where("generation", "==", state.generation)
            .limit(MAX_WHITEBOARD_STROKES + 1),
        );
        if (strokes.size !== state.strokeCount || strokes.size > MAX_WHITEBOARD_STROKES) {
          fail("data-loss", "The company whiteboard count needs reconciliation.");
        }
        for (const document of strokes.docs) {
          canonicalStroke(document, { ...input, strokeId: document.id });
        }
        const generation = nextRevision(state.generation, "Whiteboard generation");
        const boardRevision = nextRevision(state.revision, "Whiteboard");
        for (const document of strokes.docs) transaction.delete(document.ref);
        transaction.update(stateReference, {
          generation,
          revision: boardRevision,
          strokeCount: 0,
          nextSequence: 1,
          clearedAt: now,
          clearedById: auth.uid,
          updatedAt: now,
        });
        return {
          serverId: input.serverId,
          channelId: input.channelId,
          cleared: true,
          deletedCount: strokes.size,
          generation,
          revision: boardRevision,
        };
      },
    );
  }

  return {
    createServerWhiteboardStrokeV1,
    undoServerWhiteboardStrokeV1,
    clearServerWhiteboardV1,
  };
}

module.exports = {
  MAX_LINE_WIDTH,
  MAX_STROKE_POINTS,
  MAX_WHITEBOARD_STROKES,
  WHITEBOARD_COLORS,
  WHITEBOARD_STATE_ID,
  canonicalStrokeId,
  createServerWhiteboardService,
};
