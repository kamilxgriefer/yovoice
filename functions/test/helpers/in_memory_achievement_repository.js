function clone(value) {
  return value === undefined ? undefined : structuredClone(value);
}

function cloneMap(input) {
  return new Map([...input.entries()].map(([key, value]) => [key, clone(value)]));
}

class InMemoryAchievementRepository {
  constructor() {
    this.users = new Map();
    this.progress = new Map();
    this.events = new Map();
    this.notifications = new Map();
    this.transactionCount = 0;
    this._tail = Promise.resolve();
  }

  seedUser(uid, data = {}) {
    this.users.set(uid, clone(data));
  }

  seedProgress(uid, data = {}) {
    this.progress.set(uid, clone(data));
  }

  seedNotification(uid, notificationId, data = {}) {
    this.notifications.set(`${uid}/${notificationId}`, clone(data));
  }

  user(uid) {
    return clone(this.users.get(uid));
  }

  progressFor(uid) {
    return clone(this.progress.get(uid));
  }

  event(eventId) {
    return clone(this.events.get(eventId));
  }

  notification(uid, notificationId) {
    return clone(this.notifications.get(`${uid}/${notificationId}`));
  }

  notificationEntries(uid) {
    const prefix = `${uid}/`;
    return [...this.notifications.entries()]
      .filter(([key]) => key.startsWith(prefix))
      .map(([key, value]) => ({ id: key.slice(prefix.length), ...clone(value) }));
  }

  async runTransaction(callback) {
    let release;
    const previous = this._tail;
    this._tail = new Promise((resolve) => {
      release = resolve;
    });
    await previous;
    const users = cloneMap(this.users);
    const progress = cloneMap(this.progress);
    const events = cloneMap(this.events);
    const notifications = cloneMap(this.notifications);
    this.transactionCount += 1;
    try {
      const result = await callback({
        async getEvent(eventId) {
          return clone(events.get(eventId)) ?? null;
        },
        async getUser(uid) {
          return clone(users.get(uid)) ?? null;
        },
        async getProgress(uid) {
          return clone(progress.get(uid)) ?? null;
        },
        async getNotification(uid, notificationId) {
          return clone(notifications.get(`${uid}/${notificationId}`)) ?? null;
        },
        async createEvent(eventId, data) {
          if (events.has(eventId)) throw new Error(`event exists: ${eventId}`);
          events.set(eventId, clone(data));
        },
        async setProgress(uid, data) {
          progress.set(uid, clone(data));
        },
        async setUserProjection(uid, data) {
          users.set(uid, { ...(users.get(uid) ?? {}), ...clone(data) });
        },
        async createNotification(uid, notificationId, data) {
          const key = `${uid}/${notificationId}`;
          if (notifications.has(key)) {
            throw new Error(`notification exists: ${key}`);
          }
          notifications.set(key, clone(data));
        },
      });
      this.users = users;
      this.progress = progress;
      this.events = events;
      this.notifications = notifications;
      return result;
    } finally {
      release();
    }
  }
}

module.exports = { InMemoryAchievementRepository };
