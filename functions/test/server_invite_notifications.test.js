const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { after, test } = require("node:test");

const enabled = /^(127\.0\.0\.1|localhost):[0-9]+$/u.test(
  process.env.FIRESTORE_EMULATOR_HOST ?? "",
);
process.env.GCLOUD_PROJECT ||= "demo-yovoice-server-invite-notifications";

const { getApps, initializeApp, deleteApp } = require("firebase-admin/app");
if (getApps().length === 0) initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const { Timestamp } = require("firebase-admin/firestore");
const { db } = require("../utils/firestore");
const { createServerInviteService } = require("../servers/invites");
const { createServerMembershipService } = require("../servers/memberships");
const { notificationSourceIsCurrent } = require("../notifications/social_source");
const {
  cleanupExpiredServerInvitePointer,
  handleServerInviteWritten,
  onServerInviteWritten,
  serverInviteNotificationId,
  serverInviteNotificationSourceIsCurrent,
  sweepExpiredServerInvites,
  sweepExpiredServerInvitesSchedule,
} = require("../notifications/invites");

const NOW_MS = 1_900_000_000_000;
const emulatorTest = (name, fn) => test(
  `Server invite notifications: ${name}`,
  {
    skip: enabled
      ? false
      : "Requires explicit localhost Firestore emulator; no cloud fallback.",
    timeout: 60_000,
  },
  fn,
);
const request = (uid, data) => ({
  auth: { uid, token: { email_verified: true } },
  data,
});
const requestId = (prefix) => `${prefix}_${randomUUID()}`;

after(async () => {
  if (getApps().length > 0) await deleteApp(getApps()[0]);
});

async function deleteQuery(query) {
  const snapshot = await query.get();
  await Promise.all(snapshot.docs.map((document) => document.ref.delete()));
}

async function fixture() {
  const token = randomUUID().replaceAll("-", "");
  const ownerId = `sin_owner_${token}`;
  const inviteeId = `sin_invitee_${token}`;
  const serverId = `sin_server_${token}`;
  const now = Timestamp.fromMillis(NOW_MS);
  const deps = { db, Timestamp, clock: () => NOW_MS };
  const service = {
    ...createServerInviteService(deps),
    ...createServerMembershipService(deps),
  };
  await Promise.all([
    db.doc(`users/${ownerId}`).set({
      displayName: "Canonical Inviter",
      status: "active",
      banned: false,
      disabled: false,
    }),
    db.doc(`users/${inviteeId}`).set({
      displayName: "Canonical Invitee",
      status: "active",
      banned: false,
      disabled: false,
    }),
    db.doc(`clubs/${serverId}`).set({
      serverSchemaVersion: 1,
      serverType: "friends",
      templateVersion: 1,
      type: "community",
      serverActivationState: "active",
      status: "active",
      deletionInProgress: false,
      revision: 1,
      ownerId,
      ownerName: "Canonical Inviter",
      name: "Weekend Crew",
      privacy: "inviteOnly",
      memberCount: 1,
      createdAt: now,
      updatedAt: now,
    }),
    db.doc(`clubs/${serverId}/members/${ownerId}`).set({
      userId: ownerId,
      displayName: "Canonical Inviter",
      photoUrl: null,
      role: "owner",
      isOnline: false,
      joinedAt: now,
      invitedBy: null,
      authorizationRevision: 1,
    }),
    db.doc(`friendshipGuards/${ownerId}/friends/${inviteeId}`).set({
      ownerId,
      friendId: inviteeId,
      schemaVersion: 1,
      establishedAt: now,
    }),
    db.doc(`friendshipGuards/${inviteeId}/friends/${ownerId}`).set({
      ownerId: inviteeId,
      friendId: ownerId,
      schemaVersion: 1,
      establishedAt: now,
    }),
  ]);
  const inviteReference = db.doc(`clubs/${serverId}/invites/${inviteeId}`);
  const pointerReference = db.doc(
    `users/${inviteeId}/serverInviteRefs/${serverId}`,
  );
  const notificationReference = (generation) => db.doc(
    `users/${inviteeId}/notifications/${serverInviteNotificationId(
      serverId,
      inviteeId,
      generation,
    )}`,
  );

  async function createInvite() {
    const before = await inviteReference.get();
    const result = await service.createServerInviteV1(request(ownerId, {
      serverId,
      inviteeId,
      requestId: requestId("create"),
    }));
    const afterSnapshot = await inviteReference.get();
    return { before, after: afterSnapshot, result };
  }

  async function cleanup() {
    await Promise.all([
      db.recursiveDelete(db.doc(`users/${ownerId}`)),
      db.recursiveDelete(db.doc(`users/${inviteeId}`)),
      db.recursiveDelete(db.doc(`clubs/${serverId}`)),
      db.recursiveDelete(db.doc(`friendshipGuards/${ownerId}`)),
      db.recursiveDelete(db.doc(`friendshipGuards/${inviteeId}`)),
      db.doc(`restrictions/${ownerId}`).delete(),
      db.doc(`restrictions/${inviteeId}`).delete(),
    ]);
    await Promise.all([
      deleteQuery(db.collection("privateRateLimits").where("ownerId", "in", [
        ownerId,
        inviteeId,
      ])),
      deleteQuery(db.collection("integrityOperationLedgers").where("uid", "in", [
        ownerId,
        inviteeId,
      ])),
      deleteQuery(db.collection("notificationDeliveryEvents")
        .where("sourcePath", "==", inviteReference.path)),
      deleteQuery(db.collection("serverControlOutbox").where("serverId", "==", serverId)),
    ]);
  }

  return {
    ownerId,
    inviteeId,
    serverId,
    service,
    inviteReference,
    pointerReference,
    notificationReference,
    createInvite,
    cleanup,
  };
}

function changeEvent(value, id) {
  return {
    id,
    params: { clubId: value.serverId, inviteeId: value.inviteeId },
    data: { before: value.before, after: value.after },
  };
}

test("V1 trigger and expiry schedule are pinned to the reviewed deployment bindings", () => {
  const endpoint = onServerInviteWritten.__endpoint;
  assert.equal(endpoint.region?.[0] ?? endpoint.region, "europe-west1");
  assert.equal(
    endpoint.eventTrigger?.eventFilterPathPatterns?.document,
    "clubs/{clubId}/invites/{inviteeId}",
  );
  assert.equal(
    endpoint.eventTrigger?.eventType,
    "google.cloud.firestore.document.v1.written",
  );
  assert.equal(endpoint.eventTrigger?.retry, true);
  assert.equal(endpoint.maxInstances, 50);

  const schedule = sweepExpiredServerInvitesSchedule.__endpoint;
  assert.equal(schedule.region?.[0] ?? schedule.region, "europe-west1");
  assert.equal(schedule.scheduleTrigger?.schedule, "every 15 minutes");
  assert.equal(schedule.scheduleTrigger?.timeZone, "UTC");
  assert.equal(schedule.maxInstances, 1);
  assert.equal(schedule.timeoutSeconds, 300);
});

emulatorTest("a canonical generation writes once and remains source-valid", async () => {
  const value = await fixture();
  try {
    const created = await value.createInvite();
    assert.equal(created.result.generation, 1);
    const event = changeEvent({ ...value, ...created }, requestId("event"));
    assert.equal(
      await handleServerInviteWritten(event, { nowMs: NOW_MS }),
      "written",
    );
    assert.equal(
      await handleServerInviteWritten(event, { nowMs: NOW_MS }),
      "skipped:replay",
    );

    const reference = value.notificationReference(1);
    const snapshot = await reference.get();
    const notification = snapshot.data();
    assert.deepEqual(
      {
        type: notification.type,
        actorId: notification.actorId,
        actorName: notification.actorName,
        targetId: notification.targetId,
        targetLabel: notification.targetLabel,
        dedupeKey: notification.dedupeKey,
        bellSuppressed: notification.bellSuppressed,
        sourcePath: notification.sourcePath,
        sourceGeneration: notification.sourceGeneration,
      },
      {
        type: "clubInvite",
        actorId: value.ownerId,
        actorName: "Canonical Inviter",
        targetId: value.serverId,
        targetLabel: "Weekend Crew",
        dedupeKey: reference.id,
        bellSuppressed: false,
        sourcePath: value.inviteReference.path,
        sourceGeneration: "1",
      },
    );
    assert.equal(await serverInviteNotificationSourceIsCurrent({
      recipientId: value.inviteeId,
      notificationId: reference.id,
      notification,
      firestore: db,
      nowMs: NOW_MS,
    }), true);
    assert.equal(await notificationSourceIsCurrent({
      recipientId: value.inviteeId,
      notificationId: reference.id,
      notification,
      firestore: db,
    }), true, "the push claim must use the same V1 source gate");

    await reference.update({ isRead: true, readAt: Timestamp.fromMillis(NOW_MS + 1) });
    assert.equal(
      await handleServerInviteWritten(event, { nowMs: NOW_MS }),
      "skipped:replay",
    );
    assert.equal((await reference.get()).data().isRead, true);
  } finally {
    await value.cleanup();
  }
});

emulatorTest("the push source gate re-proves active parties, restrictions, blocks and friendship after issuance", async () => {
  const value = await fixture();
  try {
    const created = await value.createInvite();
    const event = changeEvent({ ...value, ...created }, requestId("event"));
    assert.equal(await handleServerInviteWritten(event, { nowMs: NOW_MS }), "written");
    const reference = value.notificationReference(1);
    const notification = (await reference.get()).data();
    const sourceIsCurrent = () => serverInviteNotificationSourceIsCurrent({
      recipientId: value.inviteeId,
      notificationId: reference.id,
      notification,
      firestore: db,
      nowMs: NOW_MS,
    });
    const pushSourceIsCurrent = () => notificationSourceIsCurrent({
      recipientId: value.inviteeId,
      notificationId: reference.id,
      notification,
      firestore: db,
    });
    const friendship = async () => {
      const establishedAt = Timestamp.fromMillis(NOW_MS);
      await Promise.all([
        db.doc(`friendshipGuards/${value.ownerId}/friends/${value.inviteeId}`).set({
          ownerId: value.ownerId,
          friendId: value.inviteeId,
          schemaVersion: 1,
          establishedAt,
        }),
        db.doc(`friendshipGuards/${value.inviteeId}/friends/${value.ownerId}`).set({
          ownerId: value.inviteeId,
          friendId: value.ownerId,
          schemaVersion: 1,
          establishedAt,
        }),
      ]);
    };
    const scenarios = [
      ["unfriend", async () => Promise.all([
        db.doc(`friendshipGuards/${value.ownerId}/friends/${value.inviteeId}`).delete(),
        db.doc(`friendshipGuards/${value.inviteeId}/friends/${value.ownerId}`).delete(),
      ]), friendship],
      ["inviter block", async () =>
        db.doc(`users/${value.ownerId}/blocked/${value.inviteeId}`).set({ blockedAt: Timestamp.fromMillis(NOW_MS) }),
      async () => db.doc(`users/${value.ownerId}/blocked/${value.inviteeId}`).delete()],
      ["invitee block", async () =>
        db.doc(`users/${value.inviteeId}/blocked/${value.ownerId}`).set({ blockedAt: Timestamp.fromMillis(NOW_MS) }),
      async () => db.doc(`users/${value.inviteeId}/blocked/${value.ownerId}`).delete()],
      ["inviter restriction", async () =>
        db.doc(`restrictions/${value.ownerId}`).set({ type: "communicationMute", expiresAt: null }),
      async () => db.doc(`restrictions/${value.ownerId}`).delete()],
      ["invitee restriction", async () =>
        db.doc(`restrictions/${value.inviteeId}`).set({ type: "communicationMute", expiresAt: null }),
      async () => db.doc(`restrictions/${value.inviteeId}`).delete()],
      ["inactive inviter", async () => db.doc(`users/${value.ownerId}`).update({ banned: true }),
        async () => db.doc(`users/${value.ownerId}`).update({ banned: false })],
      ["inactive invitee", async () => db.doc(`users/${value.inviteeId}`).update({ disabled: true }),
        async () => db.doc(`users/${value.inviteeId}`).update({ disabled: false })],
    ];

    for (const [label, invalidate, restore] of scenarios) {
      await invalidate();
      assert.equal(await sourceIsCurrent(), false, label);
      assert.equal(await pushSourceIsCurrent(), false, `${label}: shared push gate`);
      await restore();
      assert.equal(await sourceIsCurrent(), true, `${label}: restored`);
    }
    assert.equal((await reference.get()).exists, true,
      "a source probe does not mutate the inbox row");
  } finally {
    await value.cleanup();
  }
});

emulatorTest("stale authority and malformed source fail closed", async () => {
  const value = await fixture();
  try {
    const created = await value.createInvite();
    await db.doc(`clubs/${value.serverId}/members/${value.ownerId}`)
      .update({ authorizationRevision: 2 });
    const event = changeEvent({ ...value, ...created }, requestId("stale"));
    assert.equal(
      await handleServerInviteWritten(event, { nowMs: NOW_MS }),
      "skipped:invalid-source",
    );
    assert.equal((await value.notificationReference(1).get()).exists, false);
    await db.doc(`clubs/${value.serverId}/members/${value.ownerId}`)
      .update({ authorizationRevision: 1 });
    assert.equal(
      await handleServerInviteWritten(event, { nowMs: NOW_MS }),
      "skipped:replay",
      "a rejected event must not gain life after its source authority changes",
    );

    const canonical = await value.inviteReference.get();
    await value.inviteReference.update({ forgedPreview: true });
    const malformed = await value.inviteReference.get();
    assert.equal(await handleServerInviteWritten(changeEvent({
      ...value,
      before: canonical,
      after: malformed,
    }, requestId("malformed")), { nowMs: NOW_MS }), "skipped:not-pending");
    assert.equal((await value.notificationReference(1).get()).exists, false);
  } finally {
    await value.cleanup();
  }
});

emulatorTest("revoke, re-issue and accept retire only their own generation", async () => {
  const value = await fixture();
  try {
    const first = await value.createInvite();
    await handleServerInviteWritten(
      changeEvent({ ...value, ...first }, requestId("first")),
      { nowMs: NOW_MS },
    );
    const firstNotification = value.notificationReference(1);
    assert.equal((await firstNotification.get()).exists, true);

    const beforeRevoke = await value.inviteReference.get();
    await value.service.revokeServerInviteV1(request(value.ownerId, {
      serverId: value.serverId,
      inviteeId: value.inviteeId,
      requestId: requestId("revoke"),
    }));
    const afterRevoke = await value.inviteReference.get();
    assert.equal(await handleServerInviteWritten(changeEvent({
      ...value,
      before: beforeRevoke,
      after: afterRevoke,
    }, requestId("revoked")), { nowMs: NOW_MS }), "deleted");
    assert.equal((await firstNotification.get()).exists, false);
    assert.equal((await value.pointerReference.get()).exists, false);

    const second = await value.createInvite();
    assert.equal(second.result.generation, 2);
    assert.equal(await handleServerInviteWritten(
      changeEvent({ ...value, ...second }, requestId("second")),
      { nowMs: NOW_MS },
    ), "written");
    const secondNotification = value.notificationReference(2);
    assert.notEqual(secondNotification.id, firstNotification.id);
    assert.equal((await secondNotification.get()).exists, true);

    const beforeAccept = await value.inviteReference.get();
    await value.service.respondToServerInviteV1(request(value.inviteeId, {
      serverId: value.serverId,
      response: "accept",
      requestId: requestId("accept"),
    }));
    const afterAccept = await value.inviteReference.get();
    assert.equal(await handleServerInviteWritten(changeEvent({
      ...value,
      before: beforeAccept,
      after: afterAccept,
    }, requestId("accepted")), { nowMs: NOW_MS }), "deleted");
    assert.equal((await secondNotification.get()).exists, false);
    assert.equal((await value.pointerReference.get()).exists, false);
    assert.equal(afterAccept.data().status, "accepted");
  } finally {
    await value.cleanup();
  }
});

emulatorTest("expiry sweep removes pointer and matching bell, preserving history", async () => {
  const value = await fixture();
  try {
    const created = await value.createInvite();
    await handleServerInviteWritten(
      changeEvent({ ...value, ...created }, requestId("expiring")),
      { nowMs: NOW_MS },
    );
    const expiresAt = created.after.data().expiresAt;
    const notification = value.notificationReference(1);
    assert.equal((await notification.get()).exists, true);

    const outcome = await sweepExpiredServerInvites({
      database: db,
      now: Timestamp.fromMillis(expiresAt.toMillis() + 1),
    });
    assert.ok(outcome.scanned >= 1);
    assert.ok(outcome.pointersDeleted >= 1);
    assert.ok(outcome.notificationsDeleted >= 1);
    assert.equal(outcome.failed, 0);
    assert.equal((await value.pointerReference.get()).exists, false);
    assert.equal((await notification.get()).exists, false);
    const history = await value.inviteReference.get();
    assert.equal(history.exists, true);
    assert.equal(history.data().status, "pending");
    assert.equal(history.data().generation, 1);
    assert.equal(await serverInviteNotificationSourceIsCurrent({
      recipientId: value.inviteeId,
      notificationId: notification.id,
      notification: {
        type: "clubInvite",
        actorId: value.ownerId,
        targetId: value.serverId,
        targetLabel: "Weekend Crew",
        sourcePath: value.inviteReference.path,
        sourceGeneration: "1",
        dedupeKey: notification.id,
      },
      firestore: db,
      nowMs: expiresAt.toMillis() + 1,
    }), false);
  } finally {
    await value.cleanup();
  }
});

emulatorTest("cleanup never deletes a mismatched bell or a current pointer", async () => {
  const value = await fixture();
  try {
    const created = await value.createInvite();
    const expiresAt = created.after.data().expiresAt;
    const notification = value.notificationReference(1);
    await notification.set({
      type: "clubInvite",
      targetId: "different_server",
      sourceGeneration: "1",
      sourcePath: value.inviteReference.path,
    });
    assert.deepEqual(await cleanupExpiredServerInvitePointer(value.pointerReference, {
      database: db,
      now: Timestamp.fromMillis(expiresAt.toMillis() - 1),
    }), { pointer: "current", notification: "untouched" });
    assert.equal((await value.pointerReference.get()).exists, true);

    const expired = await cleanupExpiredServerInvitePointer(value.pointerReference, {
      database: db,
      now: Timestamp.fromMillis(expiresAt.toMillis()),
    });
    assert.deepEqual(expired, { pointer: "deleted", notification: "mismatch" });
    assert.equal((await value.pointerReference.get()).exists, false);
    assert.equal((await notification.get()).exists, true);
  } finally {
    await value.cleanup();
  }
});
