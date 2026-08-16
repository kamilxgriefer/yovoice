const ACHIEVEMENT_EVENTS = "achievementEvents";
const ACHIEVEMENT_PROGRESS = "achievementProgress";

class FirestoreAchievementRepository {
  constructor({ db = null } = {}) {
    // Resolve lazily so importing the pure engine in a unit test does not
    // require an initialized Firebase Admin app.
    this.db = db ?? require("../utils/firestore").db;
  }

  async runTransaction(callback) {
    if (typeof callback !== "function") throw new TypeError("callback is required.");
    return this.db.runTransaction(async (firestoreTransaction) => {
      const repository = this;
      return callback({
        async getEvent(eventId) {
          const snapshot = await firestoreTransaction.get(
            repository.db.collection(ACHIEVEMENT_EVENTS).doc(eventId),
          );
          return snapshot.exists ? snapshot.data() : null;
        },
        async getUser(uid) {
          const snapshot = await firestoreTransaction.get(
            repository.db.collection("users").doc(uid),
          );
          return snapshot.exists ? snapshot.data() : null;
        },
        async getProgress(uid) {
          const snapshot = await firestoreTransaction.get(
            repository.db.collection(ACHIEVEMENT_PROGRESS).doc(uid),
          );
          return snapshot.exists ? snapshot.data() : null;
        },
        async getNotification(uid, notificationId) {
          const snapshot = await firestoreTransaction.get(
            repository.db
              .collection("users")
              .doc(uid)
              .collection("notifications")
              .doc(notificationId),
          );
          return snapshot.exists ? snapshot.data() : null;
        },
        async createEvent(eventId, data) {
          firestoreTransaction.create(
            repository.db.collection(ACHIEVEMENT_EVENTS).doc(eventId),
            data,
          );
        },
        async setProgress(uid, data) {
          firestoreTransaction.set(
            repository.db.collection(ACHIEVEMENT_PROGRESS).doc(uid),
            data,
          );
        },
        async setUserProjection(uid, data) {
          firestoreTransaction.set(
            repository.db.collection("users").doc(uid),
            data,
            { merge: true },
          );
        },
        async createNotification(uid, notificationId, data) {
          firestoreTransaction.create(
            repository.db
              .collection("users")
              .doc(uid)
              .collection("notifications")
              .doc(notificationId),
            data,
          );
        },
      });
    });
  }
}

module.exports = {
  ACHIEVEMENT_EVENTS,
  ACHIEVEMENT_PROGRESS,
  FirestoreAchievementRepository,
};
