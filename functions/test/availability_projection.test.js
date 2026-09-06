const assert = require("node:assert/strict");
const { test, describe } = require("node:test");

const { getApps, initializeApp } = require("firebase-admin/app");

// The module touches the Admin SDK at load; a demo app keeps this pure test
// free of any emulator or network.
if (getApps().length === 0) initializeApp({ projectId: "demo-yovoice" });

const {
  SOCIAL_PRESENCE_FIELDS,
  deriveSocialPresence,
  deriveVisibleAvailability,
} = require("../profile/public_profiles");

// Pure projection logic: no emulator, no Admin SDK calls.
describe("availability projection", () => {
  test("projects the chosen availability only while online", () => {
    assert.deepEqual(
      deriveVisibleAvailability({ isOnline: true, availability: "busy" }),
      { isOnline: true, availability: "busy" },
    );
    assert.deepEqual(
      deriveVisibleAvailability({ isOnline: true, availability: "away" }),
      { isOnline: true, availability: "away" },
    );
    assert.deepEqual(deriveVisibleAvailability({ isOnline: true }), {
      isOnline: true,
      availability: "available",
    });
    assert.deepEqual(
      deriveVisibleAvailability({ isOnline: true, availability: "party" }),
      { isOnline: true, availability: "available" },
    );
  });

  test("invisible is indistinguishable from offline for everyone else", () => {
    assert.deepEqual(
      deriveVisibleAvailability({ isOnline: true, availability: "invisible" }),
      { isOnline: false, availability: "offline" },
    );
    assert.deepEqual(
      deriveVisibleAvailability({ isOnline: false, availability: "busy" }),
      { isOnline: false, availability: "offline" },
    );
  });

  test("the presence projection carries availability and never invisible", () => {
    const presence = deriveSocialPresence("uid-1", {
      uid: "uid-1",
      displayName: "Ada",
      isOnline: true,
      availability: "invisible",
      lastSeen: null,
    });
    assert.ok(presence, "an active account has a projection");
    assert.equal(presence.isOnline, false);
    assert.equal(presence.availability, "offline");
    assert.ok(SOCIAL_PRESENCE_FIELDS.has("availability"));
  });
});
