const assert = require("node:assert/strict");
const { describe, test } = require("node:test");

const {
  AchievementOutboxValidationError,
  buildAchievementOutboxRecord,
} = require("../achievements/runtime");
const {
  createAchievementSourceHandlers,
  storageObjectNotFound,
} = require("../achievements/triggers");

const AT = new Date("2026-08-16T12:00:00.000Z");

function snapshot(data, { createTime = AT, updateTime = createTime } = {}) {
  return {
    createTime,
    updateTime,
    data: () => structuredClone(data),
    ref: { path: "achievementOutbox/outbox-1" },
  };
}

class FakeReader {
  constructor(documents = {}) {
    this.documents = new Map(Object.entries(documents));
    this.storageResult = null;
    this.storageError = null;
    this.processed = [];
    this.invalid = [];
  }

  async read(path) {
    return structuredClone(this.documents.get(path) ?? null);
  }

  async readStorageObject() {
    if (this.storageError) throw this.storageError;
    return structuredClone(this.storageResult);
  }

  async markOutboxProcessed(reference, result) {
    this.processed.push({ reference, result });
  }

  async markOutboxInvalid(reference) {
    this.invalid.push(reference);
  }
}

function runtimeRecorder() {
  const sources = [];
  const outboxes = [];
  return {
    sources,
    outboxes,
    runtime: {
      async processSourceEvent(source, options) {
        sources.push({ source, options });
        return source
          ? { outcome: "processed", results: [] }
          : { outcome: "skipped:invalid-source", results: [] };
      },
      async processOutboxRecord(record, id) {
        outboxes.push({ record, id });
        return { outcome: "applied", eventId: id };
      },
    },
  };
}

function directMessage() {
  return {
    schemaVersion: 2,
    sequence: 1,
    conversationId: "conversation-1",
    senderId: "sender-1",
    type: "text",
    content: "hello",
    mediaUrl: null,
    durationSeconds: null,
    sentAt: AT,
    readBy: ["sender-1"],
    reactions: {},
    isDeleted: false,
    editedAt: null,
    replyToMessageId: null,
    replyToSenderId: null,
    replyToContent: null,
  };
}

function momentPair() {
  const momentId = "a".repeat(20);
  const common = {
    schemaVersion: 2,
    authorId: "author-1",
    authorName: "Author",
    authorPhotoUrl: null,
    caption: "hello",
    storagePath: `voice_moments/author-1/${momentId}.m4a`,
    durationSeconds: 20,
    likeCount: 0,
    commentCount: 0,
    replyToMomentId: null,
    isDeleted: false,
    createdAt: new Date(AT.getTime() - 1000),
  };
  return {
    momentId,
    before: {
      ...common,
      audioUrl: null,
      isPublished: false,
      status: "uploading",
      mediaGeneration: null,
      mediaSize: null,
      mediaContentType: null,
      publishedAt: null,
      updatedAt: new Date(AT.getTime() - 1000),
    },
    after: {
      ...common,
      audioUrl: "https://storage.example/audio.m4a",
      isPublished: true,
      status: "published",
      mediaGeneration: "7",
      mediaSize: 4096,
      mediaContentType: "audio/mp4",
      publishedAt: AT,
      updatedAt: AT,
    },
  };
}

describe("server-authoritative achievement bindings", () => {
  test("direct messages are re-read against conversation and account authority", async () => {
    const reader = new FakeReader({
      "conversations/conversation-1": {
        schemaVersion: 2,
        participantIds: ["sender-1", "recipient-1"],
      },
      "users/sender-1": { banned: false, disabled: false },
    });
    const recorded = runtimeRecorder();
    const handlers = createAchievementSourceHandlers({
      reader,
      runtimeProvider: () => recorded.runtime,
    });
    const result = await handlers.onDirectMessageCreated({
      params: { conversationId: "conversation-1", messageId: "message-1" },
      data: snapshot(directMessage()),
    });
    assert.equal(result.outcome, "processed");
    assert.equal(recorded.sources[0].source.beneficiaryId, "sender-1");

    reader.documents.set("users/sender-1", { banned: true });
    const denied = await handlers.onDirectMessageCreated({
      params: { conversationId: "conversation-1", messageId: "message-2" },
      data: snapshot({ ...directMessage(), sequence: 2 }),
    });
    assert.equal(denied.outcome, "skipped:unauthorized-direct-sender");
    assert.equal(recorded.sources.length, 1);
  });

  test("moment not-found skips, but transient Storage failures remain retryable", async () => {
    const pair = momentPair();
    const reader = new FakeReader({
      "users/author-1": { banned: false, disabled: false },
    });
    const recorded = runtimeRecorder();
    const handlers = createAchievementSourceHandlers({
      reader,
      runtimeProvider: () => recorded.runtime,
    });
    reader.storageError = Object.assign(new Error("gone"), { code: 404 });
    const missing = await handlers.onMomentPublished({
      params: { momentId: pair.momentId },
      data: {
        before: snapshot(pair.before),
        after: snapshot(pair.after, { updateTime: AT }),
      },
    });
    assert.equal(missing.outcome, "skipped:missing-moment-media");

    const transient = Object.assign(new Error("storage timeout"), { code: 503 });
    reader.storageError = transient;
    await assert.rejects(
      handlers.onMomentPublished({
        params: { momentId: pair.momentId },
        data: {
          before: snapshot(pair.before),
          after: snapshot(pair.after, { updateTime: AT }),
        },
      }),
      transient,
    );
    assert.equal(storageObjectNotFound(transient), false);
  });

  test("valid outbox is marked only after processing succeeds", async () => {
    const reader = new FakeReader();
    const recorded = runtimeRecorder();
    const handlers = createAchievementSourceHandlers({
      reader,
      runtimeProvider: () => recorded.runtime,
    });
    const record = buildAchievementOutboxRecord({
      sourceType: "liveKitVoiceSession",
      sourceKey: "livekit/r/p",
      beneficiaryId: "user-1",
      actorId: "user-1",
      metric: "voiceSeconds",
      mode: "increment",
      delta: 60,
      occurredAt: AT,
    }, AT);
    const result = await handlers.onOutboxCreated({
      params: { outboxId: record.eventId },
      data: snapshot(record),
    });
    assert.equal(result.outcome, "applied");
    assert.equal(reader.processed.length, 1);
    assert.equal(reader.invalid.length, 0);
  });

  test("poison outbox becomes deterministic invalid, while transient engine errors throw", async () => {
    const reader = new FakeReader();
    const poisonRuntime = {
      async processOutboxRecord() {
        throw new AchievementOutboxValidationError("tampered");
      },
    };
    const poison = createAchievementSourceHandlers({
      reader,
      runtimeProvider: () => poisonRuntime,
    });
    const invalid = await poison.onOutboxCreated({
      params: { outboxId: "forged" },
      data: snapshot({ status: "pending" }),
    });
    assert.deepEqual(invalid, { outcome: "invalid", outboxId: "forged" });
    assert.equal(reader.invalid.length, 1);
    assert.equal(reader.processed.length, 0);

    const transient = new Error("firestore unavailable");
    const retryable = createAchievementSourceHandlers({
      reader: new FakeReader(),
      runtimeProvider: () => ({
        async processOutboxRecord() {
          throw transient;
        },
      }),
    });
    await assert.rejects(
      retryable.onOutboxCreated({
        params: { outboxId: "canonical" },
        data: snapshot({ status: "pending" }),
      }),
      transient,
    );
  });

  test("social snapshots require monotonic server revision fields", async () => {
    const recorded = runtimeRecorder();
    const handlers = createAchievementSourceHandlers({
      reader: new FakeReader(),
      runtimeProvider: () => recorded.runtime,
    });
    const result = await handlers.onUserSocialCountersChanged({
      params: { userId: "user-1" },
      data: {
        before: snapshot({
          friendCount: 1,
          followerCount: 2,
          friendAchievementRevision: 4,
          followerAchievementRevision: 7,
        }),
        after: snapshot({
          friendCount: 2,
          followerCount: 2,
          friendAchievementRevision: 5,
          followerAchievementRevision: 7,
        }, { updateTime: AT }),
      },
    });
    assert.equal(result.outcome, "processed");
    assert.equal(recorded.sources.length, 1);
    assert.equal(recorded.sources[0].source.metric, "friends");
    assert.deepEqual(recorded.sources[0].options, { includeActiveDay: false });

    const rollback = await handlers.onUserSocialCountersChanged({
      params: { userId: "user-1" },
      data: {
        before: snapshot({
          friendCount: 2,
          followerCount: 2,
          friendAchievementRevision: 5,
          followerAchievementRevision: 7,
        }),
        after: snapshot({
          friendCount: 99,
          followerCount: 2,
          friendAchievementRevision: 4,
          followerAchievementRevision: 7,
        }, { updateTime: AT }),
      },
    });
    assert.equal(rollback.outcome, "skipped:invalid-social-revision");
  });
});
