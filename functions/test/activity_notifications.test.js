const test = require("node:test");
const assert = require("node:assert/strict");

process.env.FIRESTORE_EMULATOR_HOST ||= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ||= "yovoice-fn-test";

const { initializeApp, getApps } = require("firebase-admin/app");
if (getApps().length === 0) initializeApp();
const { Timestamp } = require("firebase-admin/firestore");

const { db } = require("../utils/firestore");
const {
  fanOutRoomLiveFollowers,
  handleDirectMessageCreated,
  handleRoomLiveChanged,
  processRoomLiveFanoutOutbox,
  writeActivityNotification,
} = require("../notifications/activity");
const {
  EVENT_LEDGER_RETENTION_MS,
  eventLedgerReference,
} = require("../notifications/canonical");
const {
  claimPushDelivery,
  handleNotificationCreated,
} = require("../notifications/push");
const { documentGeneration } = require("../notifications/social_source");

const ACTOR = "activity-actor";
const RECIPIENT = "activity-recipient";

test("room-live fanout paginates >1k followers with bounded concurrency", async () => {
  const ids = Array.from(
    { length: 1005 },
    (_, index) => `follower-${index.toString().padStart(4, "0")}`,
  );
  const cursors = [];
  let active = 0;
  let peak = 0;
  const notified = [];
  let cursor = null;
  let complete = false;
  const totals = { followers: 0, pages: 0, written: 0 };
  while (!complete) {
    const outcome = await fanOutRoomLiveFollowers({
      afterId: cursor,
      hostId: ACTOR,
      pageSize: 200,
      concurrency: 7,
      pageLoader: async ({ afterId, pageSize }) => {
        cursors.push(afterId);
        const start = afterId === null ? 0 : ids.indexOf(afterId) + 1;
        return ids.slice(start, start + pageSize);
      },
      notify: async (id) => {
        active += 1;
        peak = Math.max(peak, active);
        await new Promise((resolve) => setImmediate(resolve));
        active -= 1;
        notified.push(id);
        return "written";
      },
    });
    cursor = outcome.afterId;
    complete = outcome.complete;
    totals.followers += outcome.followers;
    totals.pages += outcome.pages;
    totals.written += outcome.written;
  }
  assert.deepEqual(totals, { followers: 1005, pages: 6, written: 1005 });
  assert.equal(new Set(notified).size, 1005);
  assert.ok(peak <= 7);
  assert.deepEqual(cursors, [
    null,
    "follower-0199",
    "follower-0399",
    "follower-0599",
    "follower-0799",
    "follower-0999",
  ]);
});

test("room-live page retry resumes from the durable cursor, never page zero", async () => {
  const ids = Array.from(
    { length: 250 },
    (_, index) => `resume-${index.toString().padStart(4, "0")}`,
  );
  const requestedCursors = [];
  const pageLoader = async ({ afterId, pageSize }) => {
    requestedCursors.push(afterId);
    const start = afterId === null ? 0 : ids.indexOf(afterId) + 1;
    return ids.slice(start, start + pageSize);
  };
  const first = await fanOutRoomLiveFollowers({
    afterId: null,
    hostId: ACTOR,
    pageSize: 100,
    pageLoader,
    notify: async () => "written",
  });
  assert.equal(first.afterId, "resume-0099");
  let crashed = false;
  await assert.rejects(
    fanOutRoomLiveFollowers({
      afterId: first.afterId,
      hostId: ACTOR,
      pageSize: 100,
      pageLoader,
      notify: async (id) => {
        if (!crashed && id === "resume-0150") {
          crashed = true;
          throw new Error("simulated timeout");
        }
        return "written";
      },
    }),
    /simulated timeout/u,
  );
  const retried = await fanOutRoomLiveFollowers({
    afterId: first.afterId,
    hostId: ACTOR,
    pageSize: 100,
    pageLoader,
    notify: async () => "skipped:replay",
  });
  assert.equal(retried.afterId, "resume-0199");
  assert.deepEqual(requestedCursors, [
    null,
    "resume-0099",
    "resume-0099",
  ]);
});

test("room-live outbox persists its page cursor across a failed worker", async () => {
  const reference = db.doc("roomLiveFanoutOutbox/durable-cursor-proof");
  await reference.delete();
  await reference.set({
    schemaVersion: 1,
    roomId: "durable-room",
    hostId: ACTOR,
    session: "durable-session-0001",
    sourcePath: "rooms/durable-room",
    sourceGeneration: "generation-1",
    targetLabel: "Durable room",
    afterId: null,
    status: "pending",
    followers: 0,
    pages: 0,
    written: 0,
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
  });
  const ids = Array.from(
    { length: 450 },
    (_, index) => `durable-${index.toString().padStart(4, "0")}`,
  );
  const requestedCursors = [];
  const pageLoader = async ({ afterId, pageSize }) => {
    requestedCursors.push(afterId);
    const start = afterId === null ? 0 : ids.indexOf(afterId) + 1;
    return ids.slice(start, start + pageSize);
  };

  const first = await processRoomLiveFanoutOutbox(reference, {
    pageLoader,
    notify: async () => "written",
  });
  assert.equal(first.state, "pending");
  assert.equal((await reference.get()).data().afterId, "durable-0199");

  let crashed = false;
  await assert.rejects(
    processRoomLiveFanoutOutbox(reference, {
      pageLoader,
      notify: async (id) => {
        if (!crashed && id === "durable-0250") {
          crashed = true;
          throw new Error("simulated worker timeout");
        }
        return "written";
      },
    }),
    /simulated worker timeout/u,
  );
  const afterCrash = (await reference.get()).data();
  assert.equal(afterCrash.afterId, "durable-0199");
  assert.equal(afterCrash.followers, 200);
  assert.equal(afterCrash.pages, 1);

  const retry = await processRoomLiveFanoutOutbox(reference, {
    pageLoader,
    notify: async () => "skipped:replay",
  });
  assert.equal(retry.state, "pending");
  assert.equal((await reference.get()).data().afterId, "durable-0399");
  assert.deepEqual(requestedCursors, [
    null,
    "durable-0199",
    "durable-0199",
  ]);
  await reference.delete();
});

async function reset() {
  const fanoutOutbox = await db.collection("roomLiveFanoutOutbox").get();
  await Promise.all(fanoutOutbox.docs.map((document) => document.ref.delete()));
  for (const uid of [ACTOR, RECIPIENT]) {
    const user = db.doc(`users/${uid}`);
    for (const collection of [
      "notifications",
      "blocked",
      "fcmTokens",
      "friendRequests",
    ]) {
      const snapshot = await user.collection(collection).get();
      await Promise.all(snapshot.docs.map((document) => document.ref.delete()));
    }
    await user.delete();
  }
  const ledgers = await db.collection("notificationDeliveryEvents")
    .where("recipientId", "==", RECIPIENT)
    .get();
  await Promise.all(ledgers.docs.map((document) => document.ref.delete()));
  for (const path of [
    "conversations/activity-conversation/messages/activity-message",
    "conversations/activity-conversation",
    "rooms/activity-room",
    `users/${ACTOR}/followers/${RECIPIENT}`,
  ]) {
    await db.doc(path).delete();
  }
}

async function seed() {
  await db.doc(`users/${ACTOR}`).set({ displayName: "Ada", photoUrl: "photo" });
  await db.doc(`users/${RECIPIENT}`).set({ displayName: "Bo" });
}

test("server-derived activity notifications", async (t) => {
  t.beforeEach(async () => {
    await reset();
    await seed();
  });
  t.after(reset);

  await t.test("writes a routable live notification with a safe payload", async () => {
    const outcome = await writeActivityNotification({
      recipientId: RECIPIENT,
      actorId: ACTOR,
      type: "liveStarted",
      entryId: "live_room_1_session_1",
      targetId: "room-1",
      targetLabel: "Friday show",
    });
    assert.equal(outcome, "written");
    const record = (await db.doc(
      `users/${RECIPIENT}/notifications/live_room_1_session_1`,
    ).get()).data();
    assert.equal(record.type, "liveStarted");
    assert.equal(record.actorName, "Ada");
    assert.equal(record.targetId, "room-1");
    assert.equal(record.targetLabel, "Friday show");
    assert.equal(record.bellSuppressed, false);
    assert.ok(record.createdAt);
  });

  await t.test("a room-live trigger retry deduplicates one voice session", async () => {
    await db.doc(`users/${ACTOR}/followers/${RECIPIENT}`).set({
      followedAt: Timestamp.now(),
    });
    const room = db.doc("rooms/activity-room");
    await room.set({
      hostId: ACTOR,
      isLive: true,
      visibility: "public",
      name: "Activity room",
      voiceSessionId: "voice-session-retry-0001",
    });
    const after = await room.get();
    const event = {
      params: { roomId: "activity-room" },
      data: {
        before: { data: () => ({ isLive: false }) },
        after,
      },
    };
    await handleRoomLiveChanged(event);
    await handleRoomLiveChanged(event);
    const notificationId =
      "live_activity-room_voice-session-retry-0001";
    assert.equal((await db.doc(
      `users/${RECIPIENT}/notifications/${notificationId}`,
    ).get()).exists, true);
    assert.equal((await db.collection(
      `users/${RECIPIENT}/notifications`,
    ).get()).size, 1);
  });

  await t.test("a retry cannot overwrite, unread or resurrect its record", async () => {
    const input = {
      recipientId: RECIPIENT,
      actorId: ACTOR,
      type: "directMessage",
      entryId: "message-1",
      targetId: "conversation-1",
      bellSuppressed: true,
    };
    assert.equal(await writeActivityNotification(input), "written");
    const reference = db.doc(`users/${RECIPIENT}/notifications/message-1`);
    const first = await reference.get();
    await reference.update({ isRead: true, readAt: first.data().createdAt });
    assert.equal(await writeActivityNotification(input), "skipped:replay");
    const inbox = await db.collection(`users/${RECIPIENT}/notifications`).get();
    assert.equal(inbox.size, 1);
    assert.equal(inbox.docs[0].data().bellSuppressed, true);
    assert.equal(inbox.docs[0].data().isRead, true);
    const ledger = (await eventLedgerReference(
      `activity:directMessage:${RECIPIENT}:message-1`,
    ).get()).data();
    assert.equal(ledger.outcome, "written");
    assert.equal(
      ledger.expiresAt.toMillis() - ledger.createdAt.toMillis(),
      EVENT_LEDGER_RETENTION_MS,
    );

    await reference.delete();
    assert.equal(await writeActivityNotification(input), "skipped:replay");
    assert.equal((await reference.get()).exists, false);
  });

  await t.test("a block in either direction suppresses delivery", async () => {
    await db.doc(`users/${RECIPIENT}/blocked/${ACTOR}`).set({ blocked: true });
    const outcome = await writeActivityNotification({
      recipientId: RECIPIENT,
      actorId: ACTOR,
      type: "directMessage",
      entryId: "blocked-message",
      targetId: "conversation-1",
    });
    assert.equal(outcome, "skipped:blocked");
    assert.equal(
      (await db.collection(`users/${RECIPIENT}/notifications`).get()).size,
      0,
    );
    const eventId = `activity:directMessage:${RECIPIENT}:blocked-message`;
    const ledger = (await eventLedgerReference(eventId).get()).data();
    assert.equal(ledger.outcome, "skipped:blocked");
    assert.equal(
      ledger.expiresAt.toMillis() - ledger.createdAt.toMillis(),
      EVENT_LEDGER_RETENTION_MS,
    );
    await db.doc(`users/${RECIPIENT}/blocked/${ACTOR}`).delete();
    assert.equal(await writeActivityNotification({
      recipientId: RECIPIENT,
      actorId: ACTOR,
      type: "directMessage",
      entryId: "blocked-message",
      targetId: "conversation-1",
    }), "skipped:replay");
  });

  await t.test("one notification CloudEvent can claim FCM delivery only once", async () => {
    const notification = db.doc(
      `users/${RECIPIENT}/notifications/push-claim-message`,
    );
    await notification.set({ type: "directMessage" });
    const snapshot = await notification.get();
    const input = {
      eventId: "cloud-event-direct-message-1",
      userId: RECIPIENT,
      notificationId: notification.id,
      notificationSnapshot: snapshot,
    };

    const claims = await Promise.all([
      claimPushDelivery(input),
      claimPushDelivery(input),
    ]);
    assert.equal(claims.filter((claim) => claim.state === "claimed").length, 1);
    assert.equal(claims.filter((claim) => claim.state === "terminal").length, 1);
    const claimed = (await notification.get()).data();
    assert.match(claimed.pushClaimEventId, /^[a-f0-9]{64}$/u);
    assert.ok(claimed.pushClaimedAt);
    assert.equal(claimed.pushLeaseExpiresAt, undefined);
    assert.equal(claimed.pushDeliveryStatus, "dispatching");
    assert.equal(claimed.pushAttemptCount, 1);
  });

  await t.test("a crash after FCM cannot resend and a confirmed success is sent",
    async () => {
      await db.doc(`users/${RECIPIENT}/fcmTokens/token-a`).set({
        updatedAt: Timestamp.now(),
      });
      const notification = db.doc(
        `users/${RECIPIENT}/notifications/push-crash-message`,
      );
      await notification.set({
        type: "system",
        actorId: ACTOR,
        actorName: "Ada",
        targetLabel: "System event",
      });
      const snapshot = await notification.get();
      const event = {
        id: "cloud-event-before-crash",
        params: { userId: RECIPIENT, notificationId: notification.id },
        data: snapshot,
      };
      const messages = [];
      const messaging = {
        sendEachForMulticast: async (message) => {
          messages.push(message);
          return { responses: message.tokens.map(() => ({ success: true })) };
        },
      };
      await handleNotificationCreated(event, {
        messaging,
        afterExternalSend: async () => {
          throw new Error("simulated lost acknowledgement");
        },
      });
      assert.equal(messages.length, 1);
      const uncertain = (await notification.get()).data();
      assert.equal(uncertain.pushDeliveryStatus, "dispatching");
      assert.match(uncertain.pushClaimEventId, /^[a-f0-9]{64}$/u);
      assert.equal(
        messages[0].android.collapseKey,
        uncertain.pushClaimEventId,
      );
      assert.equal(
        messages[0].apns.headers["apns-collapse-id"],
        uncertain.pushClaimEventId,
      );
      assert.equal(
        messages[0].webpush.notification.tag,
        uncertain.pushClaimEventId,
      );

      await handleNotificationCreated({ ...event, id: "redelivery-event" }, {
        messaging,
      });
      assert.equal(messages.length, 1);

      const sentRef = db.doc(
        `users/${RECIPIENT}/notifications/push-success-message`,
      );
      await sentRef.set({
        type: "system",
        actorId: ACTOR,
        actorName: "Ada",
        targetLabel: "System event",
      });
      const sentSnapshot = await sentRef.get();
      await handleNotificationCreated({
        id: "success-event",
        params: { userId: RECIPIENT, notificationId: sentRef.id },
        data: sentSnapshot,
      }, { messaging });
      const sent = (await sentRef.get()).data();
      assert.equal(sent.pushDeliveryStatus, "sent");
      assert.ok(sent.pushSentAt);
      assert.ok(sent.pushCompletedAt);
      const replay = await claimPushDelivery({
        eventId: "different-envelope",
        userId: RECIPIENT,
        notificationId: sentRef.id,
        notificationSnapshot: sentSnapshot,
      });
      assert.deepEqual(replay, { state: "terminal", reason: "sent" });
    });

  await t.test("deleted DM and ended room are rejected in creation transactions",
    async () => {
      const conversation = db.doc("conversations/activity-conversation");
      const message = conversation.collection("messages")
        .doc("activity-message");
      await conversation.set({
        participantIds: [ACTOR, RECIPIENT],
        mutedBy: [],
      });
      await message.set({ senderId: ACTOR, isDeleted: false });
      const originalMessage = await message.get();
      await message.update({ isDeleted: true });
      await handleDirectMessageCreated({
        params: {
          conversationId: "activity-conversation",
          messageId: "activity-message",
        },
        data: originalMessage,
      });
      const dmLedger = (await eventLedgerReference(
        `direct-message:activity-conversation:activity-message:${RECIPIENT}`,
      ).get()).data();
      assert.equal(dmLedger.outcome, "skipped:invalid-source");
      assert.equal((await db.doc(
        `users/${RECIPIENT}/notifications/message_activity-message`,
      ).get()).exists, false);

      await db.doc(`users/${ACTOR}/followers/${RECIPIENT}`).set({
        followedAt: Timestamp.now(),
      });
      const room = db.doc("rooms/activity-room");
      await room.set({
        hostId: ACTOR,
        isLive: true,
        visibility: "public",
        name: "Activity room",
      });
      const liveGeneration = await room.get();
      const session = liveGeneration.updateTime.toMillis();
      await room.update({ isLive: false });
      await handleRoomLiveChanged({
        params: { roomId: "activity-room" },
        data: {
          before: { data: () => ({ isLive: false }) },
          after: liveGeneration,
        },
      });
      const liveLedger = (await eventLedgerReference(
        `room-live:activity-room:${session}:${RECIPIENT}`,
      ).get()).data();
      assert.equal(liveLedger.outcome, "skipped:invalid-source");
      assert.equal((await db.doc(
        `users/${RECIPIENT}/notifications/live_activity-room_${session}`,
      ).get()).exists, false);
    });

  await t.test("deleted DM and ended room cannot cross the pre-push boundary",
    async () => {
      await db.doc(`users/${RECIPIENT}/fcmTokens/token-a`).set({
        updatedAt: Timestamp.now(),
      });
      const sent = [];
      const messaging = {
        sendEachForMulticast: async (message) => {
          sent.push(message);
          return { responses: message.tokens.map(() => ({ success: true })) };
        },
      };

      const conversation = db.doc("conversations/activity-conversation");
      const message = conversation.collection("messages")
        .doc("activity-message");
      await conversation.set({
        participantIds: [ACTOR, RECIPIENT],
        mutedBy: [],
      });
      await message.set({ senderId: ACTOR, isDeleted: false });
      const messageGeneration = await message.get();
      const dmNotification = db.doc(
        `users/${RECIPIENT}/notifications/message_activity-message`,
      );
      await dmNotification.set({
        type: "directMessage",
        actorId: ACTOR,
        actorName: "Ada",
        targetId: "activity-conversation",
        sourcePath:
          "conversations/activity-conversation/messages/activity-message",
        sourceGeneration: documentGeneration(messageGeneration, "createTime"),
      });
      const dmSnapshot = await dmNotification.get();
      await message.update({ isDeleted: true });
      await handleNotificationCreated({
        id: "push-deleted-dm",
        params: {
          userId: RECIPIENT,
          notificationId: dmNotification.id,
        },
        data: dmSnapshot,
      }, { messaging });
      assert.equal(sent.length, 0);
      assert.equal((await dmNotification.get()).exists, false);

      const room = db.doc("rooms/activity-room");
      await room.set({
        hostId: ACTOR,
        isLive: true,
        visibility: "public",
        name: "Activity room",
      });
      const roomGeneration = await room.get();
      const liveNotification = db.doc(
        `users/${RECIPIENT}/notifications/live_activity-room_pre_push`,
      );
      await liveNotification.set({
        type: "liveStarted",
        actorId: ACTOR,
        actorName: "Ada",
        targetId: "activity-room",
        sourcePath: "rooms/activity-room",
        sourceGeneration: documentGeneration(roomGeneration, "updateTime"),
      });
      const liveSnapshot = await liveNotification.get();
      await room.update({ isLive: false });
      await handleNotificationCreated({
        id: "push-ended-room",
        params: {
          userId: RECIPIENT,
          notificationId: liveNotification.id,
        },
        data: liveSnapshot,
      }, { messaging });
      assert.equal(sent.length, 0);
      assert.equal((await liveNotification.get()).exists, false);
    });

  await t.test(
    "a social source change retries the terminal claim and cleans without FCM",
    async () => {
      await db.doc(`users/${RECIPIENT}/fcmTokens/token-a`).set({
        updatedAt: Timestamp.now(),
      });
      const notificationId = `friendRequest_${ACTOR}_generation`;
      const source = db.doc(
        `users/${RECIPIENT}/friendRequests/${ACTOR}`,
      );
      await source.set({ senderId: ACTOR, notificationId });
      const notification = db.doc(
        `users/${RECIPIENT}/notifications/${notificationId}`,
      );
      await notification.set({
        type: "friendRequest",
        actorId: ACTOR,
        actorName: "Ada",
      });
      const snapshot = await notification.get();
      const sent = [];
      let sourceMutationCount = 0;

      await handleNotificationCreated({
        id: "social-source-race-event",
        params: { userId: RECIPIENT, notificationId },
        data: snapshot,
      }, {
        messaging: {
          sendEachForMulticast: async (message) => {
            sent.push(message);
            return { responses: message.tokens.map(() => ({ success: true })) };
          },
        },
        beforeDispatchClaim: async () => {
          sourceMutationCount++;
          await source.delete();
        },
      });

      // The source was valid during the handler's first check. Removing only
      // that source immediately before the terminal transaction must make its
      // reader-bound validation skip the claim before any network send.
      assert.equal(sourceMutationCount, 1);
      assert.equal(sent.length, 0);
      assert.equal((await source.get()).exists, false);
      assert.equal(
        (await notification.get()).exists,
        false,
        "source-only invalidation removes the stale actionable inbox row",
      );
    },
  );

  await t.test("all activity triggers are part of the deploy export", () => {
    const deployed = require("../index");
    assert.equal(typeof deployed.onDirectMessageCreated, "function");
    assert.equal(typeof deployed.onRoomLiveFanoutOutboxWritten, "function");
    assert.equal(typeof deployed.onRoomLiveChanged, "function");
  });
});
