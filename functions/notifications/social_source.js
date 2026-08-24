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

async function socialNotificationSourceIsCurrent({
  recipientId,
  notificationId,
  notification,
  firestore,
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
  switch (type) {
    case "friendRequest": {
      const request = await firestore.doc(
        `users/${recipientId}/friendRequests/${actorId}`,
      ).get();
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
      const [recipientMirror, actorMirror] = await firestore.getAll(
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
      const edge = await firestore
        .doc(`users/${recipientId}/followers/${actorId}`)
        .get();
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

module.exports = {
  isLegacySocialNotificationId,
  socialNotificationSourceIsCurrent,
};
