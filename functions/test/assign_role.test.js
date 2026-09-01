// Coverage for assignUserRole as an OWNERSHIP capability.
//
// Runs against BOTH emulators: Firestore for the authoritative records
// and audit log, Auth for the real claim writes the callable performs.
// The auth-emulator env var is set before any require so the module-level
// getAuth() binds to the emulator, never to production.
//
//   firebase emulators:start --only firestore,auth --project rules-test-yovoice
//   npm test

const assert = require("node:assert/strict");
const { test, beforeEach, afterEach, describe } = require("node:test");

process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST =
  process.env.FIREBASE_AUTH_EMULATOR_HOST ?? "127.0.0.1:9099";
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT ?? "yovoice-fn-test";

const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");

if (getApps().length === 0) initializeApp();

const {
  assignUserRole,
  setRoleAuthorityWriterForTests,
} = require("../admin/users");
const { setProtectedOwnerUidForTests } = require("../utils/roles");
const { hasStaffPreviewAccess } = require("../utils/premium_access");
const {
  persistRoleAuthoritySafely,
} = require("../utils/role_authority");

const db = getFirestore();
const adminAuth = getAuth();
const run = assignUserRole.run ?? assignUserRole;

const P = "asr-";
const OWNER = `${P}owner`;
const FAKE_SUPER = `${P}fake-super`;
const MOD = `${P}mod`;
const PLAIN = `${P}plain`;
const TARGET = `${P}target`;
const ORIGINAL_PRIVILEGED_MFA_MODE =
  process.env.YOVOICE_PRIVILEGED_MFA_MODE;

function request(uid, role, data, token = {}) {
  return {
    auth: {
      uid,
      token: {
        role,
        auth_time: Math.floor(Date.now() / 1000),
        ...token,
      },
    },
    data,
  };
}

async function wipeOwn() {
  await Promise.all(
    [OWNER, FAKE_SUPER, MOD, PLAIN, TARGET].map((uid) =>
      db.collection("users").doc(uid).delete(),
    ),
  );
  for (const action of ["assign_user_role", "security_alert_non_owner_super_admin"]) {
    const entries = await db
      .collection("adminAuditLogs")
      .where("action", "==", action)
      .get();
    await Promise.all(
      entries.docs
        .filter((doc) =>
          String(doc.data().targetId ?? doc.data().userId ?? "").startsWith(P),
        )
        .map((doc) => doc.ref.delete()),
    );
  }
  // Reset the target's Auth record for a clean previousRole.
  for (const uid of [TARGET, OWNER]) {
    try {
      await adminAuth.deleteUser(uid);
    } catch {
      /* not present */
    }
    await adminAuth.createUser({ uid, email: `${uid}@test.invalid` });
  }
}

beforeEach(async () => {
  setProtectedOwnerUidForTests(OWNER);
  await wipeOwn();
  await db.collection("users").doc(OWNER).set({ role: "superAdmin" });
  await db.collection("users").doc(FAKE_SUPER).set({ role: "superAdmin" });
  await db.collection("users").doc(MOD).set({ role: "moderator" });
  await db.collection("users").doc(PLAIN).set({ role: "user" });
  // The target has VIP that must SURVIVE every role change.
  await db
    .collection("users")
    .doc(TARGET)
    .set({ role: "user", premiumIdentity: true, displayName: "Target" });
});

afterEach(() => {
  setProtectedOwnerUidForTests(null);
  setRoleAuthorityWriterForTests(null);
  if (ORIGINAL_PRIVILEGED_MFA_MODE === undefined) {
    delete process.env.YOVOICE_PRIVILEGED_MFA_MODE;
  } else {
    process.env.YOVOICE_PRIVILEGED_MFA_MODE =
      ORIGINAL_PRIVILEGED_MFA_MODE;
  }
});

const assignArgs = (role, extra = {}) => ({
  uid: TARGET,
  role,
  reason: "verified staff application",
  ...extra,
});

describe("allowed: the confirmed owner", () => {
  test("a stale owner sign-in cannot change any role", async () => {
    await assert.rejects(
      run(request(OWNER, "superAdmin", assignArgs("moderator"), {
        auth_time:
          Math.floor(Date.now() / 1000) - (5 * 60) - 1,
      })),
      (error) => {
        assert.equal(error.code, "failed-precondition");
        assert.equal(
          error.details?.reason,
          "recent-authentication-required",
        );
        return true;
      },
    );

    assert.equal(
      (await adminAuth.getUser(TARGET)).customClaims?.role,
      undefined,
    );
    assert.equal(
      (await db.collection("users").doc(TARGET).get()).data().role,
      "user",
    );
  });

  test("required MFA rejects an owner token without a second factor", async () => {
    process.env.YOVOICE_PRIVILEGED_MFA_MODE = "required";

    await assert.rejects(
      run(request(OWNER, "superAdmin", assignArgs("moderator"))),
      (error) => {
        assert.equal(error.code, "failed-precondition");
        assert.equal(
          error.details?.reason,
          "multi-factor-authentication-required",
        );
        return true;
      },
    );

    assert.equal(
      (await adminAuth.getUser(TARGET)).customClaims?.role,
      undefined,
    );
    assert.equal(
      (await db.collection("users").doc(TARGET).get()).data().role,
      "user",
    );
  });

  for (const role of [
    "guideMaster",
    "support",
    "auditor",
    "moderator",
    "superModerator",
  ]) {
    test(`assigns ${role}, audited with reason, and VIP survives`, async () => {
      const result = await run(
        request(OWNER, "superAdmin", assignArgs(role)),
      );
      assert.equal(result.success, true);
      assert.equal(result.role, role);

      // The claim was really written.
      const record = await adminAuth.getUser(TARGET);
      assert.equal(record.customClaims.role, role);

      // The authoritative mirror followed, and VIP was untouched.
      const profile = (await db.collection("users").doc(TARGET).get()).data();
      assert.equal(profile.role, role);
      assert.equal(profile.roleTransitionInProgress, false);
      assert.equal(profile.premiumIdentity, true, "VIP must never be removed");

      // Audit: actor, target, previous, new, reason.
      const audit = await db
        .collection("adminAuditLogs")
        .where("action", "==", "assign_user_role")
        .get();
      const mine = audit.docs
        .map((doc) => doc.data())
        .filter((entry) => (entry.targetId ?? entry.userId) === TARGET);
      assert.equal(mine.length, 1);
      assert.equal(mine[0].details.previousRole, "user");
      assert.equal(mine[0].details.newRole, role);
      assert.equal(mine[0].details.reason, "verified staff application");
    });
  }

  test("revokes a staff role by assigning user back", async () => {
    await run(request(OWNER, "superAdmin", assignArgs("moderator")));
    const result = await run(
      request(
        OWNER,
        "superAdmin",
        assignArgs("user", { expectedRole: "moderator" }),
      ),
    );
    assert.equal(result.success, true);
    const record = await adminAuth.getUser(TARGET);
    assert.equal(record.customClaims.role, "user");
  });

  test("an Auth-write failure leaves demotion fail-closed and the exact "
      + "expectedRole retry converges", async () => {
    await run(request(OWNER, "superAdmin", assignArgs("moderator")));

    setRoleAuthorityWriterForTests((operation) =>
      persistRoleAuthoritySafely({
        ...operation,
        writeClaims: async () => {
          throw new Error("injected setCustomUserClaims failure");
        },
      }));

    await assert.rejects(
      run(request(
        OWNER,
        "superAdmin",
        assignArgs("user", { expectedRole: "moderator" }),
      )),
      /injected setCustomUserClaims failure/,
    );

    const partialProfile = (
      await db.collection("users").doc(TARGET).get()
    ).data();
    const partialAuth = await adminAuth.getUser(TARGET);
    assert.equal(partialProfile.role, "user");
    assert.equal(partialProfile.roleTransitionInProgress, false);
    assert.equal(partialAuth.customClaims.role, "moderator");
    assert.equal(
      hasStaffPreviewAccess({
        user: partialProfile,
        tokenRole: partialAuth.customClaims.role,
        requireTokenRole: true,
      }),
      false,
      "the stale moderator claim must not survive a partial demotion",
    );

    // The Auth claim is still the role the operator originally saw, so the
    // same expectedRole request is a safe, idempotent resume.
    setRoleAuthorityWriterForTests(null);
    const retry = await run(request(
      OWNER,
      "superAdmin",
      assignArgs("user", { expectedRole: "moderator" }),
    ));
    assert.equal(retry.success, true);
    assert.equal(
      (await db.collection("users").doc(TARGET).get()).data().role,
      "user",
    );
    assert.equal(
      (await adminAuth.getUser(TARGET)).customClaims.role,
      "user",
    );
  });

  test("a failed re-promotion cannot reactivate a historical moderator token",
    async () => {
      const historicalTokenRole = "moderator";
      setRoleAuthorityWriterForTests((operation) =>
        persistRoleAuthoritySafely({
          ...operation,
          writeClaims: async () => {
            throw new Error("injected promotion Auth failure");
          },
        }));

      await assert.rejects(
        run(request(
          OWNER,
          "superAdmin",
          assignArgs("moderator", { expectedRole: "user" }),
        )),
        /injected promotion Auth failure/,
      );

      const profile = (
        await db.collection("users").doc(TARGET).get()
      ).data();
      const currentAuth = await adminAuth.getUser(TARGET);
      assert.equal(profile.role, "user");
      assert.notEqual(profile.roleTransitionInProgress, true);
      assert.equal(currentAuth.customClaims?.role, undefined);
      assert.equal(
        hasStaffPreviewAccess({
          user: profile,
          tokenRole: historicalTokenRole,
          requireTokenRole: true,
        }),
        false,
      );

      setRoleAuthorityWriterForTests(null);
      const retry = await run(request(
        OWNER,
        "superAdmin",
        assignArgs("moderator", { expectedRole: "user" }),
      ));
      assert.equal(retry.success, true);
      assert.equal(
        (await db.collection("users").doc(TARGET).get()).data().role,
        "moderator",
      );
      assert.equal(
        (await adminAuth.getUser(TARGET)).customClaims.role,
        "moderator",
      );
    });

  test("a lateral role failure uses a neutral mirror and retry converges",
    async () => {
      await run(request(OWNER, "superAdmin", assignArgs("support")));
      let mirrorWrites = 0;
      setRoleAuthorityWriterForTests((operation) =>
        persistRoleAuthoritySafely({
          ...operation,
          writeMirror: async (write) => {
            mirrorWrites += 1;
            if (mirrorWrites === 2) {
              throw new Error("injected final role mirror failure");
            }
            return operation.writeMirror(write);
          },
        }));

      await assert.rejects(
        run(request(
          OWNER,
          "superAdmin",
          assignArgs("auditor", { expectedRole: "support" }),
        )),
        /injected final role mirror failure/,
      );

      const partialProfile = (
        await db.collection("users").doc(TARGET).get()
      ).data();
      const partialAuth = await adminAuth.getUser(TARGET);
      assert.equal(partialProfile.role, "user");
      assert.equal(partialProfile.roleTransitionInProgress, true);
      assert.equal(partialAuth.customClaims.role, "auditor");
      assert.notEqual(partialProfile.role, "support");
      assert.notEqual(partialProfile.role, "auditor");

      // Auth already reached the requested role, so the same stale
      // expectedRole is accepted only as an idempotent convergence retry.
      setRoleAuthorityWriterForTests(null);
      const retry = await run(request(
        OWNER,
        "superAdmin",
        assignArgs("auditor", { expectedRole: "support" }),
      ));
      assert.equal(retry.success, true);
      assert.equal(
        (await db.collection("users").doc(TARGET).get()).data().role,
        "auditor",
      );
      assert.equal(
        (await db.collection("users").doc(TARGET).get()).data()
          .roleTransitionInProgress,
        false,
      );
      assert.equal(
        (await adminAuth.getUser(TARGET)).customClaims.role,
        "auditor",
      );
    });

  test("the stale-result guard refuses an outdated expectedRole", async () => {
    await run(request(OWNER, "superAdmin", assignArgs("moderator")));
    // A second admin session still believes the target is `user`.
    await assert.rejects(
      () =>
        run(
          request(
            OWNER,
            "superAdmin",
            assignArgs("support", { expectedRole: "user" }),
          ),
        ),
      /changed since you looked/,
    );
    // With the CURRENT role declared, the same change is accepted.
    const result = await run(
      request(
        OWNER,
        "superAdmin",
        assignArgs("support", { expectedRole: "moderator" }),
      ),
    );
    assert.equal(result.success, true);
  });
});

describe("denied", () => {
  test("superAdmin can never be assigned, even by the owner", async () => {
    await assert.rejects(
      () => run(request(OWNER, "superAdmin", assignArgs("superAdmin"))),
      /cannot be assigned from the app/,
    );
  });

  test("a missing or trivial reason is refused", async () => {
    await assert.rejects(
      () =>
        run(
          request(OWNER, "superAdmin", {
            uid: TARGET,
            role: "moderator",
            reason: "",
          }),
        ),
      /reason .* required/i,
    );
  });

  test("the retired legacy values are not assignable", async () => {
    for (const role of ["vip", "admin"]) {
      await assert.rejects(
        () => run(request(OWNER, "superAdmin", assignArgs(role))),
        /Role must be/,
      );
    }
  });

  test("the protected owner cannot be modified", async () => {
    await assert.rejects(
      () =>
        run(
          request(OWNER, "superAdmin", {
            uid: OWNER,
            role: "user",
            reason: "should never work",
          }),
        ),
      /owner's role cannot be changed/,
    );
  });

  test("a FORGED superAdmin is refused and recorded; moderators and "
      + "ordinary users are refused flat", async () => {
    await assert.rejects(
      () => run(request(FAKE_SUPER, "superAdmin", assignArgs("moderator"))),
      /reserved for the application owner/,
    );
    const alerts = await db
      .collection("adminAuditLogs")
      .where("action", "==", "security_alert_non_owner_super_admin")
      .where("targetId", "==", FAKE_SUPER)
      .get();
    assert.equal(alerts.size, 1);

    for (const [uid, role] of [
      [MOD, "moderator"],
      [PLAIN, "user"],
    ]) {
      await assert.rejects(
        () => run(request(uid, role, assignArgs("support"))),
        /super administrator|permission/i,
      );
    }
    await assert.rejects(
      () => run({ auth: null, data: assignArgs("support") }),
      /signed in/i,
    );

    // Nothing moved.
    const record = await adminAuth.getUser(TARGET);
    assert.equal(record.customClaims?.role, undefined);
  });
});
