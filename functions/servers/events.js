const {
  digest,
  fail,
  requireBoolean,
  requireExactInput,
  requireId,
  requireRequestId,
  requireSafeInteger,
  requireUid,
  timestampMillis,
} = require("../integrity/guards");
const { MODERATOR_ROLES, denied, readChannelAccess, validRevision } = require("./authority");
const { requireEnum, revision, text } = require("./contract");
const { createServerOperations } = require("./operations");

const EVENT_STATUSES = Object.freeze(["scheduled", "cancelled"]);
const EVENT_RESPONSES = Object.freeze(["going", "maybe", "declined"]);
const EVENT_PROFILES = Object.freeze(Object.fromEntries(Object.entries({
  "friends:events": {
    eventKind: "friendsEvent", rsvpEnabled: true, reminderOptInEnabled: false,
  },
  "community:events": {
    eventKind: "communityEvent", rsvpEnabled: true, reminderOptInEnabled: false,
  },
  "family:calendar": {
    eventKind: "familyCalendarEvent", rsvpEnabled: true, reminderOptInEnabled: true,
  },
  "podcast:events": {
    eventKind: "podcastProgramEvent", rsvpEnabled: true, reminderOptInEnabled: true,
  },
}).map(([key, value]) => [key, Object.freeze(value)])));
const EVENT_HORIZON_MS = 2 * 366 * 24 * 60 * 60_000;
const EVENT_MAX_DURATION_MS = 7 * 24 * 60 * 60_000;
const MAX_TIMESTAMP_MILLIS = 253_402_300_799_999;

function canonicalEventId(uid, requestId) {
  requireUid(uid);
  requireRequestId(requestId);
  return `ev_${digest("server.event.create.v1", uid, requestId).slice(0, 40)}`;
}

function eventMutationInput(data, extras = [], optional = []) {
  const fields = ["serverId", "channelId", "requestId", ...extras];
  requireExactInput(data, [...fields, ...optional], fields);
  return {
    serverId: requireId(data.serverId, "serverId"),
    channelId: requireId(data.channelId, "channelId"),
    requestId: requireRequestId(data.requestId),
  };
}

function eventTimestamp(value, label) {
  return requireSafeInteger(value, label, { min: 0, max: MAX_TIMESTAMP_MILLIS });
}

function eventTimeZone(value) {
  const zone = text(value, 64, "timeZone", 1);
  try {
    new Intl.DateTimeFormat("en", { timeZone: zone }).format(0);
  } catch {
    fail("invalid-argument", "timeZone must be a valid IANA time zone.");
  }
  return zone;
}

function eventFields(data) {
  return {
    title: text(data.title, 120, "title", 1),
    description: text(data.description, 2000, "description"),
    startsAtMillis: eventTimestamp(data.startsAtMillis, "startsAtMillis"),
    endsAtMillis: eventTimestamp(data.endsAtMillis, "endsAtMillis"),
    timeZone: eventTimeZone(data.timeZone),
  };
}

function requireSchedule(fields, nowMs) {
  if (fields.startsAtMillis < nowMs || fields.startsAtMillis > nowMs + EVENT_HORIZON_MS) {
    fail("invalid-argument", "The event must start within the next two years.");
  }
  const duration = fields.endsAtMillis - fields.startsAtMillis;
  if (!Number.isSafeInteger(duration) || duration < 1 || duration > EVENT_MAX_DURATION_MS) {
    fail("invalid-argument", "The event duration is invalid.");
  }
}

function responseCounts(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail("data-loss", "The event response counts need reconciliation.");
  }
  const keys = Object.keys(value).sort();
  if (keys.length !== 3 || keys[0] !== "declined" || keys[1] !== "going" || keys[2] !== "maybe") {
    fail("data-loss", "The event response counts need reconciliation.");
  }
  for (const key of EVENT_RESPONSES) {
    if (!Number.isSafeInteger(value[key]) || value[key] < 0 || value[key] >= Number.MAX_SAFE_INTEGER) {
      fail("data-loss", "The event response counts need reconciliation.");
    }
  }
  return value;
}

function eventProfile(access) {
  const serverType = access?.server?.serverType;
  const channelKind = access?.channel?.kind;
  const profile = EVENT_PROFILES[`${serverType}:${channelKind}`];
  if (!profile) denied();
  return { ...profile, serverType, channelKind };
}

function canonicalEvent(snapshot, { serverId, channelId, eventId }, profile) {
  if (!snapshot.exists) fail("not-found", "The selected event is unavailable.");
  const event = snapshot.data() ?? {};
  const startsAtMillis = timestampMillis(event.startsAt);
  const endsAtMillis = timestampMillis(event.endsAt);
  if (event.schemaVersion !== 1 || event.serverId !== serverId ||
      event.channelId !== channelId || event.eventId !== eventId ||
      event.eventKind !== profile.eventKind || event.serverType !== profile.serverType ||
      event.channelKind !== profile.channelKind || event.rsvpEnabled !== profile.rsvpEnabled ||
      event.reminderOptInEnabled !== profile.reminderOptInEnabled ||
      !Number.isSafeInteger(event.reminderCount) || event.reminderCount < 0 ||
      event.reminderCount >= Number.MAX_SAFE_INTEGER || !EVENT_STATUSES.includes(event.status) ||
      !validRevision(event.revision) || typeof event.authorId !== "string" ||
      startsAtMillis === null || endsAtMillis === null || endsAtMillis <= startsAtMillis ||
      typeof event.title !== "string" || typeof event.description !== "string" ||
      typeof event.timeZone !== "string") {
    fail("data-loss", "The event needs reconciliation.");
  }
  responseCounts(event.responseCounts);
  return { ...event, startsAtMillis, endsAtMillis };
}

function canonicalResponse(snapshot, { serverId, channelId, eventId, uid }, profile) {
  if (!snapshot.exists) return null;
  const value = snapshot.data() ?? {};
  if (value.schemaVersion !== 1 || value.serverId !== serverId ||
      value.channelId !== channelId || value.eventId !== eventId ||
      value.userId !== uid || !EVENT_RESPONSES.includes(value.response) ||
      typeof value.reminderRequested !== "boolean" ||
      (value.reminderRequested && !profile.reminderOptInEnabled) ||
      !validRevision(value.eventRevision) || typeof value.operationId !== "string" ||
      timestampMillis(value.createdAt) === null || timestampMillis(value.updatedAt) === null) {
    fail("data-loss", "The event response needs reconciliation.");
  }
  return value;
}

function canManageEvent(access, uid, event) {
  return event.authorId === uid || MODERATOR_ROLES.includes(access.member.role);
}

function requireExpected(actual, expected) {
  if (actual !== expected) {
    fail("aborted", "This event changed. Refresh before retrying this change.");
  }
}

function createServerEventService(dependencies) {
  const { db, Timestamp } = dependencies;
  if (!db?.runTransaction || !Timestamp?.fromMillis) {
    throw new TypeError("db and Timestamp are required.");
  }
  const operations = createServerOperations(dependencies);

  async function createServerEventV1(request) {
    const required = ["title", "description", "startsAtMillis", "endsAtMillis", "timeZone"];
    const input = eventMutationInput(request.data, required);
    Object.assign(input, eventFields(request.data));
    return operations.execute(request, "server.event.create.v1", input, async ({
      transaction, auth, prior, now, nowMs,
    }) => {
      const access = await readChannelAccess({
        db, transaction, uid: auth.uid, serverId: input.serverId,
        channelId: input.channelId, capability: "write",
      });
      const profile = eventProfile(access);
      const eventId = canonicalEventId(auth.uid, input.requestId);
      const reference = access.channelReference.collection("events").doc(eventId);
      const existing = await transaction.get(reference);
      if (prior) {
        const event = canonicalEvent(existing, { ...input, eventId }, profile);
        if (event.revision === prior.revision && event.authorId === auth.uid) return prior;
        fail("aborted", "The event changed after the original request.");
      }
      if (existing.exists) fail("data-loss", "An event exists without its creation receipt.");
      requireSchedule(input, nowMs);
      const event = {
        schemaVersion: 1,
        serverId: input.serverId,
        channelId: input.channelId,
        eventId,
        eventKind: profile.eventKind,
        serverType: profile.serverType,
        channelKind: profile.channelKind,
        rsvpEnabled: profile.rsvpEnabled,
        reminderOptInEnabled: profile.reminderOptInEnabled,
        title: input.title,
        description: input.description,
        startsAt: Timestamp.fromMillis(input.startsAtMillis),
        endsAt: Timestamp.fromMillis(input.endsAtMillis),
        timeZone: input.timeZone,
        status: "scheduled",
        responseCounts: { going: 0, maybe: 0, declined: 0 },
        reminderCount: 0,
        authorId: auth.uid,
        revision: 1,
        createdAt: now,
        updatedAt: now,
      };
      transaction.create(reference, event);
      return {
        serverId: input.serverId,
        channelId: input.channelId,
        eventId,
        revision: 1,
        status: "scheduled",
      };
    });
  }

  async function updateServerEventV1(request) {
    const input = eventMutationInput(request.data, ["eventId", "expectedRevision", "patch"]);
    input.eventId = requireId(request.data.eventId, "eventId");
    input.expectedRevision = revision(request.data.expectedRevision, "expectedRevision");
    requireExactInput(request.data.patch, [
      "title", "description", "startsAtMillis", "endsAtMillis", "timeZone",
    ]);
    if (Object.keys(request.data.patch).length === 0) fail("invalid-argument", "The patch is empty.");
    input.patch = {};
    if (Object.hasOwn(request.data.patch, "title")) {
      input.patch.title = text(request.data.patch.title, 120, "title", 1);
    }
    if (Object.hasOwn(request.data.patch, "description")) {
      input.patch.description = text(request.data.patch.description, 2000, "description");
    }
    if (Object.hasOwn(request.data.patch, "startsAtMillis")) {
      input.patch.startsAtMillis = eventTimestamp(request.data.patch.startsAtMillis, "startsAtMillis");
    }
    if (Object.hasOwn(request.data.patch, "endsAtMillis")) {
      input.patch.endsAtMillis = eventTimestamp(request.data.patch.endsAtMillis, "endsAtMillis");
    }
    if (Object.hasOwn(request.data.patch, "timeZone")) {
      input.patch.timeZone = eventTimeZone(request.data.patch.timeZone);
    }
    return operations.execute(request, "server.event.update.v1", input, async ({
      transaction, auth, prior, now, nowMs,
    }) => {
      const access = await readChannelAccess({
        db, transaction, uid: auth.uid, serverId: input.serverId,
        channelId: input.channelId, capability: "write",
      });
      const profile = eventProfile(access);
      const reference = access.channelReference.collection("events").doc(input.eventId);
      const event = canonicalEvent(await transaction.get(reference), input, profile);
      if (!canManageEvent(access, auth.uid, event)) denied();
      if (prior) {
        if (event.revision === prior.revision) return prior;
        fail("aborted", "The event changed after the original request.");
      }
      requireExpected(event.revision, input.expectedRevision);
      if (event.status !== "scheduled" || event.startsAtMillis <= nowMs) {
        fail("failed-precondition", "Only an upcoming event can be updated.");
      }
      const schedule = {
        startsAtMillis: input.patch.startsAtMillis ?? event.startsAtMillis,
        endsAtMillis: input.patch.endsAtMillis ?? event.endsAtMillis,
      };
      requireSchedule(schedule, nowMs);
      const nextRevision = event.revision + 1;
      if (!validRevision(nextRevision)) fail("data-loss", "The event revision is exhausted.");
      const patch = {
        ...(Object.hasOwn(input.patch, "title") ? { title: input.patch.title } : {}),
        ...(Object.hasOwn(input.patch, "description") ? { description: input.patch.description } : {}),
        ...(Object.hasOwn(input.patch, "startsAtMillis")
          ? { startsAt: Timestamp.fromMillis(input.patch.startsAtMillis) } : {}),
        ...(Object.hasOwn(input.patch, "endsAtMillis")
          ? { endsAt: Timestamp.fromMillis(input.patch.endsAtMillis) } : {}),
        ...(Object.hasOwn(input.patch, "timeZone") ? { timeZone: input.patch.timeZone } : {}),
        revision: nextRevision,
        updatedAt: now,
      };
      transaction.update(reference, patch);
      return {
        serverId: input.serverId,
        channelId: input.channelId,
        eventId: input.eventId,
        revision: nextRevision,
        status: "scheduled",
      };
    });
  }

  async function cancelServerEventV1(request) {
    const input = eventMutationInput(request.data, ["eventId", "expectedRevision"]);
    input.eventId = requireId(request.data.eventId, "eventId");
    input.expectedRevision = revision(request.data.expectedRevision, "expectedRevision");
    return operations.execute(request, "server.event.cancel.v1", input, async ({
      transaction, auth, prior, now,
    }) => {
      const access = await readChannelAccess({
        db, transaction, uid: auth.uid, serverId: input.serverId,
        channelId: input.channelId, capability: "write",
      });
      const profile = eventProfile(access);
      const reference = access.channelReference.collection("events").doc(input.eventId);
      const event = canonicalEvent(await transaction.get(reference), input, profile);
      if (!canManageEvent(access, auth.uid, event)) denied();
      if (prior) {
        if (event.status === "cancelled" && event.revision === prior.revision) return prior;
        fail("aborted", "The event changed after the original request.");
      }
      requireExpected(event.revision, input.expectedRevision);
      if (event.status === "cancelled") {
        return {
          serverId: input.serverId,
          channelId: input.channelId,
          eventId: input.eventId,
          revision: event.revision,
          status: "cancelled",
          cancelled: false,
        };
      }
      const nextRevision = event.revision + 1;
      if (!validRevision(nextRevision)) fail("data-loss", "The event revision is exhausted.");
      transaction.update(reference, {
        status: "cancelled",
        revision: nextRevision,
        cancelledById: auth.uid,
        cancelledAt: now,
        updatedAt: now,
      });
      return {
        serverId: input.serverId,
        channelId: input.channelId,
        eventId: input.eventId,
        revision: nextRevision,
        status: "cancelled",
        cancelled: true,
      };
    }, { allowRestricted: true });
  }

  async function respondToServerEventV1(request) {
    const input = eventMutationInput(
      request.data,
      ["eventId", "expectedRevision", "response"],
      ["reminderRequested"],
    );
    input.eventId = requireId(request.data.eventId, "eventId");
    input.expectedRevision = revision(request.data.expectedRevision, "expectedRevision");
    input.response = requireEnum(request.data.response, EVENT_RESPONSES, "response");
    input.reminderRequested = Object.hasOwn(request.data, "reminderRequested")
      ? requireBoolean(request.data.reminderRequested, "reminderRequested")
      : false;
    return operations.execute(request, "server.event.respond.v1", input, async ({
      transaction, auth, prior, now, nowMs, identity,
    }) => {
      const access = await readChannelAccess({
        db, transaction, uid: auth.uid, serverId: input.serverId,
        channelId: input.channelId, capability: "write",
      });
      const profile = eventProfile(access);
      if (input.reminderRequested && !profile.reminderOptInEnabled) {
        fail("invalid-argument", "This event does not support reminder opt-in.");
      }
      const reference = access.channelReference.collection("events").doc(input.eventId);
      const responseReference = reference.collection("responses").doc(auth.uid);
      const [eventSnapshot, responseSnapshot] = await Promise.all([
        transaction.get(reference), transaction.get(responseReference),
      ]);
      const event = canonicalEvent(eventSnapshot, input, profile);
      const existing = canonicalResponse(responseSnapshot, { ...input, uid: auth.uid }, profile);
      if (prior) {
        if (existing?.operationId === identity.id && existing.response === prior.response &&
            existing.reminderRequested === prior.reminderRequested &&
            event.revision === prior.eventRevision) return prior;
        fail("aborted", "The response changed after the original request.");
      }
      requireExpected(event.revision, input.expectedRevision);
      if (event.status !== "scheduled" || event.startsAtMillis <= nowMs) {
        fail("failed-precondition", "This event is no longer accepting responses.");
      }
      const counts = { ...responseCounts(event.responseCounts) };
      const responseChanged = existing?.response !== input.response;
      const reminderChanged = (existing?.reminderRequested ?? false) !== input.reminderRequested;
      if (responseChanged) {
        if (existing) {
          if (counts[existing.response] === 0) {
            fail("data-loss", "The event response counts need reconciliation.");
          }
          counts[existing.response] -= 1;
        }
        counts[input.response] += 1;
        if (counts[input.response] >= Number.MAX_SAFE_INTEGER) {
          fail("data-loss", "The event response count is exhausted.");
        }
      }
      let reminderCount = event.reminderCount;
      if (reminderChanged) reminderCount += input.reminderRequested ? 1 : -1;
      if (!Number.isSafeInteger(reminderCount) || reminderCount < 0 ||
          reminderCount >= Number.MAX_SAFE_INTEGER) {
        fail("data-loss", "The event reminder count needs reconciliation.");
      }
      const changed = responseChanged || reminderChanged;
      if (changed) transaction.update(reference, {
        responseCounts: counts, reminderCount, updatedAt: now,
      });
      transaction.set(responseReference, {
        schemaVersion: 1,
        serverId: input.serverId,
        channelId: input.channelId,
        eventId: input.eventId,
        userId: auth.uid,
        response: input.response,
        reminderRequested: input.reminderRequested,
        eventRevision: event.revision,
        operationId: identity.id,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      });
      return {
        serverId: input.serverId,
        channelId: input.channelId,
        eventId: input.eventId,
        response: input.response,
        reminderRequested: input.reminderRequested,
        reminderCount,
        eventRevision: event.revision,
        changed,
        responseCounts: counts,
      };
    });
  }

  return {
    createServerEventV1,
    updateServerEventV1,
    cancelServerEventV1,
    respondToServerEventV1,
  };
}

module.exports = {
  EVENT_MAX_DURATION_MS,
  EVENT_PROFILES,
  EVENT_RESPONSES,
  EVENT_STATUSES,
  canonicalEventId,
  createServerEventService,
};
