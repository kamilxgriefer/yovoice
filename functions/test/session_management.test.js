const assert = require("node:assert/strict");
const { test } = require("node:test");

const {
  FIREBASE_ID_TOKEN_MAX_AGE_SECONDS,
  RECENT_AUTH_MAX_AGE_SECONDS,
  createSessionManagementService,
} = require("../auth/session_management");

const UID = "session-owner";
const NOW_MS = 1_825_000_000_000;
const NOW_SECONDS = Math.floor(NOW_MS / 1000);

function request({
  uid = UID,
  authTime = NOW_SECONDS,
  data = {},
  token = {},
} = {}) {
  return {
    auth: uid === null
      ? null
      : { uid, token: { ...token, auth_time: authTime } },
    data,
  };
}

function service(revokeRefreshTokens = async () => {}) {
  return createSessionManagementService({
    auth: { revokeRefreshTokens },
    clock: () => NOW_MS,
  });
}

test("revokes refresh tokens only for the authenticated caller", async () => {
  const revoked = [];
  const result = await service(async (uid) => revoked.push(uid))
    .revokeMyRefreshTokens(request());

  assert.deepEqual(revoked, [UID]);
  assert.deepEqual(result, {
    revoked: true,
    completeWithinSeconds: FIREBASE_ID_TOKEN_MAX_AGE_SECONDS,
  });
});

test("opaque UIDs and restricted account claims cannot block recovery", async () => {
  const opaqueUid = "konto / użytkownik 🔒";
  const revoked = [];
  await service(async (uid) => revoked.push(uid)).revokeMyRefreshTokens(
    request({
      uid: opaqueUid,
      token: { banned: true, disabled: true, role: "user" },
    }),
  );

  // Revocation is a security/recovery action. It intentionally does not read
  // active-profile state and never normalizes a Firebase UID.
  assert.deepEqual(revoked, [opaqueUid]);
});

test("rejects unauthenticated callers before touching Admin Auth", async () => {
  let calls = 0;
  await assert.rejects(
    service(async () => { calls += 1; }).revokeMyRefreshTokens(
      request({ uid: null }),
    ),
    (error) => error.code === "unauthenticated",
  );
  assert.equal(calls, 0);
});

test("rejects every client-controlled input field", async () => {
  for (const data of [{ uid: "victim" }, [], "victim", 1]) {
    await assert.rejects(
      service().revokeMyRefreshTokens(request({ data })),
      (error) => error.code === "invalid-argument",
    );
  }
});

test("requires a recent, well-formed server-verified auth_time", async () => {
  await assert.rejects(
    service().revokeMyRefreshTokens({
      auth: { uid: UID, token: {} },
      data: {},
    }),
    (error) => error.code === "failed-precondition",
  );
  const rejectedAuthTimes = [
    null,
    "123",
    -1,
    NOW_SECONDS + 1,
    NOW_SECONDS - RECENT_AUTH_MAX_AGE_SECONDS - 1,
  ];

  for (const authTime of rejectedAuthTimes) {
    await assert.rejects(
      service().revokeMyRefreshTokens(request({ authTime })),
      (error) => {
        assert.equal(error.code, "failed-precondition");
        assert.equal(error.details.reason, "recent-authentication-required");
        return true;
      },
    );
  }

  await service().revokeMyRefreshTokens(request({
    authTime: NOW_SECONDS - RECENT_AUTH_MAX_AGE_SECONDS,
  }));
});

test("maps Admin failures without leaking provider details", async () => {
  await assert.rejects(
    service(async () => {
      throw new Error("service-account@example.test project-secret");
    }).revokeMyRefreshTokens(request()),
    (error) => {
      assert.equal(error.code, "unavailable");
      assert.doesNotMatch(error.message, /service-account|secret/);
      return true;
    },
  );
});

test("constructor fails closed without an Auth revocation boundary", () => {
  assert.throws(
    () => createSessionManagementService({ auth: {} }),
    /revokeRefreshTokens/,
  );
});
