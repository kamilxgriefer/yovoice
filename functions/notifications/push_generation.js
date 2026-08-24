// A deterministic notification id is reused only after the previous social
// lifecycle was deleted. Firestore may deliver the old onCreate event late,
// so existence alone is not enough: the currently stored document must be
// the exact generation that produced the event.
function isCurrentNotificationGeneration(createdSnapshot, currentSnapshot) {
  if (!createdSnapshot || !currentSnapshot?.exists) return false;
  const createdAt = createdSnapshot.createTime;
  const currentAt = currentSnapshot.createTime;
  if (!createdAt || !currentAt || typeof createdAt.isEqual !== "function") {
    return false;
  }
  return createdAt.isEqual(currentAt);
}

module.exports = { isCurrentNotificationGeneration };
