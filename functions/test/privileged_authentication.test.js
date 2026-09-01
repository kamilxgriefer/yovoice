const assert = require("node:assert/strict");
const { afterEach, describe, test } = require("node:test");

const {
  PRIVILEGED_AUTH_MAX_AGE_SECONDS,
  PRIVILEGED_MFA_MODES,
  requirePrivilegedAuthentication,
  requireRecentPrivilegedAuthentication,
  resolvePrivilegedMfaMode,
} = require("../utils/auth");

const NOW_SECONDS = 1_825_000_000;
const ORIGINAL_PRIVILEGED_MFA_MODE =
  process.env.YOVOICE_PRIVILEGED_MFA_MODE;

afterEach(() => {
  if (ORIGINAL_PRIVILEGED_MFA_MODE === undefined) {
    delete process.env.YOVOICE_PRIVILEGED_MFA_MODE;
  } else {
    process.env.YOVOICE_PRIVILEGED_MFA_MODE =
      ORIGINAL_PRIVILEGED_MFA_MODE;
  }
});

function auth({ authTime = NOW_SECONDS, firebase, iat } = {}) {
  return {
    uid: "privileged-actor",
    token: {
      auth_time: authTime,
      ...(firebase === undefined ? {} : { firebase }),
      ...(iat === undefined ? {} : { iat }),
    },
  };
}

function expectReason(action, reason) {
  assert.throws(action, (error) => {
    assert.equal(error.code, "failed-precondition");
    assert.equal(error.details?.reason, reason);
    return true;
  });
}

describe("recent privileged authentication", () => {
  test("accepts the exact five-minute boundary", () => {
    assert.equal(
      requireRecentPrivilegedAuthentication(
        auth({
          authTime: NOW_SECONDS - PRIVILEGED_AUTH_MAX_AGE_SECONDS,
        }),
        { nowSeconds: NOW_SECONDS },
      ),
      NOW_SECONDS - PRIVILEGED_AUTH_MAX_AGE_SECONDS,
    );
  });

  test("fails closed for missing, malformed, future and stale auth_time", () => {
    const rejected = [
      undefined,
      null,
      "1825000000",
      -1,
      NOW_SECONDS + 1,
      NOW_SECONDS - PRIVILEGED_AUTH_MAX_AGE_SECONDS - 1,
    ];

    for (const authTime of rejected) {
      const candidate = authTime === undefined
        ? { uid: "privileged-actor", token: {} }
        : auth({ authTime });
      expectReason(
        () => requireRecentPrivilegedAuthentication(candidate, {
          nowSeconds: NOW_SECONDS,
        }),
        "recent-authentication-required",
      );
    }
  });

  test("never substitutes a freshly refreshed iat for stale auth_time", () => {
    expectReason(
      () => requireRecentPrivilegedAuthentication(
        auth({
          authTime: NOW_SECONDS - PRIVILEGED_AUTH_MAX_AGE_SECONDS - 1,
          iat: NOW_SECONDS,
        }),
        { nowSeconds: NOW_SECONDS },
      ),
      "recent-authentication-required",
    );
  });
});

describe("privileged MFA rollout policy", () => {
  test("optional rollout still reports whether the token used MFA", () => {
    process.env.YOVOICE_PRIVILEGED_MFA_MODE =
      PRIVILEGED_MFA_MODES.OPTIONAL;
    const authTime = Math.floor(Date.now() / 1000);
    assert.deepEqual(requirePrivilegedAuthentication(auth({ authTime })), {
      authTime,
      mfaMode: "optional",
      secondFactorVerified: false,
    });

    assert.equal(
      requirePrivilegedAuthentication(
        auth({
          authTime,
          firebase: { sign_in_second_factor: "totp" },
        }),
      ).secondFactorVerified,
      true,
    );
  });

  test("required mode rejects absence and malformed second-factor claims", () => {
    process.env.YOVOICE_PRIVILEGED_MFA_MODE =
      PRIVILEGED_MFA_MODES.REQUIRED;
    const authTime = Math.floor(Date.now() / 1000);
    for (const firebase of [
      undefined,
      {},
      { sign_in_second_factor: "" },
      { sign_in_second_factor: "   " },
      { sign_in_second_factor: 123456 },
    ]) {
      expectReason(
        () => requirePrivilegedAuthentication(auth({ authTime, firebase })),
        "multi-factor-authentication-required",
      );
    }
  });

  test("required mode accepts a server-provided second-factor claim", () => {
    process.env.YOVOICE_PRIVILEGED_MFA_MODE =
      PRIVILEGED_MFA_MODES.REQUIRED;
    const result = requirePrivilegedAuthentication(
      auth({
        authTime: Math.floor(Date.now() / 1000),
        firebase: {
          sign_in_provider: "password",
          sign_in_second_factor: "totp",
          second_factor_identifier: "factor-id",
        },
      }),
    );

    assert.equal(result.mfaMode, "required");
    assert.equal(result.secondFactorVerified, true);
  });

  test("an invalid deployment mode fails closed instead of disabling MFA", () => {
    expectReason(
      () => resolvePrivilegedMfaMode("requird"),
      "privileged-authentication-policy-invalid",
    );
  });
});
