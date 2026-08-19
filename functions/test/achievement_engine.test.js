const assert = require("node:assert/strict");
const { describe, test } = require("node:test");

const {
  AchievementEngine,
  AchievementEventValidationError,
  eventIdFor,
} = require("../achievements/engine");
const { catalog } = require("../achievements/catalog");
const {
  availableTitleIds,
  buildUserAchievementProjection,
  normalizeProgress,
} = require("../achievements/model");
const { InMemoryAchievementRepository } = require(
  "./helpers/in_memory_achievement_repository",
);

const UID = "achievement-user";
const NOW = new Date("2026-08-16T12:00:00.000Z");

function event(sourceKey, overrides = {}) {
  return {
    sourceType: "dmMessageCreated",
    sourceKey,
    beneficiaryId: UID,
    actorId: UID,
    metric: "messages",
    mode: "increment",
    delta: 1,
    occurredAt: new Date("2026-08-16T11:59:58.000Z"),
    ...overrides,
  };
}

function setup({ user = { uid: UID, displayName: "Ada" }, clock } = {}) {
  const repository = new InMemoryAchievementRepository();
  repository.seedUser(UID, user);
  const engine = new AchievementEngine({
    repository,
    clock: clock ?? (() => NOW),
  });
  return { repository, engine };
}

describe("idempotent achievement engine", () => {
  test("one canonical event increments, unlocks and emits one deterministic notification", async () => {
    const { repository, engine } = setup();
    const result = await engine.process(event("conversations/c/messages/m1"));

    assert.equal(result.outcome, "applied");
    assert.deepEqual(result.newDisplayTitleIds, ["messages_1"]);
    assert.deepEqual(result.notificationIds, ["achievementUnlocked_messages_1"]);
    assert.equal(repository.progressFor(UID).verifiedMetrics.messages, 1);
    assert.equal(repository.user(UID).messageCount, 1);
    const notification = repository.notification(
      UID,
      "achievementUnlocked_messages_1",
    );
    assert.deepEqual(Object.keys(notification).sort(), [
      "actorId",
      "actorName",
      "actorPhotoUrl",
      "bellSuppressed",
      "createdAt",
      "dedupeKey",
      "isRead",
      "targetId",
      "targetLabel",
      "type",
    ]);
    assert.equal(notification.targetLabel, "First Word");
    assert.ok(!JSON.stringify(notification).includes("Ada"));
  });

  test("sequential and concurrent replay are absorbed exactly once", async () => {
    const { repository, engine } = setup();
    const source = event("conversations/c/messages/replay");
    const results = await Promise.all([
      engine.process(source),
      engine.process(source),
      engine.process(source),
    ]);
    assert.deepEqual(results.map((item) => item.outcome).sort(), [
      "applied",
      "replayed",
      "replayed",
    ]);
    assert.equal(repository.progressFor(UID).verifiedMetrics.messages, 1);
    assert.equal(repository.events.size, 1);
    assert.equal(repository.notificationEntries(UID).length, 1);

    assert.equal((await engine.process(source)).outcome, "replayed");
    assert.equal(repository.progressFor(UID).verifiedMetrics.messages, 1);
  });

  test("different concurrent sources both commit without losing an increment", async () => {
    const { repository, engine } = setup();
    const results = await Promise.all([
      engine.process(event("conversations/c/messages/a")),
      engine.process(event("conversations/c/messages/b")),
    ]);
    assert.deepEqual(results.map((item) => item.outcome), ["applied", "applied"]);
    assert.equal(repository.progressFor(UID).verifiedMetrics.messages, 2);
    assert.equal(repository.events.size, 2);
    assert.equal(repository.notificationEntries(UID).length, 1);
  });

  test("one large trusted backfill effect unlocks every crossed threshold", async () => {
    const { repository, engine } = setup();
    const result = await engine.process(event("backfill/messages/page-1", { delta: 100 }));
    assert.deepEqual(result.newVerifiedTitleIds, [
      "messages_1",
      "messages_10",
      "messages_50",
      "messages_100",
    ]);
    assert.equal(repository.notificationEntries(UID).length, 4);
  });

  test("canonical source collision resolves terminally without weakening dedup", async () => {
    const errors = [];
    const repository = new InMemoryAchievementRepository();
    repository.seedUser(UID, { uid: UID, displayName: "Ada" });
    repository.seedUser("other-user", { uid: "other-user" });
    const engine = new AchievementEngine({
      repository,
      clock: () => NOW,
      logger: { error: (...args) => errors.push(args) },
    });
    const first = event("conversations/c/messages/collision");
    await engine.process(first);

    // A permanent content mismatch must terminate, not throw: throwing turns
    // an at-least-once redelivery into an infinite retry loop, because the
    // redelivered event can only ever derive the same fingerprint again.
    const collided = await engine.process({
      ...first,
      beneficiaryId: "other-user",
      actorId: "other-user",
    });
    assert.equal(collided.outcome, "collision");
    assert.deepEqual(collided.newVerifiedTitleIds, []);
    assert.deepEqual(collided.newDisplayTitleIds, []);
    assert.deepEqual(collided.notificationIds, []);
    // The mismatched event is never applied and the stored entry wins.
    assert.equal(repository.progressFor(UID).verifiedMetrics.messages, 1);
    assert.equal(repository.progressFor("other-user"), undefined);
    assert.equal(repository.events.size, 1);
    assert.equal(repository.event(collided.eventId).beneficiaryId, UID);
    // Dedup is not weakened: the original content still replays cleanly and
    // the collision replays terminally again.
    assert.equal((await engine.process(first)).outcome, "replayed");
    assert.equal((await engine.process({
      ...first,
      beneficiaryId: "other-user",
      actorId: "other-user",
    })).outcome, "collision");
    // Terminal means logged: one forensic report per collision.
    assert.equal(errors.length, 2);
    assert.match(errors[0][0], /Canonical source collision/u);
    assert.equal(errors[0][1].eventId, collided.eventId);
    assert.equal(
      errors[0][1].storedFingerprint,
      repository.event(collided.eventId).eventFingerprint,
    );
    assert.notEqual(errors[0][1].derivedFingerprint, errors[0][1].storedFingerprint);
  });

  test("a recurrence differing only in observation time replays quietly", async () => {
    // Some identities deliberately collapse repeatable occurrences: a
    // community re-join or a reaction removed and re-added arrives with the
    // same canonical content at a new snapshot time. That is a replay of the
    // identity, not an integrity violation — terminal, silent, unapplied.
    const errors = [];
    const repository = new InMemoryAchievementRepository();
    repository.seedUser(UID, { uid: UID });
    const engine = new AchievementEngine({
      repository,
      clock: () => NOW,
      logger: { error: (...args) => errors.push(args) },
    });
    const joined = event(`clubs/club-1/members/${UID}`, {
      sourceType: "communityJoined",
      metric: "communities",
    });
    await engine.process(joined);
    const storedBefore = repository.event(eventIdFor(joined));

    const rejoined = await engine.process({
      ...joined,
      occurredAt: new Date("2026-08-17T09:00:00.000Z"),
    });
    assert.equal(rejoined.outcome, "replayed");
    assert.equal(repository.progressFor(UID).verifiedMetrics.communities, 1);
    assert.equal(repository.events.size, 1);
    // The stored entry keeps its first-write fingerprint and time.
    assert.deepEqual(repository.event(eventIdFor(joined)), storedBefore);
    assert.equal(errors.length, 0);
  });

  test("opaque UIDs are preserved byte-for-byte and never trimmed into another account", async () => {
    const spacedUid = " achievement-user ";
    const repository = new InMemoryAchievementRepository();
    repository.seedUser(UID, { uid: UID });
    repository.seedUser(spacedUid, { uid: spacedUid });
    const engine = new AchievementEngine({ repository, clock: () => NOW });

    const result = await engine.process(event("conversations/c/messages/opaque", {
      beneficiaryId: spacedUid,
      actorId: spacedUid,
    }));

    assert.equal(result.outcome, "applied");
    assert.equal(repository.progressFor(spacedUid).verifiedMetrics.messages, 1);
    assert.equal(repository.progressFor(UID), undefined);
    assert.equal(repository.event(result.eventId).beneficiaryId, spacedUid);
    assert.equal(repository.event(result.eventId).actorId, spacedUid);
  });

  test("legacy claims survive privately for audit but never enter public projection", async () => {
    const legacyTimestamp = new Date("2026-08-01T08:00:00.000Z");
    const { repository, engine } = setup({
      user: {
        uid: UID,
        roomCount: 7,
        unlockedTitleIds: ["rooms_1", "unknown_999"],
        unlockedTitleTimestamps: {
          rooms_1: legacyTimestamp,
          unknown_999: legacyTimestamp,
          messages_1: "malformed",
        },
        selectedTitleId: "rooms_1",
      },
    });
    await engine.process(event("conversations/c/messages/legacy"));
    const progress = repository.progressFor(UID);
    const user = repository.user(UID);

    assert.deepEqual(progress.legacyUnlockedTitleIds, ["rooms_1"]);
    assert.equal(progress.legacyMetricFloors.rooms, 7);
    assert.deepEqual(progress.legacyUnlockedTitleTimestamps.rooms_1, legacyTimestamp);
    assert.deepEqual(progress.verifiedUnlockedTitleIds, ["messages_1"]);
    assert.equal(progress.selectedTitleId, null);
    assert.equal(user.roomCount, 0);
    assert.deepEqual(user.unlockedTitleIds, ["messages_1"]);
    assert.equal(user.unlockedTitleTimestamps.rooms_1, undefined);
  });

  test("a legacy claim emits its first public notification only after verification", async () => {
    const { repository, engine } = setup({
      user: { uid: UID, unlockedTitleIds: ["messages_1"] },
    });
    const result = await engine.process(event("conversations/c/messages/legacy-title"));
    assert.deepEqual(result.newVerifiedTitleIds, ["messages_1"]);
    assert.deepEqual(result.newDisplayTitleIds, ["messages_1"]);
    assert.deepEqual(result.notificationIds, ["achievementUnlocked_messages_1"]);
  });

  test("forged legacy counters and all 100 title ids confer zero verified XP", () => {
    const allIds = catalog.definitions.map((definition) => definition.id);
    const forgedUser = {
      uid: UID,
      messageCount: 10000,
      followerCount: 10000,
      voiceMinutes: 30000,
      roomCount: 10000,
      communityCount: 10000,
      friendCount: 10000,
      reactionCount: 10000,
      hostMinutes: 30000,
      activeDays: 730,
      momentCount: 10000,
      unlockedTitleIds: allIds,
      unlockedTitleTimestamps: Object.fromEntries(
        allIds.map((id) => [id, NOW]),
      ),
      selectedTitleId: allIds.at(-1),
    };
    const progress = normalizeProgress(null, { legacyUser: forgedUser });
    const projection = buildUserAchievementProjection(progress, NOW);
    const verifiedXp = availableTitleIds(progress).reduce(
      (total, id) => total + catalog.definitions.find(
        (definition) => definition.id === id,
      ).xp,
      0,
    );

    assert.equal(progress.legacyUnlockedTitleIds.length, 100);
    assert.equal(progress.legacyMetricFloors.messages, 10000);
    assert.deepEqual(progress.verifiedUnlockedTitleIds, []);
    assert.deepEqual(projection.unlockedTitleIds, []);
    assert.equal(projection.selectedTitleId, null);
    assert.equal(projection.messageCount, 0);
    assert.equal(verifiedXp, 0);
  });

  test("absolute social snapshots reject stale versions and never relock titles", async () => {
    const { repository, engine } = setup();
    const absolute = (sourceKey, value, version) => event(sourceKey, {
      sourceType: "socialMetricSnapshot",
      metric: "friends",
      mode: "absolute",
      delta: undefined,
      value,
      version,
    });
    await engine.process(absolute("users/u/social/friends/v2", 10, 2));
    await engine.process(absolute("users/u/social/friends/v3", 0, 3));
    const stale = await engine.process(absolute("users/u/social/friends/v1", 100, 1));

    assert.equal(stale.outcome, "stale");
    const progress = repository.progressFor(UID);
    assert.equal(progress.verifiedMetrics.friends, 0);
    assert.equal(progress.peakMetrics.friends, 10);
    assert.ok(progress.verifiedUnlockedTitleIds.includes("friends_10"));
    assert.ok(!progress.verifiedUnlockedTitleIds.includes("friends_50"));
    // Achievement projection never overwrites authoritative social counters.
    assert.equal("friendCount" in repository.user(UID), false);
  });

  test("voice seconds accumulate before whole-minute unlocks", async () => {
    const { repository, engine } = setup();
    const voice = (key, delta) => event(key, {
      sourceType: "liveKitVoiceSession",
      metric: "voiceSeconds",
      delta,
    });
    let result = await engine.process(voice("livekit/r/p1", 59));
    assert.deepEqual(result.newVerifiedTitleIds, []);
    assert.equal(repository.user(UID).voiceMinutes, 0);
    result = await engine.process(voice("livekit/r/p2", 1));
    assert.deepEqual(result.newVerifiedTitleIds, ["voiceMinutes_1"]);
    assert.equal(repository.user(UID).voiceMinutes, 1);
  });

  test("an existing deterministic notification is neither overwritten nor duplicated", async () => {
    const { repository, engine } = setup();
    repository.seedNotification(UID, "achievementUnlocked_messages_1", {
      type: "achievementUnlocked",
      isRead: true,
      marker: "preserve-me",
    });
    const result = await engine.process(event("conversations/c/messages/existing-note"));
    assert.deepEqual(result.notificationIds, []);
    assert.equal(
      repository.notification(UID, "achievementUnlocked_messages_1").marker,
      "preserve-me",
    );
  });

  test("deleting a delivered notification then replaying cannot resurrect it", async () => {
    const { repository, engine } = setup();
    const source = event("conversations/c/messages/deleted-note");
    await engine.process(source);
    repository.notifications.delete(`${UID}/achievementUnlocked_messages_1`);

    assert.equal((await engine.process(source)).outcome, "replayed");
    assert.equal(
      repository.notification(UID, "achievementUnlocked_messages_1"),
      undefined,
    );
  });

  test("the first unlock timestamp remains stable when later thresholds unlock", async () => {
    const times = [
      new Date("2026-08-16T12:00:00.000Z"),
      new Date("2026-08-16T12:05:00.000Z"),
    ];
    const { repository, engine } = setup({ clock: () => times.shift() });
    await engine.process(event("conversations/c/messages/timestamp-1"));
    const firstTimestamp = repository
      .progressFor(UID)
      .verifiedUnlockedTitleTimestamps.messages_1;
    await engine.process(event("conversations/c/messages/timestamp-2", { delta: 9 }));
    const timestamps = repository.progressFor(UID).verifiedUnlockedTitleTimestamps;

    assert.deepEqual(timestamps.messages_1, firstTimestamp);
    assert.deepEqual(timestamps.messages_10, new Date("2026-08-16T12:05:00.000Z"));
  });

  test("a deleted beneficiary is not resurrected and receives no ledger row", async () => {
    const repository = new InMemoryAchievementRepository();
    const engine = new AchievementEngine({ repository, clock: () => NOW });
    const source = event("conversations/c/messages/missing");
    const result = await engine.process(source);
    assert.equal(result.outcome, "skipped:missing-user");
    assert.equal(repository.user(UID), undefined);
    assert.equal(repository.event(eventIdFor(source)), undefined);
  });

  test("unknown metrics and non-positive deltas are rejected before storage", async () => {
    const { repository, engine } = setup();
    await assert.rejects(
      engine.process(event("bad/metric", { metric: "totalXp" })),
      AchievementEventValidationError,
    );
    await assert.rejects(
      engine.process(event("bad/delta", { delta: 0 })),
      AchievementEventValidationError,
    );
    await assert.rejects(
      engine.process(event("bad/uid-slash", { beneficiaryId: "bad/user" })),
      AchievementEventValidationError,
    );
    await assert.rejects(
      engine.process(event("bad/uid-control", { beneficiaryId: "bad\nuser" })),
      AchievementEventValidationError,
    );
    assert.equal(repository.events.size, 0);
  });
});
