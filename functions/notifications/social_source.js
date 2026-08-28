function isLegacySocialNotificationId(notificationId, notification) {
  const actorId = notification?.actorId;
  return (
    typeof actorId === "string" &&
    ["friendRequest", "friendAccepted", "follow"].includes(
      notification?.type,
    ) &&
    notificationId === `${notification.type}_${actorId}`
  );
}

function timestampGeneration(timestamp) {
  if (!timestamp || !Number.isSafeInteger(timestamp.seconds) ||
      !Number.isSafeInteger(timestamp.nanoseconds)) {
    return null;
  }
  return `${timestamp.seconds}:${timestamp.nanoseconds}`;
}

function documentGeneration(snapshot, field) {
  return timestampGeneration(snapshot?.[field]);
}

function canonicalDirectMessagePath(notification, notificationId) {
  const conversationId = notification?.targetId;
  if (typeof conversationId !== "string" || conversationId.length === 0) {
    return null;
  }
  const explicit = notification?.sourcePath;
  if (typeof explicit === "string" && explicit.length > 0) {
    const prefix = `conversations/${conversationId}/messages/`;
    return explicit.startsWith(prefix) && explicit.length > prefix.length
      ? explicit
      : null;
  }
  if (typeof notificationId !== "string" ||
      !notificationId.startsWith("message_") ||
      notificationId.length === "message_".length) {
    return null;
  }
  return `conversations/${conversationId}/messages/${notificationId.slice(8)}`;
}

async function directMessageSourceIsCurrent({
  recipientId,
  notificationId,
  notification,
  reader,
  firestore,
}) {
  const actorId = notification?.actorId;
  const conversationId = notification?.targetId;
  const sourcePath = canonicalDirectMessagePath(notification, notificationId);
  if (!sourcePath || typeof actorId !== "string" || actorId.length === 0 ||
      typeof recipientId !== "string" || recipientId.length === 0) {
    return false;
  }
  const sourceReader = reader ?? firestore;
  const [message, conversation] = await sourceReader.getAll(
    firestore.doc(sourcePath),
    firestore.doc(`conversations/${conversationId}`),
  );
  const participants = conversation.data()?.participantIds;
  const mutedBy = conversation.data()?.mutedBy;
  const expectedGeneration = notification?.sourceGeneration;
  return message.exists && conversation.exists &&
    message.data()?.isDeleted !== true &&
    message.data()?.senderId === actorId &&
    (typeof expectedGeneration !== "string" || expectedGeneration.length === 0 ||
      documentGeneration(message, "createTime") === expectedGeneration) &&
    Array.isArray(participants) && participants.length === 2 &&
    new Set(participants).size === 2 &&
    participants.includes(actorId) && participants.includes(recipientId) &&
    (!Array.isArray(mutedBy) || !mutedBy.includes(recipientId));
}

function canonicalRoomPath(notification) {
  const roomId = notification?.targetId;
  if (typeof roomId !== "string" || roomId.length === 0) return null;
  const explicit = notification?.sourcePath;
  if (explicit === undefined || explicit === null || explicit === "") {
    return `rooms/${roomId}`;
  }
  return explicit === `rooms/${roomId}` ? explicit : null;
}

function legacyRoomGeneration(notificationId, roomId) {
  const prefix = `live_${roomId}_`;
  if (typeof notificationId !== "string" || !notificationId.startsWith(prefix)) {
    return null;
  }
  const millis = Number(notificationId.slice(prefix.length));
  return Number.isSafeInteger(millis) ? millis : null;
}

async function liveRoomSourceIsCurrent({
  notificationId,
  notification,
  reader,
  firestore,
}) {
  const sourcePath = canonicalRoomPath(notification);
  const actorId = notification?.actorId;
  const roomId = notification?.targetId;
  if (!sourcePath || typeof actorId !== "string" || actorId.length === 0) {
    return false;
  }
  const roomReference = firestore.doc(sourcePath);
  const room = reader
    ? await reader.get(roomReference)
    : await roomReference.get();
  if (!room.exists || room.data()?.isLive !== true ||
      room.data()?.visibility !== "public" || room.data()?.hostId !== actorId) {
    return false;
  }
  const expectedGeneration = notification?.sourceGeneration;
  if (typeof expectedGeneration === "string" && expectedGeneration.length > 0) {
    return documentGeneration(room, "updateTime") === expectedGeneration;
  }
  const legacyMillis = legacyRoomGeneration(notificationId, roomId);
  return legacyMillis === null || room.updateTime?.toMillis?.() === legacyMillis;
}

async function socialNotificationSourceIsCurrent({
  recipientId,
  notificationId,
  notification,
  firestore,
  reader = null,
}) {
  const type = notification?.type;
  if (!["friendRequest", "friendAccepted", "follow"].includes(type)) {
    return true;
  }
  const actorId = notification?.actorId;
  if (typeof actorId !== "string" || actorId.length === 0) return false;
  const legacyGeneration = isLegacySocialNotificationId(
    notificationId,
    notification,
  );
  const sourceReader = reader ?? firestore;
  switch (type) {
    case "friendRequest": {
      const requestReference = firestore.doc(
        `users/${recipientId}/friendRequests/${actorId}`,
      );
      const request = reader
        ? await sourceReader.get(requestReference)
        : await requestReference.get();
      const data = request.data() ?? {};
      return (
        request.exists &&
        typeof notificationId === "string" &&
        (legacyGeneration
          ? !("notificationId" in data)
          : data.notificationId === notificationId)
      );
    }
    case "friendAccepted": {
      const [recipientMirror, actorMirror] = await sourceReader.getAll(
        firestore.doc(`users/${recipientId}/friends/${actorId}`),
        firestore.doc(`users/${actorId}/friends/${recipientId}`),
      );
      const recipientData = recipientMirror.data() ?? {};
      const actorData = actorMirror.data() ?? {};
      if (legacyGeneration) {
        return (
          recipientMirror.exists &&
          actorMirror.exists &&
          !("acceptanceNotificationId" in recipientData) &&
          !("acceptanceNotificationId" in actorData) &&
          !("acceptanceRecipientId" in recipientData) &&
          !("acceptanceRecipientId" in actorData)
        );
      }
      return (
        recipientMirror.exists &&
        actorMirror.exists &&
        typeof notificationId === "string" &&
        recipientData.acceptanceNotificationId === notificationId &&
        actorData.acceptanceNotificationId === notificationId &&
        recipientData.acceptanceRecipientId === recipientId &&
        actorData.acceptanceRecipientId === recipientId
      );
    }
    case "follow": {
      const edgeReference = firestore.doc(
        `users/${recipientId}/followers/${actorId}`,
      );
      const edge = reader
        ? await sourceReader.get(edgeReference)
        : await edgeReference.get();
      const data = edge.data() ?? {};
      return (
        edge.exists &&
        typeof notificationId === "string" &&
        (legacyGeneration
          ? !("notificationId" in data)
          : data.notificationId === notificationId)
      );
    }
    default:
      return true;
  }
}

async function notificationSourceIsCurrent({
  recipientId,
  notificationId,
  notification,
  firestore,
  reader = null,
}) {
  if (["directMessage", "reply"].includes(notification?.type)) {
    return directMessageSourceIsCurrent({
      recipientId,
      notificationId,
      notification,
      reader,
      firestore,
    });
  }
  if (notification?.type === "liveStarted") {
    return liveRoomSourceIsCurrent({
      notificationId,
      notification,
      reader,
      firestore,
    });
  }
  return socialNotificationSourceIsCurrent({
    recipientId,
    notificationId,
    notification,
    firestore,
    reader,
  });
}

module.exports = {
  directMessageSourceIsCurrent,
  documentGeneration,
  isLegacySocialNotificationId,
  liveRoomSourceIsCurrent,
  notificationSourceIsCurrent,
  socialNotificationSourceIsCurrent,
  timestampGeneration,
};
